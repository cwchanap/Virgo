import Testing
import SwiftData
import Foundation
@testable import Virgo

extension ServerSongServiceTests {
    @Test("downloadAndImportSong surfaces soft warning on success without setting errorMessage")
    func testDownloadAndImportSongSurfacesWarningOnSuccess() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let downloader = MockServerSongDownloader()
            downloader.result = (true, "Chart chart.dtx imported with no playable notes (normalization failed).")
            let statusManager = MockServerSongStatusManager()
            let service = ServerSongService(downloader: downloader, statusManager: statusManager)
            service.setModelContext(context)

            let serverSong = ServerSong(songId: "download-warn", title: "Warn", artist: "Artist", bpm: 120.0)
            context.insert(serverSong)
            try context.save()

            let success = await service.downloadAndImportSong(serverSong)

            #expect(success)
            #expect(serverSong.isDownloaded == true)
            #expect(service.errorMessage == nil)
            #expect(service.warningMessage != nil)
            #expect(service.warningMessage?.contains("chart.dtx") == true)
            #expect(statusManager.refreshDownloadStatusCalled)
        }
    }
}
