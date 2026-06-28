import Testing
import SwiftUI
@testable import Virgo

@Suite("Design system")
struct DesignSystemTests {
    @Test("hex initializer maps RGB channels correctly")
    func hexChannels() throws {
        let c = Color(hex: 0xC8341F).cgColor
        let comps = try #require(c?.components)
        #expect(abs(comps[0] - 0xC8/255.0) < 0.001)
        #expect(abs(comps[1] - 0x34/255.0) < 0.001)
        #expect(abs(comps[2] - 0x1F/255.0) < 0.001)
    }

    @Test("paper and ink themes differ and share the vermillion accent")
    func themeWorlds() {
        #expect(VirgoTheme.paper.background != VirgoTheme.ink.background)
        #expect(VirgoTheme.paper.primary != VirgoTheme.ink.primary)
        #expect(VirgoTheme.paper.accent == VirgoTheme.ink.accent)
        #expect(VirgoTheme.paper.accent == Palette.vermillion)
    }

    @Test("difficulty pip fill scales with difficulty", arguments: [
        (Difficulty.easy, 2), (.medium, 3), (.hard, 4), (.expert, 5)
    ])
    func pipFill(difficulty: Difficulty, expected: Int) {
        #expect(DifficultyPipScale.filled(for: difficulty) == expected)
        #expect(DifficultyPipScale.filled(for: difficulty) <= DifficultyPipScale.total)
    }
}
