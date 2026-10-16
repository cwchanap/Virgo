//
//  SwiftUITestUtilitiesTests.swift
//  VirgoTests
//
//  Contract tests for the shared `SwiftUITestUtilities` render helpers that
//  every SwiftUI rendering test relies on: mounting must not create visible
//  windows (the CLAUDE.md macOS window-restoration lesson), and hierarchy
//  inspection must see post-`onAppear` state.
//

import Testing
import SwiftUI
import Foundation
#if os(macOS)
import AppKit
#endif
@testable import Virgo

@Suite("SwiftUI Test Utilities Tests", .serialized)
@MainActor
struct SwiftUITestUtilitiesTests {
    private struct MountedLifecycleTextView: View {
        @State private var text = "Initial Text"

        var body: some View {
            Text(text)
                .onAppear {
                    text = "Mounted Text"
                }
        }
    }

    @Test("Render helper does not create visible windows")
    func testRenderHelperDoesNotCreateVisibleWindows() async throws {
        try await TestSetup.withTestSetup {
            #if os(macOS)
            let initialVisibleWindowCount = NSApp.windows.filter(\.isVisible).count

            SwiftUITestUtilities.assertViewWithEnvironment(Text("Offscreen Render"))

            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            let finalVisibleWindowCount = NSApp.windows.filter(\.isVisible).count
            #expect(finalVisibleWindowCount == initialVisibleWindowCount)
            #endif
        }
    }

    @Test("assertView inspects the mounted hierarchy after onAppear updates")
    func testAssertViewUsesMountedHierarchyAfterOnAppear() async throws {
        try await TestSetup.withTestSetup {
            SwiftUITestUtilities.assertView(
                MountedLifecycleTextView(),
                containsStrings: ["Mounted Text"],
                excludesStrings: ["Initial Text"]
            )
        }
    }
}
