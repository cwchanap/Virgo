//
//  AudioPlaybackService.swift
//  Virgo
//
//  Created by Claude Code on 27/7/2025.
//

import Foundation
import AVFoundation
import SwiftUI

@MainActor
class AudioPlaybackService: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentlyPlayingSong: String?
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?

    // Audio caching for fast replay
    private var audioCache: [String: AVAudioPlayer] = [:]
    private let maxCacheSize = 10

    override init() {
        super.init()
        setupAudioSession()
    }

    deinit {
        audioPlayer?.stop()
        audioPlayer = nil
        progressTimer?.invalidate()
        progressTimer = nil

        // Clean up cached audio players
        for (_, player) in audioCache {
            player.stop()
        }
        audioCache.removeAll()
    }

    private func setupAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Logger.audioPlayback("Failed to setup audio session: \(error)")
        }
        #endif
    }

    func playPreview(for song: Song) {
        guard let previewPath = song.previewFilePath else {
            handleNoPreviewFile(for: song)
            return
        }

        // Try to play from cache first
        if tryPlayCachedPreview(for: song) {
            return
        }

        // Load and play in background
        loadAndPlayPreview(song: song, previewPath: previewPath)
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentlyPlayingSong = nil
        currentTime = 0
        duration = 0
        stopProgressTimer()
    }

    func pause() {
        isPlaying = false
        audioPlayer?.pause()
        stopProgressTimer()
    }

    func resume() {
        isPlaying = true
        audioPlayer?.play()
        startProgressTimer()
    }

    func togglePlayback(for song: Song) {
        if currentlyPlayingSong == song.title && isPlaying {
            pause()
        } else if currentlyPlayingSong == song.title && !isPlaying {
            resume()
        } else {
            // Stop any currently playing audio immediately
            audioPlayer?.stop()
            stopProgressTimer()

            // Set UI state IMMEDIATELY for responsive feedback (like download button pattern)
            currentlyPlayingSong = song.title
            isPlaying = true

            // Then start audio playback in background
            playPreview(for: song)
        }
    }

    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard let player = audioPlayer else { return }
        currentTime = player.currentTime
    }

    // MARK: - Helper Methods

    private func handleNoPreviewFile(for song: Song) {
        Logger.audioPlayback("No preview file available for song: \(song.title)")
        isPlaying = false
        currentlyPlayingSong = nil
    }

    private func tryPlayCachedPreview(for song: Song) -> Bool {
        guard let cachedPlayer = audioCache[song.title] else { return false }

        audioPlayer = cachedPlayer
        audioPlayer?.delegate = self
        audioPlayer?.currentTime = 0
        duration = cachedPlayer.duration
        currentTime = 0
        startProgressTimer()

        let playResult = cachedPlayer.play()
        if playResult {
            isPlaying = true
            currentlyPlayingSong = song.title
            Logger.audioPlayback("Started playing cached preview for: \(song.title)")
        }

        return playResult
    }

    private func loadAndPlayPreview(song: Song, previewPath: String) {
        // Set loading state first
        isPlaying = true
        currentlyPlayingSong = song.title

        Task {
            do {
                let url = URL(fileURLWithPath: previewPath)

                #if os(iOS)
                try AVAudioSession.sharedInstance().setActive(true)
                #endif

                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = 1.0
                _ = player.prepareToPlay()

                await setupAndPlayNewPlayer(player: player, song: song)
            } catch {
                await handlePlaybackError(error, song: song)
            }
        }
    }

    @MainActor
    private func setupAndPlayNewPlayer(player: AVAudioPlayer, song: Song) {
        cacheAudioPlayer(player, for: song.title)

        // Only set as current player if user hasn't switched songs
        guard currentlyPlayingSong == song.title else { return }

        audioPlayer = player
        audioPlayer?.delegate = self
        duration = player.duration
        currentTime = 0
        startProgressTimer()

        let playResult = player.play()
        if !playResult {
            isPlaying = false
            currentlyPlayingSong = nil
            stopProgressTimer()
            Logger.audioPlayback("Failed to start audio playback")
            return
        }

        Logger.audioPlayback("Started playing preview for: \(song.title)")
    }

    @MainActor
    private func handlePlaybackError(_ error: Error, song: Song) {
        Logger.audioPlayback("Failed to play preview audio: \(error)")
        Logger.audioPlayback("Failed to play preview for \(song.title): \(error.localizedDescription)")

        // Only reset state if user hasn't switched songs
        if currentlyPlayingSong == song.title {
            isPlaying = false
            currentlyPlayingSong = nil
        }

        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            Logger.audioPlayback("Failed to deactivate audio session: \(error)")
        }
        #endif
    }

    // MARK: - Audio Caching

    private func cacheAudioPlayer(_ player: AVAudioPlayer, for songTitle: String) {
        // Manage cache size
        if audioCache.count >= maxCacheSize {
            // Remove oldest entry (simple FIFO)
            if let firstKey = audioCache.keys.first {
                audioCache[firstKey]?.stop()
                audioCache.removeValue(forKey: firstKey)
            }
        }

        audioCache[songTitle] = player
    }
}

extension AudioPlaybackService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stop()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            if let error = error {
                Logger.audioPlayback("Audio player decode error: \(error)")
                Logger.audioPlayback("Audio decode error: \(error.localizedDescription)")
            }
            self.stop()
        }
    }

    nonisolated func audioPlayerBeginInterruption(_ player: AVAudioPlayer) {
        Task { @MainActor in
            self.pause()
        }
    }

    nonisolated func audioPlayerEndInterruption(_ player: AVAudioPlayer, withOptions flags: Int) {
        Task { @MainActor in
            // Optionally resume playback after interruption
            #if os(iOS)
            if flags == AVAudioSession.InterruptionOptions.shouldResume.rawValue {
                self.resume()
            }
            #endif
        }
    }
}
