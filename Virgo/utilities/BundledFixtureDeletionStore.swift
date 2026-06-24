//
//  BundledFixtureDeletionStore.swift
//  Virgo
//
//  Persists user-initiated deletions of bundled DTX fixture songs so the startup
//  import path does not resurrect a demo song the user explicitly removed.
//
//  Background: `ContentView.seedLocalDTXFixtures()` runs on every production
//  launch (suppressed only by `-SkipSeed`), and `LocalDTXFixtureImporter` dedupes
//  purely by `serverSongId`. Without this store, deleting the bundled Soukyuu
//  demo from the library is not durable — the next launch sees no matching
//  `serverSongId` and recreates it. This store closes that loop by recording the
//  user's intent, which the importer consults before recreating an absent record.
//

import Foundation

/// Records and recalls which bundled DTX fixture songs the user has explicitly
/// deleted from their library, so the startup seed path
/// (`ContentView.seedLocalDTXFixtures` →
/// `LocalDTXFixtureImporter.importBundledSoukyuuIfAvailable`) does not recreate a
/// demo song the user removed.
///
/// `UserDefaults`-backed (device-local, not iCloud-synced) to match the
/// device-local SwiftData store that holds the `Song` records. The `UserDefaults`
/// instance is injectable so tests can isolate state via a unique `suiteName`
/// rather than polluting (or reading from) `UserDefaults.standard`.
///
/// Marked `@unchecked Sendable`: the only stored state is a `UserDefaults`
/// instance, which Apple documents as thread-safe, and the store performs only
/// atomic read/replace on a single key. It is read from a detached delete task
/// (`ServerSongStatusManager.deleteLocalSong`) and the main-actor import path.
struct BundledFixtureDeletionStore: @unchecked Sendable {
    let defaults: UserDefaults

    /// Shared production store backed by `UserDefaults.standard`.
    static let standard = BundledFixtureDeletionStore(defaults: .standard)

    private static let storageKey = "BundledFixtureDeletedSongIds"

    /// Song ids that count as bundled fixtures whose deletion must be durable.
    /// A user delete of one of these is recorded and consulted by the importer on
    /// subsequent launches. Adding a future bundled fixture means adding its id
    /// here so that a user delete of it is likewise respected.
    private static let bundledFixtureIds: Set<String> = [LocalDTXFixtureImporter.soukyuuSongId]

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Returns true if the user previously deleted the given bundled fixture
    /// song (and the tombstone has not since been cleared).
    func isDeleted(songId: String) -> Bool {
        deletedIds().contains(songId)
    }

    /// Records `songId` as deleted **only if** it is a known bundled fixture id.
    /// Returns whether a new entry was recorded.
    ///
    /// Safe to call with any song id — a server-downloaded id (or `nil`) is
    /// ignored — so callers such as `ServerSongStatusManager.deleteLocalSong`
    /// need no knowledge of which songs are bundled. This keeps the "what is a
    /// bundled fixture" decision in one place (this store + the importer
    /// constant) instead of leaking it into the delete path.
    @discardableResult
    func recordIfBundled(songId: String?) -> Bool {
        guard let songId, Self.bundledFixtureIds.contains(songId) else { return false }
        var ids = deletedIds()
        guard !ids.contains(songId) else { return false }
        ids.insert(songId)
        defaults.set(Array(ids), forKey: Self.storageKey)
        return true
    }

    /// Clears all recorded bundled-fixture deletions. Used by the UI-test reset
    /// path (`-ResetState`) to restore a clean slate where the demo re-seeds.
    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func deletedIds() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }
}
