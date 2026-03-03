import Testing
import SwiftData
@testable import Virgo

@Suite("ServerSongService Tests", .serialized)
@MainActor
struct ServerSongServiceTests {
    @Test("loadServerSongs returns empty list when modelContext is not set")
    func testLoadServerSongsWithoutModelContext() async {
        let service = ServerSongService()

        let songs = await service.loadServerSongs()

        #expect(songs.isEmpty)
    }

    @Test("refresh methods are no-op when modelContext is not set")
    func testRefreshWithoutModelContext() async {
        let service = ServerSongService()

        await service.refreshServerSongs()
        #expect(service.isRefreshing == false)
        #expect(service.errorMessage == nil)

        await service.forceRefreshServerSongs()
        #expect(service.isRefreshing == false)
        #expect(service.errorMessage == nil)
    }

    @Test("deleteDownloadedSong returns false when modelContext is not set")
    func testDeleteDownloadedSongWithoutModelContext() async {
        let service = ServerSongService()
        let serverSong = ServerSong(songId: "song-1", title: "Song", artist: "Artist", bpm: 120.0)

        let success = await service.deleteDownloadedSong(serverSong)

        #expect(success == false)
    }

    @Test("deleteLocalSong returns false and sets error when modelContext is missing")
    func testDeleteLocalSongWithoutModelContext() async {
        let service = ServerSongService()
        let song = Song(title: "Missing", artist: "Context", bpm: 100.0, duration: "1:00", genre: "DTX Import")

        let success = await service.deleteLocalSong(song)

        #expect(success == false)
        #expect(service.errorMessage == "No model context available")
        #expect(service.deletingSongs.isEmpty)
    }

    @Test("deleteLocalSong returns false immediately when song is already deleting")
    func testDeleteLocalSongWhenAlreadyDeleting() async {
        let service = ServerSongService()
        let song = Song(title: "A", artist: "B", bpm: 100.0, duration: "1:00", genre: "DTX Import")
        let key = "a|b"
        service.deletingSongs = [key]

        let success = await service.deleteLocalSong(song)

        #expect(success == false)
        #expect(service.deletingSongs == [key])
    }

    @Test("downloadAndImportSong returns false when song is already downloaded")
    func testDownloadAndImportSongAlreadyDownloaded() async {
        let service = ServerSongService()
        let serverSong = ServerSong(
            songId: "already-downloaded",
            title: "Downloaded",
            artist: "Artist",
            bpm: 120.0,
            isDownloaded: true
        )

        let success = await service.downloadAndImportSong(serverSong)

        #expect(success == false)
        #expect(service.downloadingSongs.isEmpty)
    }

    @Test("downloadAndImportSong returns false when song is already being downloaded")
    func testDownloadAndImportSongAlreadyDownloading() async {
        let service = ServerSongService()
        let serverSong = ServerSong(songId: "in-flight", title: "In Flight", artist: "Artist", bpm: 120.0)
        service.downloadingSongs = ["in-flight"]

        let success = await service.downloadAndImportSong(serverSong)

        #expect(success == false)
        #expect(service.downloadingSongs == ["in-flight"])
    }

    @Test("downloadAndImportSong returns false and reports missing context when modelContext is nil")
    func testDownloadAndImportSongWithoutModelContext() async {
        let service = ServerSongService()
        let serverSong = ServerSong(songId: "no-context", title: "No Context", artist: "Artist", bpm: 120.0)

        let success = await service.downloadAndImportSong(serverSong)

        #expect(success == false)
        #expect(service.errorMessage == "No model context available")
        #expect(service.downloadingSongs.isEmpty)
    }

    @Test("isDownloading and isDeleting helpers reflect tracking sets")
    func testHelperMethodsTrackState() async {
        let service = ServerSongService()
        let serverSong = ServerSong(songId: "song-x", title: "Song X", artist: "Artist X", bpm: 120.0)
        let localSong = Song(title: "Mixed Case", artist: "Artist", bpm: 100.0, duration: "1:00", genre: "Rock")

        service.downloadingSongs = ["song-x"]
        service.deletingSongs = ["mixed case|artist"]

        #expect(service.isDownloading(serverSong))
        #expect(service.isDeleting(localSong))
    }

    @Test("setModelContext enables deleteDownloadedSong delegation")
    func testDeleteDownloadedSongWithContext() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let service = ServerSongService()
            service.setModelContext(context)

            let serverSong = ServerSong(
                songId: "service-delete",
                title: "Delete Me",
                artist: "Artist",
                bpm: 120.0,
                isDownloaded: true
            )
            let importedSong = Song(
                title: "Delete Me",
                artist: "Artist",
                bpm: 120.0,
                duration: "3:00",
                genre: "DTX Import"
            )
            context.insert(serverSong)
            context.insert(importedSong)
            try context.save()

            let success = await service.deleteDownloadedSong(serverSong)

            #expect(success)
            #expect(serverSong.isDownloaded == false)
            TestAssertions.assertDeleted(importedSong, in: context)
        }
    }
}
