import Testing
import Foundation
import AVFoundation
@testable import Virgo

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
            #expect(service.progressTimerForTesting == nil)
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

            let firstTimer = service.progressTimerForTesting
            #expect(firstTimer?.isValid == true)

            service.pause()
            #expect(firstTimer?.isValid == false)

            service.resume()
            let resumedTimer = service.progressTimerForTesting

            #expect(firstTimer?.isValid == false)
            #expect(resumedTimer?.isValid == true)
            #expect(firstTimer !== resumedTimer)

            service.resume()
            let replacementTimer = service.progressTimerForTesting

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
