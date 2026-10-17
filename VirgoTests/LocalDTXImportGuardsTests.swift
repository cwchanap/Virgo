//
//  LocalDTXImportGuardsTests.swift
//  VirgoTests
//
//  Ownership of fresh-import guards: error throws, chart drop/survival,
//  difficulty-label mapping, duration derivation, and error descriptions.
//  Split from LocalDTXFixtureImporterTests to keep that file under the
//  SwiftLint file/type-length limits (HPA-583 review).
//

import Foundation
import SwiftData
import Testing
@testable import Virgo

@Suite("Local DTX Import Guards Tests", .serialized)
@MainActor
struct LocalDTXImportGuardsTests {

    @Test("importSong throws noPlayableCharts when every label is unrecognized")
    func importSongThrowsNoPlayableChartsWhenAllLabelsUnrecognized() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        defer { removeTemp(tempDir) }
        try writeSETDef(
            in: tempDir,
            content: "#TITLE: No Charts\n#L1LABEL: CHALLENGE\n#L1FILE: chart1.dtx\n"
                + "#L2LABEL: ENCORE\n#L2FILE: chart2.dtx\n"
        )
        try writeMinimalChart(in: tempDir, filename: "chart1.dtx", title: "No Charts")
        try writeMinimalChart(in: tempDir, filename: "chart2.dtx", title: "No Charts")

        do {
            _ = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)
            Issue.record("Expected noPlayableCharts error")
        } catch LocalDTXFixtureImportError.noPlayableCharts {
            // Expected: all charts dropped by the unrecognized-label guard.
        } catch {
            Issue.record("Expected .noPlayableCharts but got \(error)")
        }
    }

    @Test("importSong throws noPlayableCharts when the referenced chart file is missing")
    func importSongThrowsNoPlayableChartsWhenChartFileMissing() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        defer { removeTemp(tempDir) }
        try writeSETDef(
            in: tempDir,
            content: "#TITLE: Ghost\n#L1LABEL: BASIC\n#L1FILE: ghost.dtx\n"
        )
        // ghost.dtx is intentionally never created.

        do {
            _ = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)
            Issue.record("Expected noPlayableCharts error")
        } catch LocalDTXFixtureImportError.noPlayableCharts {
            // Expected: the missing-file guard drops the only chart.
        } catch {
            Issue.record("Expected .noPlayableCharts but got \(error)")
        }
    }

    @Test("importSong drops a missing chart file but keeps remaining charts")
    func importSongDropsMissingChartFileButKeepsRemaining() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        defer { removeTemp(tempDir) }
        try writeSETDef(
            in: tempDir,
            content: "#TITLE: Partial\n#L1LABEL: BASIC\n#L1FILE: present.dtx\n"
                + "#L2LABEL: ADVANCED\n#L2FILE: missing.dtx\n"
        )
        try writeMinimalChart(in: tempDir, filename: "present.dtx", title: "Partial")

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        #expect(song.charts.count == 1, "Missing chart file must be dropped; present chart kept")
        #expect(song.charts.first?.difficulty == .easy)
    }

    @Test("importSong drops charts whose difficulty label is not recognized")
    func dropsChartsWithUnrecognizedDifficultyLabel() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        defer { removeTemp(tempDir) }

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

    @Test("duration uses the canonical one-measure timeline when the imported chart has no notes")
    func durationUsesCanonicalTimelineWhenChartHasNoNotes() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        defer { removeTemp(tempDir) }
        try writeSETDef(in: tempDir, content: "#TITLE: Empty\n#L1LABEL: BASIC\n#L1FILE: chart.dtx\n")
        // No note lines still produce the timeline's canonical minimum one measure.
        let chart = "#TITLE: Empty\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 50"
        try chart.write(
            to: tempDir.appendingPathComponent("chart.dtx"),
            atomically: true, encoding: .utf8
        )

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        #expect(song.duration == "0:02")
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

    @Test("LocalizedError descriptions are populated for every error case")
    func errorDescriptionsArePopulated() {
        let url = URL(fileURLWithPath: "/tmp/SET.def")
        let missing = LocalDTXFixtureImportError.missingSETFile(url)
        let unreadable = LocalDTXFixtureImportError.unreadableSETFile(url)
        let noCharts = LocalDTXFixtureImportError.noPlayableCharts("song-42")

        #expect(missing.errorDescription?.contains("Missing SET.def") == true)
        #expect(unreadable.errorDescription?.contains("Unable to decode") == true)
        #expect(noCharts.errorDescription?.contains("song-42") == true)
    }

    // MARK: - Helpers

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

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-dtx-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeTemp(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func writeSETDef(in dir: URL, content: String) throws {
        try content.write(
            to: dir.appendingPathComponent("SET.def"),
            atomically: true, encoding: .utf8
        )
    }

    private func writeMinimalChart(in dir: URL, filename: String, title: String) throws {
        let chart = "#TITLE: \(title)\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 50\n#01111: 01000000"
        try chart.write(to: dir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
    }
}
