import Testing
import DrumNotation

/// HPA-166 review fix 1: a note/rest's exact duration span must stay inside
/// its owning measure — `localTick + durationTicks <= measure.durationTicks`, with
/// the exact measure end allowed and no integer-overflow trap. Onset-only
/// containment and positivity live in the sibling validation suite. The
/// `validateEventDurations` pass also rejects negative dot counts here —
/// malformed rhythm the engraver must never see.
@Suite("Resolved notation event-span validation")
struct ResolvedNotationSpanValidationTests {
    @Test("event spans ending exactly at the measure end validate")
    func eventSpansEndingAtMeasureEndValidate() throws {
        // 1440 + 480 == 1920: the span ends exactly on the measure end —
        // contained, never crossing.
        let note = Fixtures.makeNote(id: 1, localTick: 1440, staffStep: 3, durationTicks: 480)
        // A whole rest at the onset covers the measure exactly.
        let rest = ResolvedRest(
            id: 2,
            position: NotationTickPosition(measureIndex: 0, localTick: 0),
            duration: .whole,
            dotCount: 0,
            isFullMeasure: true,
            voice: .upper,
            durationTicks: 1920
        )
        _ = try Fixtures.document(notes: [note], rests: [rest], controls: [])
    }

    @Test("validation rejects a note span crossing the measure end")
    func validationRejectsNoteSpanCrossingMeasureEnd() {
        // 240 + 1920 > 1920: a nominal whole note whose exact span runs
        // past the measure edge is unrepresentable.
        #expect {
            try Fixtures.document(
                notes: [Fixtures.makeNote(id: 1, localTick: 240, staffStep: 3, duration: .whole)],
                rests: [],
                controls: []
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .eventSpanOutsideMeasure(
                    eventID: 1,
                    measureIndex: 0,
                    localTick: 240,
                    durationTicks: 1920
                )
        }
        // One tick past the exact boundary still crosses.
        #expect {
            try Fixtures.document(
                notes: [Fixtures.makeNote(id: 2, localTick: 1440, staffStep: 3, durationTicks: 481)],
                rests: [],
                controls: []
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .eventSpanOutsideMeasure(
                    eventID: 2,
                    measureIndex: 0,
                    localTick: 1440,
                    durationTicks: 481
                )
        }
    }

    @Test("validation rejects a rest span crossing the measure end")
    func validationRejectsRestSpanCrossingMeasureEnd() {
        #expect {
            try Fixtures.document(
                notes: [],
                rests: [ResolvedRest(
                    id: 2,
                    position: NotationTickPosition(measureIndex: 0, localTick: 1440),
                    duration: .half,
                    dotCount: 0,
                    isFullMeasure: false,
                    voice: .upper,
                    durationTicks: 960
                )],
                controls: []
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .eventSpanOutsideMeasure(
                    eventID: 2,
                    measureIndex: 0,
                    localTick: 1440,
                    durationTicks: 960
                )
        }
    }

    @Test("validation rejects a span whose end overflows Int without trapping")
    func validationRejectsOverflowingSpanEndWithoutTrapping() {
        // Onset is inside the Int.max measure; localTick + durationTicks
        // cannot be represented — must reject, never trap.
        #expect {
            try Fixtures.document(
                measures: [Fixtures.measure(durationTicks: Int.max)],
                notes: [Fixtures.makeNote(
                    id: 1,
                    localTick: Int.max - 10,
                    staffStep: 3,
                    durationTicks: 480
                )],
                rests: [],
                controls: []
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .eventSpanOutsideMeasure(
                    eventID: 1,
                    measureIndex: 0,
                    localTick: Int.max - 10,
                    durationTicks: 480
                )
        }
    }

    // MARK: Dot counts

    @Test("validation rejects negative note and rest dot counts")
    func validationRejectsNegativeDotCounts() {
        #expect {
            try Fixtures.document(
                notes: [Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, dotCount: -1)],
                rests: [],
                controls: []
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .invalidEventDotCount(eventID: 1, dotCount: -1)
        }
        #expect {
            try Fixtures.document(
                notes: [],
                rests: [ResolvedRest(
                    id: 2,
                    position: NotationTickPosition(measureIndex: 0, localTick: 480),
                    duration: .quarter,
                    dotCount: -2,
                    isFullMeasure: false,
                    voice: .upper,
                    durationTicks: 480
                )],
                controls: []
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .invalidEventDotCount(eventID: 2, dotCount: -2)
        }
    }

    @Test("validation accepts zero and positive dot counts")
    func validationAcceptsNonNegativeDotCounts() throws {
        _ = try Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, dotCount: 0),
                Fixtures.makeNote(id: 2, localTick: 480, staffStep: 3, dotCount: 2)
            ],
            rests: [Fixtures.rest(id: 3, localTick: 960)],
            controls: []
        )
    }

    // MARK: Meter terms

    @Test("validation rejects non-positive meter terms")
    func validationRejectsNonPositiveMeter() {
        // The meter signature prints both terms verbatim — a 0/4 or 4/0
        // would render an impossible signature.
        #expect {
            try Fixtures.document(
                measures: [Fixtures.measure(meter: NotationMeter(beats: 0, noteValue: 4))],
                notes: [],
                rests: [],
                controls: []
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .invalidMeter(measureIndex: 0, beats: 0, noteValue: 4)
        }
        #expect {
            try Fixtures.document(
                measures: [Fixtures.measure(meter: NotationMeter(beats: 4, noteValue: 0))],
                notes: [],
                rests: [],
                controls: []
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .invalidMeter(measureIndex: 0, beats: 4, noteValue: 0)
        }
        #expect {
            try Fixtures.document(
                measures: [Fixtures.measure(meter: NotationMeter(beats: -3, noteValue: -8))],
                notes: [],
                rests: [],
                controls: []
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .invalidMeter(measureIndex: 0, beats: -3, noteValue: -8)
        }
    }

    @Test("validation accepts ordinary meters")
    func validationAcceptsPositiveMeters() throws {
        _ = try Fixtures.document(
            measures: [Fixtures.measure(meter: NotationMeter(beats: 6, noteValue: 8))],
            notes: [],
            rests: [],
            controls: []
        )
    }
}
