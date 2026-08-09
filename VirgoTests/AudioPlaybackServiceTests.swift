import Testing
import Foundation
import AVFoundation
@testable import Virgo

@Suite(
    "AudioPlaybackService Tests",
    .serialized,
    .timeLimit(.minutes(1))
)
@MainActor
struct AudioPlaybackServiceTests {
    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private func makeSilentWAVData(durationSeconds: Double = 0.1) -> Data {
        let sampleRate: UInt32 = 44_100
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let sampleCount = UInt32(max(1.0, durationSeconds * Double(sampleRate)))

        let blockAlign = channels * bitsPerSample / 8
        let byteRate = sampleRate * UInt32(blockAlign)
        let dataSize = sampleCount * UInt32(blockAlign)
        let chunkSize: UInt32 = 36 + dataSize

        var wavData = Data()
        wavData.append("RIFF".data(using: .ascii)!)
        appendLittleEndian(chunkSize, to: &wavData)
        wavData.append("WAVE".data(using: .ascii)!)
        wavData.append("fmt ".data(using: .ascii)!)
        appendLittleEndian(UInt32(16), to: &wavData) // PCM chunk size
        appendLittleEndian(UInt16(1), to: &wavData) // Audio format PCM
        appendLittleEndian(channels, to: &wavData)
        appendLittleEndian(sampleRate, to: &wavData)
        appendLittleEndian(byteRate, to: &wavData)
        appendLittleEndian(blockAlign, to: &wavData)
        appendLittleEndian(bitsPerSample, to: &wavData)
        wavData.append("data".data(using: .ascii)!)
        appendLittleEndian(dataSize, to: &wavData)
        wavData.append(Data(repeating: 0, count: Int(dataSize)))
        return wavData
    }

    private func makeSilentAudioPlayer() throws -> AVAudioPlayer {
        try AVAudioPlayer(data: makeSilentWAVData(durationSeconds: 0.1))
    }

    private func makeTemporaryWAVPath(durationSeconds: Double = 2.0) throws -> String {
        let path = "/tmp/virgo-preview-\(UUID().uuidString).wav"
        let url = URL(fileURLWithPath: path)
        try makeSilentWAVData(durationSeconds: durationSeconds).write(to: url)
        return path
    }

    private func makeSong(title: String, previewPath: String? = nil) -> Song {
        Song(
            title: title,
            artist: "Test Artist",
            bpm: 120.0,
            duration: "1:00",
            genre: "DTX Import",
            previewFilePath: previewPath
        )
    }

    private func insertSong(title: String, previewPath: String? = nil) -> Song {
        let song = makeSong(title: title, previewPath: previewPath)
        TestContainer.shared.context.insert(song)
        return song
    }

    private func startPreview(
        service: AudioPlaybackService,
        loader: ControlledPlayerLoader,
        song: Song,
        path: String,
        player: AVAudioPlayer
    ) async {
        service.playPreview(for: song)
        await loader.waitForRequest(path: path)
        await loader.succeed(path: path, player: player)
        #expect(service.currentlyPlaying == song.id)
        #expect(service.isPlaying)
    }

    private func progressTimer(in service: AudioPlaybackService) -> Timer? {
        Mirror(reflecting: service).descendant("progressTimer") as? Timer
    }

    @Test("playPreview with missing preview path clears playback state")
    func testPlayPreviewWithoutPreviewPath() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let previewPath = try makeTemporaryWAVPath()
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let previewSong = insertSong(title: "Preview", previewPath: previewPath)
            let song = insertSong(title: "No Preview")
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: previewPath))

            await startPreview(
                service: service,
                loader: loader,
                song: previewSong,
                path: previewPath,
                player: player
            )

            service.playPreview(for: song)

            #expect(service.isPlaying == false)
            #expect(service.currentlyPlaying == nil)
        }
    }

    @Test("same-title songs use distinct preview identities and cache resources")
    func sameTitleSongsUseDistinctPreviewIdentities() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let firstPath = try makeTemporaryWAVPath(durationSeconds: 1.0)
            let secondPath = try makeTemporaryWAVPath(durationSeconds: 2.0)
            defer {
                try? FileManager.default.removeItem(atPath: firstPath)
                try? FileManager.default.removeItem(atPath: secondPath)
            }

            let first = insertSong(title: "Collision", previewPath: firstPath)
            let second = insertSong(title: "Collision", previewPath: secondPath)
            #expect(first.id != second.id)

            let firstPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: firstPath))
            let secondPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: secondPath))

            service.playPreview(for: first)
            #expect(!service.isPlaying)
            #expect(service.currentlyPlaying == nil)
            await loader.waitForRequest(path: firstPath)
            await loader.succeed(path: firstPath, player: firstPlayer)
            #expect(service.currentlyPlaying == first.id)

            service.stop()
            service.playPreview(for: second)
            await loader.waitForRequest(path: secondPath)
            await loader.succeed(path: secondPath, player: secondPlayer)

            #expect(service.currentlyPlaying == second.id)
            #expect(service.duration == secondPlayer.duration)
            #expect(loader.requests == [
                URL(fileURLWithPath: firstPath).standardizedFileURL.path,
                URL(fileURLWithPath: secondPath).standardizedFileURL.path
            ])
        }
    }

    @Test("togglePlayback pauses and resumes when the same song is selected")
    func testTogglePlaybackPauseAndResume() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let previewPath = try makeTemporaryWAVPath()
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let song = insertSong(title: "Toggle Song", previewPath: previewPath)
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: previewPath))
            await startPreview(
                service: service,
                loader: loader,
                song: song,
                path: previewPath,
                player: player
            )

            service.togglePlayback(for: song)
            #expect(service.isPlaying == false)
            #expect(service.currentlyPlaying == song.id)

            service.togglePlayback(for: song)
            #expect(service.isPlaying == true)
            #expect(service.currentlyPlaying == song.id)
        }
    }

    @Test("stop resets playback state")
    func testStopResetsPlaybackState() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let previewPath = try makeTemporaryWAVPath()
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let song = insertSong(title: "Stop Song", previewPath: previewPath)
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: previewPath))
            await startPreview(
                service: service,
                loader: loader,
                song: song,
                path: previewPath,
                player: player
            )
            service.currentTime = 12.34

            service.stop()

            #expect(service.isPlaying == false)
            #expect(service.currentlyPlaying == nil)
            #expect(service.currentTime == 0)
            #expect(service.duration == 0)
        }
    }

    @Test("playPreview with invalid file path reports failure asynchronously")
    func testPlayPreviewWithInvalidPath() async throws {
        let loader = ControlledPlayerLoader()
        let service = AudioPlaybackService(
            loadPlayer: { try await loader.load($0) },
            startPlayback: { _ in true }
        )
        let invalidPath = "/tmp/virgo-missing-preview-\(UUID().uuidString).mp3"
        let song = makeSong(title: "Broken Preview", previewPath: invalidPath)

        service.playPreview(for: song)

        #expect(service.isPlaying == false)
        #expect(service.currentlyPlaying == nil)
        await loader.waitForRequest(path: invalidPath)
        await loader.fail(path: invalidPath, error: NSError(domain: "Test", code: -1))

        #expect(service.isPlaying == false)
        #expect(service.currentlyPlaying == nil)
    }

    @Test("audioPlayerDidFinishPlaying stops playback state")
    func testAudioPlayerDidFinishPlayingStopsPlayback() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let previewPath = try makeTemporaryWAVPath()
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let song = insertSong(title: "Finish Song", previewPath: previewPath)
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: previewPath))
            await startPreview(
                service: service,
                loader: loader,
                song: song,
                path: previewPath,
                player: player
            )
            service.currentTime = 3.2

            service.audioPlayerDidFinishPlaying(player, successfully: true)
            await Task.yield()

            #expect(service.isPlaying == false)
            #expect(service.currentlyPlaying == nil)
            #expect(service.currentTime == 0)
            #expect(service.duration == 0)
        }
    }

    @Test("audioPlayerDecodeErrorDidOccur stops playback state")
    func testAudioPlayerDecodeErrorStopsPlayback() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let previewPath = try makeTemporaryWAVPath()
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let song = insertSong(title: "Decode Song", previewPath: previewPath)
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: previewPath))
            await startPreview(
                service: service,
                loader: loader,
                song: song,
                path: previewPath,
                player: player
            )

            service.audioPlayerDecodeErrorDidOccur(player, error: NSError(domain: "Test", code: -1))
            await Task.yield()

            #expect(service.isPlaying == false)
            #expect(service.currentlyPlaying == nil)
        }
    }

    @Test("audioPlayerBeginInterruption pauses playback")
    func testAudioPlayerBeginInterruptionPausesPlayback() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let previewPath = try makeTemporaryWAVPath()
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let song = insertSong(title: "Interrupted Song", previewPath: previewPath)
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: previewPath))
            await startPreview(
                service: service,
                loader: loader,
                song: song,
                path: previewPath,
                player: player
            )

            service.audioPlayerBeginInterruption(player)
            await Task.yield()

            #expect(service.isPlaying == false)
            #expect(service.currentlyPlaying == song.id)
        }
    }

    @Test("togglePlayback with different song switches and starts new preview")
    func testTogglePlaybackDifferentSongStartsPlayback() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let oldPath = try makeTemporaryWAVPath(durationSeconds: 1.0)
            let newPath = try makeTemporaryWAVPath(durationSeconds: 2.0)
            defer {
                try? FileManager.default.removeItem(atPath: oldPath)
                try? FileManager.default.removeItem(atPath: newPath)
            }

            let oldSong = insertSong(title: "Old Song", previewPath: oldPath)
            let newSong = insertSong(title: "New Song", previewPath: newPath)
            let oldPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: oldPath))
            let newPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: newPath))
            await startPreview(
                service: service,
                loader: loader,
                song: oldSong,
                path: oldPath,
                player: oldPlayer
            )

            service.togglePlayback(for: newSong)
            #expect(service.isPlaying == false)
            #expect(service.currentlyPlaying == nil)
            await loader.waitForRequest(path: newPath)
            await loader.succeed(path: newPath, player: newPlayer)

            #expect(service.isPlaying == true)
            #expect(service.currentlyPlaying == newSong.id)
            #expect(service.duration == newPlayer.duration)
        }
    }

    @Test("playPreview reuses cached player even after source file is removed")
    func testPlayPreviewUsesCachedPlayer() async throws {
        try await TestSetup.withTestSetup {
            let service = AudioPlaybackService()
            let previewPath = try makeTemporaryWAVPath(durationSeconds: 2.0)
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let song = insertSong(title: "Cached Song", previewPath: previewPath)

            service.playPreview(for: song)
            try await Task.sleep(nanoseconds: 250_000_000)
            #expect(service.duration > 0)

            service.stop()
            try? FileManager.default.removeItem(atPath: previewPath)

            service.playPreview(for: song)
            try await Task.sleep(nanoseconds: 100_000_000)

            #expect(service.isPlaying == true)
            #expect(service.currentlyPlaying == song.id)
        }
    }

    @Test("playPreview updates currentTime via progress timer")
    func testPlayPreviewUpdatesProgress() async throws {
        try await TestSetup.withTestSetup {
            let service = AudioPlaybackService(startPlayback: { player in
                player.currentTime = 0.25
                return true
            })
            let previewPath = try makeTemporaryWAVPath(durationSeconds: 2.0)
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let song = insertSong(title: "Progress Song", previewPath: previewPath)
            service.playPreview(for: song)

            // The progress timer (0.1s interval) updates currentTime from the audio
            // player, but the player is loaded asynchronously via loadAndPlayPreview's
            // Task chain. Under CI load this can take longer than a fixed sleep, so
            // poll until currentTime becomes positive (or timeout).
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(10))
            var currentTimeUpdated = false
            while clock.now < deadline {
                if service.currentTime > 0 {
                    currentTimeUpdated = true
                    break
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }

            #expect(currentTimeUpdated, "currentTime should be updated by the progress timer")
            #expect(service.duration > 0)
        }
    }

    @Test("playPreview clears state when audio player play returns false")
    func testPlayPreviewPlayFailureClearsState() async throws {
        let loader = ControlledPlayerLoader()
        let service = AudioPlaybackService(
            loadPlayer: { try await loader.load($0) },
            startPlayback: { _ in false }
        )
        let previewPath = try makeTemporaryWAVPath(durationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(atPath: previewPath) }

        let song = makeSong(title: "Play Failure Song", previewPath: previewPath)
        let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: previewPath))
        service.playPreview(for: song)

        #expect(service.isPlaying == false)
        #expect(service.currentlyPlaying == nil)
        await loader.waitForRequest(path: previewPath)
        await loader.succeed(path: previewPath, player: player)

        #expect(service.isPlaying == false)
        #expect(service.currentlyPlaying == nil)
        #expect(service.currentTime == 0)
    }

    @Test("playPreview evicts oldest cached player after exceeding cache limit")
    func testPlayPreviewEvictsOldestCachedPlayer() async throws {
        try await TestSetup.withTestSetup {
            let service = AudioPlaybackService()
            var songs: [Song] = []
            var previewPaths: [String] = []

            for index in 0..<11 {
                let path = try makeTemporaryWAVPath(durationSeconds: 1.5)
                previewPaths.append(path)
                songs.append(insertSong(title: "Cache Song \(index)", previewPath: path))
            }

            defer {
                for path in previewPaths {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }

            for song in songs {
                service.playPreview(for: song)
                try await Task.sleep(nanoseconds: 120_000_000)
                service.stop()
            }

            for path in previewPaths {
                try? FileManager.default.removeItem(atPath: path)
            }

            // One of the first ten entries should be evicted and fail without source files.
            var evictedCount = 0
            for song in songs.prefix(10) {
                service.stop()
                service.playPreview(for: song)
                try await Task.sleep(nanoseconds: 220_000_000)

                let didPlayFromCache = service.isPlaying && service.currentlyPlaying == song.id
                if !didPlayFromCache {
                    evictedCount += 1
                }
            }
            #expect(evictedCount >= 1)

            // The most recently inserted entry should remain cached.
            service.stop()
            service.playPreview(for: songs[10])
            try await Task.sleep(nanoseconds: 120_000_000)
            #expect(service.isPlaying == true)
            #expect(service.currentlyPlaying == songs[10].id)
        }
    }

    @Test("audioPlayerEndInterruption callback does not alter state on macOS")
    func testAudioPlayerEndInterruptionNoStateChangeOnMacOS() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let previewPath = try makeTemporaryWAVPath()
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let song = insertSong(title: "Resume Song", previewPath: previewPath)
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: previewPath))
            await startPreview(
                service: service,
                loader: loader,
                song: song,
                path: previewPath,
                player: player
            )

            service.audioPlayerEndInterruption(player, withOptions: 0)
            await Task.yield()

            #expect(service.isPlaying == true)
            #expect(service.currentlyPlaying == song.id)
        }
    }

    @Test("deinit after caching players is a no-crash sanity check")
    func testServiceDeinitAfterCachingPlayersNoCrash() async throws {
        try await TestSetup.withTestSetup {
            let previewPath = try makeTemporaryWAVPath(durationSeconds: 1.5)
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            var service: AudioPlaybackService? = AudioPlaybackService()
            let song = insertSong(title: "Deinit Song", previewPath: previewPath)

            service?.playPreview(for: song)
            try await Task.sleep(nanoseconds: 200_000_000)

            service = nil

            #expect(service == nil)
        }
    }
}

extension AudioPlaybackServiceTests {
    @Test("out-of-order preview loads keep the newest preview active")
    func outOfOrderPreviewLoadsKeepNewestPreviewActive() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let firstPath = try makeTemporaryWAVPath(durationSeconds: 1.0)
            let secondPath = try makeTemporaryWAVPath(durationSeconds: 2.0)
            defer {
                try? FileManager.default.removeItem(atPath: firstPath)
                try? FileManager.default.removeItem(atPath: secondPath)
            }

            let first = insertSong(title: "First", previewPath: firstPath)
            let second = insertSong(title: "Second", previewPath: secondPath)
            let firstPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: firstPath))
            let secondPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: secondPath))

            service.playPreview(for: first)
            await loader.waitForRequest(path: firstPath)
            service.playPreview(for: second)
            await loader.waitForRequest(path: secondPath)

            await loader.succeed(path: secondPath, player: secondPlayer)
            #expect(service.currentlyPlaying == second.id)
            #expect(service.duration == secondPlayer.duration)

            await loader.succeed(path: firstPath, player: firstPlayer)
            #expect(service.currentlyPlaying == second.id)
            #expect(service.duration == secondPlayer.duration)

            service.stop()
            service.playPreview(for: first)
            await loader.waitForRequest(path: firstPath, count: 2)
        }
    }

    @Test("stopping during a preview load prevents stale publication")
    func stoppingDuringPreviewLoadPreventsStalePublication() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let previewPath = try makeTemporaryWAVPath(durationSeconds: 1.0)
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let song = insertSong(title: "Stopped", previewPath: previewPath)
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: previewPath))

            service.playPreview(for: song)
            await loader.waitForRequest(path: previewPath)
            service.stop()
            await loader.succeed(path: previewPath, player: player)

            #expect(!service.isPlaying)
            #expect(service.currentlyPlaying == nil)
            #expect(service.duration == 0)
            #expect(service.currentTime == 0)

            service.playPreview(for: song)
            await loader.waitForRequest(path: previewPath, count: 2)
        }
    }

    @Test("stale preview load errors leave the newest preview active")
    func stalePreviewLoadErrorsLeaveNewestPreviewActive() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let firstPath = try makeTemporaryWAVPath(durationSeconds: 1.0)
            let secondPath = try makeTemporaryWAVPath(durationSeconds: 2.0)
            defer {
                try? FileManager.default.removeItem(atPath: firstPath)
                try? FileManager.default.removeItem(atPath: secondPath)
            }

            let first = insertSong(title: "First", previewPath: firstPath)
            let second = insertSong(title: "Second", previewPath: secondPath)
            let secondPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: secondPath))

            service.playPreview(for: first)
            await loader.waitForRequest(path: firstPath)
            service.playPreview(for: second)
            await loader.waitForRequest(path: secondPath)

            await loader.succeed(path: secondPath, player: secondPlayer)
            #expect(service.currentlyPlaying == second.id)
            #expect(service.duration == secondPlayer.duration)

            await loader.fail(path: firstPath, error: TestError.loadFailed)

            #expect(service.isPlaying)
            #expect(service.currentlyPlaying == second.id)
            #expect(service.duration == secondPlayer.duration)
        }
    }
}

extension AudioPlaybackServiceTests {
    @Test("resume without an installed player stays stopped")
    func resumeWithoutPlayerStaysStopped() {
        let service = AudioPlaybackService(startPlayback: { _ in true })

        service.resume()

        #expect(!service.isPlaying)
        #expect(service.currentlyPlaying == nil)
    }

    @Test("failed resume clears installed preview playback state")
    func failedResumeClearsInstalledPreviewPlaybackState() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            var attempts = 0
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in
                    attempts += 1
                    return attempts == 1
                }
            )
            let previewPath = try makeTemporaryWAVPath()
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let song = insertSong(title: "Failed Resume", previewPath: previewPath)
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: previewPath))
            await startPreview(
                service: service,
                loader: loader,
                song: song,
                path: previewPath,
                player: player
            )

            service.pause()
            service.resume()

            #expect(!service.isPlaying)
            #expect(service.currentlyPlaying == nil)
            #expect(service.currentTime == 0)
            #expect(service.duration == 0)
            #expect(progressTimer(in: service) == nil)
        }
    }

    @Test("pause and resume replace the installed preview progress timer")
    func pauseAndResumeReplaceInstalledPreviewProgressTimer() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let previewPath = try makeTemporaryWAVPath()
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let song = insertSong(title: "Timer Ownership", previewPath: previewPath)
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: previewPath))
            await startPreview(
                service: service,
                loader: loader,
                song: song,
                path: previewPath,
                player: player
            )

            let firstTimer = progressTimer(in: service)
            #expect(firstTimer?.isValid == true)

            service.pause()
            #expect(firstTimer?.isValid == false)

            service.resume()
            let resumedTimer = progressTimer(in: service)

            #expect(firstTimer?.isValid == false)
            #expect(resumedTimer?.isValid == true)
            #expect(firstTimer !== resumedTimer)

            service.resume()
            let replacementTimer = progressTimer(in: service)

            #expect(resumedTimer?.isValid == false)
            #expect(replacementTimer?.isValid == true)
            #expect(resumedTimer !== replacementTimer)
        }
    }

    @Test("obsolete finish callback leaves current preview active")
    func obsoleteFinishCallbackLeavesCurrentPreviewActive() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let firstPath = try makeTemporaryWAVPath()
            let secondPath = try makeTemporaryWAVPath()
            defer {
                try? FileManager.default.removeItem(atPath: firstPath)
                try? FileManager.default.removeItem(atPath: secondPath)
            }

            let first = insertSong(title: "Obsolete Finish", previewPath: firstPath)
            let second = insertSong(title: "Current Finish", previewPath: secondPath)
            let firstPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: firstPath))
            let secondPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: secondPath))
            await startPreview(
                service: service,
                loader: loader,
                song: first,
                path: firstPath,
                player: firstPlayer
            )
            await startPreview(
                service: service,
                loader: loader,
                song: second,
                path: secondPath,
                player: secondPlayer
            )

            service.audioPlayerDidFinishPlaying(firstPlayer, successfully: true)
            await Task.yield()

            #expect(service.currentlyPlaying == second.id)
            #expect(service.isPlaying)
        }
    }

    @Test("obsolete interruption-begin callback leaves current preview active")
    func obsoleteInterruptionBeginCallbackLeavesCurrentPreviewActive() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let firstPath = try makeTemporaryWAVPath()
            let secondPath = try makeTemporaryWAVPath()
            defer {
                try? FileManager.default.removeItem(atPath: firstPath)
                try? FileManager.default.removeItem(atPath: secondPath)
            }

            let first = insertSong(title: "Obsolete Interruption", previewPath: firstPath)
            let second = insertSong(title: "Current Interruption", previewPath: secondPath)
            let firstPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: firstPath))
            let secondPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: secondPath))
            await startPreview(
                service: service,
                loader: loader,
                song: first,
                path: firstPath,
                player: firstPlayer
            )
            await startPreview(
                service: service,
                loader: loader,
                song: second,
                path: secondPath,
                player: secondPlayer
            )

            service.audioPlayerBeginInterruption(firstPlayer)
            await Task.yield()

            #expect(service.currentlyPlaying == second.id)
            #expect(service.isPlaying)
        }
    }

    @Test("obsolete decode and interruption-end callbacks leave current preview active")
    func obsoleteDecodeAndInterruptionEndCallbacksLeaveCurrentPreviewActive() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let firstPath = try makeTemporaryWAVPath()
            let secondPath = try makeTemporaryWAVPath()
            defer {
                try? FileManager.default.removeItem(atPath: firstPath)
                try? FileManager.default.removeItem(atPath: secondPath)
            }

            let first = insertSong(title: "Obsolete Decode", previewPath: firstPath)
            let second = insertSong(title: "Current Decode", previewPath: secondPath)
            let firstPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: firstPath))
            let secondPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: secondPath))
            await startPreview(
                service: service,
                loader: loader,
                song: first,
                path: firstPath,
                player: firstPlayer
            )
            await startPreview(
                service: service,
                loader: loader,
                song: second,
                path: secondPath,
                player: secondPlayer
            )

            service.audioPlayerDecodeErrorDidOccur(firstPlayer, error: TestError.loadFailed)
            await Task.yield()

            #expect(service.currentlyPlaying == second.id)
            #expect(service.isPlaying)

            service.audioPlayerEndInterruption(firstPlayer, withOptions: 0)
            await Task.yield()

            #expect(service.currentlyPlaying == second.id)
            #expect(service.isPlaying)
        }
    }
}
