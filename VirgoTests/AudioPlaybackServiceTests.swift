import Testing
import Foundation
import AVFoundation
@testable import Virgo

@Suite("AudioPlaybackService Tests", .serialized)
@MainActor
struct AudioPlaybackServiceTests {
    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private func makeSilentAudioPlayer() throws -> AVAudioPlayer {
        let sampleRate: UInt32 = 44_100
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let sampleCount: UInt32 = sampleRate / 10 // 0.1s silence

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

        return try AVAudioPlayer(data: wavData)
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

    @Test("playPreview failure does not clear state when user switched songs")
    func testPlayPreviewFailureAfterSongSwitchKeepsCurrentState() async throws {
        let service = AudioPlaybackService()
        let invalidPath = "/tmp/virgo-missing-preview-\(UUID().uuidString).mp3"
        let firstSong = makeSong(title: "First Song", previewPath: invalidPath)

        service.playPreview(for: firstSong)

        service.currentlyPlayingSong = "Second Song"
        service.isPlaying = true

        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(service.currentlyPlayingSong == "Second Song")
        #expect(service.isPlaying == true)
    }

    @Test("audioPlayerDidFinishPlaying stops playback state")
    func testAudioPlayerDidFinishPlayingStopsPlayback() async throws {
        let service = AudioPlaybackService()
        let player = try makeSilentAudioPlayer()

        service.isPlaying = true
        service.currentlyPlayingSong = "Song"
        service.currentTime = 3.2
        service.duration = 12.0

        service.audioPlayerDidFinishPlaying(player, successfully: true)
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(service.isPlaying == false)
        #expect(service.currentlyPlayingSong == nil)
        #expect(service.currentTime == 0)
        #expect(service.duration == 0)
    }

    @Test("audioPlayerDecodeErrorDidOccur stops playback state")
    func testAudioPlayerDecodeErrorStopsPlayback() async throws {
        let service = AudioPlaybackService()
        let player = try makeSilentAudioPlayer()

        service.isPlaying = true
        service.currentlyPlayingSong = "Song"

        service.audioPlayerDecodeErrorDidOccur(player, error: NSError(domain: "Test", code: -1))
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(service.isPlaying == false)
        #expect(service.currentlyPlayingSong == nil)
    }

    @Test("audioPlayerBeginInterruption pauses playback")
    func testAudioPlayerBeginInterruptionPausesPlayback() async throws {
        let service = AudioPlaybackService()
        let player = try makeSilentAudioPlayer()

        service.isPlaying = true
        service.currentlyPlayingSong = "Song"

        service.audioPlayerBeginInterruption(player)
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(service.isPlaying == false)
        #expect(service.currentlyPlayingSong == "Song")
    }
}
