import Testing
import Foundation
@testable import Virgo

@Suite("SongsLayoutMode")
struct SongsLayoutModeTests {
    @Test("width below threshold uses rows")
    func narrowUsesRows() {
        #expect(SongsLayoutMode.forWidth(699) == .rows)
    }

    @Test("width at threshold uses grid")
    func thresholdUsesGrid() {
        #expect(SongsLayoutMode.forWidth(SongsLayoutMode.gridMinWidth) == .grid)
        #expect(SongsLayoutMode.forWidth(700) == .grid)
    }

    @Test("wide width uses grid")
    func wideUsesGrid() {
        #expect(SongsLayoutMode.forWidth(1366) == .grid)
    }

    @Test("zero width falls back to rows")
    func zeroUsesRows() {
        #expect(SongsLayoutMode.forWidth(0) == .rows)
    }
}
