import Testing
import SwiftData
@testable import Virgo

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

@Suite("ServerSongStatusManager Tests", .serialized)
@MainActor
struct ServerSongStatusManagerTests {
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

    @Test("deleteLocalSong does not remove bundle-backed audio assets (bundled-fixture regression)")
    func testDeleteLocalSongSkipsBundleAudioPaths() async throws {
        // Reproduces the bundled-Soukyuu-fixture regression: a Song whose
        // bgmFilePath/previewFilePath resolve into the app bundle must not have
        // those files deleted when the user removes the song from the library.
        // On writable macOS/dev bundles the delete would otherwise succeed and
        // silently strip BGM/preview from the bundle, so a later re-import comes
        // back without audio.
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let container = TestContainer.shared.container

            let bundleRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("virgo-test-bundle-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: bundleRoot) }

            let bgmInBundle = bundleRoot.appendingPathComponent("bgm.m4a")
            let previewInBundle = bundleRoot.appendingPathComponent("preview.mp3")
            try Data("bundle-bgm".utf8).write(to: bgmInBundle)
            try Data("bundle-preview".utf8).write(to: previewInBundle)
            #expect(FileManager.default.fileExists(atPath: bgmInBundle.path))
            #expect(FileManager.default.fileExists(atPath: previewInBundle.path))

            let fileManager = ServerSongFileManager(bundleRootURL: bundleRoot)
            let manager = ServerSongStatusManager(fileManager: fileManager)

            let bundledSong = Song(
                title: "Bundled Fixture",
                artist: "Bundled Artist",
                bpm: 120.0,
                duration: "2:00",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "bundled-fixture-id",
                bgmFilePath: bgmInBundle.path,
                previewFilePath: previewInBundle.path
            )
            context.insert(bundledSong)
            try context.save()

            let success = await manager.deleteLocalSong(bundledSong, container: container)
            #expect(success)

            // DB row is gone, but the bundle audio assets are untouched.
            #expect(FileManager.default.fileExists(atPath: bgmInBundle.path))
            #expect(FileManager.default.fileExists(atPath: previewInBundle.path))

            let verificationContext = ModelContext(container)
            let remaining = try verificationContext.fetch(FetchDescriptor<Song>())
            #expect(remaining.isEmpty)
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

    // MARK: - serverSongId-based matching

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

    @Test("deleteLocalSong clears all server song status flags including bgm and preview")
    func testDeleteLocalSongClearsAllStatusFlags() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let container = TestContainer.shared.container
            let manager = ServerSongStatusManager()

            let serverSong = ServerSong(
                songId: "flag-test-id",
                title: "Flag Test",
                artist: "Flag Artist",
                bpm: 120.0,
                isDownloaded: true,
                bgmDownloaded: true,
                previewDownloaded: true
            )
            context.insert(serverSong)

            let localSong = Song(
                title: "Flag Test",
                artist: "Flag Artist",
                bpm: 120.0,
                duration: "2:00",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "flag-test-id"
            )
            context.insert(localSong)
            try context.save()

            let success = await manager.deleteLocalSong(localSong, container: container)
            #expect(success)

            let verificationContext = ModelContext(container)
            let updatedServer = try fetchServerSong(songId: "flag-test-id", context: verificationContext)
            #expect(updatedServer?.isDownloaded == false)
            #expect(updatedServer?.bgmDownloaded == false)
            #expect(updatedServer?.previewDownloaded == false)
        }
    }

    @Test("pruneCachedSong rolls back context when save fails")
    func testPruneCachedSongRollbackOnSaveFailure() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let manager = ServerSongStatusManager(saveContext: { _ in throw SaveHookError.forced })

            let serverSong = ServerSong(
                songId: "prune-save-fail",
                title: "PruneSaveFail",
                artist: "Z",
                bpm: 120,
                isDownloaded: false
            )
            context.insert(serverSong)
            try context.save()

            await manager.pruneCachedSong(serverSong, modelContext: context)

            // ServerSong must still exist after rollback
            let remaining = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(remaining.count == 1, "ServerSong should remain after rollback on save failure")
            #expect(remaining.first?.songId == "prune-save-fail")
        }
    }
}
