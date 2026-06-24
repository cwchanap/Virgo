//
//  BundledFixtureDeletionStoreTests.swift
//  VirgoTests
//

import Foundation
import Testing
@testable import Virgo

@Suite("Bundled Fixture Deletion Store Tests")
struct BundledFixtureDeletionStoreTests {
    /// Fresh store backed by a unique UserDefaults suite so tests never touch
    /// (or read from) `UserDefaults.standard`.
    private func makeStore() -> BundledFixtureDeletionStore {
        let suite = "virgo-bundled-fixture-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return BundledFixtureDeletionStore(defaults: defaults)
    }

    @Test("isDeleted is false by default for an unrecorded id")
    func isDeletedFalseByDefault() {
        let store = makeStore()
        #expect(store.isDeleted(songId: LocalDTXFixtureImporter.soukyuuSongId) == false)
    }

    @Test("recordIfBundled records only known bundled fixture ids")
    func recordsOnlyBundledFixtureIds() {
        let store = makeStore()

        // The bundled Soukyuu id is recorded.
        #expect(store.recordIfBundled(songId: LocalDTXFixtureImporter.soukyuuSongId))
        #expect(store.isDeleted(songId: LocalDTXFixtureImporter.soukyuuSongId))

        // A server-downloaded (non-bundled) id must be ignored so that ordinary
        // server-song deletes do not get persisted as tombstones.
        #expect(store.recordIfBundled(songId: "server-downloaded-id") == false)
        #expect(store.isDeleted(songId: "server-downloaded-id") == false)

        // nil must be ignored.
        #expect(store.recordIfBundled(songId: nil) == false)
    }

    @Test("recordIfBundled is idempotent")
    func recordIsIdempotent() {
        let store = makeStore()
        #expect(store.recordIfBundled(songId: LocalDTXFixtureImporter.soukyuuSongId))
        #expect(store.recordIfBundled(songId: LocalDTXFixtureImporter.soukyuuSongId) == false)
    }

    @Test("clear removes all recorded deletions")
    func clearRemovesAllDeletions() {
        let store = makeStore()
        _ = store.recordIfBundled(songId: LocalDTXFixtureImporter.soukyuuSongId)
        #expect(store.isDeleted(songId: LocalDTXFixtureImporter.soukyuuSongId))

        store.clear()

        #expect(store.isDeleted(songId: LocalDTXFixtureImporter.soukyuuSongId) == false)
    }
}
