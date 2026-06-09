import Testing
import SwiftData
@testable import Virgo

@Suite("ServerSongStatusManager Tests", .serialized)
@MainActor
struct ServerSongStatusManagerTests {
    private enum SaveHookError: Error {
        case forced
    }

    private func fetchSong(
        songId: PersistentIdentifier,
        context: ModelContext
    ) throws -> Song? {
        let descriptor = FetchDescriptor<Song>(predicate: #Predicate<Song> { songModel in
            songModel.persistentModelID == songId
        })
        return try context.fetch(descriptor).first
    }

    private func fetchServerSong(
        songId: String,
        context: ModelContext
    ) throws -> ServerSong? {
        let descriptor = FetchDescriptor<ServerSong>(predicate: #Predicate<ServerSong> { serverSong in
            serverSong.songId == songId
        })
        return try context.fetch(descriptor).first
    }

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
                isServerImported: true
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
                isServerImported: true
            )
            context.insert(curatedSong)
            try context.save()

            let success = await manager.deleteDownloadedSong(serverSong, modelContext: context)

            #expect(success)
            #expect(serverSong.isDownloaded == false)
            TestAssertions.assertDeleted(curatedSong, in: context)
        }
    }

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

    private struct GroupedSongsData {
        let serverSong: ServerSong
        let firstImported: Song
        let secondImported: Song
        let nonImported: Song
    }

    private func setupGroupedSongs(
        context: ModelContext
    ) throws -> GroupedSongsData {
        let serverSong = ServerSong(
            songId: "song-group",
            title: "Grouped Song",
            artist: "Grouped Artist",
            bpm: 128.0,
            isDownloaded: true
        )
        context.insert(serverSong)

        let firstImported = Song(
            title: "Grouped Song",
            artist: "Grouped Artist",
            bpm: 128.0,
            duration: "2:50",
            genre: "DTX Import",
            isServerImported: true
        )
        let secondImported = Song(
            title: "Grouped Song",
            artist: "Grouped Artist",
            bpm: 128.0,
            duration: "2:50",
            genre: "DTX Import",
            isServerImported: true
        )
        let nonImported = Song(
            title: "Grouped Song",
            artist: "Grouped Artist",
            bpm: 128.0,
            duration: "2:50",
            genre: "Rock",
            isServerImported: false
        )
        context.insert(firstImported)
        context.insert(secondImported)
        context.insert(nonImported)
        try context.save()

        return GroupedSongsData(
            serverSong: serverSong,
            firstImported: firstImported,
            secondImported: secondImported,
            nonImported: nonImported
        )
    }

    @Test("deleteLocalSong updates server download status only after last server-imported match is removed")
    func testDeleteLocalSongUpdatesStatusAfterLastMatch() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let container = TestContainer.shared.container
            let manager = ServerSongStatusManager()

            let groupedData = try setupGroupedSongs(context: context)
            let firstImported = groupedData.firstImported
            let secondImported = groupedData.secondImported

            let firstImportedId = firstImported.persistentModelID
            let secondImportedId = secondImported.persistentModelID

            let firstDeleteSuccess = await manager.deleteLocalSong(firstImported, container: container)
            #expect(firstDeleteSuccess)

            let verificationContext1 = ModelContext(container)
            let firstDeletedSong = try fetchSong(songId: firstImportedId, context: verificationContext1)
            let serverAfterFirstDelete = try fetchServerSong(songId: "song-group", context: verificationContext1)
            #expect(firstDeletedSong == nil)
            #expect(serverAfterFirstDelete?.isDownloaded == true)

            let secondDeleteSuccess = await manager.deleteLocalSong(secondImported, container: container)
            #expect(secondDeleteSuccess)

            let verificationContext2 = ModelContext(container)
            let secondDeletedSong = try fetchSong(songId: secondImportedId, context: verificationContext2)
            let serverAfterSecondDelete = try fetchServerSong(songId: "song-group", context: verificationContext2)
            #expect(secondDeletedSong == nil)
            #expect(serverAfterSecondDelete?.isDownloaded == false)
        }
    }

    @Test("deleteLocalSong returns true when song is already absent")
    func testDeleteLocalSongAbsentSongIsNoOpSuccess() async throws {
        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let manager = ServerSongStatusManager()

            let orphanSong = Song(
                title: "Orphan",
                artist: "Nobody",
                bpm: 100.0,
                duration: "1:00",
                genre: "DTX Import"
            )

            let success = await manager.deleteLocalSong(orphanSong, container: container)
            #expect(success)
        }
    }

    @Test("deleteLocalSong removes associated BGM and preview files")
    func testDeleteLocalSongDeletesAssociatedFiles() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let container = TestContainer.shared.container
            let manager = ServerSongStatusManager()

            let bgmPath = "/tmp/virgo-test-bgm-\(UUID().uuidString).ogg"
            let previewPath = "/tmp/virgo-test-preview-\(UUID().uuidString).mp3"
            let didCreateBGM = FileManager.default.createFile(atPath: bgmPath, contents: Data("bgm".utf8))
            let didCreatePreview = FileManager.default.createFile(atPath: previewPath, contents: Data("preview".utf8))
            #expect(didCreateBGM)
            #expect(didCreatePreview)
            #expect(FileManager.default.fileExists(atPath: bgmPath))
            #expect(FileManager.default.fileExists(atPath: previewPath))

            defer {
                try? FileManager.default.removeItem(atPath: bgmPath)
                try? FileManager.default.removeItem(atPath: previewPath)
            }

            let serverSong = ServerSong(
                songId: "file-delete-song",
                title: "File Delete Song",
                artist: "File Artist",
                bpm: 120.0,
                isDownloaded: true
            )
            context.insert(serverSong)

            let localSong = Song(
                title: "File Delete Song",
                artist: "File Artist",
                bpm: 120.0,
                duration: "2:00",
                genre: "DTX Import",
                bgmFilePath: bgmPath,
                previewFilePath: previewPath
            )
            context.insert(localSong)
            try context.save()

            let deleteSuccess = await manager.deleteLocalSong(localSong, container: container)
            #expect(deleteSuccess)
            #expect(FileManager.default.fileExists(atPath: bgmPath) == false)
            #expect(FileManager.default.fileExists(atPath: previewPath) == false)

            let verificationContext = ModelContext(container)
            let updatedServerSong = try fetchServerSong(songId: "file-delete-song", context: verificationContext)
            #expect(updatedServerSong?.isDownloaded == false)
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
                isServerImported: true
            )
            context.insert(localSong)
            try context.save()

            let success = await manager.deleteDownloadedSong(serverSong, modelContext: context)

            #expect(success == false)
            #expect(serverSong.isDownloaded == false)
        }
    }

    @Test("deleteLocalSong returns false when delete save fails")
    func testDeleteLocalSongSaveFailureReturnsFalse() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let container = TestContainer.shared.container
            let manager = ServerSongStatusManager(saveContext: { _ in throw SaveHookError.forced })

            let localSong = Song(
                title: "Delete Save Failure",
                artist: "Artist",
                bpm: 120.0,
                duration: "2:00",
                genre: "DTX Import"
            )
            context.insert(localSong)
            try context.save()

            let success = await manager.deleteLocalSong(localSong, container: container)

            #expect(success == false)
        }
    }

    @Test("refreshDownloadStatus swallows save failures")
    func testRefreshDownloadStatusSaveFailureIsHandled() async throws {
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

            #expect(serverSong.isDownloaded == true)
            #expect(serverSong.bgmDownloaded == true)
            #expect(serverSong.previewDownloaded == true)
        }
    }

    @Test("pruneCachedSong removes the ServerSong record")
    func testPruneRemovesRecord() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let song = ServerSong(songId: "prune-me", title: "P", artist: "A", bpm: 120)
            context.insert(song); try context.save()

            await ServerSongStatusManager().pruneCachedSong(song, modelContext: context)

            let remaining = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(remaining.isEmpty)
        }
    }

    @Test("pruneCachedSong deletes local Song when ServerSong is downloaded")
    func testPruneRemovesDownloadedSongAndLocalSong() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let serverSong = ServerSong(
                songId: "prune-dl", title: "PruneDL", artist: "X", bpm: 120, isDownloaded: true
            )
            let localSong = Song(
                title: "PruneDL", artist: "X", bpm: 120, duration: "3:30", genre: "DTX Import",
                isServerImported: true
            )
            context.insert(serverSong); context.insert(localSong)
            try context.save()

            await ServerSongStatusManager().pruneCachedSong(serverSong, modelContext: context)

            let remainingServer = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(remainingServer.isEmpty, "ServerSong record must be deleted")

            let remainingLocal = try context.fetch(FetchDescriptor<Song>())
            let orphanedLocal = remainingLocal.contains {
                $0.title == "PruneDL" && $0.artist == "X" && $0.isServerImported
            }
            #expect(!orphanedLocal, "Downloaded local Song must also be deleted")
        }
    }

    @Test("pruneCachedSong deletes local Song when isDownloaded is stale false")
    func testPruneRemovesLocalSongDespiteStaleIsDownloadedFlag() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context

            // Simulates status drift: isDownloaded=false but a matching
            // server-imported local Song still exists.  This can happen when
            // refreshCatalog prunes BEFORE refreshDownloadStatus reconciles flags.
            let serverSong = ServerSong(
                songId: "stale-flag", title: "StaleFlag", artist: "Y", bpm: 130,
                isDownloaded: false
            )
            let localSong = Song(
                title: "StaleFlag", artist: "Y", bpm: 130, duration: "2:00",
                genre: "DTX Import", isServerImported: true
            )
            context.insert(serverSong); context.insert(localSong)
            try context.save()

            await ServerSongStatusManager().pruneCachedSong(serverSong, modelContext: context)

            let remainingServer = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(remainingServer.isEmpty, "ServerSong record must be deleted")

            let remainingLocal = try context.fetch(FetchDescriptor<Song>())
            let orphanedLocal = remainingLocal.contains {
                $0.title == "StaleFlag" && $0.artist == "Y" && $0.isServerImported
            }
            #expect(!orphanedLocal, "Local Song must be deleted despite stale isDownloaded=false")
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
}
