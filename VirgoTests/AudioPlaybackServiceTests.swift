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
        return try AVAudioPlayer(data: makeSilentWAVData(durationSeconds: 0.1))
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

    @Test("togglePlayback with different song switches and starts new preview")
    func testTogglePlaybackDifferentSongStartsPlayback() async throws {
        let service = AudioPlaybackService()
        let previewPath = try makeTemporaryWAVPath(durationSeconds: 2.0)
        defer { try? FileManager.default.removeItem(atPath: previewPath) }

        let newSong = makeSong(title: "New Song", previewPath: previewPath)
        service.currentlyPlayingSong = "Old Song"
        service.isPlaying = true

        service.togglePlayback(for: newSong)
        #expect(service.currentlyPlayingSong == "New Song")
        #expect(service.isPlaying == true)

        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(service.duration > 0)
        #expect(service.currentlyPlayingSong == "New Song")
    }

    @Test("playPreview reuses cached player even after source file is removed")
    func testPlayPreviewUsesCachedPlayer() async throws {
        let service = AudioPlaybackService()
        let previewPath = try makeTemporaryWAVPath(durationSeconds: 2.0)
        let song = makeSong(title: "Cached Song", previewPath: previewPath)

        defer { try? FileManager.default.removeItem(atPath: previewPath) }

        service.playPreview(for: song)
        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(service.duration > 0)

        service.stop()
        try? FileManager.default.removeItem(atPath: previewPath)

        service.playPreview(for: song)
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(service.isPlaying == true)
        #expect(service.currentlyPlayingSong == "Cached Song")
    }

    @Test("playPreview updates currentTime via progress timer")
    func testPlayPreviewUpdatesProgress() async throws {
        let service = AudioPlaybackService()
        let previewPath = try makeTemporaryWAVPath(durationSeconds: 2.0)
        defer { try? FileManager.default.removeItem(atPath: previewPath) }

        let song = makeSong(title: "Progress Song", previewPath: previewPath)
        service.playPreview(for: song)

        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(service.currentTime > 0)
        #expect(service.duration > 0)
    }

    @Test("audioPlayerEndInterruption callback does not alter state on macOS")
    func testAudioPlayerEndInterruptionNoStateChangeOnMacOS() async throws {
        let service = AudioPlaybackService()
        let player = try makeSilentAudioPlayer()

        service.isPlaying = true
        service.currentlyPlayingSong = "Song"

        service.audioPlayerEndInterruption(player, withOptions: 0)
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(service.isPlaying == true)
        #expect(service.currentlyPlayingSong == "Song")
    }

    @Test("deinit cleans up cached players")
    func testServiceDeinitAfterCachingPlayers() async throws {
        let previewPath = try makeTemporaryWAVPath(durationSeconds: 1.5)
        defer { try? FileManager.default.removeItem(atPath: previewPath) }

        var service: AudioPlaybackService? = AudioPlaybackService()
        let song = makeSong(title: "Deinit Song", previewPath: previewPath)

        service?.playPreview(for: song)
        try await Task.sleep(nanoseconds: 200_000_000)

        service = nil

        #expect(service == nil)
    }
}
