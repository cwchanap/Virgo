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

    @Test("Audio availability comes from file keys (suffix match)")
    func testAudioAvailability() {
        let withBoth = SimfileMapper.makeServerSong(
            from: sampleDTO(fileKeys: ["song-1/bgm.ogg", "song-1/preview.mp3"]))
        #expect(withBoth.hasBGM == true)
        #expect(withBoth.hasPreview == true)

        let withNone = SimfileMapper.makeServerSong(from: sampleDTO(fileKeys: ["song-1/ext.dtx"]))
        #expect(withNone.hasBGM == false)
        #expect(withNone.hasPreview == false)
    }

    @Test("Assembles audio URLs from R2 base + id")
    func testAudioURLAssembly() {
        let base = URL(string: "https://r2.example/bucket")!
        #expect(SimfileMapper.bgmURL(base: base, songId: "song-1")
                == URL(string: "https://r2.example/bucket/song-1/bgm.ogg"))
        #expect(SimfileMapper.previewURL(base: base, songId: "song-1")
                == URL(string: "https://r2.example/bucket/song-1/preview.mp3"))
    }
}
