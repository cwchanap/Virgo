//
//  PerformanceTestUtilities.swift
//  VirgoTests
//
//  Created by Claude Code on 28/12/2025.
//

import Foundation
import Testing

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
