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

    @Test("DTXAPIClient initializes with correct configuration")
    func testAPIClientInitialization() {
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "DTXAPIClientInitTests.init.\(UUID().uuidString)"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let client = DTXAPIClient(userDefaults: userDefaults)
        
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
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "DTXAPIClientInitTests.session.\(UUID().uuidString)"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let client = DTXAPIClient(userDefaults: userDefaults)
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
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "DTXAPIClientInitTests.state.\(UUID().uuidString)"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let client = DTXAPIClient(userDefaults: userDefaults)
        
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
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "DTXAPIClientInitTests.protocols.\(UUID().uuidString)"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let client = DTXAPIClient(userDefaults: userDefaults)
        
        // Test that client conforms to expected protocols
        #expect(client is DTXConfiguration)
        #expect(client is DTXNetworking)
        #expect(client is DTXFileOperations)
        #expect(client is DTXDownloadOperations)
    }
}
