import Testing
import DrumNotation

/// HPA-166 Task 1: beat-group coverage validation — groups must be
/// positive-duration, contiguous from tick 0, and exactly tile their
/// measure so the array position is a trustworthy ordinal.
@Suite("Resolved notation beat-group validation")
struct ResolvedNotationBeatGroupValidationTests {
    @Test("validation rejects a beat group with non-positive duration")
    func validationRejectsNonPositiveBeatGroupDuration() {
        #expect {
            try Fixtures.document(measures: [Fixtures.measure(beatGroups: [
                ResolvedBeatGroup(startTick: 0, durationTicks: 960),
                ResolvedBeatGroup(startTick: 960, durationTicks: 0)
            ])])
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .invalidBeatGroupDuration(measureIndex: 0, startTick: 960, durationTicks: 0)
        }
        #expect {
            try Fixtures.document(measures: [Fixtures.measure(beatGroups: [
                ResolvedBeatGroup(startTick: 0, durationTicks: -240)
            ])])
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .invalidBeatGroupDuration(measureIndex: 0, startTick: 0, durationTicks: -240)
        }
    }

    @Test("validation rejects a gap between beat groups")
    func validationRejectsBeatGroupGap() {
        // [0,960) then [1440,1920): ticks 960..<1440 are uncovered, so the
        // second group does not start where the first ended.
        #expect {
            try Fixtures.document(measures: [Fixtures.measure(beatGroups: [
                ResolvedBeatGroup(startTick: 0, durationTicks: 960),
                ResolvedBeatGroup(startTick: 1440, durationTicks: 480)
            ])])
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .nonContiguousBeatGroups(measureIndex: 0, expectedStartTick: 960, actualStartTick: 1440)
        }
    }

    @Test("validation rejects overlapping beat groups")
    func validationRejectsBeatGroupOverlap() {
        // [0,1440) then [960,1920): the second group starts inside the first.
        #expect {
            try Fixtures.document(measures: [Fixtures.measure(beatGroups: [
                ResolvedBeatGroup(startTick: 0, durationTicks: 1440),
                ResolvedBeatGroup(startTick: 960, durationTicks: 960)
            ])])
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .nonContiguousBeatGroups(measureIndex: 0, expectedStartTick: 1440, actualStartTick: 960)
        }
    }

    @Test("validation rejects beat groups that do not start at tick zero")
    func validationRejectsBeatGroupsNotStartingAtZero() {
        #expect {
            try Fixtures.document(measures: [Fixtures.measure(beatGroups: [
                ResolvedBeatGroup(startTick: 480, durationTicks: 1440)
            ])])
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .nonContiguousBeatGroups(measureIndex: 0, expectedStartTick: 0, actualStartTick: 480)
        }
    }

    @Test("validation rejects beat groups that do not reach the measure end")
    func validationRejectsBeatGroupsNotCoveringMeasure() {
        // [0,960) + [960,1440) covers only 1440 of the measure's 1920 ticks.
        #expect {
            try Fixtures.document(measures: [Fixtures.measure(beatGroups: [
                ResolvedBeatGroup(startTick: 0, durationTicks: 960),
                ResolvedBeatGroup(startTick: 960, durationTicks: 480)
            ])])
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .beatGroupsDoNotCoverMeasure(measureIndex: 0, durationTicks: 1920, coveredTicks: 1440)
        }
    }

    @Test("validation rejects beat groups that overshoot the measure end")
    func validationRejectsBeatGroupsOvershootingMeasureEnd() {
        // [0,960) + [960,2880) covers 2880, past the 1920-tick measure end.
        #expect {
            try Fixtures.document(measures: [Fixtures.measure(beatGroups: [
                ResolvedBeatGroup(startTick: 0, durationTicks: 960),
                ResolvedBeatGroup(startTick: 960, durationTicks: 1920)
            ])])
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .beatGroupsDoNotCoverMeasure(measureIndex: 0, durationTicks: 1920, coveredTicks: 2880)
        }
    }

    @Test("validation rejects beat-group accumulation that overflows Int")
    func validationRejectsBeatGroupTickOverflow() {
        // [0,Int.max-10) then [Int.max-10,Int.max+10): the second group's
        // advance wraps past Int.max before coverage can be judged, so the
        // failure reports the saturated Int.max rather than a wrapped sum.
        #expect {
            try Fixtures.document(measures: [Fixtures.measure(
                durationTicks: Int.max,
                beatGroups: [
                    ResolvedBeatGroup(startTick: 0, durationTicks: Int.max - 10),
                    ResolvedBeatGroup(startTick: Int.max - 10, durationTicks: 20)
                ]
            )])
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .beatGroupsDoNotCoverMeasure(
                    measureIndex: 0,
                    durationTicks: Int.max,
                    coveredTicks: Int.max
                )
        }
    }

    @Test("validation rejects a measure with no beat groups")
    func validationRejectsEmptyBeatGroups() {
        #expect {
            try Fixtures.document(measures: [Fixtures.measure(beatGroups: [])])
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .beatGroupsDoNotCoverMeasure(measureIndex: 0, durationTicks: 1920, coveredTicks: 0)
        }
    }
}
