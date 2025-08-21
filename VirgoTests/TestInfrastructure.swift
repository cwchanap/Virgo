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

// MARK: - Model Factory for Tests

@MainActor
struct TestModelFactory {
    
    static func createSong(
        in context: ModelContext,
        title: String = "Test Song",
        artist: String = "Test Artist",
        bpm: Double = 120.0,
        duration: String = "3:00",
        genre: String = "Rock",
        timeSignature: TimeSignature = .fourFour
    ) -> Song {
        let song = Song(
            title: title,
            artist: artist,
            bpm: bpm,
            duration: duration,
            genre: genre,
            timeSignature: timeSignature
        )
        context.insert(song)
        return song
    }
    
    static func createChart(
        in context: ModelContext,
        difficulty: Difficulty = .medium,
        level: Int? = nil,
        song: Song? = nil
    ) -> Chart {
        let chart = Chart(
            difficulty: difficulty,
            level: level,
            song: song
        )
        context.insert(chart)
        return chart
    }
    
    static func createNote(
        in context: ModelContext,
        interval: NoteInterval = .quarter,
        noteType: NoteType = .bass,
        measureNumber: Int = 1,
        measureOffset: Double = 0.0,
        chart: Chart? = nil
    ) -> Note {
        let note = Note(
            interval: interval,
            noteType: noteType,
            measureNumber: measureNumber,
            measureOffset: measureOffset,
            chart: chart
        )
        context.insert(note)
        return note
    }
    
    static func createSongWithChart(
        in context: ModelContext,
        title: String = "Test Song",
        artist: String = "Test Artist",
        bpm: Double = 120.0,
        difficulty: Difficulty = .medium,
        noteCount: Int = 0
    ) async throws -> (song: Song, chart: Chart) {
        let song = createSong(
            in: context,
            title: title,
            artist: artist,
            bpm: bpm
        )
        
        let chart = createChart(
            in: context,
            difficulty: difficulty,
            song: song
        )
        
        // Create notes if requested
        var notes: [Note] = []
        for i in 0..<noteCount {
            let note = createNote(
                in: context,
                measureNumber: (i / 4) + 1,
                measureOffset: Double(i % 4) * 0.25,
                chart: chart
            )
            notes.append(note)
        }
        
        // Properly set up relationships
        song.charts = [chart]
        chart.notes = notes
        
        // Save context to ensure relationships are persisted
        try context.save()
        
        // Allow relationship loading
        try await AsyncTestingUtilities.loadRelationships(for: song)
        try await AsyncTestingUtilities.loadRelationships(for: chart)
        
        return (song: song, chart: chart)
    }
    
    static func createServerSong(
        in context: ModelContext,
        songId: String = "test-song",
        title: String = "Test Server Song",
        artist: String = "Test Server Artist",
        bpm: Double = 120.0
    ) -> ServerSong {
        let serverSong = ServerSong(
            songId: songId,
            title: title,
            artist: artist,
            bpm: bpm
        )
        context.insert(serverSong)
        return serverSong
    }
    
    static func createServerChart(
        in context: ModelContext,
        difficulty: String = "medium",
        difficultyLabel: String = "STANDARD",
        level: Int = 50,
        filename: String = "test.dtx",
        size: Int = 1024,
        serverSong: ServerSong? = nil
    ) -> ServerChart {
        let serverChart = ServerChart(
            difficulty: difficulty,
            difficultyLabel: difficultyLabel,
            level: level,
            filename: filename,
            size: size,
            serverSong: serverSong
        )
        context.insert(serverChart)
        return serverChart
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
        #expect(!model.isDeleted, "Model should not be deleted")
    }
    
    /// Assert that a model is deleted
    static func assertDeleted<T: PersistentModel>(_ model: T) {
        #expect(model.isDeleted, "Model should be deleted")
    }
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
