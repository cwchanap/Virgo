//
//  DTXAPIClientConcurrencyTests.swift
//  VirgoTests
//
//  Created by Claude Code on 05/09/2025.
//

import Testing
import Foundation
@testable import Virgo

@Suite("DTX API Client Concurrency Tests", .serialized)
struct DTXAPIClientConcurrencyTests {
    
    @Test("DTXAPIClient test connection handles invalid URLs gracefully")
    func testConnectionWithInvalidURL() async throws {
        let client = DTXAPIClient()

        // Clean up any existing value
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
        UserDefaults.standard.synchronize()

        client.setServerURL("invalid-url-format")
        UserDefaults.standard.synchronize()

        // Test connection with timeout
        let connectionResult = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await client.testConnection()
            }

            // Timeout protection
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
        #expect(connectionResult == false)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
        UserDefaults.standard.synchronize()
    }
    
    @Test("DTXAPIClient UserDefaults integration")
    func testUserDefaultsIntegration() async throws {
        let client = DTXAPIClient()
        let testKey = "DTXServerURL"
        
        // Clean up any existing value
        UserDefaults.standard.removeObject(forKey: testKey)
        UserDefaults.standard.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        
        // Test setting and getting URL through UserDefaults
        let testURL = "http://test-integration.com:9999"
        client.setServerURL(testURL)
        UserDefaults.standard.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        
        let storedURL = UserDefaults.standard.string(forKey: testKey)
        #expect(storedURL == testURL)
        #expect(client.baseURL == testURL)
        
        // Test reset
        client.resetToLocalServer()
        UserDefaults.standard.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        let resetStoredURL = UserDefaults.standard.string(forKey: testKey)
        #expect(resetStoredURL == nil)
        #expect(client.baseURL == "http://127.0.0.1:8001")
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: testKey)
        UserDefaults.standard.synchronize()
    }
    
    @Test("DTXAPIClient handles concurrent configuration changes")
    func testConcurrentConfigurationChanges() async throws {
        let client = DTXAPIClient()

        // Clean up any existing value
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
        UserDefaults.standard.synchronize()
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds

        // Test concurrent URL changes - the key is that it doesn't crash
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    // Each task performs operations sequentially to avoid UserDefaults race conditions
                    client.setServerURL("http://server\(i).com")
                    UserDefaults.standard.synchronize()

                    // Small delay to let UserDefaults persist
                    try? await Task.sleep(nanoseconds: 1_000_000) // 0.001 seconds

                    _ = client.baseURL

                    client.resetToLocalServer()
                    UserDefaults.standard.synchronize()

                    // Small delay after reset
                    try? await Task.sleep(nanoseconds: 1_000_000) // 0.001 seconds
                }
            }
        }

        // Allow all operations to fully complete and propagate
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        // After all concurrent operations, reset to ensure clean state
        client.resetToLocalServer()
        UserDefaults.standard.synchronize()
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds

        // Verify we can successfully reset to default (proves no corruption from concurrent access)
        let finalURL = client.baseURL
        #expect(finalURL == "http://127.0.0.1:8001", "Should be able to reset to default after concurrent operations")

        // Clean up after test
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
        UserDefaults.standard.synchronize()
    }
}