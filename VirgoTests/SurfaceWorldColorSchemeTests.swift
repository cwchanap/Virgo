import Testing
import SwiftUI
@testable import Virgo

@Suite("SurfaceWorld colorScheme mapping")
struct SurfaceWorldColorSchemeTests {
    @Test("dark scheme resolves to ink")
    func darkIsInk() {
        #expect(SurfaceWorld.forColorScheme(.dark) == .ink)
    }

    @Test("light scheme resolves to paper")
    func lightIsPaper() {
        #expect(SurfaceWorld.forColorScheme(.light) == .paper)
    }
}
