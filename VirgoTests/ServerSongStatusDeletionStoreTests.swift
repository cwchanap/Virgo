//
//  ServerSongStatusDeletionStoreTests.swift
//  VirgoTests
//
//  Extracted into its own suite so the parent `ServerSongStatusManagerTests`
//  struct stays under the SwiftLint type_body_length limit. Owns the coverage
//  for the delete → `BundledFixtureDeletionStore.recordIfBundled` wiring, which
//  could not be asserted before the store became injectable.
//

import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("ServerSongStatusManager Deletion Store Tests", .serialized)
@MainActor
struct ServerSongStatusDeletionStoreTests {
    /// Fresh `BundledFixtureDeletionStore` backed by a unique `UserDefaults`
    /// suite so delete-path tests never touch (or read from)
    /// `UserDefaults.standard`. Mirrors the isolation helper in
    /// `BundledFixtureDeletionStoreTests`.
    private func makeIsolatedDeletionStore() -> BundledFixtureDeletionStore {
        let suite = "virgo-status-manager-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return BundledFixtureDeletionStore(defaults: defaults)
    }

    @Test("deleteLocalSong records the bundled-fixture tombstone via the injected store")
    func testDeleteLocalSongRecordsBundledFixtureTombstone() async throws {
        // Closes the coverage gap where `deleteLocalSong` → `recordIfBundled` was
        // the untested recording half of the demo-resurrection fix: the line could
        // previously be deleted with zero test failures because the only
        // bundled-fixture delete test used a non-bundled id (a no-op for
        // `recordIfBundled`). Here a real bundled id is required so the recording
        // actually fires, and the store is injected with a unique UserDefaults
        // suite so the tombstone never touches `UserDefaults.standard`.
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let container = TestContainer.shared.container

            let store = makeIsolatedDeletionStore()
            let manager = ServerSongStatusManager(deletionStore: store)

            let bundledSong = Song(
                title: "Bundled Soukyuu",
                artist: "Bundled Artist",
                bpm: 165.55,
                duration: "2:00",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: LocalDTXFixtureImporter.soukyuuSongId
            )
            context.insert(bundledSong)
            try context.save()

            // Sanity: nothing recorded before the delete.
            #expect(store.isDeleted(songId: LocalDTXFixtureImporter.soukyuuSongId) == false)

            let success = await manager.deleteLocalSong(bundledSong, container: container)
            #expect(success)

            // The delete wired the tombstone through the injected store, so a later
            // seed/import pass will skip recreating this bundled demo song.
            #expect(store.isDeleted(songId: LocalDTXFixtureImporter.soukyuuSongId))

            let verificationContext = ModelContext(container)
            let remaining = try verificationContext.fetch(FetchDescriptor<Song>())
            #expect(remaining.isEmpty)
        }
    }
}
