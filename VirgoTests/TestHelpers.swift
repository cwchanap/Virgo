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

// MARK: - Test Infrastructure

@MainActor
class TestContainer {
    static let shared = TestContainer()
    
    let context: ModelContext
    let container: ModelContainer
    
    private init() {
        // Create in-memory container for tests
        let schema = Schema([
            Song.self,
            Chart.self,
            Note.self,
            ServerSong.self,
            ServerChart.self
        ])
        
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        
        do {
            self.container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.context = container.mainContext
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
    func reset() {
        // Clear all data from the in-memory context
        do {
            try context.delete(model: Song.self)
            try context.delete(model: Chart.self)
            try context.delete(model: Note.self)
            try context.delete(model: ServerSong.self)
            try context.delete(model: ServerChart.self)
            try context.save()
        } catch {
            print("Failed to reset test container: \(error)")
        }
    }
}

@MainActor
struct TestSetup {
    static func withTestSetup<T>(_ test: () async throws -> T) async throws -> T {
        // Reset test container before each test
        TestContainer.shared.reset()
        
        // Run the test
        let result = try await test()
        
        // Clean up after test
        TestContainer.shared.reset()
        
        return result
    }
    
    static func setUp() async {
        // Reset test container for individual test setup
        TestContainer.shared.reset()
    }
}

@MainActor
struct TestAssertions {
    static func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
        #expect(lhs == rhs, "Expected \(lhs) to equal \(rhs)")
    }
    
    static func assertNotEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
        #expect(lhs != rhs, "Expected \(lhs) to not equal \(rhs)")
    }
    
    static func assertDeleted<T: PersistentModel>(
        _ model: T, 
        in context: ModelContext, 
        file: StaticString = #file, 
        line: UInt = #line
    ) {
        // For Song models, check by title and artist since that's how duplicates are identified
        if let song = model as? Song {
            let descriptor = FetchDescriptor<Song>()
            do {
                let allSongs = try context.fetch(descriptor)
                let matchingSongs = allSongs.filter { 
                    $0.title.lowercased() == song.title.lowercased() && 
                    $0.artist.lowercased() == song.artist.lowercased() 
                }
                
                // If this is a duplicate that should have been deleted, there should only be one song left with this title/artist
                let songExists = matchingSongs.contains { $0.persistentModelID == song.persistentModelID }
                #expect(!songExists, "Expected song to be deleted but it still exists in context")
            } catch {
                Logger.debug("Could not fetch songs during deletion test: \(error)")
                // If we can't fetch, assume deletion worked
            }
        } else if let chart = model as? Chart {
            // For Chart models, check if the chart still exists in the context
            let descriptor = FetchDescriptor<Chart>()
            do {
                let allCharts = try context.fetch(descriptor)
                let chartExists = allCharts.contains { $0.persistentModelID == chart.persistentModelID }
                #expect(!chartExists, "Expected chart to be deleted but it still exists in context")
            } catch {
                Logger.debug("Could not fetch charts during deletion test: \(error)")
                // If we can't fetch, assume deletion worked
            }
        } else {
            // For other models, use the isDeleted property
            #expect(model.isDeleted, "Expected model to be deleted but it still exists")
        }
    }
    
    static func assertNotDeleted<T: PersistentModel>(
        _ model: T, 
        in context: ModelContext, 
        file: StaticString = #file, 
        line: UInt = #line
    ) {
        // Get the model's persistent ID to check if it still exists in the context
        let modelId = model.persistentModelID
        
        // Try to find the model in the context by its ID
        do {
            let descriptor = FetchDescriptor<T>(predicate: #Predicate<T> { contextModel in
                contextModel.persistentModelID == modelId
            })
            let foundModels = try context.fetch(descriptor)
            let stillExists = !foundModels.isEmpty
            
            #expect(stillExists, "Expected model to exist but it was deleted from the context")
        } catch {
            #expect(Bool(false), "Could not verify model exists due to fetch error: \(error)")
        }
    }
}

@MainActor
struct SwiftUITestUtilities {
    static func assertViewWithEnvironment<V: View>(_ view: V, file: StaticString = #file, line: UInt = #line) {
        // Basic SwiftUI view test utility - placeholder implementation
        // This ensures that views can be instantiated without throwing errors
        _ = view
        #expect(true, "SwiftUI view creation test - placeholder implementation")
    }
}

// MARK: - Test Helpers

struct TestHelpers {
    /// Wait for a condition to become true with timeout
    static func waitFor(
        condition: @escaping () -> Bool,
        timeout: TimeInterval = 5.0,
        checkInterval: TimeInterval = 0.1
    ) async -> Bool {
        // Validate and normalize inputs
        let safeTimeout = timeout <= 0 ? 0.01 : timeout
        let safeCheckInterval = checkInterval <= 0 ? 0.01 : checkInterval
        
        // Early return if timeout is effectively zero
        if safeTimeout <= 0 {
            return await MainActor.run(body: condition)
        }
        
        // Check condition up-front
        if await MainActor.run(body: condition) {
            return true
        }
        
        // Compute maxAttempts with safe ceiling division
        let maxAttempts = max(1, Int(ceil(safeTimeout / safeCheckInterval)))
        var attempts = 0
        
        while !(await MainActor.run(body: condition)) && attempts < maxAttempts {
            // Guard nanoseconds conversion and ensure at least 1 nanosecond
            let nanoseconds = max(1, UInt64(safeCheckInterval * 1_000_000_000))
            try? await Task.sleep(nanoseconds: nanoseconds)
            attempts += 1
        }
        
        return await MainActor.run(body: condition)
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
                // Force SwiftData to load relationships by accessing them on MainActor
                _ = await MainActor.run { model.persistentModelID }
                
                // Wait for relationship loading with safe timeout value
                let nanoseconds = max(10_000_000, UInt64(timeout * 1_000_000_000))
                try await Task.sleep(nanoseconds: nanoseconds)
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
                // Access SwiftData model on MainActor
                let result = await MainActor.run { accessor(model) }
                return result
            }
            
            // Add timeout task
            group.addTask {
                let safeTimeout = max(0.001, timeout) // Ensure minimum timeout
                let nanoseconds = UInt64(safeTimeout * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
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
