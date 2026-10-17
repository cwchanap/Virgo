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

    @Test("decode falls back to UTF-8 when Shift-JIS decode fails")
    func testDecodeUTF8Fallback() {
        // 0xC2 0x80 is valid UTF-8 (U+0080) but invalid Shift-JIS
        // because 0x80 is an undefined byte in Shift-JIS.
        let data = Data([0xC2, 0x80])
        let result = ServerSongDownloader.decode(data, encoding: "SHIFT_JIS")
        #expect(result != nil)
        #expect(result == String(data: data, encoding: .utf8))
    }
}
