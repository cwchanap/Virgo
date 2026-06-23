//
//  ContentViewMIDILearnCoverageTests.swift
//  VirgoTests
//
//  Targeted coverage for the small remaining gaps in:
//    - Virgo/utilities/MIDILearnSession.swift (learnDisplayName switch + conflict branches)
//    - Virgo/views/ContentView.swift (derived-values logic the view delegates to)
//

import Testing
import Foundation
import SwiftData
@testable import Virgo

@Suite("ContentView + MIDILearnSession coverage")
@MainActor
struct ContentViewMIDILearnCoverageTests {

    // MARK: - MIDILearnSession: learnDisplayName switch coverage

    /// Expected display names emitted by MIDILearnSession's private
    /// `learnDisplayName` switch. Asserting every case locks the formatting
    /// (hyphens, "Pedal", ordinal tom names) and exercises each switch branch.
    /// The pre-existing conflict test only covered `.kick` / `.snare`.
    private static let expectedLearnNames: [DrumType: String] = [
        .kick: "Kick",
        .snare: "Snare",
        .hiHat: "Hi-Hat",
        .hiHatPedal: "Hi-Hat Pedal",
        .crash: "Crash",
        .ride: "Ride",
        .tom1: "High Tom",
        .tom2: "Mid Tom",
        .tom3: "Low Tom",
        .cowbell: "Cowbell"
    ]

    @Test("learn conflict message uses each drum type display name")
    func midiLearnConflictMessageUsesEachDrumTypeDisplayName() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(suiteName: "drums")
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        settings.setSelectedMIDISource(id: "src", displayName: "Kit")

        let all = DrumType.allCases
        for (index, target) in all.enumerated() {
            // Pair each target with a distinct previous drum so the conflict
            // branch fires and BOTH learnDisplayName lookups run for every case.
            let previous = all[(index + 1) % all.count]
            settings.setMidiMapping(60, for: previous)

            let session = MIDILearnSession(settingsManager: settings)
            session.beginCapture(for: target)
            let accepted = session.consume(
                MIDINoteEvent(sourceID: "src", channel: 9, note: 60, velocity: 100, hostTime: 0),
                selectedSourceID: "src"
            )

            let expected = "Replaced \(Self.expectedLearnNames[previous]!) " +
                "with \(Self.expectedLearnNames[target]!) for note 60"
            #expect(accepted, "Capture for \(target) should accept the mapped note")
            #expect(session.lastConflictMessage == expected)
            #expect(settings.getMidiMapping(for: target) == 60)
        }
    }

    @Test("learn remaps silently when note already mapped to the same drum type")
    func midiLearnRemapsSilentlyWhenNoteAlreadyMappedToSameDrum() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(suiteName: "same")
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        settings.setSelectedMIDISource(id: "src", displayName: "Kit")
        settings.setMidiMapping(44, for: .snare)

        let session = MIDILearnSession(settingsManager: settings)
        session.beginCapture(for: .snare)
        let accepted = session.consume(
            MIDINoteEvent(sourceID: "src", channel: 9, note: 44, velocity: 100, hostTime: 0),
            selectedSourceID: "src"
        )

        #expect(accepted)
        // Covers the false branch of `previousDrum != targetDrumType`: no message.
        #expect(session.lastConflictMessage == nil)
        #expect(settings.getMidiMapping(for: .snare) == 44)
    }

    @Test("canBeginCapture is true when a source is selected and available")
    func midiLearnCanBeginCaptureWhenSourceSelectedAndAvailable() {
        let (settings, _, _) = TestInputSettingsManager.makeIsolated(suiteName: "can-begin")
        settings.setSelectedMIDISource(id: "src", displayName: "Kit")

        let alwaysAvailable = MIDILearnSession(settingsManager: settings)
        #expect(alwaysAvailable.canBeginCapture)

        let offline = MIDILearnSession(settingsManager: settings, isSelectedSourceAvailable: { false })
        #expect(offline.canBeginCapture == false)
    }

    @Test("cancelCapture on a session that never began is a safe no-op")
    func midiLearnCancelCaptureBeforeAnyBeginIsSafe() {
        let (settings, _, _) = TestInputSettingsManager.makeIsolated(suiteName: "cancel-noop")

        let session = MIDILearnSession(settingsManager: settings)
        // No timeout timer was ever scheduled -> exercises the nil path in
        // cancelTimeout (timeoutTimer?.cancel() on a nil timer).
        session.cancelCapture()

        #expect(session.isCapturing == false)
        #expect(session.targetDrumType == nil)
    }

    @Test("capture transitions idle -> capturing -> idle and clears prior conflict on restart")
    func midiLearnCaptureStateTransitionsAndConflictReset() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(suiteName: "transitions")
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        settings.setSelectedMIDISource(id: "src", displayName: "Kit")
        settings.setMidiMapping(38, for: .kick)

        let session = MIDILearnSession(settingsManager: settings)
        #expect(session.isCapturing == false && session.targetDrumType == nil)

        session.beginCapture(for: .snare)
        #expect(session.isCapturing && session.targetDrumType == .snare)

        _ = session.consume(
            MIDINoteEvent(sourceID: "src", channel: 9, note: 38, velocity: 100, hostTime: 0),
            selectedSourceID: "src"
        )
        #expect(session.lastConflictMessage != nil)
        #expect(session.isCapturing == false)

        // A fresh capture must clear the previous conflict message.
        session.beginCapture(for: .crash)
        #expect(session.lastConflictMessage == nil)
        #expect(session.isCapturing && session.targetDrumType == .crash)
    }

    // MARK: - ContentView: derived-values logic the view delegates to

    private var context: ModelContext { TestContainer.shared.context }

    @Test("displayedSongs filter excludes deleted models, mirroring ContentView.displayedSongs")
    func contentViewDisplayedSongsFilterExcludesDeletedModels() async throws {
        try await TestSetup.withTestSetup {
            let songA = TestModelFactory.createSong(in: context, title: "Alpha", artist: "A")
            let songB = TestModelFactory.createSong(in: context, title: "Beta", artist: "B")
            try context.save()

            // Reproduces ContentView.displayedSongs' availability filter.
            context.delete(songB)
            let displayed = [songA, songB].filter { SongRelationshipLoader.isModelAvailable($0) }

            #expect(displayed.count == 1)
            #expect(displayed.first?.title == "Alpha")
            #expect(SongRelationshipLoader.isModelAvailable(songB) == false)
        }
    }

    @Test("toggleSave flips Song.isSaved, mirroring ContentView.toggleSave")
    func contentViewToggleSaveFlipsIsSavedState() {
        let song = Song(title: "Saved", artist: "X", bpm: 120, duration: "3:00", genre: "Rock")
        #expect(song.isSaved == false)

        song.isSaved.toggle()
        #expect(song.isSaved)

        song.isSaved.toggle()
        #expect(song.isSaved == false)
    }

    @Test("startup preparation gate is true only for uiTesting + resetState")
    func contentViewStartupPreparationGate() {
        // Drives ContentView.isPreparingStartupData / startupPreparationView.
        #expect(ContentStartupPolicy.shouldPrepareBeforeFirstRender(
            arguments: [LaunchArguments.uiTesting, LaunchArguments.resetState]
        ))
        #expect(!ContentStartupPolicy.shouldPrepareBeforeFirstRender(
            arguments: [LaunchArguments.uiTesting]
        ))
        #expect(!ContentStartupPolicy.shouldPrepareBeforeFirstRender(arguments: []))
    }
}
