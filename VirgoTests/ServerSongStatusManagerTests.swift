import Testing
import SwiftData
@testable import Virgo

private enum SaveHookError: Error {
    case forced
}

@Suite("ServerSongStatusManager Tests", .serialized)
@MainActor
struct ServerSongStatusManagerTests {
    @Test("refreshDownloadStatus updates downloaded and media flags from local songs")
    func testRefreshDownloadStatusUpdatesFlags() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let manager = ServerSongStatusManager()

            let localSong = Song(
                title: "Match Song",
                artist: "Match Artist",
                bpm: 140.0,
                duration: "4:00",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "match-song",
                bgmFilePath: "/tmp/test-match.ogg",
                previewFilePath: "/tmp/test-match.mp3"
            )
            context.insert(localSong)

            let matchingServerSong = ServerSong(
                songId: "match-song",
                title: "Match Song",
                artist: "Match Artist",
                bpm: 140.0,
                isDownloaded: false,
                bgmDownloaded: false,
                previewDownloaded: false
            )
            let unmatchedServerSong = ServerSong(
                songId: "no-match-song",
                title: "No Match",
                artist: "No Match Artist",
                bpm: 100.0,
                isDownloaded: true,
                bgmDownloaded: true,
                previewDownloaded: true
            )
            context.insert(matchingServerSong)
            context.insert(unmatchedServerSong)
            try context.save()

            await manager.refreshDownloadStatus(modelContext: context)

            #expect(matchingServerSong.isDownloaded == true)
            #expect(matchingServerSong.bgmDownloaded == true)
            #expect(matchingServerSong.previewDownloaded == true)

            #expect(unmatchedServerSong.isDownloaded == false)
            #expect(unmatchedServerSong.bgmDownloaded == false)
            #expect(unmatchedServerSong.previewDownloaded == false)
        }
    }

    @Test("refreshDownloadStatus rollback cleans context on save failure")
    func testRefreshDownloadStatusRollbackOnSaveFailure() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let manager = ServerSongStatusManager(saveContext: { _ in throw SaveHookError.forced })

            let localSong = Song(
                title: "Refresh Save Failure",
                artist: "Artist",
                bpm: 120.0,
                duration: "2:00",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "refresh-save-failure",
                bgmFilePath: "/tmp/refresh-failure.ogg",
                previewFilePath: "/tmp/refresh-failure.mp3"
            )
            let serverSong = ServerSong(
                songId: "refresh-save-failure",
                title: "Refresh Save Failure",
                artist: "Artist",
                bpm: 120.0,
                isDownloaded: false,
                bgmDownloaded: false,
                previewDownloaded: false
            )

            context.insert(localSong)
            context.insert(serverSong)
            try context.save()

            await manager.refreshDownloadStatus(modelContext: context)

            // modelContext.rollback() cleans the transaction but SwiftData does not
            // revert property mutations on already-registered objects.
            #expect(serverSong.isDownloaded == true)
            #expect(serverSong.bgmDownloaded == true)
            #expect(serverSong.previewDownloaded == true)
        }
    }

    @Test("refreshDownloadStatus ignores local songs that are not server-imported")
    func testRefreshDownloadStatusIgnoresNonServerImportedSongs() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let manager = ServerSongStatusManager()

            // Local/sample song sharing title+artist but NOT server-imported
            let localSong = Song(
                title: "Local Only",
                artist: "Local Artist",
                bpm: 100.0,
                duration: "3:00",
                genre: "Rock",
                isServerImported: false,
                bgmFilePath: "/tmp/local-only.ogg",
                previewFilePath: "/tmp/local-only.mp3"
            )
            context.insert(localSong)

            let serverSong = ServerSong(
                songId: "local-only-server",
                title: "Local Only",
                artist: "Local Artist",
                bpm: 100.0,
                isDownloaded: false,
                bgmDownloaded: false,
                previewDownloaded: false
            )
            context.insert(serverSong)
            try context.save()

            await manager.refreshDownloadStatus(modelContext: context)

            // Must remain false — non-server-imported song must not match
            #expect(serverSong.isDownloaded == false)
            #expect(serverSong.bgmDownloaded == false)
            #expect(serverSong.previewDownloaded == false)
        }
    }

    // MARK: - serverSongId-based matching

    @Test("refreshDownloadStatus uses serverSongId for matching when available")
    func testRefreshDownloadStatusUsesServerSongIdMatching() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let manager = ServerSongStatusManager()

            // Server songs with same title/artist but different IDs
            let serverA = ServerSong(
                songId: "server-a",
                title: "Identical",
                artist: "Identical Artist",
                bpm: 120.0,
                isDownloaded: false,
                bgmDownloaded: false,
                previewDownloaded: false
            )
            let serverB = ServerSong(
                songId: "server-b",
                title: "Identical",
                artist: "Identical Artist",
                bpm: 130.0,
                isDownloaded: false,
                bgmDownloaded: false,
                previewDownloaded: false
            )
            context.insert(serverA)
            context.insert(serverB)

            // Only serverA has a local import
            let localA = Song(
                title: "Identical",
                artist: "Identical Artist",
                bpm: 120.0,
                duration: "3:00",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "server-a",
                bgmFilePath: "/tmp/a-bgm.ogg",
                previewFilePath: "/tmp/a-preview.mp3"
            )
            context.insert(localA)
            try context.save()

            await manager.refreshDownloadStatus(modelContext: context)

            // Only serverA should be marked as downloaded
            #expect(serverA.isDownloaded == true)
            #expect(serverA.bgmDownloaded == true)
            #expect(serverA.previewDownloaded == true)

            #expect(serverB.isDownloaded == false)
            #expect(serverB.bgmDownloaded == false)
            #expect(serverB.previewDownloaded == false)
        }
    }
}

extension ServerSongStatusManagerTests {
    @Test("deleteDownloadedSong deletes only matching server-imported songs")
    func testDeleteDownloadedSongSelectiveDeletion() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let manager = ServerSongStatusManager()

            let serverSong = ServerSong(
                songId: "server-song-a",
                title: "Song A",
                artist: "Artist A",
                bpm: 120.0,
                isDownloaded: true
            )
            context.insert(serverSong)

            let importedMatch = Song(
                title: "Song A",
                artist: "Artist A",
                bpm: 120.0,
                duration: "3:00",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "server-song-a"
            )
            let nonImportedMatch = Song(
                title: "Song A",
                artist: "Artist A",
                bpm: 120.0,
                duration: "3:00",
                genre: "Rock",
                isServerImported: false
            )
            let differentSong = Song(
                title: "Song B",
                artist: "Artist A",
                bpm: 120.0,
                duration: "3:00",
                genre: "DTX Import",
                isServerImported: true
            )
            context.insert(importedMatch)
            context.insert(nonImportedMatch)
            context.insert(differentSong)
            try context.save()

            let success = await manager.deleteDownloadedSong(serverSong, modelContext: context)

            #expect(success)
            #expect(serverSong.isDownloaded == false)
            TestAssertions.assertDeleted(importedMatch, in: context)
            TestAssertions.assertNotDeleted(nonImportedMatch, in: context)
            TestAssertions.assertNotDeleted(differentSong, in: context)
        }
    }

    @Test("deleteDownloadedSong deletes server-imported song with curated genre")
    func testDeleteDownloadedSongWithCuratedGenre() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let manager = ServerSongStatusManager()

            let serverSong = ServerSong(
                songId: "server-song-curated",
                title: "Curated",
                artist: "Curated Artist",
                bpm: 130.0,
                isDownloaded: true
            )
            context.insert(serverSong)

            // Server-imported song with a curated (non-"DTX Import") genre must still be deletable.
            let curatedSong = Song(
                title: "Curated",
                artist: "Curated Artist",
                bpm: 130.0,
                duration: "4:00",
                genre: "Rock",
                isServerImported: true,
                serverSongId: "server-song-curated"
            )
            context.insert(curatedSong)
            try context.save()

            let success = await manager.deleteDownloadedSong(serverSong, modelContext: context)

            #expect(success)
            #expect(serverSong.isDownloaded == false)
            TestAssertions.assertDeleted(curatedSong, in: context)
        }
    }

    @Test("deleteDownloadedSong returns false when save fails")
    func testDeleteDownloadedSongSaveFailureReturnsFalse() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let manager = ServerSongStatusManager(saveContext: { _ in throw SaveHookError.forced })

            let serverSong = ServerSong(
                songId: "save-failure-song",
                title: "Save Failure Song",
                artist: "Artist",
                bpm: 120.0,
                isDownloaded: true
            )
            context.insert(serverSong)

            let localSong = Song(
                title: "Save Failure Song",
                artist: "Artist",
                bpm: 120.0,
                duration: "2:00",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "save-failure-song"
            )
            context.insert(localSong)
            try context.save()

            let success = await manager.deleteDownloadedSong(serverSong, modelContext: context)

            #expect(success == false)
            #expect(serverSong.isDownloaded == false)
        }
    }

    @Test("deleteDownloadedSong uses serverSongId to match songs with same title/artist")
    func testDeleteDownloadedSongUsesServerSongIdMatching() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let manager = ServerSongStatusManager()

            // Two server songs with identical title/artist but different songIds
            let serverSongA = ServerSong(
                songId: "song-a-id",
                title: "Same Title",
                artist: "Same Artist",
                bpm: 120.0,
                isDownloaded: true
            )
            let serverSongB = ServerSong(
                songId: "song-b-id",
                title: "Same Title",
                artist: "Same Artist",
                bpm: 130.0,
                isDownloaded: true
            )
            context.insert(serverSongA)
            context.insert(serverSongB)

            // Local songs imported with serverSongId — only songA should be deleted
            let localSongA = Song(
                title: "Same Title",
                artist: "Same Artist",
                bpm: 120.0,
                duration: "3:00",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "song-a-id"
            )
            let localSongB = Song(
                title: "Same Title",
                artist: "Same Artist",
                bpm: 130.0,
                duration: "3:30",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "song-b-id"
            )
            context.insert(localSongA)
            context.insert(localSongB)
            try context.save()

            let success = await manager.deleteDownloadedSong(serverSongA, modelContext: context)

            #expect(success)
            #expect(serverSongA.isDownloaded == false)
            #expect(serverSongB.isDownloaded == true)
            TestAssertions.assertDeleted(localSongA, in: context)
            TestAssertions.assertNotDeleted(localSongB, in: context)
        }
    }

    @Test("applyDownloadStatus matches only current serverSongId")
    func testApplyDownloadStatusUsesOnlyServerSongId() async throws {
        try await TestSetup.withTestSetup {
            let manager = ServerSongStatusManager()
            let current = ServerSong(songId: "current", title: "Same", artist: "Artist", bpm: 120)
            let titleOnly = ServerSong(
                songId: "other",
                title: "Legacy",
                artist: "Artist",
                bpm: 120,
                isDownloaded: true,
                bgmDownloaded: true,
                previewDownloaded: true
            )
            let exact = Song(
                title: "Renamed",
                artist: "Different",
                bpm: 120,
                duration: "3:00",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "current",
                bgmFilePath: "/tmp/current.ogg",
                previewFilePath: "/tmp/current.mp3"
            )
            let nilID = Song(
                title: "Legacy",
                artist: "Artist",
                bpm: 120,
                duration: "3:00",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: nil,
                bgmFilePath: "/tmp/legacy.ogg",
                previewFilePath: "/tmp/legacy.mp3"
            )

            let changed = manager.applyDownloadStatus(to: [current, titleOnly], from: [exact, nilID])

            #expect(changed)
            #expect(current.isDownloaded)
            #expect(current.bgmDownloaded)
            #expect(current.previewDownloaded)
            #expect(titleOnly.isDownloaded == false)
            #expect(titleOnly.bgmDownloaded == false)
            #expect(titleOnly.previewDownloaded == false)
        }
    }

    @Test("deleteDownloadedSong ignores same-title rows without matching serverSongId")
    func testDeleteDownloadedSongRequiresServerSongId() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let manager = ServerSongStatusManager()
            let cached = ServerSong(
                songId: "current-id",
                title: "Same Title",
                artist: "Same Artist",
                bpm: 120,
                isDownloaded: true
            )
            let titleOnly = Song(
                title: "Same Title",
                artist: "Same Artist",
                bpm: 120,
                duration: "3:00",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: nil
            )
            context.insert(cached)
            context.insert(titleOnly)
            try context.save()

            #expect(await manager.deleteDownloadedSong(cached, modelContext: context))
            TestAssertions.assertNotDeleted(titleOnly, in: context)
        }
    }
}
