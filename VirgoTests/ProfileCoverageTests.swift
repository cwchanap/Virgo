//
//  ProfileCoverageTests.swift
//  VirgoTests
//
//  Created by Copilot on 22/3/2026.
//

import Testing
import SwiftUI
@testable import Virgo

@Suite("Profile Coverage Tests", .serialized)
@MainActor
struct ProfileCoverageTests {

    @Test("ProfileView renders its default layout inside a navigation stack")
    func testProfileViewDefaultRender() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                ProfileView()
            }

            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("ProfileView renders placeholder card rows under a wider layout")
    func testProfileViewWiderLayout() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                ProfileView()
            }

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1440, height: 1200)
            )
        }
    }
}
