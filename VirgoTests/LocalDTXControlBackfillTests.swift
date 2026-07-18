//
//  LocalDTXControlBackfillTests.swift
//  VirgoTests
//
//  Extracted from LocalDTXFixtureImporterTests to keep that file under the
//  SwiftLint file-length limit. Covers VIRGO_CONTROL header parsing through
//  the local DTX importer: fresh import, backfill, first-wins semantics, and
//  multi-difficulty routing.
//

import Foundation
import SwiftData
import Testing
@testable import Virgo

@Suite("Local DTX Control Backfill Tests", .serialized)
@MainActor
struct LocalDTXControlBackfillTests {
    @Test("fresh import populates controlEvents when DTX has VIRGO_CONTROL header")
    func freshImportPopulatesControlEvents() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()

        let setDef = """
        #TITLE: Control Song
        #L1LABEL: BASIC
        #L1FILE: chart.dtx
        """
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf16)
        let chartContent = """
        #TITLE: Control Song
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00012: 01000000
        #00022: 16000000
        """
        try chartContent.write(to: tempDir.appendingPathComponent("chart.dtx"), atomically: true, encoding: .utf8)

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        let chart = try #require(song.charts.first)
        #expect(chart.notes.count == 1)
        #expect(chart.controlEvents.count == 1)
        let control = try #require(chart.controlEvents.first)
        #expect(control.kind == .choke)
        #expect(control.targetLaneID == "16")
    }

    @Test("refreshControlEventsIfMissing backfills controls on existing import")
    func refreshBackfillsControls() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()

        let setDef = """
        #TITLE: Backfill Song
        #L1LABEL: BASIC
        #L1FILE: chart.dtx
        """
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf16)
        let chartWithControls = """
        #TITLE: Backfill Song
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00022: 16000000
        """
        try chartWithControls.write(to: tempDir.appendingPathComponent("chart.dtx"), atomically: true, encoding: .utf8)

        // First import WITH header but the chart has no controls yet — simulate
        // a pre-feature import by manually creating the song/chart without controls.
        let song = Song(
            title: "Backfill Song", artist: "Tester", bpm: 120, duration: "1:00",
            genre: "DTX Import", timeSignature: .fourFour,
            isServerImported: true, serverSongId: tempDir.lastPathComponent
        )
        let chart = Chart(difficulty: .easy, level: 50, song: song)
        chart.notes = [Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0, chart: chart)]
        song.charts = [chart]
        context.insert(song)
        context.insert(chart)
        try context.save()

        #expect(chart.controlEvents.isEmpty)

        // Re-import triggers refreshControlEventsIfMissing
        _ = try LocalDTXFixtureImporter.importSong(
            from: tempDir, songId: tempDir.lastPathComponent, into: context
        )

        #expect(chart.controlEvents.count == 1)
        #expect(chart.controlEvents.first?.kind == .choke)

        // Idempotent: second re-import does not duplicate
        _ = try LocalDTXFixtureImporter.importSong(
            from: tempDir, songId: tempDir.lastPathComponent, into: context
        )
        #expect(chart.controlEvents.count == 1)
    }

    @Test("refreshControlEventsIfMissing is first-wins: edited control lanes do not propagate")
    func refreshControlsFirstWinsOnEditedDTX() throws {
        // Pins the documented known limitation: backfill is first-wins, so editing
        // a DTX file's control lanes (adding, removing, or changing them) does NOT
        // propagate to an existing chart that already has controls. The upgrade
        // path for edited control lanes is delete-and-reimport. If this test
        // fails, the backfill contract changed to diff-and-replace — update the
        // spec's known-limitation section accordingly.
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()

        let setDef = """
        #TITLE: First Wins
        #L1LABEL: BASIC
        #L1FILE: chart.dtx
        """
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf16)

        // Initial chart: a choke control targeting Crash (lane 16).
        let originalChart = """
        #TITLE: First Wins
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00022: 16000000
        """
        try originalChart.write(
            to: tempDir.appendingPathComponent("chart.dtx"), atomically: true, encoding: .utf8
        )

        // Fresh import establishes the control.
        _ = try LocalDTXFixtureImporter.importSong(
            from: tempDir, songId: tempDir.lastPathComponent, into: context
        )
        let song = try context.fetch(FetchDescriptor<Song>())
            .first { $0.serverSongId == tempDir.lastPathComponent }
        let chart = try #require(song?.charts.first)
        #expect(chart.controlEvents.count == 1)
        #expect(chart.controlEvents.first?.kind == .choke)
        #expect(chart.controlEvents.first?.targetLaneID == "16")

        // Edit the DTX file: replace the choke with a stop targeting Hi-Hat (lane 12).
        let editedChart = """
        #TITLE: First Wins
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00021: 12000000
        """
        try editedChart.write(
            to: tempDir.appendingPathComponent("chart.dtx"), atomically: true, encoding: .utf8
        )

        // Re-import: first-wins means the edited control lane does NOT replace the
        // existing control. The original choke targeting Crash is retained.
        _ = try LocalDTXFixtureImporter.importSong(
            from: tempDir, songId: tempDir.lastPathComponent, into: context
        )

        #expect(chart.controlEvents.count == 1)
        #expect(chart.controlEvents.first?.kind == .choke)
        #expect(chart.controlEvents.first?.targetLaneID == "16")
    }

    @Test("multi-difficulty fresh import routes controls to the correct chart")
    func multiDifficultyFreshImportRoutesCorrectly() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()

        let setDef = """
        #TITLE: Multi Diff
        #L1LABEL: BASIC
        #L1FILE: easy.dtx
        #L2LABEL: ADVANCED
        #L2FILE: adv.dtx
        """
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf16)
        let easyChart = """
        #TITLE: Multi Diff
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 30
        #VIRGO_CONTROL: 1
        #00021: 16000000
        """
        try easyChart.write(to: tempDir.appendingPathComponent("easy.dtx"), atomically: true, encoding: .utf8)
        let advChart = """
        #TITLE: Multi Diff
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 60
        #VIRGO_CONTROL: 1
        #00022: 12000000
        """
        try advChart.write(to: tempDir.appendingPathComponent("adv.dtx"), atomically: true, encoding: .utf8)

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        let easy = song.charts.first { $0.difficulty == .easy }
        let adv = song.charts.first { $0.difficulty == .medium }

        #expect(easy?.controlEvents.count == 1)
        #expect(easy?.controlEvents.first?.kind == .stop)
        #expect(adv?.controlEvents.count == 1)
        #expect(adv?.controlEvents.first?.kind == .choke)
        // Controls from easy do not leak to adv and vice versa
        #expect(easy?.controlEvents.first?.targetLaneID == "16")
        #expect(adv?.controlEvents.first?.targetLaneID == "12")
    }

    @Test("multi-difficulty backfill routes controls to the correct existing chart")
    // swiftlint:disable:next function_body_length
    func multiDifficultyBackfillRoutesCorrectly() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()

        let setDef = """
        #TITLE: Multi Diff
        #L1LABEL: BASIC
        #L1FILE: easy.dtx
        #L2LABEL: ADVANCED
        #L2FILE: adv.dtx
        """
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf16)
        let easyChart = """
        #TITLE: Multi Diff
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 30
        #VIRGO_CONTROL: 1
        #00021: 16000000
        """
        try easyChart.write(to: tempDir.appendingPathComponent("easy.dtx"), atomically: true, encoding: .utf8)
        let advChart = """
        #TITLE: Multi Diff
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 60
        #VIRGO_CONTROL: 1
        #00022: 12000000
        """
        try advChart.write(to: tempDir.appendingPathComponent("adv.dtx"), atomically: true, encoding: .utf8)

        // Pre-seed an existing song with two charts that have notes but NO controlEvents,
        // simulating a legacy import created before VIRGO_CONTROL parsing existed. The
        // songId matches tempDir.lastPathComponent so the importer finds this song and
        // takes the backfill branch (refreshControlEventsIfMissing) rather than the
        // fresh-import branch.
        let song = Song(
            title: "Multi Diff", artist: "Tester", bpm: 120, duration: "1:00",
            genre: "DTX Import", timeSignature: .fourFour,
            isServerImported: true, serverSongId: tempDir.lastPathComponent
        )
        let easy = Chart(difficulty: .easy, level: 30, song: song)
        easy.notes = [Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0, chart: easy)]
        let medium = Chart(difficulty: .medium, level: 60, song: song)
        medium.notes = [Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0, chart: medium)]
        song.charts = [easy, medium]
        context.insert(song)
        context.insert(easy)
        context.insert(medium)
        try context.save()

        #expect(easy.controlEvents.isEmpty)
        #expect(medium.controlEvents.isEmpty)

        // Re-import triggers refreshControlEventsIfMissing, which re-parses each DTX
        // file and routes controls to the existing chart matching by difficulty.
        _ = try LocalDTXFixtureImporter.importSong(
            from: tempDir, songId: tempDir.lastPathComponent, into: context
        )

        // easy.dtx lane 21 → stop control targeting crash (lane 16)
        #expect(easy.controlEvents.count == 1)
        #expect(easy.controlEvents.first?.kind == .stop)
        #expect(easy.controlEvents.first?.targetLaneID == "16")
        // adv.dtx lane 22 → choke control targeting hi-hat (lane 12)
        #expect(medium.controlEvents.count == 1)
        #expect(medium.controlEvents.first?.kind == .choke)
        #expect(medium.controlEvents.first?.targetLaneID == "12")
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-dtx-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
