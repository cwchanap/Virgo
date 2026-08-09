import Testing
import Foundation
import AVFoundation
@testable import Virgo

extension AudioPlaybackServiceTests {
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

            // Remove the source file before replay to verify the cached player
            // is used without re-reading from disk.
            try? FileManager.default.removeItem(atPath: previewPath)

            // Second play should hit cache — no new load request.
            service.playPreview(for: song)
            #expect(service.isPlaying == true)
            #expect(service.currentlyPlaying == song.id)
            #expect(loader.requests.count == 1)
        }
    }

    @Test("cached player survives a transient startPlayback failure without reload")
    func cachedPlayerSurvivesTransientStartFailure() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            var startAttempts = 0
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in
                    startAttempts += 1
                    return startAttempts == 2 // fail first, succeed second
                }
            )
            let previewPath = try makeTemporaryWAVPath(durationSeconds: 1.0)
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let song = insertSong(title: "Transient Start Failure", previewPath: previewPath)
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: previewPath))

            // First attempt: load succeeds but startPlayback fails.
            service.playPreview(for: song)
            await loader.waitForRequest(path: previewPath)
            await loader.succeed(path: previewPath, player: player)

            #expect(service.isPlaying == false)
            #expect(service.currentlyPlaying == nil)

            // Second attempt: cache hit, startPlayback succeeds — no reload.
            service.playPreview(for: song)
            #expect(service.isPlaying == true)
            #expect(service.currentlyPlaying == song.id)
            #expect(loader.requests.count == 1)
        }
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

            // The first entry (index 0) is evicted by FIFO after 11 insertions.
            // Fail the reload to simulate a missing source file and prevent re-caching.
            var evictedCount = 0
            var evictedPath: String?
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
                evictedPath = previewPaths[index]
            }
            #expect(evictedCount == 1, "exactly one entry should be evicted by FIFO")
            #expect(evictedPath == previewPaths[0], "the oldest entry should be evicted")

            // The most recently inserted entry should remain cached.
            service.stop()
            service.playPreview(for: songs[10])
            #expect(service.isPlaying == true)
            #expect(service.currentlyPlaying == songs[10].id)

            // No additional load requests beyond the single evicted replay.
            #expect(loader.requests.count == initialRequestCount + evictedCount)
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
