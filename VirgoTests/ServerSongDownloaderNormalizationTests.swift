//
//  ServerSongDownloaderNormalizationTests.swift
//  VirgoTests
//
//  Caller-side coverage for DTX normalization failure paths exercised through
//  ServerSongDownloader.downloadAndImportSong. Split from ServerSongDownloaderTests
//  to keep that file under SwiftLint size limits.
//

import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("ServerSongDownloader Normalization Failure", .serialized)
@MainActor
struct ServerSongDownloaderNormalizationTests {

    private final class MockFileDownloader: FileDownloading, @unchecked Sendable {
        var responses: [String: Data] = [:]
        func downloadData(from url: URL) async throws -> Data {
            guard let data = responses[url.absoluteString] else {
                throw URLError(.fileDoesNotExist)
            }
            return data
        }
    }

    private let r2Base = "https://r2.example"

    private func makeConfig(_ name: String) -> ServerConfig {
        let (defaults, _) = TestUserDefaults.makeIsolated(suiteName: name)
        return ServerConfig(userDefaults: defaults)
    }

    @Test("downloadAndImportSong persists chart with no notes when normalization overflows")
    func testPersistsEmptyChartWhenNormalizationOverflows() async throws {
        let mock = MockFileDownloader()
        // Grid sizes 65 and 64 are coprime; LCM = 4160 > maximumTicksPerMeasure (4096),
        // so sharedTicksPerMeasure returns nil and normalizedRhythmicEvents() yields [].
        let bassChips = "01" + String(repeating: "00", count: 64) // 65 positions
        let snareChips = "01" + String(repeating: "00", count: 63) // 64 positions
        let dtxContent = """
        #TITLE: Overflow Grid
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #00113: \(bassChips)
        #00112: \(snareChips)
        """
        let dtx = dtxContent.data(using: .shiftJIS) ?? Data(dtxContent.utf8)
        mock.responses["\(r2Base)/overflow/chart.dtx"] = dtx
        let config = makeConfig("ServerSongDownloaderNorm.overflow.\(UUID().uuidString)")
        let downloader = ServerSongDownloader(
            downloader: mock,
            fileManager: ServerSongFileManager(),
            config: config
        )

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let serverChart = ServerChart(
                difficulty: "easy", difficultyLabel: "Easy", level: 10,
                filename: "chart.dtx", size: 100,
                fileURL: "\(r2Base)/overflow/chart.dtx", fileEncoding: "SHIFT_JIS"
            )
            let serverSong = ServerSong(
                songId: "overflow", title: "Overflow Grid", artist: "Tester", bpm: 120.0,
                charts: [serverChart], isDownloaded: false
            )

            let (success, errorMessage) = await downloader.downloadAndImportSong(
                serverSong, container: container
            )
            #expect(success, "Import should not crash when normalization overflows: \(errorMessage ?? "nil")")
            #expect(errorMessage == nil)

            let verificationContext = ModelContext(container)
            let songs = try verificationContext.fetch(FetchDescriptor<Song>())
            let importedSong = songs.first { $0.title == "Overflow Grid" && $0.artist == "Tester" }
            #expect(importedSong != nil, "Song should still be persisted despite normalization overflow")

            let allCharts = try verificationContext.fetch(FetchDescriptor<Chart>())
            let importedChart = allCharts.first { $0.song?.title == "Overflow Grid" }
            #expect(importedChart != nil, "Chart should be persisted despite normalization overflow")
            #expect(
                importedChart?.notes.isEmpty ?? true,
                "Chart should have no notes when normalization overflows"
            )
        }
    }
}
