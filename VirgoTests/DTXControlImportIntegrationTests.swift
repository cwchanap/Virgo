//
//  DTXControlImportIntegrationTests.swift
//  VirgoTests
//

import Testing
import Foundation
@testable import Virgo

/// End-to-end test: DTX string → parse → ChartControlEvent → layout engine →
/// rendered stop mark. Covers acceptance criterion 2 ("render") through the real
/// parser and layout engine, not just the data pipeline.
@Suite("DTX Control Import Integration")
@MainActor
struct DTXControlImportIntegrationTests {
    private let support = NotationLayoutTestSupport()

    @Test("parsed choke control renders as a stop mark through the layout engine")
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

        // Convert to NotationControlEvent (the immutable snapshot the layout engine consumes)
        let notationControls = controls.map { NotationControlEvent($0) }

        // Include a playable note so the tab grid has content to project onto
        let result = support.layout(
            notes: [support.fallbackGridNote()],
            controls: notationControls
        )

        #expect(result.stopNotes.count == 1)
        let stopNote = try #require(result.stopNotes.first)
        #expect(stopNote.kind == .choke)
        #expect(stopNote.targetLaneID == "16")
        #expect(stopNote.targetDisplayName == "Crash")
    }

    @Test("parsed incommensurate control preserves measure but omits mark")
    func parsedIncommensurateControlPreservesMeasure() throws {
        // The control chip targets lane 16 (Crash) — a resolvable target — so the
        // only reason the stop mark is omitted is that position 1/7 does not project
        // exactly onto the 960-tick fallback grid (960 is not a multiple of 7). An
        // earlier version of this test used noteID 01 (BGM, unresolvable target) at
        // position 0, which passed for the wrong reason: the layout engine bailed at
        // target resolution before ever checking tick projection.
        let dtx = """
        #TITLE: Incommensurate
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00012: 01000000
        #00221: 00160000000000
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)
        let controls = data.toControlEvents(for: chart)
        #expect(controls.count == 1)
        let notationControls = controls.map { NotationControlEvent($0) }

        let result = support.layout(
            notes: [support.fallbackGridNote()],
            controls: notationControls
        )

        // The control is at measure index 2 → total measures >= 3
        #expect(result.measures.count >= 3)
        // 1/7 does not project onto a 960-tick grid → no rendered mark
        #expect(result.stopNotes.isEmpty)
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
        viewModel.setupGameplay(loadPersistedSpeed: false)

        let timeline = try #require(viewModel.cachedRhythmRuntime.timeline)
        let snapshot = try #require(viewModel.cachedRhythmRuntime.layoutSnapshot)
        let targets = viewModel.cachedRhythmNoteTargets.filter { $0.position.measureIndex == 0 }
        let heads = viewModel.cachedNotationLayout.noteHeads
            .filter { $0.measureIndex == 0 }
            .sorted { $0.rhythmPosition.localTick < $1.rhythmPosition.localTick }
        let pulses = try #require(viewModel.cachedRhythmRuntime.metronomeSchedule).pulses
            .filter { $0.position.measureIndex == 0 }
        let renderedMeasure = try #require(viewModel.cachedNotationMeasuresByIndex[0])
        let headIDs = Set(heads.map(\.id))
        let eventIDs = Set(heads.map(\.eventID))

        #expect(viewModel.cachedRhythmRuntime.availability == .valid)
        #expect(targets.count == 7)
        #expect(heads.count == 7)
        #expect(pulses.count == 7)
        for (index, target) in targets.enumerated() {
            let expectedSeconds = Double(index) * 0.25
            let expectedX = viewModel.cachedNotationLayout.tabGrid.xPosition(
                in: renderedMeasure,
                localTick: target.position.localTick
            )
            #expect(target.targetSecondsAtOneX == expectedSeconds)
            #expect(heads[index].eventID == target.eventID)
            #expect(heads[index].rhythmPosition == target.position)
            #expect(heads[index].position.x == expectedX)
            #expect(timeline.seconds(for: target.position, bpm: 120, speed: 1) == expectedSeconds)
        }
        #expect(pulses.map(\.offsetSecondsAtOneX) == (0..<7).map { Double($0) * 0.25 })
        #expect(pulses.map(\.accentLevel) == [.downbeat] + Array(repeating: .regular, count: 6))
        #expect(snapshot.measures[0].engravingSupport == .unsupported([.ambiguousBeatGrouping]))
        #expect(viewModel.cachedNotationLayout.beams.allSatisfy { headIDs.isDisjoint(with: $0.noteHeadIDs) })
        #expect(viewModel.cachedNotationLayout.flags.allSatisfy { !headIDs.contains($0.noteHeadID) })
        #expect(viewModel.cachedNotationLayout.rhythmDots.allSatisfy { dot in
            if case let .event(eventID) = dot.source { return !eventIDs.contains(eventID) }
            return true
        })
        #expect(viewModel.cachedNotationLayout.tuplets.allSatisfy {
            eventIDs.isDisjoint(with: $0.memberEventIDs)
        })
        #expect(viewModel.cachedNotationLayout.rests.filter { $0.measureIndex == 0 }.isEmpty)
        #expect(viewModel.cachedNotationLayout.rhythmWarnings.filter { $0.scope == .measure(0) }.count == 1)
        viewModel.cleanup()
    }
}
