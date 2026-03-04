import Testing
import Foundation
@testable import Virgo

@Suite("AudioPlaybackService Tests", .serialized)
@MainActor
struct AudioPlaybackServiceTests {
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

    @Test("playPreview with missing preview path clears playback state")
    func testPlayPreviewWithoutPreviewPath() {
        let service = AudioPlaybackService()
        let song = makeSong(title: "No Preview")

        service.isPlaying = true
        service.currentlyPlayingSong = song.title

        service.playPreview(for: song)

        #expect(service.isPlaying == false)
        #expect(service.currentlyPlayingSong == nil)
    }

    @Test("togglePlayback pauses and resumes when the same song is selected")
    func testTogglePlaybackPauseAndResume() {
        let service = AudioPlaybackService()
        let song = makeSong(title: "Toggle Song")

        service.currentlyPlayingSong = song.title
        service.isPlaying = true

        service.togglePlayback(for: song)
        #expect(service.isPlaying == false)
        #expect(service.currentlyPlayingSong == song.title)

        service.togglePlayback(for: song)
        #expect(service.isPlaying == true)
        #expect(service.currentlyPlayingSong == song.title)
    }

    @Test("stop resets playback state")
    func testStopResetsPlaybackState() {
        let service = AudioPlaybackService()

        service.isPlaying = true
        service.currentlyPlayingSong = "Any Song"
        service.currentTime = 12.34
        service.duration = 56.78

        service.stop()

        #expect(service.isPlaying == false)
        #expect(service.currentlyPlayingSong == nil)
        #expect(service.currentTime == 0)
        #expect(service.duration == 0)
    }

    @Test("playPreview with invalid file path reports failure asynchronously")
    func testPlayPreviewWithInvalidPath() async throws {
        let service = AudioPlaybackService()
        let invalidPath = "/tmp/virgo-missing-preview-\(UUID().uuidString).mp3"
        let song = makeSong(title: "Broken Preview", previewPath: invalidPath)

        service.playPreview(for: song)

        #expect(service.isPlaying == true)
        #expect(service.currentlyPlayingSong == song.title)

        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(service.isPlaying == false)
        #expect(service.currentlyPlayingSong == nil)
    }
}
