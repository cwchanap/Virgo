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
        let context = TestContainer.isolatedContainer().context
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

        // Duration must be derived from the chart BPM (165.55) rather than the old
        // hard-coded 2 sec/measure assumption (which only holds at 120 BPM). All four
        // Soukyuu charts reach measure 156 (0-based raw DTX measure index), so the
        // expected total is 157 measures × (4 × 60 / 165.55) ≈ 227.6s → "3:47".
        // The old 120-BPM math produced "5:14", which made gameplay progress run well
        // past the audio end because calculateTrackDurationInSeconds trusts this field.
        #expect(
            song.duration == "3:47",
            "Soukyuu duration should be BPM-derived (3:47 at 165.55 BPM), not the 120-BPM '5:14' value"
        )

        let charts = song.charts.sorted { $0.difficulty.sortOrder < $1.difficulty.sortOrder }
        #expect(charts.map(\.difficulty) == [.easy, .medium, .hard, .expert])
        #expect(charts.map(\.level) == [36, 60, 74, 87])
        #expect(charts.allSatisfy { $0.notesCount > 0 })
    }

    @Test("does not duplicate Soukyuu fixture when already imported")
    func doesNotDuplicateSoukyuuFixtureWhenAlreadyImported() throws {
        let context = TestContainer.isolatedContainer().context
        let fixtureURL = try soukyuuFixtureURL()

        _ = try LocalDTXFixtureImporter.importSong(from: fixtureURL, into: context)
        _ = try LocalDTXFixtureImporter.importSong(from: fixtureURL, into: context)

        let songs = try context.fetch(FetchDescriptor<Song>())
        #expect(songs.count == 1)
    }

    @Test("refreshes stale Soukyuu audio paths when already imported")
    func refreshesStaleSoukyuuAudioPathsWhenAlreadyImported() throws {
        let context = TestContainer.isolatedContainer().context
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
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()

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

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        #expect(song.charts.count == 1, "Only the BASIC chart should import; CHALLENGE must be dropped")
        #expect(song.charts.first?.difficulty == .easy)
    }

    @Test("re-import clears stale audio paths when the bundled audio is removed")
    func refreshClearsStaleAudioPathsWhenAssetsRemoved() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()

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

        let first = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)
        #expect(first.bgmFilePath?.hasSuffix("bgm.m4a") == true, "Initial import should record bgm.m4a")
        #expect(first.previewFilePath?.hasSuffix("preview.mp3") == true, "Initial import should record preview.mp3")

        // Remove the assets to simulate a stale-bundle / missing-asset regression.
        // Re-import must not leave a dangling path that would silently disable BGM.
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("bgm.m4a"))
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("preview.mp3"))

        let refreshed = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        #expect(refreshed === first, "Re-import should return the existing song")
        #expect(refreshed.bgmFilePath == nil, "Stale bgm path must be cleared when bgm.m4a is absent")
        #expect(refreshed.previewFilePath == nil, "Stale preview path must be cleared when preview.mp3 is absent")
    }

    @Test("re-import backfills missing BGM start offset on an existing legacy record")
    func reImportBackfillsMissingBGMStartOffset() throws {
        let context = TestContainer.isolatedContainer().context
        let fixtureURL = try soukyuuFixtureURL()

        // Simulate a legacy record created before BGM-offset parsing existed: same
        // serverSongId, nil offset, and already-correct audio paths so refreshAudioPaths
        // makes no change. Without the refresh-path backfill this record would keep nil
        // (and fall back to the note-position heuristic in calculateBGMOffset) while a
        // fresh import gets the authoritative parsed offset — an audible sync drift.
        let legacy = Song(
            title: "蒼穹への翔歌",
            artist: "legacy",
            bpm: 165.55,
            duration: "3:50",
            genre: "DTX Import",
            timeSignature: .fourFour,
            isServerImported: true,
            serverSongId: LocalDTXFixtureImporter.soukyuuSongId,
            bgmFilePath: fixtureURL.appendingPathComponent("bgm.m4a").path,
            previewFilePath: fixtureURL.appendingPathComponent("preview.mp3").path,
            bgmStartOffsetSeconds: nil
        )
        context.insert(legacy)
        try context.save()

        let refreshed = try LocalDTXFixtureImporter.importSong(from: fixtureURL, into: context)

        #expect(refreshed === legacy, "Re-import should return the existing song, not a duplicate")
        #expect(
            (refreshed.bgmStartOffsetSeconds ?? 0) > 0,
            "Re-import must backfill the parsed BGM offset on a legacy nil-offset record"
        )
    }

    @Test("re-import does not clobber an already-set BGM start offset")
    func reImportDoesNotClobberExistingBGMStartOffset() throws {
        let context = TestContainer.isolatedContainer().context
        let fixtureURL = try soukyuuFixtureURL()

        // An existing record that already has a positive offset must be left alone —
        // refreshBGMStartOffsetIfMissing's guard returns early so it neither re-parses
        // nor overrides (first-positive-wins contract from setBGMStartOffsetIfUnset).
        let existing = Song(
            title: "蒼穹への翔歌",
            artist: "existing",
            bpm: 165.55,
            duration: "3:50",
            genre: "DTX Import",
            timeSignature: .fourFour,
            isServerImported: true,
            serverSongId: LocalDTXFixtureImporter.soukyuuSongId,
            bgmFilePath: fixtureURL.appendingPathComponent("bgm.m4a").path,
            previewFilePath: fixtureURL.appendingPathComponent("preview.mp3").path,
            bgmStartOffsetSeconds: 0.42
        )
        context.insert(existing)
        try context.save()

        let refreshed = try LocalDTXFixtureImporter.importSong(from: fixtureURL, into: context)

        #expect(refreshed === existing)
        #expect(
            refreshed.bgmStartOffsetSeconds == 0.42,
            "An already-set offset must not be overwritten by re-import"
        )
    }

    @Test("importSong decodes a BOM-less UTF-8 SET.def without lossy UTF-16 garbage")
    func decodesUTF8SETDefWithoutBOM() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()

        // UTF-8 with no BOM. Before the BOM-aware decodeSETFile fix, the lazy
        // [.utf16, ...].first chain *lossily succeeded* on these bytes as garbage CJK
        // (containing no #LxLABEL/#LxFILE directives), so the importer rejected the
        // fixture with noPlayableCharts. The fix gates UTF-16 behind an actual BOM and
        // falls through to strict UTF-8 for BOM-less files.
        let setDef = """
        #TITLE: UTF8 Fixture
        #L1LABEL: BASIC
        #L1FILE: chart.dtx
        """
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf8)
        let chart = "#TITLE: UTF8 Fixture\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 50\n#03113: 01000000"
        try chart.write(to: tempDir.appendingPathComponent("chart.dtx"), atomically: true, encoding: .utf8)

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        #expect(song.charts.count == 1, "BOM-less UTF-8 SET.def must decode correctly, not be rejected as garbage")
        #expect(song.charts.first?.difficulty == .easy)
    }

    @Test("locateSETFile finds SET.def nested in a subdirectory (folder-reference layout)")
    func locateSETFileFindsNestedSETDef() throws {
        // Simulates a bundle laid out as a folder reference — the fixture's directory
        // structure is preserved (Fixtures/soukyuu/...) instead of being flattened into
        // the resource root. The 2-arg `Bundle.url(forResource:withExtension:)` cannot
        // recurse into this, so the importer's `locateBundledSETDef` falls back to the
        // whole-bundle walk implemented by `locateSETFile`. Constructing a loadable
        // `Bundle` with this layout in-process is impractical; the filesystem walk is
        // the unit that needs coverage here.
        let bundleRoot = try makeTempDirectory()
        let fixtureDir = bundleRoot
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("soukyuu_e_no_shouka", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let setDef = "#TITLE: Nested\n#L1LABEL: BASIC\n#L1FILE: chart.dtx\n"
        try setDef.write(to: fixtureDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf8)

        let found = LocalDTXFixtureImporter.locateSETFile(in: bundleRoot)

        #expect(found?.lastPathComponent == "SET.def", "Enumeration fallback should find the nested SET.def")
        #expect(
            found?.deletingLastPathComponent().lastPathComponent == "soukyuu_e_no_shouka",
            "Should locate SET.def inside the preserved fixture directory"
        )
    }

    @Test("locateSETFile returns nil when no SET.def exists in the tree")
    func locateSETFileReturnsNilWhenAbsent() throws {
        let bundleRoot = try makeTempDirectory()
        // A directory with other files but no SET.def.
        try Data().write(to: bundleRoot.appendingPathComponent("chart.dtx"))

        #expect(LocalDTXFixtureImporter.locateSETFile(in: bundleRoot) == nil)
    }

    @Test("importSong derives duration from chart BPM, not a hard-coded 2 sec/measure")
    func durationDerivedFromChartBPM() throws {
        // Two synthetic fixtures with the same measure layout but different BPMs must
        // produce proportionally different durations. The old `calculateDuration`
        // hard-coded 120 BPM (2 sec/measure), so a 200-BPM chart was overstated by
        // 67% and gameplay progress kept running past the audio end. Both fixtures
        // place a single note in raw measure 99 (0-based), so total measures = 100.
        let slow = try importSyntheticFixture(
            bpm: 120.0, label: "SLOW", into: TestContainer.isolatedContainer().context
        )
        let fast = try importSyntheticFixture(
            bpm: 200.0, label: "FAST", into: TestContainer.isolatedContainer().context
        )

        // 100 measures × (4 × 60 / BPM):
        //   120 BPM → 200.0s → "3:20"
        //   200 BPM → 120.0s → "2:00"
        // The old code produced "3:20" for both.
        #expect(slow.duration == "3:20", "120 BPM @ 100 measures = 200s = 3:20")
        #expect(fast.duration == "2:00", "200 BPM @ 100 measures = 120s = 2:00")
        #expect(
            fast.duration != slow.duration,
            "Duration must vary with BPM, not be the fixed 2 sec/measure value"
        )
    }

    @discardableResult
    private func importSyntheticFixture(
        bpm: Double, label: String, into context: ModelContext
    ) throws -> Song {
        let tempDir = try makeTempDirectory()
        let setDef = """
        #TITLE: \(label)
        #L1LABEL: BASIC
        #L1FILE: chart.dtx
        """
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf8)
        // Raw measure index 099 in DTX is 0-based; importer uses (maxMeasure + 1) = 100.
        let chart = "#TITLE: \(label)\n#ARTIST: Tester\n#BPM: \(bpm)\n#DLEVEL: 50\n#09911: 01000000"
        try chart.write(to: tempDir.appendingPathComponent("chart.dtx"), atomically: true, encoding: .utf8)
        return try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)
    }

    private func soukyuuFixtureURL() throws -> URL {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Virgo/Fixtures/soukyuu_e_no_shouka", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: url.path))
        return url
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-dtx-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
