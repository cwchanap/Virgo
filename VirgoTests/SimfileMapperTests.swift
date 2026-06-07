import Testing
import Foundation
@testable import Virgo

@Suite("SimfileMapper Tests")
struct SimfileMapperTests {
    private func sampleDTO(fileKeys: [String]) -> SimfileDTO {
        SimfileDTO(
            id: "song-1", title: "Title", artist: "Artist", bpm: 165.55,
            genre: nil, tags: ["jrock"], durationSeconds: 200,
            updatedAt: "2026-06-01T12:00:00Z",
            dtxFiles: [
                DtxFileDTO(label: "EXTREME", level: 74.0,
                           fileURL: "https://r2/song-1/ext.dtx",
                           fileSizeBytes: 4096, encoding: .shiftJIS)
            ],
            fileKeys: fileKeys
        )
    }

    @Test("Maps core fields, derives difficulty, rounds level")
    func testCoreMapping() {
        let song = SimfileMapper.makeServerSong(from: sampleDTO(fileKeys: []))
        #expect(song.songId == "song-1")
        #expect(song.bpm == 165.55)
        #expect(song.genre == nil) // nil here; downloader applies "DTX Import" fallback
        #expect(song.durationSeconds == 200)
        #expect(song.charts.count == 1)
        #expect(song.charts[0].difficulty == "hard")     // EXTREME -> .hard, lowercased bucket
        #expect(song.charts[0].level == 74)
        #expect(song.charts[0].filename == "ext.dtx")     // derived from fileURL lastPathComponent
        #expect(song.charts[0].fileURL == "https://r2/song-1/ext.dtx")
        #expect(song.charts[0].fileEncoding == "SHIFT_JIS")
    }

    @Test("Audio availability comes from file keys (exact lastPathComponent match)")
    func testAudioAvailability() {
        let withBoth = SimfileMapper.makeServerSong(
            from: sampleDTO(fileKeys: ["song-1/bgm.ogg", "song-1/preview.mp3"]))
        #expect(withBoth.hasBGM == true)
        #expect(withBoth.hasPreview == true)

        let withNone = SimfileMapper.makeServerSong(from: sampleDTO(fileKeys: ["song-1/ext.dtx"]))
        #expect(withNone.hasBGM == false)
        #expect(withNone.hasPreview == false)

        // Suffix over-match must NOT trigger: "intro-bgm.ogg" ≠ "bgm.ogg".
        let withSimilar = SimfileMapper.makeServerSong(
            from: sampleDTO(fileKeys: ["song-1/intro-bgm.ogg", "song-1/demo-preview.mp3"]))
        #expect(withSimilar.hasBGM == false)
        #expect(withSimilar.hasPreview == false)
    }

    @Test("Assembles audio URLs from R2 base + id")
    func testAudioURLAssembly() {
        let base = URL(string: "https://r2.example/bucket")!
        #expect(SimfileMapper.bgmURL(base: base, songId: "song-1")
                == URL(string: "https://r2.example/bucket/song-1/bgm.ogg"))
        #expect(SimfileMapper.previewURL(base: base, songId: "song-1")
                == URL(string: "https://r2.example/bucket/song-1/preview.mp3"))
    }

    @Test("Malformed updatedAt falls back to .distantPast (not Date())")
    func testMalformedDateFallback() {
        let song = SimfileMapper.makeServerSong(
            from: SimfileDTO(
                id: "bad-date", title: "T", artist: "A", bpm: 120, genre: nil, tags: [],
                durationSeconds: nil, updatedAt: "not-a-date",
                dtxFiles: [], fileKeys: []
            )
        )
        #expect(song.lastUpdated == .distantPast)
    }

    @Test("Valid fractional ISO8601 date parses correctly")
    func testValidFractionalDate() {
        let song = SimfileMapper.makeServerSong(
            from: SimfileDTO(
                id: "good-date", title: "T", artist: "A", bpm: 120, genre: nil, tags: [],
                durationSeconds: nil, updatedAt: "2026-01-15T10:30:00.123Z",
                dtxFiles: [], fileKeys: []
            )
        )
        let expected = ISO8601DateFormatter()
        expected.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(song.lastUpdated == expected.date(from: "2026-01-15T10:30:00.123Z"))
    }
}
