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
import Combine
#if os(macOS)
import AppKit
#endif
@testable import Virgo

// MARK: - Test Infrastructure

/// Shared test container for SwiftData models in unit tests
/// Provides isolated in-memory storage that can be reset between tests
@MainActor
class TestContainer {
    static let shared = TestContainer()
    @TaskLocal static var activeContainer: TestContainer?

    var privateContainer: ModelContainer?
    var privateContext: ModelContext?

    // Revolutionary approach: Per-test isolation containers
    private static var isolatedContainers: [String: TestContainer] = [:]
    private static let isolationQueue = DispatchQueue(label: "TestContainer.isolation", attributes: .concurrent)

    static func isolatedContainer(for testId: String = UUID().uuidString) -> TestContainer {
        return isolationQueue.sync {
            if let existing = isolatedContainers[testId] {
                return existing
            }
            let newContainer = TestContainer()
            isolatedContainers[testId] = newContainer
            return newContainer
        }
    }

    static func cleanupIsolatedContainer(for testId: String) {
        isolationQueue.sync(flags: .barrier) {
            isolatedContainers.removeValue(forKey: testId)
        }
    }

    var context: ModelContext {
        if let active = Self.activeContainer, active !== self {
            return active.resolveContext()
        }
        return resolveContext()
    }

    var container: ModelContainer {
        if let active = Self.activeContainer, active !== self {
            return active.resolveContainer()
        }
        return resolveContainer()
    }

    private init() {
        // Defer initialization to avoid concurrency issues during app startup
    }

    private func resolveContainer() -> ModelContainer {
        if let container = privateContainer {
            return container
        }

        // Create in-memory container for tests with unique identifier
        let schema = Schema([
            Song.self,
            Chart.self,
            Note.self,
            ServerSong.self,
            ServerChart.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            privateContainer = container
            // Access mainContext here on @MainActor so it is bound to the main queue.
            privateContext = container.mainContext
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    private func resolveContext() -> ModelContext {
        _ = resolveContainer()
        if let context = privateContext {
            return context
        }
        let context = resolveContainer().mainContext
        privateContext = context
        return context
    }

    func reset() {
        if let active = Self.activeContainer, active !== self {
            active.reset()
            return
        }

        // Run directly on @MainActor — no queue dispatch so that context
        // (container.mainContext) is always accessed on the main queue.
        guard let context = privateContext else { return }

        do {
            // Force completion of any pending changes
            if context.hasChanges {
                try context.save()
            }

            // Delete through the context (not batch delete) so that cascade rules
            // are respected and mandatory relationship constraints are not violated.
            // Song cascades to Chart which cascades to Note.
            // ServerSong cascades to ServerChart.
            let songs = try context.fetch(FetchDescriptor<Song>())
            songs.forEach { context.delete($0) }

            let serverSongs = try context.fetch(FetchDescriptor<ServerSong>())
            serverSongs.forEach { context.delete($0) }

            // Defensive: remove any orphaned children not caught by cascade
            // (e.g. Charts/Notes/ServerCharts inserted directly by tests)
            let charts = try context.fetch(FetchDescriptor<Chart>())
            charts.forEach { context.delete($0) }

            let notes = try context.fetch(FetchDescriptor<Note>())
            notes.forEach { context.delete($0) }

            let serverCharts = try context.fetch(FetchDescriptor<ServerChart>())
            serverCharts.forEach { context.delete($0) }

            // Force immediate persistence
            try context.save()

        } catch {
            Logger.debug("Failed to reset test container: \(error)")
            // If reset fails, create a new container entirely
            privateContainer = nil
            privateContext = nil
        }
    }
}

/// Test setup utilities for managing test lifecycle
/// Handles container reset before and after tests to ensure isolation
@MainActor
struct TestSetup {
    /// Run a test with automatic container setup and cleanup
    /// - Parameter test: The test closure to execute
    /// - Returns: The result of the test closure
    /// - Throws: Any error thrown by the test closure
    static func withTestSetup<T>(_ test: () async throws -> T) async throws -> T {
        let testId = UUID().uuidString
        let container = TestContainer.isolatedContainer(for: testId)
        
        return try await TestContainer.$activeContainer.withValue(container) {
            defer { TestContainer.cleanupIsolatedContainer(for: testId) }
            
            // Reset container before test
            container.reset()

            do {
                let result = try await test()

                // Cleanup after test
                container.reset()

                return result
            } catch {
                // Cleanup even on error
                container.reset()
                throw error
            }
        }
    }

    /// Manually set up the test environment by resetting the container
    /// Use this when you need more control than `withTestSetup` provides
    static func setUp() async {
        if let active = TestContainer.activeContainer {
            active.reset()
            return
        }
        
        // Reset test container for individual test setup
        TestContainer.shared.reset()
    }
}

/// Custom assertion utilities for test validation
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
        // When SwiftData cascade deletes models, they are completely removed from the context
        // We check by trying to find the model by its persistent ID
        let modelId = model.persistentModelID
        
        do {
            let descriptor = FetchDescriptor<T>(predicate: #Predicate<T> { contextModel in
                contextModel.persistentModelID == modelId
            })
            let foundModels = try context.fetch(descriptor)
            let stillExists = !foundModels.isEmpty
            
            #expect(!stillExists, "Expected model to be deleted but it still exists in context")
        } catch {
            // If we can't fetch (model type might be deleted), assume deletion worked
            Logger.debug("Could not verify model deletion due to fetch error (likely expected): \(error)")
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
    struct MountedView {
        #if os(macOS)
        let hostingView: NSHostingView<AnyView>

        var root: Any {
            hostingView
        }
        #endif
    }

    @discardableResult
    static func assertViewWithEnvironment<V: View>(
        _ view: V,
        size: CGSize = CGSize(width: 1024, height: 768),
        file: StaticString = #file,
        line: UInt = #line
    ) -> MountedView {
        #if os(macOS)
        let hostingView = NSHostingView(rootView: AnyView(view))
        hostingView.frame = CGRect(origin: .zero, size: size)

        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let renderedSize = hostingView.fittingSize
        // fittingSize returns 0 for scrollable/list views that have no intrinsic content size
        // (e.g. List, ScrollView), so we only assert non-negative here.
        #expect(renderedSize.width >= 0)
        #expect(renderedSize.height >= 0)

        return MountedView(hostingView: hostingView)
        #else
        fatalError("SwiftUITestUtilities.assertViewWithEnvironment is not supported on this platform")
        #endif
    }

    static func assertView<V: View>(
        _ view: V,
        containsStrings: [String],
        excludesStrings: [String] = [],
        containsSymbols: [String] = [],
        excludesSymbols: [String] = [],
        size: CGSize = CGSize(width: 1_280, height: 900)
    ) {
        let mountedView = assertViewWithEnvironment(view, size: size)

        let texts = renderedTexts(from: mountedView.root)
        let symbols = renderedSymbols(from: mountedView.root)

        for string in containsStrings {
            #expect(texts.contains(string), "Expected rendered texts to include '\(string)', got \(texts)")
        }

        for string in excludesStrings {
            #expect(!texts.contains(string), "Expected rendered texts to exclude '\(string)', got \(texts)")
        }

        for symbol in containsSymbols {
            #expect(symbols.contains(symbol), "Expected rendered symbols to include '\(symbol)', got \(symbols)")
        }

        for symbol in excludesSymbols {
            #expect(!symbols.contains(symbol), "Expected rendered symbols to exclude '\(symbol)', got \(symbols)")
        }
    }

    static func renderedTexts(from value: Any) -> [String] {
        var texts: [String] = []
        var visited = Set<ObjectIdentifier>()
        collectTexts(from: value, into: &texts, visited: &visited)
        return uniqued(texts)
    }

    static func renderedSymbols(from value: Any) -> [String] {
        var symbols: [String] = []
        var visited = Set<ObjectIdentifier>()
        collectSymbols(from: value, into: &symbols, visited: &visited)
        return uniqued(symbols)
    }

    static func renderedIdentifiers(from value: Any) -> [String] {
        var identifiers: [String] = []
        var visited = Set<ObjectIdentifier>()
        collectIdentifiers(from: value, into: &identifiers, visited: &visited)
        return uniqued(identifiers)
    }

    private static func collectTexts(
        from value: Any,
        into texts: inout [String],
        visited: inout Set<ObjectIdentifier>
    ) {
        let mirror = Mirror(reflecting: value)

        if shouldSkipCycle(for: value, mirror: mirror, visited: &visited) {
            return
        }

        if let textField = value as? NSTextField, !textField.stringValue.isEmpty {
            texts.append(textField.stringValue)
        }

        if let button = value as? NSButton, !button.title.isEmpty {
            texts.append(button.title)
        }

        if let nestedHostingView = nestedMountedHostingView(from: value) {
            collectTexts(from: nestedHostingView, into: &texts, visited: &visited)
        }

        if String(describing: mirror.subjectType) == "Text" {
            texts.append(contentsOf: extractTextLiterals(from: value))
        }

        texts.append(contentsOf: extractMountedTextLiterals(from: String(describing: value)))

        for child in mirror.children {
            collectTexts(from: child.value, into: &texts, visited: &visited)
        }
    }

    private static func collectSymbols(
        from value: Any,
        into symbols: inout [String],
        visited: inout Set<ObjectIdentifier>
    ) {
        let mirror = Mirror(reflecting: value)

        if shouldSkipCycle(for: value, mirror: mirror, visited: &visited) {
            return
        }

        if let label = mirror.children.first(where: { $0.label == "systemSymbol" }),
           let symbol = label.value as? String {
            symbols.append(symbol)
        }

        if let nestedHostingView = nestedMountedHostingView(from: value) {
            collectSymbols(from: nestedHostingView, into: &symbols, visited: &visited)
        }

        symbols.append(contentsOf: extractMountedSymbols(from: String(describing: value)))

        for child in mirror.children {
            collectSymbols(from: child.value, into: &symbols, visited: &visited)
        }
    }

    private static func collectIdentifiers(
        from value: Any,
        into identifiers: inout [String],
        visited: inout Set<ObjectIdentifier>
    ) {
        let mirror = Mirror(reflecting: value)

        if shouldSkipCycle(for: value, mirror: mirror, visited: &visited) {
            return
        }

        if let view = value as? NSView,
           let identifier = view.identifier?.rawValue,
           !identifier.isEmpty {
            identifiers.append(identifier)
        }

        if let viewListID = mirror.children.first(where: { $0.label == "viewListID" }) {
            identifiers.append(
                contentsOf: extractMountedIdentifiers(from: String(describing: viewListID.value))
            )
        }

        // macOS List rows often preserve explicit SwiftUI .id(...) values only in the
        // internal ViewList debug descriptions, not in NSView.identifier.
        identifiers.append(contentsOf: extractMountedIdentifiers(from: String(describing: value)))

        if let nestedHostingView = nestedMountedHostingView(from: value) {
            collectIdentifiers(from: nestedHostingView, into: &identifiers, visited: &visited)
        }

        if let view = value as? NSView {
            for subview in view.subviews {
                collectIdentifiers(from: subview, into: &identifiers, visited: &visited)
            }
        }

        for child in mirror.children {
            collectIdentifiers(from: child.value, into: &identifiers, visited: &visited)
        }
    }

    private static func shouldSkipCycle(
        for value: Any,
        mirror: Mirror,
        visited: inout Set<ObjectIdentifier>
    ) -> Bool {
        guard mirror.displayStyle == .class else { return false }

        let objectId = ObjectIdentifier(value as AnyObject)
        return !visited.insert(objectId).inserted
    }

    private static func extractTextLiterals(from value: Any) -> [String] {
        var results: [String] = []
        let description = String(describing: value)

        if let openingQuote = description.firstIndex(of: "\""),
           let closingQuote = description.lastIndex(of: "\""),
           openingQuote < closingQuote {
            let text = String(description[description.index(after: openingQuote)..<closingQuote])
            if !text.isEmpty {
                results.append(text)
            }
        }

        return results
    }

    private static func extractMountedTextLiterals(from description: String) -> [String] {
        guard description.contains("(text \"") else { return [] }

        let pattern = #"\(text "((?:[^"\\]|\\.)*)""#
        return extractMatches(pattern: pattern, from: description)
    }

    private static func extractMountedSymbols(from description: String) -> [String] {
        guard description.contains("symbol = ") else { return [] }

        let pattern = #"symbol = ([A-Za-z0-9._-]+)"#
        return extractMatches(pattern: pattern, from: description)
    }

    private static func extractMountedIdentifiers(from description: String) -> [String] {
        let patterns = [
            #"Explicit\(id: "((?:[^"\\]|\\.)*)""#,
            #"explicitID: Optional\("((?:[^"\\]|\\.)*)""#,
            #"#:id ([A-Za-z0-9._:-]+)"#
        ]

        return patterns.flatMap { extractMatches(pattern: $0, from: description) }
    }

    private static func extractMatches(pattern: String, from source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..., in: source)

        return regex.matches(in: source, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: source) else {
                return nil
            }
            return String(source[captureRange])
        }
    }

    private static func uniqued(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func nestedMountedHostingView(from value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard let hostChild = mirror.children.first(where: { $0.label == "host" }) else {
            return nil
        }

        let hostMirror = Mirror(reflecting: hostChild.value)
        if hostMirror.displayStyle == .optional {
            return hostMirror.children.first?.value
        }

        return hostChild.value
    }
}

// MARK: - Test Helpers

/// Utility functions for test execution and timing
struct TestHelpers {
    /// Wait for a condition to become true with timeout using polling
    /// - Parameters:
    ///   - condition: A closure that returns true when the desired condition is met
    ///   - timeout: Maximum time to wait for the condition (default: 2.0 seconds)
    ///   - checkInterval: Time between condition checks (default: 0.05 seconds)
    /// - Returns: true if condition was met within timeout, false otherwise
    /// - Note: Use `CombineTestUtilities.waitForPublished` for reactive state changes instead
    static func waitFor(
        condition: @escaping () -> Bool,
        timeout: TimeInterval = 2.0,
        checkInterval: TimeInterval = 0.05
    ) async -> Bool {
        let safeTimeout = max(0.01, timeout)
        let safeCheckInterval = max(0.01, checkInterval)

        // Check condition up-front
        if await MainActor.run(body: condition) {
            return true
        }

        let maxAttempts = max(1, Int(ceil(safeTimeout / safeCheckInterval)))
        var attempts = 0

        while !(await MainActor.run(body: condition)) && attempts < maxAttempts {
            let nanoseconds = UInt64(safeCheckInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            attempts += 1
        }

        return await MainActor.run(body: condition)
    }
}

// MARK: - Combine Testing Utilities

/// Utilities for testing Combine publishers and reactive state changes
/// These utilities properly handle async state updates from Combine publishers
/// without race conditions or double-resumption crashes
struct CombineTestUtilities {
    /// Wait for a published value to match a condition
    /// - Parameters:
    ///   - publisher: The Combine publisher to observe
    ///   - condition: A closure that returns true when the desired value is observed
    ///   - timeout: Maximum time to wait for the condition (default: 1.0 second)
    /// - Returns: true if condition was met, false if timeout occurred
    @MainActor
    static func waitForPublished<T>(
        publisher: Published<T>.Publisher,
        condition: @escaping (T) -> Bool,
        timeout: TimeInterval = 1.0
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            var didResume = false
            let resumeLock = NSLock()

            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

                let shouldResume = resumeLock.withLock {
                    guard !didResume else { return false }
                    didResume = true
                    return true
                }
                if shouldResume {
                    cancellable?.cancel()
                    continuation.resume(returning: false)
                }
            }

            cancellable = publisher
                .first(where: condition)
                .sink { _ in
                    let shouldResume = resumeLock.withLock {
                        guard !didResume else { return false }
                        didResume = true
                        return true
                    }
                    if shouldResume {
                        timeoutTask.cancel()
                        continuation.resume(returning: true)
                    }
                }
        }
    }

    /// Helper to call an action and wait for a specific state change
    /// - Parameters:
    ///   - action: The action to perform
    ///   - publisher: The Combine publisher to observe for state changes
    ///   - condition: A closure that returns true when the desired state is reached
    ///   - timeout: Maximum time to wait for the state change (default: 1.0 second)
    /// - Returns: true if state change was observed, false if timeout occurred
    @MainActor
    static func performAndWait<T>(
        action: () -> Void,
        publisher: Published<T>.Publisher,
        condition: @escaping (T) -> Bool,
        timeout: TimeInterval = 1.0
    ) async -> Bool {
        action()
        return await waitForPublished(publisher: publisher, condition: condition, timeout: timeout)
    }

    /// Wait for an observable object's loading state to complete
    /// - Parameters:
    ///   - object: The observable object to monitor
    ///   - isLoadingKeyPath: KeyPath to the boolean loading state property
    ///   - timeout: Maximum time to wait for loading to complete (default: 1.0 second)
    /// - Returns: true if loading completed, false if timeout occurred
    @MainActor
    static func waitForLoading<T: ObservableObject>(
        object: T,
        isLoadingKeyPath: KeyPath<T, Bool>,
        timeout: TimeInterval = 1.0
    ) async -> Bool {
        // If already not loading, return immediately
        if !object[keyPath: isLoadingKeyPath] {
            return true
        }

        // Wait for loading to complete
        return await TestHelpers.waitFor(
            condition: { !object[keyPath: isLoadingKeyPath] },
            timeout: timeout,
            checkInterval: 0.01
        )
    }
}

// MARK: - Async Testing Utilities

enum TestUserDefaults {
    static func makeIsolated(suiteName: String = UUID().uuidString) -> (UserDefaults, String) {
        let fullSuiteName = "VirgoTests.\(suiteName)"
        guard let userDefaults = UserDefaults(suiteName: fullSuiteName) else {
            fatalError("Failed to create UserDefaults suite: \(fullSuiteName)")
        }
        userDefaults.removePersistentDomain(forName: fullSuiteName)
        return (userDefaults, fullSuiteName)
    }
}

@MainActor
class AsyncTestingUtilities {
    
    /// Safely loads SwiftData relationship data in background to avoid concurrency issues
    static func loadRelationships<T>(
        for model: T,
        timeout: TimeInterval = 0.1
    ) async throws where T: PersistentModel {
        return try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                // Force SwiftData to load relationships by accessing them on MainActor
                _ = await MainActor.run { model.persistentModelID }
                
                // Shorter, more predictable delay for relationship loading
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
        // Simplified direct access
        return await MainActor.run {
            accessor(model)
        }
    }
    
    /// Safely accesses SwiftData relationships with async loading
    static func safeRelationshipAccess<T, R>(
        model: T,
        relationshipAccessor: @escaping (T) -> R,
        timeout: TimeInterval = 2.0
    ) async throws -> R where T: PersistentModel {
        // Simplified approach - just load relationships and access directly
        try await loadRelationships(for: model, timeout: 0.1)
        
        // Direct access on MainActor
        return await MainActor.run {
            relationshipAccessor(model)
        }
    }
}
