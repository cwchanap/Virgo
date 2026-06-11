//
//  DTXAPIClientTests.swift
//  VirgoTests
//
//  Created by Claude Code on 19/8/2025.
//

import Testing
import Foundation
@testable import Virgo

/// Core DTX API Client functionality tests
/// Additional tests in: DTXAPIClientInitTests, DTXAPIClientNetworkingTests
@Suite("DTX API Client Core Tests", .serialized)
struct DTXAPIClientTests {

    @Test("DTXAPIClient initializes with correct configuration")
    func testAPIClientInitialization() {
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "DTXAPIClientTests.init.\(UUID().uuidString)"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let client = DTXAPIClient(userDefaults: userDefaults)
        
        // Should initialize without crashing
        #expect(client.session != nil)
    }
}
