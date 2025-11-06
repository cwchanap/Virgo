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
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        
        // Test concurrent URL changes
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    client.setServerURL("http://server\(i).com")
                    UserDefaults.standard.synchronize()
                    _ = client.baseURL
                    client.resetToLocalServer()
                    UserDefaults.standard.synchronize()
                }
            }
        }
        
        // Allow final operations to complete
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        
        // Should not crash and should have consistent final state
        #expect(client.baseURL == "http://127.0.0.1:8001")
        
        // Clean up after test
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
        UserDefaults.standard.synchronize()
    }
}