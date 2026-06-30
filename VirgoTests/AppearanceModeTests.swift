import Testing
import SwiftUI
@testable import Virgo

@Suite("AppearanceMode")
struct AppearanceModeTests {
    @Test("system maps to no preferred color scheme")
    func systemIsNil() {
        #expect(AppearanceMode.system.preferredColorScheme == nil)
    }

    @Test("light forces light")
    func lightForcesLight() {
        #expect(AppearanceMode.light.preferredColorScheme == .light)
    }

    @Test("dark forces dark")
    func darkForcesDark() {
        #expect(AppearanceMode.dark.preferredColorScheme == .dark)
    }

    @Test("unknown stored value has no case (falls back via AppStorage default)")
    func unknownRawValueIsNil() {
        #expect(AppearanceMode(rawValue: "bogus") == nil)
    }

    @Test("all three modes are selectable")
    func allCases() {
        #expect(AppearanceMode.allCases == [.system, .light, .dark])
    }
}
