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
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "DTXAPIClientConcurrencyTests.invalidURL.\(UUID().uuidString)"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let client = DTXAPIClient(userDefaults: userDefaults)

        // Clean up any existing value
        userDefaults.removeObject(forKey: "DTXServerURL")
        userDefaults.synchronize()

        client.setServerURL("invalid-url-format")
        userDefaults.synchronize()

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
        userDefaults.removeObject(forKey: "DTXServerURL")
        userDefaults.synchronize()
    }
    
    @Test("DTXAPIClient UserDefaults integration")
    func testUserDefaultsIntegration() async throws {
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "DTXAPIClientConcurrencyTests.userDefaults.\(UUID().uuidString)"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let client = DTXAPIClient(userDefaults: userDefaults)
        let testKey = "DTXServerURL"
        
        // Clean up any existing value
        userDefaults.removeObject(forKey: testKey)
        userDefaults.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        
        // Test setting and getting URL through UserDefaults
        let testURL = "http://test-integration.com:9999"
        client.setServerURL(testURL)
        userDefaults.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        
        let storedURL = userDefaults.string(forKey: testKey)
        #expect(storedURL == testURL)
        #expect(client.baseURL == testURL)
        
        // Test reset
        client.resetToLocalServer()
        userDefaults.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        let resetStoredURL = userDefaults.string(forKey: testKey)
        #expect(resetStoredURL == nil)
        #expect(client.baseURL == "http://127.0.0.1:8001")
        
        // Clean up
        userDefaults.removeObject(forKey: testKey)
        userDefaults.synchronize()
    }
    
    @Test("DTXAPIClient handles concurrent configuration changes")
    func testConcurrentConfigurationChanges() async throws {
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "DTXAPIClientConcurrencyTests.concurrent.\(UUID().uuidString)"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let client = DTXAPIClient(userDefaults: userDefaults)
        
        // Clean up any existing value
        userDefaults.removeObject(forKey: "DTXServerURL")
        userDefaults.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        
        // Test concurrent URL changes
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    client.setServerURL("http://server\(i).com")
                    userDefaults.synchronize()
                    _ = client.baseURL
                    client.resetToLocalServer()
                    userDefaults.synchronize()
                }
            }
        }
        
        // Allow final operations to complete
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        
        // Should not crash and should have consistent final state
        #expect(client.baseURL == "http://127.0.0.1:8001")
        
        // Clean up after test
        userDefaults.removeObject(forKey: "DTXServerURL")
        userDefaults.synchronize()
    }
}
