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
        #expect(song.bgmStartOffsetSeconds == nil)

        // Duration comes from the same canonical timeline end used by gameplay,
        // rather than fixed 4/4 measure arithmetic.
        // The old 120-BPM math produced "5:14", which made gameplay progress run well
        // past the audio end because calculateTrackDurationInSeconds trusts this field.
        #expect(
            song.duration == "3:46",
            "Soukyuu duration should come from the canonical timeline, not the old '5:14' value"
        )

        let charts = song.charts.sorted { $0.difficulty.sortOrder < $1.difficulty.sortOrder }
        #expect(charts.map(\.difficulty) == [.easy, .medium, .hard, .expert])
        #expect(charts.map(\.level) == [36, 60, 74, 87])
        #expect(charts.allSatisfy { $0.notesCount > 0 })
        #expect(charts.allSatisfy { $0.rhythmMetadataData != nil })
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

    @Test("re-import refreshes audio paths without repairing persisted graph data")
    func reImportRefreshesOnlyAudioPaths() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()

        try """
        #TITLE: Current Source
        #L1LABEL: BASIC
        #L1FILE: chart.dtx
        """.write(
            to: tempDir.appendingPathComponent("SET.def"),
            atomically: true,
            encoding: .utf8
        )

        try """
        #TITLE: Current Source
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00012: 01000000
        #00022: 16000000
        """.write(
            to: tempDir.appendingPathComponent("chart.dtx"),
            atomically: true,
            encoding: .utf8
        )

        let currentBGM = tempDir.appendingPathComponent("bgm.m4a")
        let currentPreview = tempDir.appendingPathComponent("preview.mp3")
        try Data().write(to: currentBGM)
        try Data().write(to: currentPreview)

        let existing = Song(
            title: "Legacy Local State",
            artist: "Legacy Artist",
            bpm: 90,
            duration: "9:59",
            genre: "DTX Import",
            timeSignature: .fourFour,
            isServerImported: false,
            serverSongId: tempDir.lastPathComponent,
            bgmFilePath: "/old-container/bgm.m4a",
            previewFilePath: "/old-container/preview.mp3",
            bgmStartOffsetSeconds: 0.42
        )
        let chart = Chart(difficulty: .easy, level: 50, song: existing)
        let note = Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: 0,
            chart: chart
        )
        chart.notes = [note]
        existing.charts = [chart]
        context.insert(existing)
        context.insert(chart)
        context.insert(note)
        try context.save()

        #expect(chart.rhythmMetadataData == nil)
        #expect(chart.safeControlEvents.isEmpty)

        let returned = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        #expect(returned === existing)
        #expect(returned.bgmFilePath == currentBGM.path)
        #expect(returned.previewFilePath == currentPreview.path)
        #expect(returned.duration == "9:59")
        #expect(returned.isServerImported == false)
        #expect(returned.bgmStartOffsetSeconds == 0.42)
        #expect(returned.charts.count == 1)
        #expect(returned.charts.first === chart)
        #expect(chart.safeNotes.count == 1)
        #expect(chart.safeNotes.first === note)
        #expect(chart.safeControlEvents.isEmpty)
        #expect(chart.rhythmMetadataData == nil)
        #expect(try context.fetch(FetchDescriptor<Song>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Chart>()).count == 1)
    }

    @Test("re-import clears stale audio paths when current assets are removed")
    func refreshClearsStaleAudioPathsWhenAssetsRemoved() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()

        let setDef = """
        #TITLE: Stale Fixture
        #L1LABEL: BASIC
        #L1FILE: chart.dtx
        """
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf16)
        let chartContent =
            "#TITLE: Stale Fixture\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 50\n#03113: 01000000"
        try chartContent.write(
            to: tempDir.appendingPathComponent("chart.dtx"),
            atomically: true,
            encoding: .utf8
        )
        try Data().write(to: tempDir.appendingPathComponent("bgm.m4a"))
        try Data().write(to: tempDir.appendingPathComponent("preview.mp3"))

        let first = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)
        #expect(first.bgmFilePath?.hasSuffix("bgm.m4a") == true)
        #expect(first.previewFilePath?.hasSuffix("preview.mp3") == true)

        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("bgm.m4a"))
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("preview.mp3"))

        let returned = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        #expect(returned === first)
        #expect(returned.bgmFilePath == nil)
        #expect(returned.previewFilePath == nil)
    }

    @Test("re-import leaves an unset BGM start offset unset")
    func reImportLeavesUnsetBGMStartOffsetUnset() throws {
        let context = TestContainer.isolatedContainer().context
        let fixtureURL = try soukyuuFixtureURL()
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
            bgmStartOffsetSeconds: nil
        )
        context.insert(existing)
        try context.save()

        let returned = try LocalDTXFixtureImporter.importSong(from: fixtureURL, into: context)

        #expect(returned === existing)
        #expect(returned.bgmStartOffsetSeconds == nil)
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
        // Exercise the bundled fixture's UTF-16 format. The importer only selects
        // UTF-16 when a BOM is present; BOM-less sources take the UTF-8/Shift-JIS path.
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf16)
        let chart1 = "#TITLE: Partial Drop\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 50\n#03113: 01000000"
        try chart1.write(to: tempDir.appendingPathComponent("chart1.dtx"), atomically: true, encoding: .utf8)
        let chart2 = "#TITLE: Partial Drop\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 99\n#03113: 01000000"
        try chart2.write(to: tempDir.appendingPathComponent("chart2.dtx"), atomically: true, encoding: .utf8)

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        #expect(song.charts.count == 1, "Only the BASIC chart should import; CHALLENGE must be dropped")
        #expect(song.charts.first?.difficulty == .easy)
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

    @Test("fresh import persists valid rhythm payload and canonical timing without song BGM offset")
    func freshImportPersistsCanonicalRhythmTiming() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        try """
        #TITLE: Canonical Local
        #L1LABEL: BASIC
        #L1FILE: chart.dtx
        """.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf8)
        try """
        #TITLE: Canonical Local
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 40
        #VIRGO_TIME_SIGNATURE: 6/8
        #VIRGO_CONTROL: 1
        #00102: 0.5
        #00001: 0001
        #00012: 01000000
        #00122: 00160000
        #00113: 00000100
        """.write(to: tempDir.appendingPathComponent("chart.dtx"), atomically: true, encoding: .utf8)

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)
        let chart = try #require(song.charts.first)

        #expect(song.bgmStartOffsetSeconds == nil)
        #expect(chart.timeSignature == .sixEight)
        guard case let .valid(metadata) = chart.rhythmMetadataState else {
            Issue.record("Expected a persisted rhythm metadata payload")
            return
        }
        #expect(metadata.timingStatus == .valid)
        #expect(metadata.bgmStartAnchor != nil)
        #expect(Set(chart.notes.compactMap(\.normalizedAbsoluteTick)) == Set([0, 16]))
        #expect(Set(chart.notes.compactMap(\.normalizedTicksPerMeasure)) == Set([8, 12]))
        let control = try #require(chart.controlEvents.first)
        #expect(control.normalizedMeasureIndex == 1)
        #expect(control.normalizedAbsoluteTick == 14)
        #expect(control.normalizedTickWithinMeasure == 2)
        #expect(control.normalizedTicksPerMeasure == 8)
    }

    @Test("fresh timing-fatal import keeps identifiable chart and source values")
    func freshFatalImportKeepsIdentifiableChart() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        try """
        #TITLE: Fatal Local
        #L1LABEL: BASIC
        #L1FILE: chart.dtx
        """.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf8)
        try """
        #TITLE: Fatal Local
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 40
        #VIRGO_CONTROL: 1
        #00102: 0
        #00112: 0100
        #00122: 0016
        """.write(to: tempDir.appendingPathComponent("chart.dtx"), atomically: true, encoding: .utf8)

        let result = try LocalDTXFixtureImporter.importSongResult(from: tempDir, into: context)
        let song = result.song
        let chart = try #require(song.charts.first)

        let warning = try #require(result.warnings.first)
        #expect(result.warnings.count == 1)
        #expect(warning.chartFilename == "chart.dtx")
        #expect(warning.message.contains("Unsupported chart timing"))
        #expect(warning.message.contains("measure 2"))
        #expect(warning.message.contains("measure length must be positive"))
        guard case let .valid(metadata) = chart.rhythmMetadataState else {
            Issue.record("Expected fatal diagnostics to be persisted")
            return
        }
        #expect(metadata.timingStatus == .fatal)
        #expect(!metadata.diagnostics.isEmpty)
        let note = try #require(chart.notes.first)
        #expect(note.sourceLaneID == "12")
        #expect(note.sourceGridSize == 2)
        #expect(note.normalizedMeasureIndex == nil)
        #expect(note.normalizedAbsoluteTick == nil)
        #expect(note.normalizedTickWithinMeasure == nil)
        #expect(note.normalizedTicksPerMeasure == nil)
        let control = try #require(chart.controlEvents.first)
        #expect(control.sourceLaneID == "22")
        #expect(control.normalizedAbsoluteTick == nil)
        #expect(RhythmTimelineResolver().resolve(chart: chart).availability == .fatal)
    }

    // Control-event import/routing tests live in
    // LocalDTXControlImportTests.swift, extracted to keep this file under the
    // SwiftLint file-length limit.

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
