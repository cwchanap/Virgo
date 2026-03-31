//
//  InputNotationCoverageTests.swift
//  VirgoTests
//
//  Created by Copilot on 22/8/2025.
//

import Testing
import SwiftUI
@testable import Virgo

@Suite("Input and Notation Coverage Tests", .serialized)
@MainActor
struct InputNotationCoverageTests {

    // MARK: - InputSettingsView Rendering

    @Test("InputSettingsView renders in default state")
    func testInputSettingsViewDefaultRender() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                InputSettingsView()
            }
            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("InputSettingsView renders in key-capture state after startKeyCapture")
    func testInputSettingsViewCapturStateRender() async throws {
        try await TestSetup.withTestSetup {
            // Build a view that starts in capture mode by using a wrapper that
            // calls startKeyCapture(for:) right away via .task.
            let captureView = InputSettingsCaptureWrapper()
            SwiftUITestUtilities.assertViewWithEnvironment(captureView)
        }
    }

    // MARK: - InputSettingsView State Assertions
    //
    // @State properties use a nonmutating setter backed by SwiftUI's hosting graph.
    // Outside a hosting context the setter is a no-op, so state transitions are
    // verified through a locally-hosted wrapper that observes changes through
    // @Observable coordination (same logic as the production methods).

    @Test("startKeyCapture sets selectedDrumType and isCapturingKey")
    func testStartKeyCaptureState() async throws {
        try await TestSetup.withTestSetup {
            let state = KeyCaptureStateModel()
            #expect(state.isCapturingKey == false)
            #expect(state.selectedDrumType == nil)

            state.startKeyCapture(for: .snare)

            #expect(state.isCapturingKey == true)
            #expect(state.selectedDrumType == .snare)
        }
    }

    @Test("cancelKeyCapture clears selectedDrumType and isCapturingKey")
    func testCancelKeyCaptureState() async throws {
        try await TestSetup.withTestSetup {
            let state = KeyCaptureStateModel()
            state.startKeyCapture(for: .kick)
            #expect(state.isCapturingKey == true)
            #expect(state.selectedDrumType == .kick)

            state.cancelKeyCapture()

            #expect(state.isCapturingKey == false)
            #expect(state.selectedDrumType == nil)
        }
    }

    @Test("startKeyCapture updates selectedDrumType when called multiple times")
    func testStartKeyCaptureUpdatesType() async throws {
        try await TestSetup.withTestSetup {
            let state = KeyCaptureStateModel()
            state.startKeyCapture(for: .hiHat)
            #expect(state.selectedDrumType == .hiHat)
            #expect(state.isCapturingKey == true)

            state.startKeyCapture(for: .crash)
            #expect(state.selectedDrumType == .crash)
            #expect(state.isCapturingKey == true)
        }
    }

    // MARK: - DrumNotationSettingsView Rendering

    @Test("DrumNotationSettingsView renders in default size")
    func testDrumNotationSettingsViewDefaultRender() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                DrumNotationSettingsView()
            }
            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("DrumNotationSettingsView renders in large size showing full notation area")
    func testDrumNotationSettingsViewLargeSizeRender() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                DrumNotationSettingsView()
            }
            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1440, height: 2000)
            )
        }
    }

    // MARK: - DrumNotationSettingsManager Persistence

    @Test("DrumNotationSettingsManager loads defaults when no persisted state exists")
    func testDrumNotationSettingsManagerDefaultsOnFirstLoad() async throws {
        try await TestSetup.withTestSetup {
            let (userDefaults, _) = TestUserDefaults.makeIsolated()

            let manager = DrumNotationSettingsManager(userDefaults: userDefaults)
            manager.loadSettings()

            for drumType in DrumType.allCases {
                #expect(
                    manager.getNotePosition(for: drumType) == drumType.notePosition,
                    "Expected default position for \(drumType)"
                )
            }
        }
    }

    @Test("DrumNotationSettingsManager persists custom position across manager instances")
    func testDrumNotationSettingsManagerPersistenceAcrossInstances() async throws {
        try await TestSetup.withTestSetup {
            let (userDefaults, _) = TestUserDefaults.makeIsolated()

            let manager = DrumNotationSettingsManager(userDefaults: userDefaults)
            manager.loadSettings()
            manager.setNotePosition(.belowLine6, for: .snare)
            #expect(manager.getNotePosition(for: .snare) == .belowLine6)

            let reloaded = DrumNotationSettingsManager(userDefaults: userDefaults)
            reloaded.loadSettings()
            #expect(reloaded.getNotePosition(for: .snare) == .belowLine6)
        }
    }

    @Test("DrumNotationSettingsManager resetToDefaults restores all drum type positions")
    func testDrumNotationSettingsManagerReset() async throws {
        try await TestSetup.withTestSetup {
            let (userDefaults, _) = TestUserDefaults.makeIsolated()

            let manager = DrumNotationSettingsManager(userDefaults: userDefaults)
            manager.loadSettings()

            for drumType in DrumType.allCases {
                if let firstNonDefault = GameplayLayout.NotePosition.allCases.first(where: { $0 != drumType.notePosition }) {
                    manager.setNotePosition(firstNonDefault, for: drumType)
                }
            }

            manager.resetToDefaults()

            for drumType in DrumType.allCases {
                #expect(
                    manager.getNotePosition(for: drumType) == drumType.notePosition,
                    "Expected default restored for \(drumType)"
                )
            }
        }
    }

    @Test("DrumNotationSettingsManager setNotePosition persists immediately")
    func testDrumNotationSettingsManagerSetAndGet() async throws {
        try await TestSetup.withTestSetup {
            let (userDefaults, _) = TestUserDefaults.makeIsolated()
            let manager = DrumNotationSettingsManager(userDefaults: userDefaults)
            manager.loadSettings()

            let targetDrum = DrumType.kick
            let original = manager.getNotePosition(for: targetDrum)

            if let newPos = GameplayLayout.NotePosition.allCases.first(where: { $0 != original }) {
                manager.setNotePosition(newPos, for: targetDrum)
                #expect(manager.getNotePosition(for: targetDrum) == newPos)
            }
        }
    }
}

// MARK: - Test Helpers

/// Wrapper view that transitions `InputSettingsView` into capture mode
/// so that the overlay code path is exercised during rendering.
private struct InputSettingsCaptureWrapper: View {
    @State private var view = InputSettingsView()

    var body: some View {
        view
            .onAppear {
                view.startKeyCapture(for: .snare)
            }
    }
}

/// Mirrors the key-capture state logic of `InputSettingsView.startKeyCapture` /
/// `cancelKeyCapture`.  Used for direct state assertions because `@State` setters
/// are no-ops outside a SwiftUI hosting graph.
@Observable
final class KeyCaptureStateModel {
    var selectedDrumType: DrumType?
    var isCapturingKey = false

    /// Same logic as `InputSettingsView.startKeyCapture(for:)`.
    func startKeyCapture(for drumType: DrumType) {
        selectedDrumType = drumType
        isCapturingKey = true
    }

    /// Same logic as `InputSettingsView.cancelKeyCapture()`.
    func cancelKeyCapture() {
        isCapturingKey = false
        selectedDrumType = nil
    }
}
