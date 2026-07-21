//
//  LocalDTXFixtureImporterCoverageTests.swift
//  VirgoTests
//
//  Branch-coverage complement to LocalDTXFixtureImporterTests. Focuses on the
//  error throws, decode fallbacks, drop/ignore paths, and the bundled-import
//  entry point that the happy-path suite does not exercise.
//

import Foundation
import SwiftData
import Testing
@testable import Virgo

@Suite("Local DTX Fixture Importer Coverage", .serialized)
@MainActor
struct LocalDTXFixtureImporterCoverageTests {
    // MARK: - Error throws (fresh-import guards)

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

    // MARK: - Drop-with-survival

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

    // MARK: - decodeSETFile fallbacks

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

    // MARK: - Duration + title fallback

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

    // MARK: - Refresh path edge

    @Test("re-import leaves BGM offset nil when SET.def is unreadable")
    func reImportLeavesBGMOffsetNilWhenSETDefUnreadable() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()
        defer { removeTemp(tempDir) }
        let songId = tempDir.lastPathComponent
        let legacy = Song(
            title: "Legacy", artist: "x", bpm: 120.0, duration: "1:00", genre: "DTX Import",
            timeSignature: .fourFour, isServerImported: true, serverSongId: songId,
            bgmFilePath: nil, previewFilePath: nil, bgmStartOffsetSeconds: nil
        )
        context.insert(legacy)
        try context.save()
        // SET.def as a directory → decodeSETFile returns nil on the refresh path →
        // refreshBGMStartOffsetIfMissing returns early without backfilling.
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("SET.def", isDirectory: true),
            withIntermediateDirectories: true
        )

        let refreshed = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        #expect(refreshed === legacy)
        #expect(refreshed.bgmStartOffsetSeconds == nil, "Unreadable SET.def must not backfill")
    }

    // MARK: - Bundled import entry point

    @Test("importBundledSoukyuuIfAvailable returns nil when the bundle has no SET.def")
    func importBundledSoukyuuReturnsNilWhenBundleLacksSETDef() throws {
        let context = TestContainer.isolatedContainer().context
        let bundle = try makeBundle(named: "EmptyBundle", withFixture: false)
        defer { cleanupBundle(bundle) }

        // Inject an empty store so a leftover tombstone in `.standard` cannot
        // make this return nil for the wrong reason (gate vs. missing SET.def).
        let song = try LocalDTXFixtureImporter.importBundledSoukyuuIfAvailable(
            into: context, bundle: bundle, deletionStore: makeIsolatedDeletionStore()
        )

        #expect(song == nil, "Bundle without SET.def must return nil, not throw")
        #expect(try context.fetch(FetchDescriptor<Song>()).isEmpty)
    }

    @Test("importBundledSoukyuuIfAvailable imports when the bundle contains SET.def")
    func importBundledSoukyuuImportsWhenBundleContainsFixture() throws {
        let context = TestContainer.isolatedContainer().context
        let bundle = try makeBundle(named: "FixtureBundle", withFixture: true)
        defer { cleanupBundle(bundle) }

        let song = try #require(
            try LocalDTXFixtureImporter.importBundledSoukyuuIfAvailable(
                into: context, bundle: bundle, deletionStore: makeIsolatedDeletionStore()
            )
        )

        #expect(song.serverSongId == LocalDTXFixtureImporter.soukyuuSongId)
        #expect(song.charts.count == 1)
        #expect(song.charts.first?.difficulty == .easy)
    }

    // MARK: - Bundled import deletion-durability gate

    @Test("importBundledSoukyuuIfAvailable skips re-seed after the user deletes the bundled song")
    func importBundledSoukyuuSkipsReSeedAfterUserDeletion() throws {
        // Reproduces the review finding: deleting the bundled demo was not durable
        // because the import path dedupes only by serverSongId and recreated any
        // absent record on the next launch. The gate must prevent that recreation.
        let context = TestContainer.isolatedContainer().context
        let bundle = try makeBundle(named: "DeletionGateBundle", withFixture: true)
        defer { cleanupBundle(bundle) }
        let store = makeIsolatedDeletionStore()

        // First import seeds the bundled fixture (gate allows: not deleted, absent).
        let first = try #require(
            try LocalDTXFixtureImporter.importBundledSoukyuuIfAvailable(
                into: context, bundle: bundle, deletionStore: store
            )
        )
        #expect(first.serverSongId == LocalDTXFixtureImporter.soukyuuSongId)
        #expect(try context.fetch(FetchDescriptor<Song>()).count == 1)

        // Simulate the user deleting the song from the library, then the delete
        // path recording the tombstone (ServerSongStatusManager.deleteLocalSong).
        context.delete(first)
        try context.save()
        _ = store.recordIfBundled(songId: LocalDTXFixtureImporter.soukyuuSongId)

        // Next launch: the startup seed path must NOT recreate the deleted song.
        let second = try LocalDTXFixtureImporter.importBundledSoukyuuIfAvailable(
            into: context, bundle: bundle, deletionStore: store
        )

        #expect(second == nil, "A user-deleted bundled fixture must not be recreated on re-seed")
        #expect(try context.fetch(FetchDescriptor<Song>()).isEmpty, "The delete must be durable")
    }

    @Test("importBundledSoukyuuIfAvailable still refreshes an existing record marked deleted")
    func importBundledSoukyuuRefreshesExistingEvenIfMarkedDeleted() throws {
        // If the song still exists (e.g. a delete that did not persist) but the
        // tombstone was recorded, the importer must fall through to the normal
        // path and refresh/return the existing record rather than skip. Otherwise
        // the self-healing refresh logic (audio paths, BGM offset, duration) would
        // be bypassed whenever the tombstone and a live record briefly coexist.
        let context = TestContainer.isolatedContainer().context
        let bundle = try makeBundle(named: "RefreshExistingBundle", withFixture: true)
        defer { cleanupBundle(bundle) }
        let store = makeIsolatedDeletionStore()

        let first = try #require(
            try LocalDTXFixtureImporter.importBundledSoukyuuIfAvailable(
                into: context, bundle: bundle, deletionStore: store
            )
        )
        // Tombstone recorded, but the record is NOT deleted from the context.
        _ = store.recordIfBundled(songId: LocalDTXFixtureImporter.soukyuuSongId)

        let second = try LocalDTXFixtureImporter.importBundledSoukyuuIfAvailable(
            into: context, bundle: bundle, deletionStore: store
        )

        #expect(second === first, "An existing record must be refreshed, not skipped")
    }

    @Test("importBundledSoukyuuIfAvailable re-seeds after the deletion tombstone is cleared")
    func importBundledSoukyuuReSeedsAfterClear() throws {
        // Mirrors the `-ResetState` UI-test path (clearPersistedTestState), which
        // clears the tombstone so the demo re-seeds into a clean slate.
        let context = TestContainer.isolatedContainer().context
        let bundle = try makeBundle(named: "ClearTombstoneBundle", withFixture: true)
        defer { cleanupBundle(bundle) }
        let store = makeIsolatedDeletionStore()

        _ = store.recordIfBundled(songId: LocalDTXFixtureImporter.soukyuuSongId)
        store.clear()

        let song = try #require(
            try LocalDTXFixtureImporter.importBundledSoukyuuIfAvailable(
                into: context, bundle: bundle, deletionStore: store
            )
        )

        #expect(song.serverSongId == LocalDTXFixtureImporter.soukyuuSongId)
    }

    // MARK: - LocalizedError descriptions

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

    // MARK: - SETList parsing robustness

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
            .appendingPathComponent("virgo-dtx-cov-\(UUID().uuidString)", isDirectory: true)
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

    private func makeBundle(named name: String, withFixture: Bool) throws -> Bundle {
        let bundleDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).bundle", isDirectory: true)
        let contents = bundleDir.appendingPathComponent("Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try makeInfoPList(named: name).write(
            to: contents.appendingPathComponent("Info.plist"),
            atomically: true, encoding: .utf8
        )
        if withFixture {
            try writeSETDef(
                in: resources,
                content: "#TITLE: Bundle Fixture\n#L1LABEL: BASIC\n#L1FILE: chart.dtx\n"
            )
            try writeMinimalChart(in: resources, filename: "chart.dtx", title: "Bundle Fixture")
        }
        guard let bundle = Bundle(url: bundleDir) else {
            throw NSError(
                domain: "VirgoTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not load bundle at \(bundleDir.path)"]
            )
        }
        return bundle
    }

    private func makeInfoPList(named name: String) -> String {
        let header = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        let doctype = "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" " +
            "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"
        let body = "<plist version=\"1.0\"><dict>" +
            "<key>CFBundleIdentifier</key><string>\(name)</string>" +
            "</dict></plist>"
        return header + doctype + body
    }

    private func cleanupBundle(_ bundle: Bundle) {
        try? FileManager.default.removeItem(atPath: bundle.bundlePath)
    }

    /// Fresh `BundledFixtureDeletionStore` backed by a unique UserDefaults suite,
    /// so the gate tests never read from or write to `UserDefaults.standard`.
    private func makeIsolatedDeletionStore() -> BundledFixtureDeletionStore {
        let suite = "virgo-dtx-cov-deletion-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return BundledFixtureDeletionStore(defaults: defaults)
    }
}
