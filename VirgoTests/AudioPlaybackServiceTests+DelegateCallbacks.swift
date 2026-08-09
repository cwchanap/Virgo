import Testing
import Foundation
import AVFoundation
@testable import Virgo

extension AudioPlaybackServiceTests {
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
            await service.waitForDelegateCallback()

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
            await service.waitForDelegateCallback()

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
            await service.waitForDelegateCallback()

            #expect(service.isPlaying == false)
            #expect(service.currentlyPlaying == song.id)
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
            await service.waitForDelegateCallback()

            #expect(service.isPlaying == true)
            #expect(service.currentlyPlaying == song.id)
        }
    }

    @Test("waitForDelegateCallback returns immediately when callback already completed")
    func waitForDelegateCallbackAfterCompletionDoesNotHang() async throws {
        try await TestSetup.withTestSetup {
            let loader = ControlledPlayerLoader()
            let service = AudioPlaybackService(
                loadPlayer: { try await loader.load($0) },
                startPlayback: { _ in true }
            )
            let previewPath = try makeTemporaryWAVPath()
            defer { try? FileManager.default.removeItem(atPath: previewPath) }

            let song = insertSong(title: "Late Wait Song", previewPath: previewPath)
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: previewPath))
            await startPreview(
                service: service,
                loader: loader,
                song: song,
                path: previewPath,
                player: player
            )

            // Fire the delegate callback and let its Task fully complete before
            // registering a waiter. The latch must prevent a hang.
            service.audioPlayerDidFinishPlaying(player, successfully: true)

            // Poll the observable side effect (stop() sets isPlaying = false) to
            // confirm the delegate Task has run to completion.
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))
            while service.isPlaying && clock.now < deadline {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            #expect(service.isPlaying == false, "delegate Task should have completed")

            // Registering a waiter after completion must return immediately.
            await service.waitForDelegateCallback()

            #expect(service.isPlaying == false)
            #expect(service.currentlyPlaying == nil)
        }
    }
}
