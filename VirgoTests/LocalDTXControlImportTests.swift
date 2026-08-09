//
//  LocalDTXControlImportTests.swift
//  VirgoTests
//
//  Extracted from LocalDTXFixtureImporterTests to keep that file under the
//  SwiftLint file-length limit. Covers VIRGO_CONTROL header parsing through
//  the local DTX importer: fresh import and multi-difficulty routing.
//

import Foundation
import SwiftData
import Testing
@testable import Virgo

@Suite("Local DTX Control Import Tests", .serialized)
@MainActor
struct LocalDTXControlImportTests {
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
        // Controls from easy do not leak to adv and vice versa.
        #expect(easy?.controlEvents.first?.targetLaneID == "16")
        #expect(adv?.controlEvents.first?.targetLaneID == "12")
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-dtx-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
