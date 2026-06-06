import Testing
import Foundation
@testable import Virgo

@Suite("ServerSongDownloader Decode Tests")
struct ServerSongDownloaderDecodeTests {
    @Test("Decodes chart bytes per declared encoding")
    func testDecode() {
        let utf8 = Data("#TITLE: x".utf8)
        #expect(ServerSongDownloader.decode(utf8, encoding: "UTF_8") == "#TITLE: x")
        let sjis = "あ".data(using: .shiftJIS)!
        #expect(ServerSongDownloader.decode(sjis, encoding: "SHIFT_JIS") == "あ")
    }
}
