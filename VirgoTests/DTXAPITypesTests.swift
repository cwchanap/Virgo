//
//  DTXAPITypesTests.swift
//  VirgoTests
//
//  Tests for the Codable DTX API response types that are decoded from server JSON.
//

import Testing
import Foundation
@testable import Virgo

@Suite("DTX API Types JSON Coding Tests")
struct DTXAPITypesTests {

    // MARK: - DTXFileInfo

    @Test("DTXFileInfo decodes filename and size from JSON")
    func testDTXFileInfoDecoding() throws {
        let json = """
        {"filename": "song.dtx", "size": 4096}
        """
        let data = Data(json.utf8)
        let info = try JSONDecoder().decode(DTXFileInfo.self, from: data)
        #expect(info.filename == "song.dtx")
        #expect(info.size == 4096)
    }

    @Test("DTXFileInfo encodes to JSON with correct keys")
    func testDTXFileInfoEncoding() throws {
        let info = DTXFileInfo(filename: "alpha.dtx", size: 100)
        let data = try JSONEncoder().encode(info)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(dict?["filename"] as? String == "alpha.dtx")
        #expect(dict?["size"] as? Int == 100)
    }

    // MARK: - DTXChartInfo

    @Test("DTXChartInfo decodes all required fields from JSON")
    func testDTXChartInfoDecoding() throws {
        let json = """
        {
          "difficulty": "hard",
          "difficulty_label": "HARD",
          "level": 8,
          "filename": "hard.dtx",
          "size": 2048
        }
        """
        let data = Data(json.utf8)
        let chart = try JSONDecoder().decode(DTXChartInfo.self, from: data)
        #expect(chart.difficulty == "hard")
        #expect(chart.difficultyLabel == "HARD")
        #expect(chart.level == 8)
        #expect(chart.filename == "hard.dtx")
        #expect(chart.size == 2048)
    }

    @Test("DTXChartInfo encodes using snake_case CodingKeys")
    func testDTXChartInfoEncoding() throws {
        let chart = DTXChartInfo(
            difficulty: "easy",
            difficultyLabel: "EASY",
            level: 3,
            filename: "easy.dtx",
            size: 512
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(chart)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(dict?["difficulty"] as? String == "easy")
        #expect(dict?["difficulty_label"] as? String == "EASY")
        #expect(dict?["level"] as? Int == 3)
    }

    // MARK: - DTXSongInfo

    @Test("DTXSongInfo decodes all fields including optional ones")
    func testDTXSongInfoDecodingFull() throws {
        let json = """
        {
          "song_id": "abc123",
          "title": "Test Song",
          "artist": "Test Artist",
          "bpm": 140.0,
          "charts": [
            {
              "difficulty": "normal",
              "difficulty_label": "NORMAL",
              "level": 5,
              "filename": "normal.dtx",
              "size": 1024
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let song = try JSONDecoder().decode(DTXSongInfo.self, from: data)
        #expect(song.songId == "abc123")
        #expect(song.title == "Test Song")
        #expect(song.artist == "Test Artist")
        #expect(song.bpm == 140.0)
        #expect(song.charts.count == 1)
        #expect(song.charts.first?.difficulty == "normal")
    }

    @Test("DTXSongInfo decodes with nil optional fields")
    func testDTXSongInfoDecodingNilOptionals() throws {
        let json = """
        {
          "song_id": "xyz",
          "title": "Minimal",
          "charts": []
        }
        """
        let data = Data(json.utf8)
        let song = try JSONDecoder().decode(DTXSongInfo.self, from: data)
        #expect(song.songId == "xyz")
        #expect(song.title == "Minimal")
        #expect(song.artist == nil)
        #expect(song.bpm == nil)
        #expect(song.charts.isEmpty)
    }

    @Test("DTXSongInfo encodes songId as song_id")
    func testDTXSongInfoEncodesSnakeCaseSongId() throws {
        let song = DTXSongInfo(songId: "id1", title: "T", artist: nil, bpm: nil, charts: [])
        let data = try JSONEncoder().encode(song)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(dict?["song_id"] as? String == "id1")
        #expect(dict?["title"] as? String == "T")
    }

    // MARK: - DTXListResponse

    @Test("DTXListResponse decodes songs and individual_files arrays")
    func testDTXListResponseDecoding() throws {
        let json = """
        {
          "songs": [
            {
              "song_id": "s1",
              "title": "Song One",
              "charts": []
            }
          ],
          "individual_files": [
            {"filename": "extra.dtx", "size": 99}
          ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(DTXListResponse.self, from: data)
        #expect(response.songs.count == 1)
        #expect(response.songs.first?.title == "Song One")
        #expect(response.individualFiles.count == 1)
        #expect(response.individualFiles.first?.filename == "extra.dtx")
    }

    @Test("DTXListResponse decodes empty arrays")
    func testDTXListResponseDecodingEmpty() throws {
        let json = """
        {"songs": [], "individual_files": []}
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(DTXListResponse.self, from: data)
        #expect(response.songs.isEmpty)
        #expect(response.individualFiles.isEmpty)
    }

    @Test("DTXListResponse encodes individualFiles as individual_files")
    func testDTXListResponseEncodingKey() throws {
        let response = DTXListResponse(songs: [], individualFiles: [])
        let data = try JSONEncoder().encode(response)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(dict?["individual_files"] != nil)
        #expect(dict?["songs"] != nil)
    }

    // MARK: - DTXMetadataInfo

    @Test("DTXMetadataInfo decodes all optional fields")
    func testDTXMetadataInfoDecodingFull() throws {
        let json = """
        {"title": "Meta Title", "artist": "Meta Artist", "bpm": 120.0, "level": 7}
        """
        let data = Data(json.utf8)
        let meta = try JSONDecoder().decode(DTXMetadataInfo.self, from: data)
        #expect(meta.title == "Meta Title")
        #expect(meta.artist == "Meta Artist")
        #expect(meta.bpm == 120.0)
        #expect(meta.level == 7)
    }

    @Test("DTXMetadataInfo decodes when all fields are null")
    func testDTXMetadataInfoDecodingAllNil() throws {
        let json = """
        {"title": null, "artist": null, "bpm": null, "level": null}
        """
        let data = Data(json.utf8)
        let meta = try JSONDecoder().decode(DTXMetadataInfo.self, from: data)
        #expect(meta.title == nil)
        #expect(meta.artist == nil)
        #expect(meta.bpm == nil)
        #expect(meta.level == nil)
    }

    // MARK: - DTXMetadataResponse

    @Test("DTXMetadataResponse decodes filename and nested metadata")
    func testDTXMetadataResponseDecoding() throws {
        let json = """
        {
          "filename": "track.dtx",
          "metadata": {
            "title": "Track Title",
            "artist": null,
            "bpm": 150.5,
            "level": 9
          }
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(DTXMetadataResponse.self, from: data)
        #expect(response.filename == "track.dtx")
        #expect(response.metadata.title == "Track Title")
        #expect(response.metadata.artist == nil)
        #expect(response.metadata.bpm == 150.5)
        #expect(response.metadata.level == 9)
    }

    // MARK: - Round-trip encoding/decoding

    @Test("DTXListResponse round-trips through JSON encoding and decoding")
    func testDTXListResponseRoundTrip() throws {
        let original = DTXListResponse(
            songs: [
                DTXSongInfo(
                    songId: "rt1",
                    title: "Round Trip",
                    artist: "Artist",
                    bpm: 128.0,
                    charts: [
                        DTXChartInfo(
                            difficulty: "medium",
                            difficultyLabel: "MEDIUM",
                            level: 6,
                            filename: "med.dtx",
                            size: 777
                        )
                    ]
                )
            ],
            individualFiles: [DTXFileInfo(filename: "solo.dtx", size: 42)]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DTXListResponse.self, from: data)

        #expect(decoded.songs.count == 1)
        #expect(decoded.songs.first?.songId == "rt1")
        #expect(decoded.songs.first?.title == "Round Trip")
        #expect(decoded.songs.first?.artist == "Artist")
        #expect(decoded.songs.first?.bpm == 128.0)
        #expect(decoded.songs.first?.charts.first?.difficulty == "medium")
        #expect(decoded.songs.first?.charts.first?.level == 6)
        #expect(decoded.individualFiles.first?.filename == "solo.dtx")
        #expect(decoded.individualFiles.first?.size == 42)
    }
}
