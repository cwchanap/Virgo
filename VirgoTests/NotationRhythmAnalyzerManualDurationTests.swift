import Testing
@testable import Virgo

/// Manual-note duration resolution off the chart's tick grid: the stored
/// interval has no exact span, so the rhythm resolves indeterminate with the
/// `manualDurationOffGrid` measure diagnostic — never a supported 1-tick
/// stand-in. Split from `NotationRhythmAnalyzerTests` for the lint length
/// limits.
@Suite("Notation Rhythm Analyzer Manual Duration Tests")
struct NotationRhythmAnalyzerManualDurationTests {
    private let analyzer = NotationRhythmAnalyzer()

    @Test("a manual interval off the tick grid stays indeterminate with a measure diagnostic")
    func manualIntervalOffGridStaysIndeterminate() {
        // ticksPerWholeNote 48 divides quarter/eighth/sixteenth but not
        // thirtysecond: the manual note's stored interval has no exact span,
        // so its rhythm resolves indeterminate with the off-grid code — and
        // the measure carries the diagnostic warning while keeping its
        // engraving support.
        let offGridMeasure = RhythmMeasure(
            measureIndex: 0,
            startTick: 0,
            durationTicks: 48,
            timeSignature: .fourFour,
            beatGroups: (0..<4).map {
                RhythmBeatGroup(groupIndex: $0, startTick: $0 * 12, durationTicks: 12, isResidual: false)
            },
            engravingSupport: .supported
        )
        let event = RhythmAnalysisEvent(
            eventID: RhythmEventID(rawValue: 1),
            origin: .manual,
            position: RhythmEventPosition(measureIndex: 0, localTick: 0, absoluteTick: 0),
            voice: .upper,
            storedInterval: .thirtysecond,
            visualDurationCandidate: nil
        )
        let analysis = analyzer.analyze(
            events: [event],
            measures: [offGridMeasure],
            ticksPerWholeNote: 48,
            feel: .straight
        )

        let note = analysis.notes.first
        #expect(note?.rhythm.support == .indeterminate(.manualDurationOffGrid))
        #expect(note?.durationTicks == 1)
        #expect(analysis.warnings.contains {
            $0.measureIndex == 0 && $0.codes.contains(.manualDurationOffGrid)
        })
    }
}
