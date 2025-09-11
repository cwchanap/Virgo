//
//  DTXAPIClientInitTests.swift
//  VirgoTests
//
//  Created by Claude Code on 05/09/2025.
//

import Testing
import Foundation
@testable import Virgo

@Suite("DTX API Client Initialization Tests", .serialized)
struct DTXAPIClientInitTests {
    
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
    
    @Test("DTXAPIClient protocols conformance")
    func testProtocolConformance() {
        let client = DTXAPIClient()
        
        // Test that client conforms to expected protocols
        #expect(client is DTXConfiguration)
        #expect(client is DTXNetworking)
        #expect(client is DTXFileOperations)
        #expect(client is DTXDownloadOperations)
    }
}