import Foundation

/// Minimal file download seam used by the downloader (mockable in tests).
protocol FileDownloading {
    func downloadData(from url: URL) async throws -> Data
}
