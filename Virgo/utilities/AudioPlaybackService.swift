//
//  AudioPlaybackService.swift
//  Virgo
//
//  Created by Claude Code on 27/7/2025.
//

import Foundation
import AVFoundation
import SwiftUI
import SwiftData

@MainActor
class AudioPlaybackService: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentlyPlaying: PersistentIdentifier?
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?

    // Audio caching for fast replay
    private var audioCache: [String: AVAudioPlayer] = [:]
    private var audioCacheOrder: [String] = []
    private let maxCacheSize = 10
    private var requestGeneration: UInt64 = 0
    // Test-only: continuations resumed when a delegate callback's Task completes,
    // replacing nondeterministic Task.yield() in tests. Always empty in production.
    private var delegateCallbackWaiters: [CheckedContinuation<Void, Never>] = []
    // Test-only: latches delegate callbacks that completed before a waiter
    // registered, so a late waitForDelegateCallback returns immediately instead
    // of hanging. Always zero in production.
    private var latchedDelegateCallbackCount = 0
    private let loadPlayer: @MainActor (URL) async throws -> AVAudioPlayer
    private let startPlayback: (AVAudioPlayer) -> Bool

    init(
        loadPlayer: @escaping @MainActor (URL) async throws -> AVAudioPlayer = { url in
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 1.0
            _ = player.prepareToPlay()
            return player
        },
        startPlayback: @escaping (AVAudioPlayer) -> Bool = { $0.play() }
    ) {
        self.loadPlayer = loadPlayer
        self.startPlayback = startPlayback
        super.init()
        if !TestEnvironment.isRunningTests {
            setupAudioSession()
        }
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
        audioCacheOrder.removeAll()
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
        let generation = nextRequestGeneration()
        clearCurrentPlayback()

        guard let previewPath = song.previewFilePath else {
            handleNoPreviewFile(for: song)
            return
        }

        // Try cached player first — synchronous activation with generation guard.
        let cacheKey = previewCacheKey(for: previewPath)
        if let cachedPlayer = audioCache[cacheKey] {
            activatePreviewPlayer(
                cachedPlayer,
                song: song,
                previewPath: previewPath,
                generation: generation,
                shouldCache: false
            )
            return
        }

        // Cache miss — load and play in background.
        loadAndPlayPreview(song: song, previewPath: previewPath, generation: generation)
    }

    func stop() {
        invalidatePreviewRequests()
        clearCurrentPlayback()
    }

    private func clearCurrentPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentlyPlaying = nil
        currentTime = 0
        duration = 0
        stopProgressTimer()
    }

    private func nextRequestGeneration() -> UInt64 {
        requestGeneration &+= 1
        return requestGeneration
    }

    private func invalidatePreviewRequests() {
        requestGeneration &+= 1
    }

    func pause() {
        isPlaying = false
        audioPlayer?.pause()
        stopProgressTimer()
    }

    func resume() {
        guard let player = audioPlayer, currentlyPlaying != nil else {
            clearCurrentPlayback()
            return
        }

        guard startPlayback(player) else {
            clearCurrentPlayback()
            return
        }

        isPlaying = true
        startProgressTimer()
    }

    func togglePlayback(for song: Song) {
        if currentlyPlaying == song.id && isPlaying {
            pause()
        } else if currentlyPlaying == song.id {
            resume()
        } else {
            playPreview(for: song)
        }
    }

    private func startProgressTimer() {
        stopProgressTimer()
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

    /// Test-only accessor for verifying timer state. In production this state is
    /// only reached via the progress timer lifecycle (start/stop/pause/resume).
    var progressTimerForTesting: Timer? { progressTimer }

    /// Test-only: awaits completion of the next delegate callback's Task.
    /// Replaces nondeterministic Task.yield() after calling nonisolated
    /// AVAudioPlayerDelegate methods that spawn Task { @MainActor in ... }.
    /// If the callback already completed before registration, the latched
    /// count is consumed and the method returns immediately.
    func waitForDelegateCallback() async {
        await withCheckedContinuation { continuation in
            if latchedDelegateCallbackCount > 0 {
                latchedDelegateCallbackCount -= 1
                continuation.resume()
            } else {
                delegateCallbackWaiters.append(continuation)
            }
        }
    }

    private func resumeDelegateCallbackWaiters() {
        let waiters = delegateCallbackWaiters
        delegateCallbackWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        // Latch completions that arrived with no waiter registered.
        if waiters.isEmpty {
            latchedDelegateCallbackCount += 1
        }
    }

    private func updateProgress() {
        guard let player = audioPlayer else { return }
        currentTime = player.currentTime
    }

    // MARK: - Helper Methods

    private func handleNoPreviewFile(for song: Song) {
        Logger.audioPlayback("No preview file available for song: \(song.title)")
        isPlaying = false
        currentlyPlaying = nil
    }

    private func loadAndPlayPreview(
        song: Song,
        previewPath: String,
        generation: UInt64
    ) {
        Task {
            do {
                let url = URL(fileURLWithPath: previewPath)

                #if os(iOS)
                try AVAudioSession.sharedInstance().setActive(true)
                #endif

                let player = try await loadPlayer(url)

                activatePreviewPlayer(
                    player,
                    song: song,
                    previewPath: previewPath,
                    generation: generation,
                    shouldCache: true
                )
            } catch {
                handlePlaybackError(error, song: song, generation: generation)
            }
        }
    }

    /// Single shared activation path for both cached and freshly loaded players.
    /// Validates the current generation before any audio activation, preserving
    /// cancellation when stop() or a newer request invalidates playback.
    /// A failed start does not trigger a second activation sequence — the caller
    /// can retry via a new playPreview request.
    private func activatePreviewPlayer(
        _ player: AVAudioPlayer,
        song: Song,
        previewPath: String,
        generation: UInt64,
        shouldCache: Bool
    ) {
        guard generation == requestGeneration else {
            player.stop()
            return
        }

        // Cache the decoded/prepared player before the start attempt. A failed
        // play() can be transient and does not prove the resource is invalid, so
        // HPA-576 retains the cached entry even when start fails.
        if shouldCache {
            cacheAudioPlayer(player, for: previewPath)
        }

        guard startInstalledPlayer(player, songID: song.id) else {
            Logger.audioPlayback("Failed to start audio playback")
            return
        }

        Logger.audioPlayback("Started playing preview for: \(song.title)")
    }

    private func handlePlaybackError(_ error: Error, song: Song, generation: UInt64) {
        Logger.audioPlayback("Failed to play preview audio: \(error)")
        Logger.audioPlayback("Failed to play preview for \(song.title): \(error.localizedDescription)")

        guard generation == requestGeneration else { return }

        isPlaying = false
        currentlyPlaying = nil

        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            Logger.audioPlayback("Failed to deactivate audio session: \(error)")
        }
        #endif
    }

    // MARK: - Audio Caching

    private func previewCacheKey(for path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    @discardableResult
    private func startInstalledPlayer(
        _ player: AVAudioPlayer,
        songID: PersistentIdentifier
    ) -> Bool {
        audioPlayer = player
        player.delegate = self
        player.currentTime = 0
        duration = player.duration
        currentTime = 0

        guard startPlayback(player) else {
            audioPlayer = nil
            currentlyPlaying = nil
            isPlaying = false
            duration = 0
            currentTime = 0
            stopProgressTimer()
            return false
        }

        currentlyPlaying = songID
        isPlaying = true
        startProgressTimer()
        return true
    }

    private func cacheAudioPlayer(_ player: AVAudioPlayer, for previewPath: String) {
        let cacheKey = previewCacheKey(for: previewPath)
        let isReplacingExistingEntry = audioCache[cacheKey] != nil

        if let existingPlayer = audioCache[cacheKey], existingPlayer !== player {
            existingPlayer.stop()
        }
        audioCacheOrder.removeAll { $0 == cacheKey }

        // Manage cache size
        if !isReplacingExistingEntry && audioCache.count >= maxCacheSize {
            // Remove oldest entry (deterministic FIFO)
            if let firstKey = audioCacheOrder.first {
                audioCache[firstKey]?.stop()
                audioCache.removeValue(forKey: firstKey)
                audioCacheOrder.removeFirst()
            }
        }

        audioCache[cacheKey] = player
        audioCacheOrder.append(cacheKey)
    }
}

extension AudioPlaybackService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            defer { self.resumeDelegateCallbackWaiters() }
            guard player === self.audioPlayer else { return }
            self.stop()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            defer { self.resumeDelegateCallbackWaiters() }
            if let error = error {
                Logger.audioPlayback("Audio player decode error: \(error)")
                Logger.audioPlayback("Audio decode error: \(error.localizedDescription)")
            }
            guard player === self.audioPlayer else { return }
            self.stop()
        }
    }

    nonisolated func audioPlayerBeginInterruption(_ player: AVAudioPlayer) {
        Task { @MainActor in
            defer { self.resumeDelegateCallbackWaiters() }
            guard player === self.audioPlayer else { return }
            self.pause()
        }
    }

    nonisolated func audioPlayerEndInterruption(_ player: AVAudioPlayer, withOptions flags: Int) {
        Task { @MainActor in
            defer { self.resumeDelegateCallbackWaiters() }
            guard player === self.audioPlayer else { return }
            // Optionally resume playback after interruption
            #if os(iOS)
            if flags == AVAudioSession.InterruptionOptions.shouldResume.rawValue {
                self.resume()
            }
            #endif
        }
    }
}
