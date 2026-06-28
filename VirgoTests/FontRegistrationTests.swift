// VirgoTests/FontRegistrationTests.swift
import Testing
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import Virgo

@Suite("Font registration")
struct FontRegistrationTests {
    private func fontExists(_ name: String) -> Bool {
        #if canImport(UIKit)
        return UIFont(name: name, size: 12) != nil
        #elseif canImport(AppKit)
        return NSFont(name: name, size: 12) != nil
        #else
        return false
        #endif
    }

    @Test("registering bundled fonts makes the three families resolvable")
    func registersFamilies() {
        AppFonts.registerAll()
        #expect(fontExists(AppFontFamily.serif))
        #expect(fontExists(AppFontFamily.sans))
        #expect(fontExists(AppFontFamily.mono))

        // Test idempotency: calling registerAll() again should not cause issues
        AppFonts.registerAll()
        #expect(fontExists(AppFontFamily.serif))
        #expect(fontExists(AppFontFamily.sans))
        #expect(fontExists(AppFontFamily.mono))
    }
}
