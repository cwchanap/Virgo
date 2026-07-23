import Testing
@testable import Virgo

@Suite("Metronome Timing Engine Exhaustion Tests", .serialized)
@MainActor
struct MetronomeTimingEngineExhaustionTests {
    @Test("starting beyond the final timeline pulse leaves the engine stopped")
    func startingBeyondScheduleStopsPlayback() async throws {
        let engine = MetronomeTimingEngine()
        let schedule = try onePulseSchedule()

        engine.startAtTime(
            startTime: 100,
            schedule: schedule,
            speed: 1,
            elapsedTime: 1
        )
        await Task.yield()

        #expect(engine.isPlaying == false)
        #expect(engine.getCurrentPlaybackTime() == nil)
    }

    @Test("consuming the final timeline pulse stops playback")
    func finalTimelinePulseStopsPlayback() async throws {
        let engine = MetronomeTimingEngine(isTestEnvironment: false)
        let schedule = try onePulseSchedule()

        engine.startAtTime(
            startTime: CFAbsoluteTimeGetCurrent() + 0.05,
            schedule: schedule,
            speed: 1,
            elapsedTime: 0
        )

        let stopped = await TestHelpers.waitFor(
            condition: { !engine.isPlaying },
            timeout: 1,
            checkInterval: 0.01
        )

        #expect(stopped)
        #expect(engine.getCurrentPlaybackTime() == nil)
    }

    private func onePulseSchedule() throws -> RhythmMetronomeSchedule {
        let measure = RhythmMeasure(
            measureIndex: 0,
            startTick: 0,
            durationTicks: 1,
            timeSignature: .fourFour,
            beatGroups: [RhythmBeatGroup(
                groupIndex: 0,
                startTick: 0,
                durationTicks: 1,
                isResidual: false
            )],
            engravingSupport: .supported
        )
        let timeline = RhythmTimeline(
            ticksPerWholeNote: 4,
            measures: [measure],
            eventPositions: [:],
            bgmStartPosition: nil
        )
        return try RhythmMetronomeSchedule(timeline: timeline, bpm: 120)
    }
}
