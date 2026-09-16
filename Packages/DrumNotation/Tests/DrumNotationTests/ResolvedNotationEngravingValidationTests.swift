import Testing
import DrumNotation

/// HPA-166 Task 1: event and tuplet validation — exact event durations stay
/// positive, IDs are unique per collection, and tuplets must reference
/// existing members in their own measure and voice. Beat-group coverage
/// validation lives in the sibling suite.
@Suite("Resolved notation engraving validation")
struct ResolvedNotationEngravingValidationTests {
    // MARK: Event durations

    @Test("validation rejects a note with non-positive durationTicks")
    func validationRejectsNonPositiveNoteDurationTicks() {
        #expect {
            try Fixtures.document(
                notes: [Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, durationTicks: 0)],
                rests: [],
                controls: []
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .invalidEventDurationTicks(eventID: 1, durationTicks: 0)
        }
        #expect {
            try Fixtures.document(
                notes: [Fixtures.makeNote(id: 2, localTick: 0, staffStep: 3, durationTicks: -120)],
                rests: [],
                controls: []
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .invalidEventDurationTicks(eventID: 2, durationTicks: -120)
        }
    }

    @Test("a nominal duration extending past the measure end still validates")
    func nominalDurationPastMeasureEndStillValidates() throws {
        // Resolved notes legitimately carry nominal `.whole`/`.half`
        // durations that extend past the measure edge — the app's stemless
        // boundary notes rely on this — so containment binds the onset,
        // which `eventOutsideMeasure` already enforces, not the span.
        let note = Fixtures.makeNote(id: 1, localTick: 240, staffStep: 3, duration: .whole)
        _ = try Fixtures.document(notes: [note], rests: [], controls: [])
    }

    @Test("validation rejects a rest with non-positive durationTicks")
    func validationRejectsNonPositiveRestDurationTicks() {
        #expect {
            try Fixtures.document(
                notes: [],
                rests: [ResolvedRest(
                    id: 2,
                    position: NotationTickPosition(measureIndex: 0, localTick: 480),
                    duration: .quarter,
                    dotCount: 0,
                    isFullMeasure: false,
                    voice: .upper,
                    durationTicks: 0
                )],
                controls: []
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .invalidEventDurationTicks(eventID: 2, durationTicks: 0)
        }
    }

    // MARK: ID uniqueness

    @Test("validation rejects duplicate note, rest and control IDs")
    func validationRejectsDuplicateEventIDs() {
        #expect {
            try Fixtures.document(
                notes: [Fixtures.note(id: 5), Fixtures.note(id: 5, localTick: 480)],
                rests: [],
                controls: []
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError == .duplicateEventID(5)
        }
        #expect {
            try Fixtures.document(
                notes: [],
                rests: [Fixtures.rest(id: 6), Fixtures.rest(id: 6, localTick: 960)],
                controls: []
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError == .duplicateEventID(6)
        }
        #expect {
            try Fixtures.document(
                notes: [],
                rests: [],
                controls: [Fixtures.control(id: 7), Fixtures.control(id: 7, localTick: 960)]
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError == .duplicateEventID(7)
        }
    }

    @Test("validation rejects duplicate tuplet IDs")
    func validationRejectsDuplicateTupletIDs() {
        #expect {
            try Fixtures.document(
                notes: [Fixtures.note(id: 1)],
                rests: [],
                controls: [],
                tuplets: [
                    ResolvedTupletGroup(
                        id: 8,
                        measureIndex: 0,
                        voice: .upper,
                        ratio: ResolvedTupletRatio(actual: 3, normal: 2),
                        memberNoteIDs: [1],
                        memberRestIDs: []
                    ),
                    ResolvedTupletGroup(
                        id: 8,
                        measureIndex: 0,
                        voice: .upper,
                        ratio: ResolvedTupletRatio(actual: 3, normal: 2),
                        memberNoteIDs: [1],
                        memberRestIDs: []
                    )
                ]
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError == .duplicateEventID(8)
        }
    }

    @Test("validation allows equal IDs across separate collections")
    func validationAllowsSharedIDsAcrossCollections() throws {
        _ = try Fixtures.document(
            notes: [Fixtures.note(id: 5)],
            rests: [Fixtures.rest(id: 5)],
            controls: [Fixtures.control(id: 5)]
        )
    }

    // MARK: Tuplets

    @Test("validation rejects a tuplet with non-positive ratio")
    func validationRejectsNonPositiveTupletRatio() {
        #expect {
            try Fixtures.document(
                notes: [Fixtures.note(id: 1)],
                rests: [],
                controls: [],
                tuplets: [ResolvedTupletGroup(
                    id: 0,
                    measureIndex: 0,
                    voice: .upper,
                    ratio: ResolvedTupletRatio(actual: 0, normal: 2),
                    memberNoteIDs: [1],
                    memberRestIDs: []
                )]
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .invalidTupletRatio(tupletID: 0, actual: 0, normal: 2)
        }
        #expect {
            try Fixtures.document(
                notes: [Fixtures.note(id: 1)],
                rests: [],
                controls: [],
                tuplets: [ResolvedTupletGroup(
                    id: 0,
                    measureIndex: 0,
                    voice: .upper,
                    ratio: ResolvedTupletRatio(actual: 3, normal: -1),
                    memberNoteIDs: [1],
                    memberRestIDs: []
                )]
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .invalidTupletRatio(tupletID: 0, actual: 3, normal: -1)
        }
    }

    @Test("validation rejects a tuplet in an unknown measure")
    func validationRejectsTupletInUnknownMeasure() {
        #expect {
            try Fixtures.document(
                notes: [Fixtures.note(id: 1)],
                rests: [],
                controls: [],
                tuplets: [ResolvedTupletGroup(
                    id: 0,
                    measureIndex: 3,
                    voice: .upper,
                    ratio: ResolvedTupletRatio(actual: 3, normal: 2),
                    memberNoteIDs: [],
                    memberRestIDs: []
                )]
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .unknownTupletMeasure(tupletID: 0, measureIndex: 3)
        }
    }

    @Test("validation rejects a tuplet referencing an unknown member")
    func validationRejectsTupletUnknownMember() {
        #expect {
            try Fixtures.document(
                notes: [Fixtures.note(id: 1)],
                rests: [],
                controls: [],
                tuplets: [ResolvedTupletGroup(
                    id: 0,
                    measureIndex: 0,
                    voice: .upper,
                    ratio: ResolvedTupletRatio(actual: 3, normal: 2),
                    memberNoteIDs: [99],
                    memberRestIDs: []
                )]
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .unknownTupletMember(tupletID: 0, memberID: 99)
        }
        #expect {
            try Fixtures.document(
                notes: [],
                rests: [Fixtures.rest(id: 2)],
                controls: [],
                tuplets: [ResolvedTupletGroup(
                    id: 0,
                    measureIndex: 0,
                    voice: .upper,
                    ratio: ResolvedTupletRatio(actual: 3, normal: 2),
                    memberNoteIDs: [],
                    memberRestIDs: [99]
                )]
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .unknownTupletMember(tupletID: 0, memberID: 99)
        }
    }

    @Test("validation rejects a tuplet member from a different measure or voice")
    func validationRejectsTupletMemberOutsideMeasureOrVoice() {
        // The member exists but sits in measure 1 while the tuplet claims 0.
        #expect {
            try Fixtures.document(
                measures: [Fixtures.measure(), Fixtures.measure(index: 1, startTick: 1920)],
                notes: [Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, measureIndex: 1)],
                rests: [],
                controls: [],
                tuplets: [ResolvedTupletGroup(
                    id: 0,
                    measureIndex: 0,
                    voice: .upper,
                    ratio: ResolvedTupletRatio(actual: 3, normal: 2),
                    memberNoteIDs: [1],
                    memberRestIDs: []
                )]
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .unknownTupletMember(tupletID: 0, memberID: 1)
        }
        // Same measure, but the member's voice differs from the tuplet's.
        #expect {
            try Fixtures.document(
                notes: [Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, voice: .lower)],
                rests: [],
                controls: [],
                tuplets: [ResolvedTupletGroup(
                    id: 0,
                    measureIndex: 0,
                    voice: .upper,
                    ratio: ResolvedTupletRatio(actual: 3, normal: 2),
                    memberNoteIDs: [1],
                    memberRestIDs: []
                )]
            )
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .unknownTupletMember(tupletID: 0, memberID: 1)
        }
    }

    @Test("validation accepts a tuplet spanning note and rest members")
    func validationAcceptsTupletWithNoteAndRestMembers() throws {
        _ = try Fixtures.document(
            notes: [Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3)],
            rests: [Fixtures.rest(id: 2, localTick: 960)],
            controls: [],
            tuplets: [ResolvedTupletGroup(
                id: 0,
                measureIndex: 0,
                voice: .upper,
                ratio: ResolvedTupletRatio(actual: 3, normal: 2),
                memberNoteIDs: [1],
                memberRestIDs: [2]
            )]
        )
    }
}
