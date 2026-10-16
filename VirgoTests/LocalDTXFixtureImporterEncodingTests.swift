//
//  LocalDTXFixtureImporterEncodingTests.swift
//  VirgoTests
//
//  Encoding, decodability, and SET.def parsing variants for
//  LocalDTXFixtureImporter, split out of LocalDTXFixtureImporterTests to keep
//  that file under the SwiftLint limits. Covers SET.def presence/decode guards,
//  BOM/decode fallbacks, and tolerant SET.def parsing.
//

import Foundation
import SwiftData
import Testing
@testable import Virgo

@Suite("Local DTX Fixture Importer Encoding Tests", .serialized)
@MainActor
struct LocalDTXFixtureImporterEncodingTests {
    @Test("importSong throws missingSETFile when SET.def is absent")
    func importSongThrowsMissingSETFileWhenSETDefAbsent() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        defer { removeTemp(tempDir) }

        do {
            _ = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)
            Issue.record("Expected missingSETFile error")
        } catch LocalDTXFixtureImportError.missingSETFile {
            // Expected: the fileExists guard rejects a folder with no SET.def.
        } catch {
            Issue.record("Expected .missingSETFile but got \(error)")
        }
    }

    @Test("importSong throws unreadableSETFile when SET.def cannot be decoded")
    func importSongThrowsUnreadableSETFileWhenSETDefIsADirectory() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        defer { removeTemp(tempDir) }
        // SET.def exists as a directory, so the fileExists guard passes but
        // Data(contentsOf:) throws and decodeSETFile returns nil.
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("SET.def", isDirectory: true),
            withIntermediateDirectories: true
        )

        do {
            _ = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)
            Issue.record("Expected unreadableSETFile error")
        } catch LocalDTXFixtureImportError.unreadableSETFile {
            // Expected.
        } catch {
            Issue.record("Expected .unreadableSETFile but got \(error)")
        }
    }

    @Test("REAL difficulty label maps to expert")
    func realDifficultyLabelMapsToExpert() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        defer { removeTemp(tempDir) }
        try writeSETDef(in: tempDir, content: "#TITLE: Real\n#L1LABEL: REAL\n#L1FILE: chart.dtx\n")
        try writeMinimalChart(in: tempDir, filename: "chart.dtx", title: "Real")

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        #expect(song.charts.count == 1)
        #expect(song.charts.first?.difficulty == .expert, "REAL label must map to .expert")
    }

    @Test("decodeSETFile decodes a UTF-16 BE BOM SET.def")
    func decodeSETFileHandlesUTF16BigEndianBOM() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        defer { removeTemp(tempDir) }
        let text = "#TITLE: BEBOM\n#L1LABEL: BASIC\n#L1FILE: chart.dtx\n"
        var data = Data([0xFE, 0xFF]) // UTF-16 BE BOM
        data.append(text.data(using: .utf16BigEndian) ?? Data())
        try data.write(to: tempDir.appendingPathComponent("SET.def"))
        try writeMinimalChart(in: tempDir, filename: "chart.dtx", title: "BEBOM")

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        #expect(song.title == "BEBOM", "UTF-16 BE BOM SET.def must decode correctly")
        #expect(song.charts.count == 1)
    }

    @Test("decodeSETFile falls back to Shift-JIS for BOM-less Japanese content")
    func decodeSETFileFallsBackToShiftJIS() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        defer { removeTemp(tempDir) }
        // Shift-JIS bytes for the title are invalid UTF-8, so the UTF-8 decode
        // fails and the Shift-JIS fallback in decodeSETFile is exercised.
        let setDef = "#TITLE: テスト曲\n#L1LABEL: BASIC\n#L1FILE: chart.dtx\n"
        let data = try #require(setDef.data(using: .shiftJIS))
        try data.write(to: tempDir.appendingPathComponent("SET.def"))
        try writeMinimalChart(in: tempDir, filename: "chart.dtx", title: "SJIS")

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        #expect(song.title == "テスト曲", "Shift-JIS SET.def must decode via the fallback")
        #expect(song.charts.count == 1)
    }

    @Test("importSong uses the chart title when SET.def omits #TITLE")
    func importSongUsesChartTitleWhenSETDefOmitsTitle() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        defer { removeTemp(tempDir) }
        try writeSETDef(in: tempDir, content: "#L1LABEL: BASIC\n#L1FILE: chart.dtx\n")
        try writeMinimalChart(in: tempDir, filename: "chart.dtx", title: "From Chart")

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        #expect(song.title == "From Chart", "Title must fall back to the first chart's title")
    }

    @Test("importSong imports a UTF-8 SET.def with a single chart and no audio assets")
    func importSongImportsUTF8FixtureWithoutAudio() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        defer { removeTemp(tempDir) }
        try writeSETDef(
            in: tempDir,
            content: "#TITLE: UTF8 Fixture\n#L1LABEL: BASIC\n#L1FILE: chart.dtx\n"
        )
        try writeMinimalChart(in: tempDir, filename: "chart.dtx", title: "UTF8 Fixture")

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        #expect(song.title == "UTF8 Fixture")
        #expect(song.charts.count == 1)
        #expect(song.charts.first?.difficulty == .easy)
        #expect(song.bgmFilePath == nil, "No bgm.m4a present -> path should be nil")
        #expect(song.previewFilePath == nil, "No preview.mp3 present -> path should be nil")
    }

    @Test("SET.def TITLE without a colon still parses")
    func setTitleWithoutColonParses() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        defer { removeTemp(tempDir) }
        // "#TITLE FromChart" (space separator, no colon) exercises the no-colon
        // branch of SETList.value(from:key:).
        try writeSETDef(in: tempDir, content: "#TITLE NoColon\n#L1LABEL: BASIC\n#L1FILE: chart.dtx\n")
        try writeMinimalChart(in: tempDir, filename: "chart.dtx", title: "X")

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        #expect(song.title == "NoColon")
    }

    @Test("importSong ignores malformed SET.def directives and imports valid charts")
    func importSongIgnoresMalformedDirectives() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        defer { removeTemp(tempDir) }
        // Covers chartDirective guards (non-integer slot, empty value) and the
        // compactMap that drops entries missing a label or filename.
        try writeSETDef(
            in: tempDir,
            content: "#TITLE: Robust\n#L9LABEL: BASIC\n#LXLABEL: BASIC\n#L1LABEL\n"
                + "#L1LABEL: BASIC\n#L1FILE: chart.dtx\n#L2FILE: ghost.dtx\n"
        )
        try writeMinimalChart(in: tempDir, filename: "chart.dtx", title: "Robust")

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        #expect(song.title == "Robust")
        #expect(song.charts.count == 1, "Malformed directives must be ignored")
        #expect(song.charts.first?.difficulty == .easy)
    }

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-dtx-enc-\(UUID().uuidString)", isDirectory: true)
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
