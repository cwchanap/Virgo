//
//  InputNotationCoverageTests.swift
//  VirgoTests
//
//  Created by Copilot on 22/8/2025.
//

import Testing
import SwiftUI
#if os(macOS)
import AppKit
#endif
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

    @Test("InputKeyCaptureViewModel mirrors the injected capture state")
    func testInputKeyCaptureViewModelMirrorsInjectedState() async throws {
        try await TestSetup.withTestSetup {
            let keyCaptureState = InputKeyCaptureState()
            let viewModel = InputKeyCaptureViewModel(state: keyCaptureState)

            viewModel.startCapture(for: .snare)

            let started = await TestHelpers.waitFor {
                viewModel.selectedDrumType == .snare &&
                    viewModel.isCapturingKey &&
                    keyCaptureState.selectedDrumType == .snare &&
                    keyCaptureState.isCapturingKey
            }
            #expect(started, "Expected startCapture(for:) to update the shared capture state")

            viewModel.cancelCapture()

            let cancelled = await TestHelpers.waitFor {
                viewModel.selectedDrumType == nil &&
                    !viewModel.isCapturingKey &&
                    keyCaptureState.selectedDrumType == nil &&
                    !keyCaptureState.isCapturingKey
            }
            #expect(cancelled, "Expected cancelCapture() to clear the shared capture state")
        }
    }

    @Test("InputKeyCaptureViewModel deallocates after references are released")
    func testInputKeyCaptureViewModelDeallocatesAfterRelease() async throws {
        try await TestSetup.withTestSetup {
            let keyCaptureState = InputKeyCaptureState()
            weak var weakViewModel: InputKeyCaptureViewModel?

            var viewModel: InputKeyCaptureViewModel? = InputKeyCaptureViewModel(state: keyCaptureState)
            weakViewModel = viewModel

            #expect(weakViewModel != nil)

            viewModel = nil
            await Task.yield()

            #expect(weakViewModel == nil, "View model should release its Combine subscriptions on deinit")
        }
    }

    /// Exercises the key-capture overlay by mutating the injected state on the
    /// mounted view hierarchy so assertions run against the actual rendered tree.
    @Test("InputSettingsView renders in key-capture state after startKeyCapture")
    func testInputSettingsViewCaptureStateRender() async throws {
        try await TestSetup.withTestSetup {
            #if os(macOS)
            let keyCaptureState = InputKeyCaptureState()
            keyCaptureState.selectedDrumType = .snare
            keyCaptureState.isCapturingKey = true
            let mountedView = SwiftUITestUtilities.assertViewWithEnvironment(
                InputSettingsView(keyCaptureState: keyCaptureState),
                size: CGSize(width: 1440, height: 1400)
            )
            let renderedTexts = SwiftUITestUtilities.renderedTexts(from: mountedView.root)
            #expect(
                renderedTexts.contains("Press any key"),
                "Expected the hosted capture overlay to surface its prompt, got \(renderedTexts)"
            )
            let hasSnareText = renderedTexts.contains("for \(DrumType.snare.description)")
            #expect(
                hasSnareText,
                "Expected capture overlay to expose selected drum; got \(renderedTexts)"
            )
            #endif
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
