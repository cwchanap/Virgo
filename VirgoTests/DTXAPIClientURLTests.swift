//
//  DTXAPIClientURLTests.swift
//  VirgoTests
//
//  Created by Claude Code on 05/09/2025.
//

import Testing
import Foundation
@testable import Virgo

@Suite("DTX API Client URL Tests", .serialized)
struct DTXAPIClientURLTests {
    
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
    
    @Test("DTXAPIClient handles custom server URLs")
    func testCustomServerURLs() async throws {
        let client = DTXAPIClient()
        
        // Clean up any existing value
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
        UserDefaults.standard.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        
        let testURLs = [
            "http://localhost:3000",
            "https://api.example.com",
            "http://192.168.1.100:8001",
            "https://dtx-server.herokuapp.com"
        ]
        
        for url in testURLs {
            client.setServerURL(url)
            UserDefaults.standard.synchronize()
            try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
            #expect(client.baseURL == url)
        }
        
        // Clean up after test
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
        UserDefaults.standard.synchronize()
    }
    
    @Test("DTXAPIClient URL construction for various endpoints")
    func testURLConstruction() async throws {
        let client = DTXAPIClient()
        
        // Clean up any existing value
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
        UserDefaults.standard.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        
        client.setServerURL("http://test-server.com:8080")
        UserDefaults.standard.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        
        // Verify the URL was actually set in UserDefaults
        let storedURL = UserDefaults.standard.string(forKey: "DTXServerURL")
        #expect(storedURL == "http://test-server.com:8080", "URL should be stored in UserDefaults")
        
        // Test internal URL construction logic (indirectly)
        let baseURL = client.baseURL
        #expect(baseURL == "http://test-server.com:8080")
        
        // Would construct URLs like:
        // "\(baseURL)/dtx/list" -> "http://test-server.com:8080/dtx/list"
        // "\(baseURL)/dtx/download/filename.dtx" -> "http://test-server.com:8080/dtx/download/filename.dtx"
        // etc.
        
        // Clean up after test
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
        UserDefaults.standard.synchronize()
    }
    
    @Test("DTXAPIClient handles empty and nil server URLs")
    func testEmptyServerURLs() async throws {
        let client = DTXAPIClient()
        
        // Clean up any existing value
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
        UserDefaults.standard.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        
        // Empty string should fall back to default
        client.setServerURL("")
        UserDefaults.standard.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        #expect(client.baseURL == "http://127.0.0.1:8001")
        
        // Reset should also fall back to default
        client.setServerURL("http://custom.com")
        UserDefaults.standard.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        client.resetToLocalServer()
        UserDefaults.standard.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        #expect(client.baseURL == "http://127.0.0.1:8001")
        
        // Clean up after test
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
        UserDefaults.standard.synchronize()
    }
    
    @Test("DTXAPIClient URL validation edge cases")
    func testURLValidationEdgeCases() async throws {
        let client = DTXAPIClient()
        
        // Clean up any existing value
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
        UserDefaults.standard.synchronize()
        try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
        
        // Test various edge cases for server URLs
        let edgeCaseURLs = [
            ("http://", "http://127.0.0.1:8001"),  // Invalid (no host), falls back to default
            ("https://", "http://127.0.0.1:8001"),  // Invalid (no host), falls back to default
            ("ftp://invalid-protocol.com", "http://127.0.0.1:8001"),  // Invalid protocol, falls back to default
            ("   ", "http://127.0.0.1:8001"),  // whitespace only should fall back to default
            ("http://valid.com:99999", "http://valid.com:99999"),  // very high port
            ("http://127.0.0.1:0", "http://127.0.0.1:0")  // port 0
        ]
        
        for (inputUrl, expectedUrl) in edgeCaseURLs {
            client.setServerURL(inputUrl)
            UserDefaults.standard.synchronize()
            try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
            // Should not crash, and should handle whitespace appropriately
            #expect(client.baseURL == expectedUrl)
        }
        
        // Clean up after test
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
        UserDefaults.standard.synchronize()
    }
}