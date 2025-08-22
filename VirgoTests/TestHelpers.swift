//
//  TestHelpers.swift
//  VirgoTests
//
//  Created by Claude Code on 22/8/2025.
//

import Testing
import SwiftUI
import SwiftData
import Foundation
@testable import Virgo

// MARK: - Test Helpers

struct TestHelpers {
    /// Wait for a condition to become true with timeout
    static func waitFor(
        condition: @escaping () -> Bool,
        timeout: TimeInterval = 5.0,
        checkInterval: TimeInterval = 0.1
    ) async -> Bool {
        let maxAttempts = Int(timeout / checkInterval)
        var attempts = 0
        
        while !condition() && attempts < maxAttempts {
            try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            attempts += 1
        }
        
        return condition()
    }
}

// MARK: - Async Testing Utilities

@MainActor
class AsyncTestingUtilities {
    
    /// Safely loads SwiftData relationship data in background to avoid concurrency issues
    static func loadRelationships<T>(
        for model: T,
        timeout: TimeInterval = 1.0
    ) async throws where T: PersistentModel {
        return try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                // Force SwiftData to load relationships by accessing them
                _ = model.persistentModelID
                
                // Wait a brief moment for relationship loading
                try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
            }
            
            try await group.waitForAll()
        }
    }
    
    /// Safely accesses SwiftData model properties with timeout
    static func safeAccess<T, R>(
        model: T,
        accessor: @escaping (T) -> R,
        timeout: TimeInterval = 1.0
    ) async throws -> R where T: PersistentModel {
        return try await withThrowingTaskGroup(of: R.self) { group in
            group.addTask {
                let result = accessor(model)
                return result
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TestingError.timeout
            }
            
            guard let result = try await group.next() else {
                throw TestingError.unexpectedNil
            }
            
            group.cancelAll()
            return result
        }
    }
    
    /// Safely accesses SwiftData relationships with async loading
    static func safeRelationshipAccess<T, R>(
        model: T,
        relationshipAccessor: @escaping (T) -> R,
        timeout: TimeInterval = 2.0
    ) async throws -> R where T: PersistentModel {
        // First load relationships
        try await loadRelationships(for: model, timeout: timeout)
        
        // Then safely access them
        return try await safeAccess(
            model: model,
            accessor: relationshipAccessor,
            timeout: timeout
        )
    }
}

// MARK: - Testing Errors

enum TestingError: Error {
    case timeout
    case unexpectedNil
    case concurrencyViolation
    case relationshipNotLoaded
}

// MARK: - Performance Testing Utilities

struct PerformanceTestUtilities {
    
    /// Measure execution time of a closure
    static func measureTime<T>(
        operation: () throws -> T
    ) rethrows -> (result: T, duration: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try operation()
        let endTime = CFAbsoluteTimeGetCurrent()
        return (result: result, duration: endTime - startTime)
    }
    
    /// Measure async execution time of a closure
    static func measureAsyncTime<T>(
        operation: () async throws -> T
    ) async rethrows -> (result: T, duration: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await operation()
        let endTime = CFAbsoluteTimeGetCurrent()
        return (result: result, duration: endTime - startTime)
    }
    
    /// Assert that an operation completes within a time limit
    static func assertPerformance<T>(
        maxDuration: TimeInterval,
        operation: () throws -> T
    ) rethrows -> T {
        let (result, duration) = try measureTime(operation: operation)
        #expect(duration < maxDuration, "Operation took \(duration)s, expected < \(maxDuration)s")
        return result
    }
    
    /// Assert that an async operation completes within a time limit
    static func assertAsyncPerformance<T>(
        maxDuration: TimeInterval,
        operation: () async throws -> T
    ) async rethrows -> T {
        let (result, duration) = try await measureAsyncTime(operation: operation)
        #expect(duration < maxDuration, "Async operation took \(duration)s, expected < \(maxDuration)s")
        return result
    }
}