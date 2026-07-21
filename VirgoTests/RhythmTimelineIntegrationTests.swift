//
//  RhythmTimelineIntegrationTests.swift
//  VirgoTests
//

import AVFoundation
import Foundation
import Testing
@testable import Virgo

@Suite("Rhythm timeline gameplay integration", .serialized)
@MainActor
struct RhythmTimelineIntegrationTests {
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

    @Test("timing-fatal runtime disables layout scoring metronome and BGM starters")
    func fatalRuntimeDisablesGameplay() async throws {
        let chart = Chart(difficulty: .medium)
        chart.rhythmMetadataData = Data([0xFF, 0x00, 0xFE])
        chart.notes.append(Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0))
        let metronome = ScheduledMetronomeSpy()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.startPlayback()
        viewModel.startBGMPlayback(track: try #require(viewModel.track))

        #expect(viewModel.cachedRhythmRuntime.availability == .fatal)
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
        viewModel.cleanup()
    }
}

private extension RhythmTimelineIntegrationTests {
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
