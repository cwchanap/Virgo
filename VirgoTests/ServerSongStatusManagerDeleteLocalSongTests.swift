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
        isServerImported: true,
        serverSongId: "song-group"
    )
    let secondImported = Song(
        title: "Grouped Song",
        artist: "Grouped Artist",
        bpm: 128.0,
        duration: "2:50",
        genre: "DTX Import",
        isServerImported: true,
        serverSongId: "song-group"
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

@Suite("ServerSongStatusManager deleteLocalSong Tests", .serialized)
@MainActor
struct ServerSongStatusManagerDeleteLocalTests {
    @Test("deleteLocalSong + refreshDownloadStatus clears server status after last match removed")
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

            // deleteLocalSong only deletes the durable Song; the cache flags
            // are reconciled by refreshDownloadStatus on the main context.
            await manager.refreshDownloadStatus(modelContext: context)

            let verificationContext1 = ModelContext(container)
            let firstDeletedSong = try fetchSong(songId: firstImportedId, context: verificationContext1)
            let serverAfterFirstDelete = try fetchServerSong(songId: "song-group", context: verificationContext1)
            #expect(firstDeletedSong == nil)
            #expect(serverAfterFirstDelete?.isDownloaded == true)

            let secondDeleteSuccess = await manager.deleteLocalSong(secondImported, container: container)
            #expect(secondDeleteSuccess)

            await manager.refreshDownloadStatus(modelContext: context)

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

            let bgm = try TestAudioFixtures.makeTemporaryAudioFile(
                label: "bgm", extension: "ogg", contents: Data("bgm".utf8)
            )
            let preview = try TestAudioFixtures.makeTemporaryAudioFile(
                label: "preview", extension: "mp3", contents: Data("preview".utf8)
            )
            let bgmURL = bgm.url
            let previewURL = preview.url
            defer {
                bgm.cleanup()
                preview.cleanup()
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
                serverSongId: "file-delete-song",
                bgmFilePath: bgmURL.path,
                previewFilePath: previewURL.path
            )
            context.insert(localSong)
            try context.save()

            let deleteSuccess = await manager.deleteLocalSong(localSong, container: container)
            #expect(deleteSuccess)
            #expect(FileManager.default.fileExists(atPath: bgmURL.path) == false)
            #expect(FileManager.default.fileExists(atPath: previewURL.path) == false)

            // deleteLocalSong only deletes the durable Song; refreshDownloadStatus
            // projects the cleared flags onto the cache on the main context.
            await manager.refreshDownloadStatus(modelContext: context)

            let verificationContext = ModelContext(container)
            let updatedServerSong = try fetchServerSong(songId: "file-delete-song", context: verificationContext)
            #expect(updatedServerSong?.isDownloaded == false)
        }
    }

    @Test("deleteLocalSong skips bundle-backed audio assets (regression)")
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

            let bgmInBundle = try TestAudioFixtures.makeTemporaryAudioFile(
                in: bundleRoot, label: "bundle-bgm", extension: "m4a",
                contents: Data("bundle-bgm".utf8)
            ).url
            let previewInBundle = try TestAudioFixtures.makeTemporaryAudioFile(
                in: bundleRoot, label: "bundle-preview", extension: "mp3",
                contents: Data("bundle-preview".utf8)
            ).url
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

    @Test("deleteLocalSong + refreshDownloadStatus clears all server song status flags including bgm and preview")
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

            // deleteLocalSong only deletes the durable Song; refreshDownloadStatus
            // projects the cleared flags onto the cache on the main context.
            await manager.refreshDownloadStatus(modelContext: context)

            let verificationContext = ModelContext(container)
            let updatedServer = try fetchServerSong(songId: "flag-test-id", context: verificationContext)
            #expect(updatedServer?.isDownloaded == false)
            #expect(updatedServer?.bgmDownloaded == false)
            #expect(updatedServer?.previewDownloaded == false)
        }
    }

    @Test("deleteLocalSong with no serverSongId does not mutate same-title cache flags")
    func testDeleteLocalSongWithoutServerIDSkipsCacheFallback() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let container = TestContainer.shared.container
            let manager = ServerSongStatusManager()
            let cached = ServerSong(
                songId: "server-id",
                title: "Same Title",
                artist: "Same Artist",
                bpm: 120,
                isDownloaded: true,
                bgmDownloaded: true,
                previewDownloaded: true
            )
            let local = Song(
                title: "Same Title",
                artist: "Same Artist",
                bpm: 120,
                duration: "3:00",
                genre: "Local",
                isServerImported: false,
                serverSongId: nil
            )
            context.insert(cached)
            context.insert(local)
            try context.save()

            #expect(await manager.deleteLocalSong(local, container: container))

            let verification = ModelContext(container)
            let remaining = try #require(
                verification.fetch(FetchDescriptor<ServerSong>())
                    .first { $0.songId == "server-id" }
            )
            #expect(remaining.isDownloaded)
            #expect(remaining.bgmDownloaded)
            #expect(remaining.previewDownloaded)
        }
    }
}
