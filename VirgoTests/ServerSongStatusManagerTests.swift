import Testing
import SwiftData
@testable import Virgo

@Suite("ServerSongStatusManager Tests", .serialized)
@MainActor
struct ServerSongStatusManagerTests {
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

    @Test("deleteDownloadedSong deletes only matching DTX Import songs")
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
                genre: "DTX Import"
            )
            let nonImportedMatch = Song(
                title: "Song A",
                artist: "Artist A",
                bpm: 120.0,
                duration: "3:00",
                genre: "Rock"
            )
            let differentSong = Song(
                title: "Song B",
                artist: "Artist A",
                bpm: 120.0,
                duration: "3:00",
                genre: "DTX Import"
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
            genre: "DTX Import"
        )
        let secondImported = Song(
            title: "Grouped Song",
            artist: "Grouped Artist",
            bpm: 128.0,
            duration: "2:50",
            genre: "DTX Import"
        )
        let nonImported = Song(
            title: "Grouped Song",
            artist: "Grouped Artist",
            bpm: 128.0,
            duration: "2:50",
            genre: "Rock"
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

    @Test("deleteLocalSong updates server download status only after last DTX Import match is removed")
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
}
