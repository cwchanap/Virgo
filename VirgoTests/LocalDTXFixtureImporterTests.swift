//
//  LocalDTXFixtureImporterTests.swift
//  VirgoTests
//

import Foundation
import SwiftData
import Testing
@testable import Virgo

@Suite("Local DTX Fixture Importer Tests", .serialized)
@MainActor
struct LocalDTXFixtureImporterTests {
    @Test("imports Soukyuu fixture with four playable charts")
    func importsSoukyuuFixtureWithFourPlayableCharts() throws {
        let store = try makeStore()
        let context = store.context
        let fixtureURL = try soukyuuFixtureURL()

        let song = try LocalDTXFixtureImporter.importSong(from: fixtureURL, into: context)

        #expect(song.title == "蒼穹への翔歌")
        #expect(song.artist == "hapadona feat. Suno AI")
        #expect(song.bpm == 165.55)
        #expect(song.genre == "DTX Import")
        #expect(song.isServerImported)
        #expect(song.serverSongId == "soukyuu_e_no_shouka")
        #expect(song.bgmFilePath?.hasSuffix("bgm.m4a") == true)
        #expect(song.previewFilePath?.hasSuffix("preview.mp3") == true)
        #expect((song.bgmStartOffsetSeconds ?? 0) > 0)

        let charts = song.charts.sorted { $0.difficulty.sortOrder < $1.difficulty.sortOrder }
        #expect(charts.map(\.difficulty) == [.easy, .medium, .hard, .expert])
        #expect(charts.map(\.level) == [36, 60, 74, 87])
        #expect(charts.allSatisfy { $0.notesCount > 0 })
    }

    @Test("does not duplicate Soukyuu fixture when already imported")
    func doesNotDuplicateSoukyuuFixtureWhenAlreadyImported() throws {
        let store = try makeStore()
        let context = store.context
        let fixtureURL = try soukyuuFixtureURL()

        _ = try LocalDTXFixtureImporter.importSong(from: fixtureURL, into: context)
        _ = try LocalDTXFixtureImporter.importSong(from: fixtureURL, into: context)

        let songs = try context.fetch(FetchDescriptor<Song>())
        #expect(songs.count == 1)
    }

    @Test("refreshes stale Soukyuu audio paths when already imported")
    func refreshesStaleSoukyuuAudioPathsWhenAlreadyImported() throws {
        let store = try makeStore()
        let context = store.context
        let fixtureURL = try soukyuuFixtureURL()
        let staleSong = Song(
            title: "蒼穹への翔歌",
            artist: "hapadona feat. Suno AI",
            bpm: 165.55,
            duration: "3:50",
            genre: "DTX Import",
            timeSignature: .fourFour,
            isServerImported: true,
            serverSongId: LocalDTXFixtureImporter.soukyuuSongId,
            bgmFilePath: fixtureURL.appendingPathComponent("bgm.ogg").path,
            previewFilePath: nil
        )
        context.insert(staleSong)
        try context.save()

        let song = try LocalDTXFixtureImporter.importSong(from: fixtureURL, into: context)

        #expect(song.bgmFilePath?.hasSuffix("bgm.m4a") == true)
        #expect(song.previewFilePath?.hasSuffix("preview.mp3") == true)
    }

    @Test("importSong drops charts whose difficulty label is not recognized")
    func dropsChartsWithUnrecognizedDifficultyLabel() throws {
        let store = try makeStore()
        let tempDir = makeTempDirectory()

        // L1 is a known label (BASIC -> easy); L2 uses an unknown label so it must be
        // dropped rather than imported as a silent missing difficulty.
        let setDef = """
        #TITLE: Partial Drop
        #L1LABEL: BASIC
        #L1FILE: chart1.dtx
        #L2LABEL: CHALLENGE
        #L2FILE: chart2.dtx
        """
        // SET.def is written as UTF-16 to match the bundled fixture format: the
        // importer's `decodeSETFile` tries `.utf16` first and a UTF-8 SET.def would be
        // lossily decoded as garbage CJK, hiding chart references.
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf16)
        let chart1 = "#TITLE: Partial Drop\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 50\n#03113: 01000000"
        try chart1.write(to: tempDir.appendingPathComponent("chart1.dtx"), atomically: true, encoding: .utf8)
        let chart2 = "#TITLE: Partial Drop\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 99\n#03113: 01000000"
        try chart2.write(to: tempDir.appendingPathComponent("chart2.dtx"), atomically: true, encoding: .utf8)

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: store.context)

        #expect(song.charts.count == 1, "Only the BASIC chart should import; CHALLENGE must be dropped")
        #expect(song.charts.first?.difficulty == .easy)
    }

    @Test("re-import clears stale audio paths when the bundled audio is removed")
    func refreshClearsStaleAudioPathsWhenAssetsRemoved() throws {
        let store = try makeStore()
        let tempDir = makeTempDirectory()

        let setDef = """
        #TITLE: Stale Fixture
        #L1LABEL: BASIC
        #L1FILE: chart.dtx
        """
        // UTF-16 to match the bundled fixture format (see comment above).
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf16)
        let chartContent = "#TITLE: Stale Fixture\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 50\n#03113: 01000000"
        try chartContent.write(to: tempDir.appendingPathComponent("chart.dtx"), atomically: true, encoding: .utf8)
        // Simulate a bundle that ships with audio assets.
        try Data().write(to: tempDir.appendingPathComponent("bgm.m4a"))
        try Data().write(to: tempDir.appendingPathComponent("preview.mp3"))

        let first = try LocalDTXFixtureImporter.importSong(from: tempDir, into: store.context)
        #expect(first.bgmFilePath?.hasSuffix("bgm.m4a") == true, "Initial import should record bgm.m4a")
        #expect(first.previewFilePath?.hasSuffix("preview.mp3") == true, "Initial import should record preview.mp3")

        // Remove the assets to simulate a stale-bundle / missing-asset regression.
        // Re-import must not leave a dangling path that would silently disable BGM.
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("bgm.m4a"))
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("preview.mp3"))

        let refreshed = try LocalDTXFixtureImporter.importSong(from: tempDir, into: store.context)

        #expect(refreshed === first, "Re-import should return the existing song")
        #expect(refreshed.bgmFilePath == nil, "Stale bgm path must be cleared when bgm.m4a is absent")
        #expect(refreshed.previewFilePath == nil, "Stale preview path must be cleared when preview.mp3 is absent")
    }

    private struct TestStore {
        let container: ModelContainer
        let context: ModelContext
    }

    private func makeStore() throws -> TestStore {
        let schema = Schema([
            Song.self,
            Chart.self,
            Note.self,
            ServerSong.self,
            ServerChart.self,
            ScoreRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return TestStore(container: container, context: container.mainContext)
    }

    private func soukyuuFixtureURL() throws -> URL {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Virgo/Fixtures/soukyuu_e_no_shouka", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: url.path))
        return url
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-dtx-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
