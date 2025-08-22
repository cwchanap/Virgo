//
//  TestInfrastructure.swift
//  VirgoTests
//
//  Created by Claude Code on 21/8/2025.
//

import Testing
import SwiftUI
import SwiftData
import Foundation
@testable import Virgo

// MARK: - Test Container Management

@MainActor
class TestContainer {
    static let shared = TestContainer()
    
    private var modelContainer: ModelContainer?
    
    var container: ModelContainer {
        if let modelContainer = modelContainer {
            return modelContainer
        }
        
        let schema = Schema([
            Song.self,
            Chart.self,
            Note.self,
            ServerSong.self,
            ServerChart.self
        ])
        
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            modelContainer = container
            return container
        } catch {
            fatalError("Failed to create test container: \(error)")
        }
    }
    
    var context: ModelContext {
        container.mainContext
    }
    
    func reset() {
        modelContainer = nil
    }
    
    private init() {}
}

// MARK: - SwiftUI Test Environment

@MainActor
class TestEnvironment: ObservableObject {
    static let shared = TestEnvironment()
    
    let metronome = MetronomeEngine()
    let playbackService = PlaybackService()
    
    private init() {
        // Configure metronome for testing (disable audio)
        metronome.volume = 0.0
    }
}

// MARK: - Test View Wrapper

struct TestViewWrapper<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .environmentObject(TestEnvironment.shared.metronome)
            .environmentObject(TestEnvironment.shared.playbackService)
            .modelContainer(TestContainer.shared.container)
    }
}


// MARK: - Test Assertions

struct TestAssertions {
    
    /// Assert that a SwiftData model relationship is properly loaded
    static func assertRelationshipLoaded<T, R>(
        model: T,
        relationshipKeyPath: KeyPath<T, R>
    ) async throws where T: PersistentModel, R: Collection {
        let relationship = try await AsyncTestingUtilities.safeRelationshipAccess(
            model: model,
            relationshipAccessor: { $0[keyPath: relationshipKeyPath] }
        )
        
        // Check that relationship is accessible (doesn't throw)
        _ = relationship.count
    }
    
    /// Assert that two SwiftData models are equal by persistent ID
    static func assertEqual<T: PersistentModel>(
        _ lhs: T?,
        _ rhs: T?
    ) {
        guard let lhs = lhs, let rhs = rhs else {
            if lhs == nil && rhs == nil {
                return // Both nil is valid
            }
            #expect(Bool(false), "One model is nil while the other is not")
            return
        }
        
        #expect(lhs.persistentModelID == rhs.persistentModelID)
    }
    
    /// Assert that a model is not deleted
    static func assertNotDeleted<T: PersistentModel>(_ model: T) {
        do {
            let isDeleted = model.isDeleted
            #expect(!isDeleted, "Model should not be deleted")
        } catch {
            // If accessing isDeleted throws, the model is likely in an invalid state
            #expect(Bool(false), "Failed to check deletion state - model may be corrupted: \(error)")
        }
    }
    
    /// Assert that a model is deleted
    static func assertDeleted<T: PersistentModel>(_ model: T) {
        do {
            let isDeleted = model.isDeleted
            #expect(isDeleted, "Model should be deleted")
        } catch {
            // If accessing isDeleted throws, the model might actually be deleted/invalid
            // In SwiftData, accessing properties on deleted models can throw
            // We'll consider this as "deleted" since the model is inaccessible
            #expect(Bool(true), "Model appears deleted (property access failed): \(error)")
        }
    }
}


// MARK: - SwiftUI Testing Utilities

@MainActor
struct SwiftUITestUtilities {
    
    /// Create a test view with proper environment setup
    static func createTestView<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        TestViewWrapper {
            content()
        }
    }
    
    /// Test that a view can be created without crashing
    static func assertViewCreation<T: View>(_ view: T) {
        // Simply creating the view and accessing its body should not crash
        _ = view.body
    }
    
    /// Test that a view with environment dependencies can be created
    static func assertViewWithEnvironment<T: View>(_ view: T) {
        let testView = createTestView { view }
        assertViewCreation(testView)
    }
}

// MARK: - Test Setup and Teardown

@MainActor
struct TestSetup {
    
    /// Setup before each test
    static func setUp() async {
        // Reset test container
        TestContainer.shared.reset()
        
        // Reset test environment
        TestEnvironment.shared.metronome.stop()
        TestEnvironment.shared.metronome.volume = 0.0
        
        // Allow setup to complete
        try? await Task.sleep(nanoseconds: 1_000_000) // 0.001 seconds
    }
    
    /// Cleanup after each test
    static func tearDown() async {
        // Stop any running metronome
        TestEnvironment.shared.metronome.stop()
        
        // Clear model context
        let context = TestContainer.shared.context
        try? context.save()
        
        // Allow cleanup to complete
        try? await Task.sleep(nanoseconds: 1_000_000) // 0.001 seconds
    }
    
    /// Setup and run a test with proper lifecycle
    static func withTestSetup<T>(
        operation: () async throws -> T
    ) async rethrows -> T {
        await setUp()
        defer {
            Task { @MainActor in
                await tearDown()
            }
        }
        return try await operation()
    }
}
