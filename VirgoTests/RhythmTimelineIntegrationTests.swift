//
//  RhythmTimelineIntegrationTests.swift
//  VirgoTests
//

import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import Virgo

@Suite("Rhythm timeline gameplay integration", .serialized)
@MainActor
struct RhythmTimelineIntegrationTests {
    @Test("real 6/8 DTX projection persists selected note and control identity")
    func realDTXProjectionPersistsResolvedIdentity() throws {
        let fixture = try makePersistedTask10Fixture()
        let projection = fixture.projection
        let persistedChart = fixture.chart
        let resolved = RhythmTimelineResolver().resolve(chart: persistedChart)
        let timeline = try #require(resolved.timeline)
        let persistedNote = try #require(persistedChart.safeNotes.first { $0.sourceNoteID == "D1" })
        let persistedControl = try #require(persistedChart.safeControlEvents.first)
        let noteEvent = try #require(resolved.orderedEvents.first {
            resolved.noteByEventID[$0.eventID] === persistedNote
        })
        let controlEvent = try #require(resolved.orderedEvents.first {
            let control = resolved.controlByEventID[$0.eventID]
            return control?.sourceLaneID == persistedControl.sourceLaneID
                && control?.sourceNoteID == persistedControl.sourceNoteID
        })
        let pickupRatio = try RhythmRatio(numerator: 3, denominator: 4)
        let extendedRatio = try RhythmRatio(numerator: 3, denominator: 2)
        let expectedAnchor = try RhythmSourceAnchor(measureIndex: 0, gridPosition: 1, gridSize: 2)
        let noteMeasureIndex = try #require(persistedNote.normalizedMeasureIndex)
        let noteLocalTick = try #require(persistedNote.normalizedTickWithinMeasure)
        let controlMeasureIndex = try #require(persistedControl.normalizedMeasureIndex)
        let controlLocalTick = try #require(persistedControl.normalizedTickWithinMeasure)

        #expect(projection.chartMetadata.timeSignature == .sixEight)
        #expect(projection.chartMetadata.measureLengthOverrides.map(\.ratioToWholeNote) == [
            pickupRatio,
            extendedRatio
        ])
        #expect(projection.chartMetadata.bgmStartAnchor == expectedAnchor)
        #expect(resolved.availability == .valid)
        #expect(persistedNote.sourceLaneID == "12")
        #expect(persistedNote.sourceNoteID == "D1")
        #expect(noteEvent.sourceLaneID == persistedNote.sourceLaneID)
        #expect(noteEvent.sourceNoteID == persistedNote.sourceNoteID)
        #expect(noteEvent.position == timeline.position(
            measureIndex: noteMeasureIndex,
            localTick: noteLocalTick
        ))
        #expect(persistedControl.sourceLaneID == "22")
        #expect(persistedControl.sourceNoteID == "16")
        #expect(controlEvent.sourceLaneID == persistedControl.sourceLaneID)
        #expect(controlEvent.sourceNoteID == persistedControl.sourceNoteID)
        #expect(controlEvent.position == timeline.position(
            measureIndex: controlMeasureIndex,
            localTick: controlLocalTick
        ))
    }

    @Test("valid DTX fixture shares event identity and exact time through gameplay consumers")
    func validDTXFixtureSharesIdentityAndTime() async throws {
        let fixture = try makePersistedTask10Fixture()
        let resolved = RhythmTimelineResolver().resolve(chart: fixture.chart)
        let timeline = try #require(resolved.timeline)
        let metronome = ScheduledMetronomeSpy()
        let viewModel = GameplayViewModel(
            chart: fixture.chart,
            metronome: metronome,
            completionScheduler: GameplayViewModelTestHarness.immediateCompletionScheduler()
        )

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        let selectedEvent = try #require(resolved.orderedEvents.first { $0.sourceNoteID == "D1" })
        let layoutSnapshot = try #require(viewModel.cachedRhythmRuntime.layoutSnapshot)
        let layoutNote = try #require(layoutSnapshot.notes.first { $0.eventID == selectedEvent.eventID })
        let noteHead = try #require(viewModel.cachedNotationLayout.noteHeads.first {
            $0.eventID == selectedEvent.eventID
        })
        let target = try #require(viewModel.cachedRhythmNoteTargets.first {
            $0.eventID == selectedEvent.eventID
        })
        let renderedMeasure = try #require(viewModel.cachedNotationMeasuresByIndex[selectedEvent.position.measureIndex])
        let expectedX = viewModel.cachedNotationLayout.tabGrid.xPosition(
            in: renderedMeasure,
            localTick: selectedEvent.position.localTick
        )
        let expectedSeconds = try #require(timeline.seconds(
            for: selectedEvent.position,
            bpm: fixture.chart.bpm,
            speed: 1
        ))

        #expect(layoutNote.position == selectedEvent.position)
        #expect(noteHead.rhythmPosition == selectedEvent.position)
        #expect(target.position == selectedEvent.position)
        #expect(target.targetSecondsAtOneX == expectedSeconds)
        #expect(noteHead.position.x == expectedX)
        #expect(layoutNote.rhythm == NotationRhythm(baseInterval: .eighth, dotCount: 1))
        #expect(viewModel.cachedNotationLayout.rhythmDots.contains { $0.source == .event(selectedEvent.eventID) })

        try assertDTXTripletSlots(resolved, layoutSnapshot, viewModel.cachedNotationLayout)
        #expect(layoutSnapshot.notes.first { $0.sourceChipID == "F1" }?.rhythm.baseInterval == .thirtysecond)
        #expect(layoutSnapshot.notes.first { $0.sourceChipID == "F2" }?.rhythm.baseInterval == .sixtyfourth)

        let cachedBeat = try #require(viewModel.cachedDrumBeats.first {
            $0.rhythmEventID == selectedEvent.eventID
        })
        #expect(cachedBeat.rhythmPosition == selectedEvent.position)

        let match = InputTimingMatcher(configuration: .timeline(
            targets: viewModel.cachedRhythmNoteTargets,
            timeline: timeline,
            speed: 1
        )).calculateNoteMatch(
            for: InputHit(drumType: target.drumType, velocity: 1, timestamp: Date()),
            elapsedTime: expectedSeconds
        )
        #expect(match.matchedEventID == selectedEvent.eventID)
        #expect(match.matchedTargetPosition == selectedEvent.position)
        #expect(match.matchedTargetSeconds == expectedSeconds)
        viewModel.isPlaying = true
        viewModel.recordHit(result: match)
        #expect(viewModel.scoredRhythmEventIDs.contains(selectedEvent.eventID))

        let anchorPosition = try #require(timeline.bgmStartPosition)
        let anchorSeconds = try #require(timeline.seconds(
            for: anchorPosition,
            bpm: fixture.chart.bpm,
            speed: 1
        ))
        #expect(viewModel.bgmOffsetSeconds == anchorSeconds)
        #expect(viewModel.cachedTrackDuration == timeline.endSeconds(bpm: fixture.chart.bpm, speed: 1))
        let selectedPulse = try #require(viewModel.cachedRhythmRuntime.metronomeSchedule?.pulses.first {
            $0.position == selectedEvent.position
        })
        #expect(selectedPulse.offsetSecondsAtOneX == expectedSeconds)

        let laterEvent = try #require(resolved.orderedEvents.first { $0.sourceNoteID == "D2" })
        let laterTarget = try #require(viewModel.cachedRhythmNoteTargets.first {
            $0.eventID == laterEvent.eventID
        })
        let laterHead = try #require(viewModel.cachedNotationLayout.noteHeads.first {
            $0.eventID == laterEvent.eventID
        })
        viewModel.updateContinuousVisualsForTesting(elapsedTime: laterTarget.targetSecondsAtOneX)
        #expect(viewModel.currentMeasureIndex == laterEvent.position.measureIndex)
        #expect(viewModel.purpleBarPosition?.x == Double(laterHead.position.x))
        viewModel.scanForMissedNotes(
            upToSeconds: laterTarget.targetSecondsAtOneX + TimingAccuracy.good.toleranceMs / 1_000
        )
        #expect(viewModel.scoredRhythmEventIDs.contains(laterEvent.eventID))

        viewModel.updateContinuousVisualsForTesting(elapsedTime: viewModel.cachedTrackDuration + 0.01)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while clock.now < deadline && !viewModel.isShowingSessionResults {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(viewModel.isShowingSessionResults)
        #expect(!viewModel.isPlaying)
        viewModel.cleanup()
    }

    @Test("gameplay caches one complete valid rhythm runtime before setup")
    func cachesCompleteRuntime() async throws {
        let chart = try makeVariableMeasureChart()
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )

        await viewModel.loadChartData()

        #expect(viewModel.cachedRhythmRuntime.availability == .valid)
        #expect(viewModel.cachedRhythmRuntime.timeline != nil)
        #expect(viewModel.cachedRhythmRuntime.layoutSnapshot != nil)
        #expect(viewModel.cachedRhythmRuntime.noteTargets.count == 2)
        #expect(viewModel.cachedRhythmRuntime.metronomeSchedule?.pulses.count == 7)
        #expect(viewModel.cachedRhythmRuntime.noteByEventID.count == 2)
        #expect(viewModel.cachedRhythmRuntime.diagnostics.isEmpty)

        viewModel.setupGameplay(loadPersistedSpeed: false)

        let timeline = try #require(viewModel.cachedRhythmRuntime.timeline)
        #expect(viewModel.cachedLayoutMeasureCount == timeline.measures.count)
        #expect(viewModel.cachedDrumBeats.count == 2)
        #expect(viewModel.cachedBeatPositions.count == 2)
        #expect(viewModel.cachedNotationLayout.measures.map(\.durationTicks) == timeline.measures.map(\.durationTicks))
        #expect(abs(viewModel.cachedTrackDuration - 3.5) < 0.0001)
        #expect(abs(viewModel.bgmOffsetSeconds - 2.5) < 0.0001)
        #expect(viewModel.cachedSong?.duration == "9:59")
        #expect(viewModel.cachedSong?.bgmStartOffsetSeconds == 99)
        viewModel.cleanup()
    }

    @Test("timeline playhead crosses a shortened bar continuously and scans misses by seconds")
    func timelinePlayheadAndMissScan() async throws {
        let chart = try makeVariableMeasureChart()
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        viewModel.updateContinuousVisualsForTesting(elapsedTime: 1.49)
        #expect(viewModel.currentMeasureIndex == 0)
        #expect(viewModel.scoredRhythmEventIDs.count == 1)

        viewModel.updateContinuousVisualsForTesting(elapsedTime: 1.51)
        let positionAfterBarline = try #require(viewModel.purpleBarPosition)
        let renderedMeasure = try #require(viewModel.cachedNotationMeasuresByIndex[1])
        let expectedX = renderedMeasure.contentStartX
            + CGFloat(0.02) * viewModel.cachedNotationLayout.tabGrid.tickWidth

        #expect(viewModel.currentMeasureIndex == 1)
        #expect(viewModel.currentRow == viewModel.rowForMeasure(1))
        #expect(abs(positionAfterBarline.x - Double(expectedX)) < 0.01)
        #expect(viewModel.scoredRhythmEventIDs.count == 1)

        viewModel.updateContinuousVisualsForTesting(elapsedTime: 2.61)
        #expect(viewModel.scoredRhythmEventIDs.count == 2)
        viewModel.cleanup()
    }

    @Test("timeline speed scales duration anchor targets and metronome from the same one-X cache")
    func sharedSpeedScaling() async throws {
        let chart = try makeVariableMeasureChart()
        let settings = GameplayViewModelTestHarness.createTestPracticeSettings()
        settings.setSpeed(0.5)
        let metronome = ScheduledMetronomeSpy()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: settings)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        #expect(abs(viewModel.cachedTrackDuration - 7) < 0.0001)
        #expect(abs(viewModel.bgmOffsetSeconds - 5) < 0.0001)
        #expect(viewModel.cachedRhythmNoteTargets.map { $0.targetSecondsAtOneX / 0.5 } == [0, 5])

        viewModel.startPlayback()

        let start = try #require(metronome.timelineStartAtTimeCalls.first)
        #expect(start.schedule == viewModel.cachedRhythmRuntime.metronomeSchedule)
        #expect(start.speed == 0.5)
        #expect(start.elapsedTime == 0)
        viewModel.cleanup()
    }

    @Test("resume restores timeline position across a shortened barline")
    func timelineResumeState() async throws {
        let chart = try makeVariableMeasureChart()
        let metronome = ScheduledMetronomeSpy()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.pausedElapsedTime = 1.51

        viewModel.startPlayback()

        #expect(viewModel.currentMeasureIndex == 1)
        #expect(abs(viewModel.currentBeatPosition - 0.005) < 0.0001)
        #expect(abs(viewModel.currentQuarterNotePosition - 3.02) < 0.0001)
        #expect(viewModel.totalBeatsElapsed == 3)
        let start = try #require(metronome.timelineStartAtTimeCalls.first)
        #expect(start.elapsedTime == 1.51)
        #expect(start.schedule.pulses.first { $0.position.measureIndex == 1 }?.beatInMeasure == 1)
        viewModel.cleanup()
    }

    @Test("ended short audio yields elapsed ownership back to the shared clock")
    func shortAudioFallsBackToSharedClock() async throws {
        let chart = try makeVariableMeasureChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer(durationSeconds: 1)
        player.currentTime = player.duration
        viewModel.bgmPlayer = player
        viewModel.isPlaying = true
        metronome.startAtTime(
            schedule: try #require(viewModel.cachedRhythmRuntime.metronomeSchedule),
            speed: 1,
            startTime: CFAbsoluteTimeGetCurrent() - 2,
            elapsedTime: 0
        )

        let elapsed = try #require(viewModel.calculateElapsedTime())

        #expect(elapsed > 1.5)
        #expect(viewModel.currentBGMPlaybackElapsedTime() == nil)
        viewModel.cleanup()
    }

    @Test("resume after short audio ends keeps the shared timeline offset")
    func resumeAfterShortAudioEnds() async throws {
        let chart = try makeVariableMeasureChart()
        let metronome = ScheduledMetronomeSpy()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer(durationSeconds: 1)
        player.currentTime = player.duration
        viewModel.bgmPlayer = player
        viewModel.pausedElapsedTime = 2

        viewModel.startPlayback()

        #expect(viewModel.currentMeasureIndex == 1)
        #expect(viewModel.pausedElapsedTime == 2)
        #expect(metronome.timelineStartAtTimeCalls.last?.elapsedTime == 2)
        #expect(player.currentTime == player.duration)
        viewModel.cleanup()
    }

    @Test("speed change after short audio ends reseats from the shared clock")
    func speedChangeAfterShortAudioEnds() async throws {
        let chart = try makeVariableMeasureChart()
        let metronome = ScheduledMetronomeSpy()
        metronome.playbackTime = 2
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer(durationSeconds: 1)
        player.currentTime = player.duration
        viewModel.bgmPlayer = player
        viewModel.isPlaying = true

        viewModel.updateSpeed(0.5)

        #expect(viewModel.pausedElapsedTime == 4)
        #expect(metronome.timelineStartAtTimeCalls.last?.elapsedTime == 4)
        #expect(player.currentTime == player.duration)
        viewModel.cleanup()
    }

    @Test("runtime controls retain resolver identity when relationship snapshots reorder")
    func runtimeControlsRetainResolverIdentityAcrossRelationshipReordering() throws {
        let chart = makeControlIdentityChart()
        let resolved = RhythmTimelineResolver().resolve(chart: chart)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        viewModel.track = DrumTrack(chart: chart)
        viewModel.cachedNotes = chart.safeNotes
        viewModel.cachedControlEvents = chart.safeControlEvents.reversed().map(NotationControlEvent.init)

        let runtime = viewModel.makeRhythmRuntime(resolvedRhythm: resolved)
        let controls = try #require(runtime.layoutSnapshot?.controls)
        let controlsBySourceID = Dictionary(uniqueKeysWithValues: controls.compactMap { control in
            control.event.sourceNoteID.map { ($0, control) }
        })

        #expect(controls.count == 2)
        #expect(controlsBySourceID["A"]?.event.kind == .stop)
        #expect(controlsBySourceID["A"]?.position.localTick == 1)
        #expect(controlsBySourceID["B"]?.event.kind == .damp)
        #expect(controlsBySourceID["B"]?.position.localTick == 3)
    }

    @Test("runtime control lookup ignores a lingering deleted-note relationship count")
    func runtimeControlLookupIgnoresLingeringDeletedNoteCount() throws {
        let chart = makeControlIdentityChart()
        let resolved = RhythmTimelineResolver().resolve(chart: chart)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        viewModel.track = DrumTrack(chart: chart)
        // `loadChartData` snapshots `chart.notes`, while the resolver deliberately
        // uses `safeNotes`. ModelContext deletion can leave that relationship
        // array one element longer until SwiftData finishes reconciliation.
        viewModel.cachedNotes = chart.safeNotes + [Note(
            interval: .quarter,
            noteType: .highTom,
            measureNumber: 99,
            measureOffset: 0
        )]
        viewModel.cachedControlEvents = chart.safeControlEvents.map(NotationControlEvent.init)

        let runtime = viewModel.makeRhythmRuntime(resolvedRhythm: resolved)
        let controls = try #require(runtime.layoutSnapshot?.controls)

        #expect(controls.count == 2)
        #expect(controls.map(\.event.sourceNoteID) == ["A", "B"])
        #expect(controls.map(\.position.localTick) == [1, 3])
    }

    @Test("timing-fatal runtime disables layout scoring metronome and BGM starters")
    func fatalRuntimeDisablesGameplay() async throws {
        let chart = Chart(difficulty: .medium)
        chart.rhythmMetadataData = Data([0xFF, 0x00, 0xFE])
        chart.notes.append(Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0))
        let metronome = ScheduledMetronomeSpy()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        let practiceState = ChartPracticeState(chart: chart)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.startPlayback()
        viewModel.startBGMPlayback(track: try #require(viewModel.track))

        #expect(viewModel.cachedRhythmRuntime.availability == .fatal)
        #expect(viewModel.cachedRhythmRuntime.diagnostics.map(\.code) == [.inconsistentPersistedTiming])
        #expect(viewModel.cachedRhythmRuntime.timeline == nil)
        #expect(viewModel.cachedRhythmRuntime.layoutSnapshot == nil)
        #expect(viewModel.cachedRhythmRuntime.noteTargets.isEmpty)
        #expect(viewModel.cachedRhythmRuntime.metronomeSchedule == nil)
        #expect(!viewModel.cachedNotationLayout.hasRenderableContent)
        #expect(viewModel.cachedNotationLayout.measures.isEmpty)
        #expect(viewModel.isGameplayPrepared == false)
        #expect(viewModel.isPlaying == false)
        #expect(metronome.startAtTimeCalls.isEmpty)
        #expect(metronome.timelineStartAtTimeCalls.isEmpty)
        #expect(viewModel.bgmPlayer == nil)
        #expect(!viewModel.rhythmFatalMessage.isEmpty)
        #expect(!practiceState.isPracticeEnabled)
        #expect(practiceState.badgeTitle == "Timing issue")
        viewModel.cleanup()
    }
}

private extension RhythmTimelineIntegrationTests {
    struct PersistedTask10Fixture {
        let container: TestContainer
        let projection: DTXChartPersistenceProjection
        let chart: Chart
    }

    func assertDTXTripletSlots(
        _ resolved: ResolvedChartRhythm, _ snapshot: RhythmLayoutSnapshot, _ renderedLayout: NotationLayout
    ) throws {
        let firstEvent = try #require(resolved.orderedEvents.first { $0.sourceNoteID == "T1" })
        let secondEvent = try #require(resolved.orderedEvents.first { $0.sourceNoteID == "T2" })
        let thirdEvent = try #require(resolved.orderedEvents.first { $0.sourceNoteID == "T3" })
        let firstNote = try #require(snapshot.notes.first { $0.eventID == firstEvent.eventID })
        let secondNote = try #require(snapshot.notes.first { $0.eventID == secondEvent.eventID })
        let thirdNote = try #require(snapshot.notes.first { $0.eventID == thirdEvent.eventID })
        let tupletID = try #require(firstNote.tupletID)
        let slotTicks = tupletID.durationTicks / 3
        #expect(secondNote.tupletID == tupletID)
        #expect(thirdNote.tupletID == tupletID)
        #expect(firstNote.position.localTick == tupletID.startTick)
        #expect(secondNote.position.localTick == tupletID.startTick + slotTicks)
        #expect(thirdNote.position.localTick == tupletID.startTick + slotTicks * 2)
        let renderedTuplet = try #require(renderedLayout.tuplets.first { $0.id == tupletID })
        #expect(renderedTuplet.memberEventIDs == [firstEvent.eventID, secondEvent.eventID, thirdEvent.eventID])
    }

    func dtxChipArray(gridSize: Int, chips: [Int: String]) -> String {
        (0..<gridSize).map { chips[$0] ?? "00" }.joined()
    }

    func makePersistedTask10Fixture() throws -> PersistedTask10Fixture {
        // The pickup resolves to 144 ticks at 192 ticks per whole note. Each
        // 36-tick span is therefore an exact dotted eighth, and the following
        // boundary onset gives the terminal chip local same-voice evidence.
        let dottedLane = dtxChipArray(
            gridSize: 12,
            chips: [0: "D1", 3: "D2", 5: "D3", 6: "D4", 9: "D5", 11: "D6"]
        )
        let tripletLane = dtxChipArray(
            gridSize: 18,
            chips: [0: "T1", 2: "T2", 4: "T3", 6: "E1", 9: "B1", 12: "B2", 15: "B3"]
        )
        let controlLane = dtxChipArray(gridSize: 18, chips: [3: "16"])
        let fineUpperLane = dtxChipArray(
            gridSize: 96,
            chips: [0: "S1", 8: "A1", 32: "A2", 56: "A3", 92: "F1", 94: "F2", 95: "F3"]
        )
        let fineLowerLane = dtxChipArray(gridSize: 96, chips: [0: "C1", 24: "C2", 48: "C3", 72: "C4"])
        let chartData = try DTXFileParser.parseChartMetadata(from: """
        #TITLE: End-to-End Rhythm
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 55
        #VIRGO_TIME_SIGNATURE: 6/8
        #VIRGO_FEEL: straight
        #VIRGO_CONTROL: 1
        #00002: 0.75
        #00202: 1.5
        #00001: 0001
        #00012: \(dottedLane)
        #00112: \(tripletLane)
        #00122: \(controlLane)
        #00212: \(fineUpperLane)
        #00213: \(fineLowerLane)
        #00312: Z1
        """)
        let projection = try chartData.persistenceProjection()
        let testContainer = TestContainer.isolatedContainer()
        let context = testContainer.context
        let song = Song(
            title: chartData.title,
            artist: chartData.artist,
            bpm: chartData.bpm,
            duration: "9:59",
            genre: "DTX"
        )
        let chart = Chart(
            difficulty: chartData.toDifficulty(),
            level: chartData.difficultyLevel,
            timeSignature: projection.timeSignature,
            song: song
        )
        try chart.setRhythmMetadata(projection.chartMetadata)
        chart.notes = projection.notes.map { $0.makeNote(for: chart) }
        chart.controlEvents = projection.controls.map { $0.makeControl(for: chart) }
        song.charts = [chart]
        context.insert(song)
        try context.save()

        let reopenedContext = ModelContext(testContainer.container)
        let persistedChart = try #require(reopenedContext.fetch(FetchDescriptor<Chart>()).first)
        return PersistedTask10Fixture(
            container: testContainer,
            projection: projection,
            chart: persistedChart
        )
    }

    func makeControlIdentityChart() -> Chart {
        let song = Song(
            title: "Control Identity",
            artist: "Tester",
            bpm: 120,
            duration: "0:02",
            genre: "Test"
        )
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour, song: song)
        chart.notes.append(Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: 0
        ))
        chart.controlEvents = [
            ChartControlEvent(
                kind: .stop,
                measureNumber: 1,
                measureOffset: 0.25,
                sourceNoteID: "A",
                targetLaneID: "1A"
            ),
            ChartControlEvent(
                kind: .damp,
                measureNumber: 1,
                measureOffset: 0.75,
                sourceNoteID: "B",
                targetLaneID: "12"
            )
        ]
        return chart
    }

    func makeVariableMeasureChart() throws -> Chart {
        let song = Song(
            title: "Variable Runtime",
            artist: "Tester",
            bpm: 120,
            duration: "9:59",
            genre: "DTX",
            bgmStartOffsetSeconds: 99
        )
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour, song: song)
        chart.notes.append(Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: 0
        ))
        chart.notes.append(Note(
            interval: .quarter,
            noteType: .bass,
            measureNumber: 2,
            measureOffset: 0.5
        ))
        let pickup = try MeasureLengthOverride(
            measureIndex: 0,
            ratioToWholeNote: RhythmRatio(numerator: 3, denominator: 4)
        )
        let anchor = try RhythmSourceAnchor(measureIndex: 1, gridPosition: 1, gridSize: 2)
        try chart.setRhythmMetadata(ChartRhythmMetadata(
            timeSignature: .fourFour,
            feel: .straight,
            measureLengthOverrides: [pickup],
            bgmStartAnchor: anchor,
            timingStatus: .valid,
            diagnostics: []
        ))
        return chart
    }
}
