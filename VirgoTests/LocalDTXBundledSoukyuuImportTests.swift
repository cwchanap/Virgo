//
//  LocalDTXBundledSoukyuuImportTests.swift
//  VirgoTests
//
//  Ownership of `importBundledSoukyuuIfAvailable`: seeding the bundled
//  demo from a real bundle, the deletion tombstone gate, and re-seeding.
//  Split from LocalDTXFixtureImporterTests to keep that file under the
//  SwiftLint file/type-length limits (HPA-583 review).
//

import Foundation
import SwiftData
import Testing
@testable import Virgo

@Suite("Local DTX Bundled Soukyuu Import Tests", .serialized)
@MainActor
struct LocalDTXBundledSoukyuuImportTests {

    @Test("bundled Soukyuu imports from the real built app bundle")
    func bundledSoukyuuImportsFromBuiltAppBundle() throws {
        let context = TestContainer.isolatedContainer().context
        let isolatedDeletionStore = makeIsolatedDeletionStore()

        let song = try #require(
            try LocalDTXFixtureImporter.importBundledSoukyuuIfAvailable(
                into: context,
                bundle: .main,
                deletionStore: isolatedDeletionStore
            )
        )
        #expect(song.bgmFilePath?.hasSuffix("bgm.m4a") == true)
        #expect(!song.charts.isEmpty)
    }

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

    @Test("importBundledSoukyuuIfAvailable returns an existing stable-ID record marked deleted")
    func importBundledSoukyuuReturnsExistingStableIDRecordEvenIfMarkedDeleted() throws {
        // If the song still exists (e.g. a delete that did not persist) but the
        // tombstone was recorded, the importer returns the existing stable-ID
        // record. The tombstone remains in force while the live record remains
        // available to the user.
        let context = TestContainer.isolatedContainer().context
        let bundle = try makeBundle(named: "ExistingDeletedBundle", withFixture: true)
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

        #expect(second === first, "An existing stable-ID record must be returned, not duplicated")
        #expect(store.isDeleted(songId: LocalDTXFixtureImporter.soukyuuSongId))
        #expect(try context.fetch(FetchDescriptor<Song>()).count == 1)
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

    // MARK: - Helpers

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
            try "#TITLE: Bundle Fixture\n#L1LABEL: BASIC\n#L1FILE: chart.dtx\n".write(
                to: resources.appendingPathComponent("SET.def"),
                atomically: true, encoding: .utf8
            )
            let chart = "#TITLE: Bundle Fixture\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 50\n#01111: 01000000"
            try chart.write(to: resources.appendingPathComponent("chart.dtx"), atomically: true, encoding: .utf8)
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
        let suite = "virgo-dtx-importer-deletion-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return BundledFixtureDeletionStore(defaults: defaults)
    }
}
