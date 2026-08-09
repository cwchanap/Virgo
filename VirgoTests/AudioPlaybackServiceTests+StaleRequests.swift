import Testing
import Foundation
import AVFoundation
@testable import Virgo

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
