//
//  SwiftUIRenderingSettingsAndHeaderTests.swift
//  VirgoTests
//
//  Created by Devin on 30/5/2026.
//

import Testing
import SwiftUI
import Foundation
import SwiftData
#if os(macOS)
import AppKit
#endif
@testable import Virgo

@Suite("SwiftUI Settings and Header Rendering Tests", .serialized)
@MainActor
struct SwiftUIRenderingSettingsAndHeaderTests {
    @Test("ProfileView renders inside a navigation stack")
    func testProfileViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                ProfileView()
            }

            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("InputSettingsView renders its default mapping state")
    func testInputSettingsViewRendering() async throws {
        try await TestSetup.withTestSetup {
            SwiftUITestUtilities.assertViewWithEnvironment(
                InputSettingsView(),
                size: CGSize(width: 1440, height: 1400)
            )
        }
    }

    @Test("InputSettingsView renders key capture overlay state")
    func testInputSettingsViewRenderingWithCaptureOverlay() async throws {
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
                "Expected the mounted overlay prompt to be rendered; got \(renderedTexts)"
            )
            #expect(
                renderedTexts.contains("for \(DrumType.snare.description)"),
                "Expected the mounted overlay to include the selected drum; got \(renderedTexts)"
            )
            #endif
        }
    }

    @Test("MetronomeView renders practice tips and settings layout")
    func testMetronomeViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                MetronomeView()
            }
            .environmentObject(MetronomeEngine(audioDriver: RecordingAudioDriver()))

            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("GameplayHeaderView renders score and transport controls")
    func testGameplayHeaderViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let chart = Chart(difficulty: .hard, level: 70)
            let song = Song(
                title: "Header Song",
                artist: "Header Artist",
                bpm: 160,
                duration: "2:34",
                genre: "Render Test",
                charts: [chart]
            )
            chart.song = song
            let track = DrumTrack(chart: chart)

            let view = GameplayHeaderView(
                track: track,
                isPlaying: .constant(true),
                viewModel: nil,
                onDismiss: {},
                onPlayPause: {},
                onRestart: {}
            )
            .background(Color.black)

            SwiftUITestUtilities.assertViewWithEnvironment(view, size: CGSize(width: 1280, height: 120))
        }
    }

    @Test("GameplayHeaderView renders score snapshot stats")
    func testGameplayHeaderViewRendersScoreSnapshotStats() async throws {
        try await TestSetup.withTestSetup {
            let vm = await GameplayViewModelCoverageTestSupport.makePreparedViewModel()
            vm.isPlaying = true
            let note = try #require(vm.cachedNotes.first)
            let result = NoteMatchResult(
                hitInput: InputHit(drumType: .kick, velocity: 1.0, timestamp: Date()),
                matchedNote: note,
                timingAccuracy: .perfect,
                measureNumber: note.measureNumber,
                measureOffset: note.measureOffset,
                timingError: 0.0
            )
            vm.recordHit(result: result)

            let track = try #require(vm.track)
            let view = GameplayHeaderView(
                track: track,
                isPlaying: .constant(true),
                viewModel: vm,
                onDismiss: {},
                onPlayPause: {},
                onRestart: {}
            )
            .background(Color.black)

            SwiftUITestUtilities.assertView(
                view,
                containsStrings: ["SCORE", "ACC", "QLTY", "100%", "1x"],
                size: CGSize(width: 1280, height: 130)
            )
            vm.cleanup()
        }
    }

    @Test("GameplayHeaderView uses compact score layout at compact portrait width")
    func testGameplayHeaderViewUsesCompactScoreLayoutAtPortraitWidth() async throws {
        try await TestSetup.withTestSetup {
            let vm = await GameplayViewModelCoverageTestSupport.makePreparedViewModel()
            vm.isPlaying = true
            let note = try #require(vm.cachedNotes.first)
            let result = NoteMatchResult(
                hitInput: InputHit(drumType: .kick, velocity: 1.0, timestamp: Date()),
                matchedNote: note,
                timingAccuracy: .perfect,
                measureNumber: note.measureNumber,
                measureOffset: note.measureOffset,
                timingError: 0.0
            )
            vm.recordHit(result: result)

            let track = try #require(vm.track)
            let view = GameplayHeaderView(
                track: track,
                isPlaying: .constant(true),
                viewModel: vm,
                onDismiss: {},
                onPlayPause: {},
                onRestart: {}
            )
            .background(Color.black)

            let mountedView = SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 390, height: 160)
            )
            let texts = SwiftUITestUtilities.renderedTexts(from: mountedView.root)

            for string in ["SCORE", "ACC", "QLTY", "100%", "1x"] {
                #expect(
                    texts.contains(string),
                    "Expected compact header texts to include '\(string)', got \(texts)"
                )
            }

            vm.cleanup()
        }
    }
}
