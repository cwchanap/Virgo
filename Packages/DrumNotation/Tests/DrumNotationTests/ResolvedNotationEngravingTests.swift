import Testing
import DrumNotation

/// HPA-166 Task 1: the resolved model's final engraving semantics — voice,
/// meter, ordered beat groups, exact event durations, control intent and
/// resolved tuplet groups. The validation that keeps malformed engraving
/// input unrepresentable lives in the sibling validation suites.
@Suite("Resolved notation engraving model")
struct ResolvedNotationEngravingTests {
    // MARK: New resolved value types

    @Test("NotationVoiceRole pins upper then lower")
    func voiceRolePinsUpperThenLower() {
        #expect(NotationVoiceRole.upper.rawValue == 0)
        #expect(NotationVoiceRole.lower.rawValue == 1)
        #expect(NotationVoiceRole.upper != NotationVoiceRole.lower)
    }

    @Test("NotationMeter carries beats and note value")
    func notationMeterCarriesBeatsAndNoteValue() {
        let meter = NotationMeter(beats: 6, noteValue: 8)
        #expect(meter.beats == 6)
        #expect(meter.noteValue == 8)
        #expect(meter == NotationMeter(beats: 6, noteValue: 8))
        #expect(meter != NotationMeter(beats: 4, noteValue: 4))
    }

    @Test("ResolvedBeatGroup carries span only; array position is the group ordinal")
    func resolvedBeatGroupCarriesSpanOnly() {
        let group = ResolvedBeatGroup(startTick: 480, durationTicks: 240)
        #expect(group.startTick == 480)
        #expect(group.durationTicks == 240)
        // No `index` field may exist: the group ordinal is the validated
        // array position inside `ResolvedMeasure.beatGroups`.
        let labels = Mirror(reflecting: group).children.compactMap(\.label)
        #expect(labels == ["startTick", "durationTicks"])
    }

    @Test("ResolvedMeasure carries meter and ordered beat groups")
    func measureCarriesMeterAndOrderedBeatGroups() throws {
        let measure = ResolvedMeasure(
            index: 0,
            startTick: 0,
            durationTicks: 1440,
            meter: NotationMeter(beats: 6, noteValue: 8),
            beatGroups: [
                ResolvedBeatGroup(startTick: 0, durationTicks: 720),
                ResolvedBeatGroup(startTick: 720, durationTicks: 720)
            ]
        )
        let document = try Fixtures.document(measures: [measure], notes: [], rests: [], controls: [])

        #expect(document.measures.first == measure)
        #expect(measure.meter == NotationMeter(beats: 6, noteValue: 8))
        #expect(measure.beatGroups.map(\.startTick) == [0, 720])
        #expect(measure.beatGroups.map(\.durationTicks) == [720, 720])
    }

    // MARK: Notes

    @Test("ResolvedNote carries voice, exact duration ticks, tiebreak order, engravability and articulation")
    func noteCarriesEngravingSemantics() throws {
        let note = ResolvedNote(
            id: 3,
            position: NotationTickPosition(measureIndex: 0, localTick: 240),
            stemDirection: .down,
            staffStep: -2,
            stemMember: true,
            noteheadStyle: .normal,
            duration: .eighth,
            dotCount: 0,
            visibleFlagDuration: nil,
            voice: .lower,
            durationTicks: 300,
            tiebreakOrder: 4,
            isRhythmEngravable: false,
            articulation: .open
        )
        let document = try Fixtures.document(notes: [note], rests: [], controls: [])
        let stored = try #require(document.notes.first)

        #expect(stored == note)
        #expect(stored.voice == .lower)
        #expect(stored.durationTicks == 300)
        #expect(stored.tiebreakOrder == 4)
        #expect(stored.isRhythmEngravable == false)
        #expect(stored.articulation == .open)
    }

    @Test("articulation defaults to nil for unarticulated notes")
    func articulationDefaultsToNil() throws {
        let document = try Fixtures.document(notes: [Fixtures.note()], rests: [], controls: [])
        #expect(document.notes.first?.articulation == nil)
    }

    // MARK: Rests

    @Test("ResolvedRest carries voice and exact duration ticks")
    func restCarriesVoiceAndDurationTicks() throws {
        let rest = ResolvedRest(
            id: 2,
            position: NotationTickPosition(measureIndex: 0, localTick: 480),
            duration: .eighth,
            dotCount: 0,
            isFullMeasure: false,
            voice: .lower,
            durationTicks: 240
        )
        let document = try Fixtures.document(notes: [], rests: [rest], controls: [])
        #expect(document.rests.first == rest)
    }

    // MARK: Controls

    @Test("ResolvedControl carries kind and resolved target staff step")
    func controlCarriesKindAndTargetStaffStep() throws {
        for kind in [NotationControlKind.stop, .choke, .damp] {
            let control = ResolvedControl(
                id: 4,
                position: NotationTickPosition(measureIndex: 0, localTick: 120),
                kind: kind,
                targetStaffStep: -4
            )
            let document = try Fixtures.document(notes: [], rests: [], controls: [control])
            #expect(document.controls.first == control)
        }
    }

    // MARK: Tuplets

    @Test("ResolvedTupletGroup carries adapter-local ID, measure, voice, ratio and member IDs")
    func tupletGroupCarriesResolvedSemantics() throws {
        let note = Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3)
        let rest = ResolvedRest(
            id: 2,
            position: NotationTickPosition(measureIndex: 0, localTick: 640),
            duration: .eighth,
            dotCount: 0,
            isFullMeasure: false,
            voice: .upper,
            durationTicks: 160
        )
        let tuplet = ResolvedTupletGroup(
            id: 0,
            measureIndex: 0,
            voice: .upper,
            ratio: ResolvedTupletRatio(actual: 3, normal: 2),
            memberNoteIDs: [1],
            memberRestIDs: [2]
        )
        let document = try Fixtures.document(
            notes: [note],
            rests: [rest],
            controls: [],
            tuplets: [tuplet]
        )

        #expect(document.tuplets == [tuplet])
        #expect(tuplet.ratio == ResolvedTupletRatio(actual: 3, normal: 2))
        #expect(tuplet.memberNoteIDs == [1])
        #expect(tuplet.memberRestIDs == [2])
    }
}
