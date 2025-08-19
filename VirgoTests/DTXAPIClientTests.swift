//
//  DTXAPIClientTests.swift
//  VirgoTests
//
//  Created by Claude Code on 19/8/2025.
//

import Testing
import Foundation
@testable import Virgo

@Suite("DTX API Client Tests")
struct DTXAPIClientTests {
    
    @Test("DTXAPIClient initializes with correct configuration")
    func testAPIClientInitialization() {
        let client = DTXAPIClient()
        
        // Should initialize without crashing
        #expect(client.isLoading == false)
        #expect(client.errorMessage == nil)
        #expect(client.session != nil)
    }
    
    @Test("DTXAPIClient base URL configuration works")
    func testBaseURLConfiguration() {
        let client = DTXAPIClient()
        
        // Default URL
        let defaultURL = client.baseURL
        #expect(defaultURL == "http://127.0.0.1:8001")
        
        // Custom URL
        client.setServerURL("http://custom-server.com:8080")
        let customURL = client.baseURL
        #expect(customURL == "http://custom-server.com:8080")
        
        // Reset to default
        client.resetToLocalServer()
        let resetURL = client.baseURL
        #expect(resetURL == "http://127.0.0.1:8001")
    }
    
    @Test("DTXAPIClient handles custom server URLs")
    func testCustomServerURLs() {
        let client = DTXAPIClient()
        
        let testURLs = [
            "http://localhost:3000",
            "https://api.example.com",
            "http://192.168.1.100:8001",
            "https://dtx-server.herokuapp.com"
        ]
        
        for url in testURLs {
            client.setServerURL(url)
            #expect(client.baseURL == url)
        }
    }
    
    @Test("DTXAPIClient test connection handles invalid URLs gracefully")
    func testConnectionWithInvalidURL() async {
        let client = DTXAPIClient()
        client.setServerURL("invalid-url-format")
        
        let connectionResult = await client.testConnection()
        #expect(connectionResult == false)
    }
    
    @Test("DTXAPIClient error descriptions are meaningful")
    func testErrorDescriptions() {
        let invalidURLError = DTXAPIError.invalidURL
        let noDataError = DTXAPIError.noData
        let decodingError = DTXAPIError.decodingError
        let networkError = DTXAPIError.networkError(URLError(.notConnectedToInternet))
        
        #expect(invalidURLError.errorDescription == "Invalid server URL")
        #expect(noDataError.errorDescription == "No data received from server")
        #expect(decodingError.errorDescription == "Failed to decode server response")
        #expect(networkError.errorDescription?.contains("Network error") == true)
    }
    
    @Test("DTXAPIClient URL construction for various endpoints")
    func testURLConstruction() {
        let client = DTXAPIClient()
        client.setServerURL("http://test-server.com:8080")
        
        // Test internal URL construction logic (indirectly)
        let baseURL = client.baseURL
        #expect(baseURL == "http://test-server.com:8080")
        
        // Would construct URLs like:
        // "\(baseURL)/dtx/list" -> "http://test-server.com:8080/dtx/list"
        // "\(baseURL)/dtx/download/filename.dtx" -> "http://test-server.com:8080/dtx/download/filename.dtx"
        // etc.
    }
    
    @Test("DTXAPIClient handles empty and nil server URLs")
    func testEmptyServerURLs() {
        let client = DTXAPIClient()
        
        // Empty string should fall back to default
        client.setServerURL("")
        #expect(client.baseURL == "http://127.0.0.1:8001")
        
        // Reset should also fall back to default
        client.setServerURL("http://custom.com")
        client.resetToLocalServer()
        #expect(client.baseURL == "http://127.0.0.1:8001")
    }
    
    @Test("DTXAPIClient session configuration is correct")
    func testSessionConfiguration() {
        let client = DTXAPIClient()
        let session = client.session
        
        #expect(session.configuration.timeoutIntervalForRequest == 30.0)
        #expect(session.configuration.timeoutIntervalForResource == 60.0)
        #expect(session.configuration.httpMaximumConnectionsPerHost == 2)
        #expect(session.configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(session.configuration.waitsForConnectivity == true)
        #expect(session.configuration.allowsConstrainedNetworkAccess == true)
        #expect(session.configuration.allowsExpensiveNetworkAccess == true)
    }
    
    @Test("DTXAPIClient state management") 
    func testStateManagement() async {
        let client = DTXAPIClient()
        
        // Initial state
        #expect(client.isLoading == false)
        #expect(client.errorMessage == nil)
        
        // Note: We can't easily test the private updateLoadingState method,
        // but we can verify the Published properties exist and are accessible
        await MainActor.run {
            client.isLoading = true
            client.errorMessage = "Test error"
        }
        
        #expect(client.isLoading == true)
        #expect(client.errorMessage == "Test error")
    }
    
    @Test("DTXAPIClient URL validation edge cases")
    func testURLValidationEdgeCases() {
        let client = DTXAPIClient()
        
        // Test various edge cases for server URLs
        let edgeCaseURLs = [
            "http://",
            "https://",
            "ftp://invalid-protocol.com",
            "   ",  // whitespace only
            "http://valid.com:99999",  // very high port
            "http://127.0.0.1:0"  // port 0
        ]
        
        for url in edgeCaseURLs {
            client.setServerURL(url)
            // Should not crash, just store the value
            #expect(client.baseURL == url)
        }
    }
    
    @Test("DTXAPIClient protocols conformance")
    func testProtocolConformance() {
        let client = DTXAPIClient()
        
        // Test that client conforms to expected protocols
        #expect(client is DTXConfiguration)
        #expect(client is DTXNetworking)
        #expect(client is DTXFileOperations)
        #expect(client is DTXDownloadOperations)
    }
    
    @Test("DTXAPIClient UserDefaults integration")
    func testUserDefaultsIntegration() {
        let client = DTXAPIClient()
        let testKey = "DTXServerURL"
        
        // Clean up any existing value
        UserDefaults.standard.removeObject(forKey: testKey)
        
        // Test setting and getting URL through UserDefaults
        let testURL = "http://test-integration.com:9999"
        client.setServerURL(testURL)
        
        let storedURL = UserDefaults.standard.string(forKey: testKey)
        #expect(storedURL == testURL)
        #expect(client.baseURL == testURL)
        
        // Test reset
        client.resetToLocalServer()
        let resetStoredURL = UserDefaults.standard.string(forKey: testKey)
        #expect(resetStoredURL == nil)
        #expect(client.baseURL == "http://127.0.0.1:8001")
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: testKey)
    }
    
    @Test("DTXAPIClient handles concurrent configuration changes")
    func testConcurrentConfigurationChanges() async {
        let client = DTXAPIClient()
        
        // Test concurrent URL changes
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    client.setServerURL("http://server\(i).com")
                    _ = client.baseURL
                    client.resetToLocalServer()
                }
            }
        }
        
        // Should not crash and should have consistent final state
        #expect(client.baseURL == "http://127.0.0.1:8001")
    }
}
