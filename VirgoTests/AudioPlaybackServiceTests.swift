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

    func makeSilentWAVData(durationSeconds: Double = 0.1) -> Data {
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

    func makeSilentAudioPlayer() throws -> AVAudioPlayer {
        try AVAudioPlayer(data: makeSilentWAVData(durationSeconds: 0.1))
    }

    func makeTemporaryWAVPath(durationSeconds: Double = 2.0) throws -> String {
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

    func insertSong(title: String, previewPath: String? = nil) -> Song {
        let song = makeSong(title: title, previewPath: previewPath)
        TestContainer.shared.context.insert(song)
        return song
    }

    func startPreview(
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
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let previewPath = try makeTemporaryWAVPath(durationSeconds: 2.0)
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let song = insertSong(title: "Cached Song", previewPath: previewPath)
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: previewPath))

            service.playPreview(for: song)
            await loader.waitForRequest(path: previewPath)
            await loader.succeed(path: previewPath, player: player)
            #expect(service.currentlyPlaying == song.id)
            #expect(service.duration > 0)

            service.stop()

            // Second play should hit cache — no new load request.
            service.playPreview(for: song)
            #expect(service.isPlaying == true)
            #expect(service.currentlyPlaying == song.id)
            #expect(loader.requests.count == 1)
        }
    }

    @Test("playPreview updates currentTime via progress timer")
    func testPlayPreviewUpdatesProgress() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { player in
                    player.currentTime = 0.25
                    return true
                }
            )
            let previewPath = try makeTemporaryWAVPath(durationSeconds: 2.0)
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let song = insertSong(title: "Progress Song", previewPath: previewPath)
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: previewPath))
            service.playPreview(for: song)
            await loader.waitForRequest(path: previewPath)
            await loader.succeed(path: previewPath, player: player)

            // The progress timer (0.1s interval) updates currentTime from the audio
            // player. Poll until currentTime becomes positive (or timeout).
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
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            var songs: [Song] = []
            var previewPaths: [String] = []
            var players: [AVAudioPlayer] = []

            for index in 0..<11 {
                let path = try makeTemporaryWAVPath(durationSeconds: 1.5)
                previewPaths.append(path)
                songs.append(insertSong(title: "Cache Song \(index)", previewPath: path))
                players.append(try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)))
            }

            defer {
                for path in previewPaths {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }

            // Play and stop each song to populate the cache (maxCacheSize = 10).
            for (index, song) in songs.enumerated() {
                service.playPreview(for: song)
                await loader.waitForRequest(path: previewPaths[index])
                await loader.succeed(path: previewPaths[index], player: players[index])
                #expect(service.currentlyPlaying == song.id)
                service.stop()
            }

            let initialRequestCount = loader.requests.count

            // One of the first ten entries should be evicted (cache miss → new load).
            // Fail the reload to simulate a missing source file and prevent re-caching.
            var evictedCount = 0
            for (index, song) in songs.prefix(10).enumerated() {
                service.stop()
                service.playPreview(for: song)

                // Cached: playback starts immediately without a new load request.
                if service.isPlaying && service.currentlyPlaying == song.id {
                    continue
                }

                // Evicted: a new load request was made.
                await loader.waitForRequest(path: previewPaths[index], count: 2)
                await loader.fail(path: previewPaths[index], error: TestError.loadFailed)
                evictedCount += 1
            }
            #expect(evictedCount >= 1)

            // The most recently inserted entry should remain cached.
            service.stop()
            service.playPreview(for: songs[10])
            #expect(service.isPlaying == true)
            #expect(service.currentlyPlaying == songs[10].id)

            // No additional load requests beyond the evicted replays.
            #expect(loader.requests.count == initialRequestCount + evictedCount)
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
            let loader = ControlledPlayerLoader()
            var service: AudioPlaybackService? = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let previewPath = try makeTemporaryWAVPath(durationSeconds: 1.5)
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let song = insertSong(title: "Deinit Song", previewPath: previewPath)
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: previewPath))

            service?.playPreview(for: song)
            await loader.waitForRequest(path: previewPath)
            await loader.succeed(path: previewPath, player: player)
            #expect(service?.currentlyPlaying == song.id)

            // Deinitialization after cached players exist must not crash.
            service = nil
        }
    }
}
