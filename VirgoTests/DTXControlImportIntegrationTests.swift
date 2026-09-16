//
//  DTXControlImportIntegrationTests.swift
//  VirgoTests
//

import Testing
import Foundation
@testable import Virgo

/// End-to-end test: DTX string → parse → ChartControlEvent → package
/// engraving → rendered stop mark. Covers acceptance criterion 2 ("render")
/// through the real parser and engraver, not just the data pipeline.
@Suite("DTX Control Import Integration")
@MainActor
struct DTXControlImportIntegrationTests {
    private let support = NotationLayoutTestSupport()

    @Test("parsed choke control renders as a stop mark through the package engraver")
    func parsedControlRendersAsStopMark() throws {
        let dtx = """
        #TITLE: Integration
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00012: 01000000
        #00022: 16000000
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)
        let controls = data.toControlEvents(for: chart)

        #expect(controls.count == 1)

        // Convert to NotationControlEvent (the immutable snapshot the projection consumes)
        let notationControls = controls.map { NotationControlEvent($0) }

        // Include a playable note so the tab grid has content to project onto
        let (engraved, presentation) = try NotationSnapshotTestSupport().requireReady(
            NotationSnapshotTestSupport().prepare(
                notes: [support.fallbackGridNote()],
                controls: notationControls
            )
        )

        #expect(engraved.controls.count == 1)
        let control = try #require(engraved.controls.first)
        #expect(control.kind == .choke)
        // The lane/target names live in the app-owned label, not the package
        // primitive: lane 16 resolves to Crash.
        #expect(presentation.accessibilityLabels[.control(control.controlID)] == "Choke Crash")
    }

    @Test("exact 7/8 timing drives gameplay while engraving falls back conservatively")
    func exactSevenEightTimingUsesConservativeEngraving() async throws {
        let chartData = try DTXFileParser.parseChartMetadata(from: """
        #TITLE: Seven Eight Integration
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_TIME_SIGNATURE: 7/8
        #VIRGO_FEEL: straight
        #00012: 01020304050607
        #00112: 08
        """)
        let projection = try chartData.persistenceProjection()
        let song = Song(
            title: chartData.title,
            artist: chartData.artist,
            bpm: chartData.bpm,
            duration: "0:04",
            genre: "DTX"
        )
        let chart = Chart(difficulty: .medium, timeSignature: projection.timeSignature, song: song)
        try chart.setRhythmMetadata(projection.chartMetadata)
        chart.notes = projection.notes.map { $0.makeNote(for: chart) }
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )

        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)

        let timeline = try #require(viewModel.cachedRhythmRuntime.timeline)
        let snapshot = try #require(viewModel.cachedRhythmRuntime.layoutSnapshot)
        let targets = viewModel.cachedRhythmNoteTargets.filter { $0.position.measureIndex == 0 }
        let engraved = try #require(viewModel.cachedEngravedNotation)
        // Engraved heads carry final geometry, not source ticks: order by
        // their formatted-column onset.
        let formatted = engraved.formatted
        var tickByNoteID: [Int: Int] = [:]
        for column in formatted.measures.first { $0.index == 0 }?.columns ?? [] {
            for head in column.noteHeads { tickByNoteID[head.noteID] = column.localTick }
        }
        let heads = engraved.noteHeads
            .filter { $0.measureIndex == 0 }
            .sorted { (tickByNoteID[$0.noteID] ?? 0) < (tickByNoteID[$1.noteID] ?? 0) }
        let pulses = try #require(viewModel.cachedRhythmRuntime.metronomeSchedule).pulses
            .filter { $0.position.measureIndex == 0 }
        let headIDs = Set(heads.map(\.noteID))

        #expect(viewModel.cachedRhythmRuntime.availability == .valid)
        #expect(targets.count == 7)
        #expect(heads.count == 7)
        #expect(pulses.count == 7)
        for (index, target) in targets.enumerated() {
            let expectedSeconds = Double(index) * 0.25
            // Head X resolves from the installed formatter output
            // (undisplaced single notes sit on their logical column).
            let expectedX = formatted
                .position(measureIndex: 0, localTick: Double(target.position.localTick))?
                .x
            #expect(target.targetSecondsAtOneX == expectedSeconds)
            #expect(heads[index].noteID == target.eventID.rawValue)
            #expect(heads[index].measureIndex == target.position.measureIndex)
            #expect(tickByNoteID[heads[index].noteID] == target.position.localTick)
            #expect(heads[index].position.x == expectedX)
            #expect(timeline.seconds(for: target.position, bpm: 120, speed: 1) == expectedSeconds)
        }
        #expect(pulses.map(\.offsetSecondsAtOneX) == (0..<7).map { Double($0) * 0.25 })
        #expect(pulses.map(\.accentLevel) == [.downbeat] + Array(repeating: .regular, count: 6))
        #expect(snapshot.measures[0].engravingSupport == .unsupported([.ambiguousBeatGrouping]))
        #expect(engraved.beams.allSatisfy { headIDs.isDisjoint(with: $0.noteIDs) })
        #expect(engraved.flags.allSatisfy { !headIDs.contains($0.noteID) })
        #expect(engraved.rhythmDots.allSatisfy { dot in
            if case let .note(noteID) = dot.source { return !headIDs.contains(noteID) }
            return true
        })
        #expect(engraved.tuplets.allSatisfy {
            headIDs.isDisjoint(with: $0.memberNoteIDs)
        })
        #expect(engraved.rests.filter { $0.measureIndex == 0 }.isEmpty)
        // The measure's unsupported diagnostic surfaces as an app-owned
        // warning annotation, not package geometry.
        let warnings = viewModel.notationPresentation?.annotations.rhythmWarnings ?? []
        #expect(warnings.filter { $0.scope == .measure(0) }.count == 1)

        let selectedTarget = try #require(targets.first)
        let match = InputTimingMatcher(configuration: .timeline(
            targets: viewModel.cachedRhythmNoteTargets,
            timeline: timeline,
            speed: 1
        )).calculateNoteMatch(
            for: InputHit(drumType: selectedTarget.drumType, velocity: 1, timestamp: Date()),
            elapsedTime: selectedTarget.targetSecondsAtOneX
        )
        #expect(match.matchedEventID == selectedTarget.eventID)
        #expect(match.matchedTargetPosition == selectedTarget.position)
        #expect(match.matchedTargetSeconds == selectedTarget.targetSecondsAtOneX)
        #expect(match.hitSongSeconds == selectedTarget.targetSecondsAtOneX)
        viewModel.isPlaying = true
        viewModel.recordHit(result: match)
        viewModel.recordHit(result: match)
        #expect(viewModel.scoredRhythmEventIDs == Set([selectedTarget.eventID]))
        #expect(viewModel.scoreEngine.combo == 1)
        #expect(viewModel.scoreEngine.score == 100)
        viewModel.cleanup()
    }
}
