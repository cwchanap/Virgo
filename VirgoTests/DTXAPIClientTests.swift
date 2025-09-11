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
/// Additional tests split into: DTXAPIClientInitTests, DTXAPIClientURLTests, DTXAPIClientConcurrencyTests
@Suite("DTX API Client Core Tests", .serialized)
struct DTXAPIClientTests {
    
    init() async throws {
        // Clean UserDefaults before any tests run
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
        UserDefaults.standard.synchronize()
        
        // Small delay to ensure cleanup completes
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
    }
    
    @Test("DTXAPIClient initializes with correct configuration")
    func testAPIClientInitialization() {
        let client = DTXAPIClient()
        
        // Should initialize without crashing
        #expect(client.isLoading == false)
        #expect(client.errorMessage == nil)
        #expect(client.session != nil)
    }
    
    @Test("DTXAPIClient base URL configuration works")
    func testBaseURLConfiguration() async throws {
        let client = DTXAPIClient()
        
        // Clean up any existing value
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
        UserDefaults.standard.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        
        // Default URL
        let defaultURL = client.baseURL
        #expect(defaultURL == "http://127.0.0.1:8001")
        
        // Custom URL
        client.setServerURL("http://custom-server.com:8080")
        UserDefaults.standard.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        let customURL = client.baseURL
        #expect(customURL == "http://custom-server.com:8080")
        
        // Reset to default
        client.resetToLocalServer()
        UserDefaults.standard.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        let resetURL = client.baseURL
        #expect(resetURL == "http://127.0.0.1:8001")
        
        // Clean up after test
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
        UserDefaults.standard.synchronize()
    }
}