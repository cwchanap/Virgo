import CoreGraphics
import Testing
@testable import DrumNotation

/// HPA-166 Task 2: package stem groups, the pinned representative
/// comparators, one `VisibleFlagPlan` per stem group, and the plan-driven
/// formatter path that reserves flag ink once at the shared stem axis.
@Suite("Stem groups and flag plans")
struct StemTopologyTests {
    /// 4/4 at the fixtures' 1920 ticks per whole note: quarter = 480 ticks,
    /// four beat groups of 480.
    private func measure(index: Int = 0, startTick: Int = 0) -> ResolvedMeasure {
        Fixtures.measure(
            index: index,
            startTick: startTick,
            beatGroups: (0..<4).map { ResolvedBeatGroup(startTick: $0 * 480, durationTicks: 480) }
        )
    }

    private func topology(
        notes: [ResolvedNote],
        measures: [ResolvedMeasure]? = nil
    ) throws -> StemTopology {
        StemTopologyBuilder().build(try ResolvedNotationInput(
            ticksPerWholeNote: Fixtures.ticksPerWholeNote,
            measures: measures ?? [measure()],
            notes: notes
        ))
    }

    private func group(_ topology: StemTopology, localTick: Int) throws -> StemGroup {
        try #require(topology.stemGroups.first { $0.key.localTick == localTick })
    }

    private func plan(_ topology: StemTopology, localTick: Int) throws -> VisibleFlagPlan {
        let stemGroup = try group(topology, localTick: localTick)
        let index = try #require(topology.stemGroups.firstIndex(of: stemGroup))
        return topology.flagPlans[index]
    }

    // MARK: Stem representative comparator (pinned order)

    @Test("up-stem representative is the lowest staff-step stem member")
    func upStemRepresentativeIsLowestMember() throws {
        let topology = try topology(notes: [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 5, duration: .eighth),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 1, duration: .eighth)
        ])
        let stemGroup = try group(topology, localTick: 0)

        #expect(topology.stemGroups.count == 1)
        #expect(stemGroup.stemRepresentativeID == 2)
    }

    @Test("down-stem representative is the highest staff-step stem member")
    func downStemRepresentativeIsHighestMember() throws {
        let topology = try topology(notes: [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 5, stem: .down, duration: .eighth),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 1, stem: .down, duration: .eighth)
        ])
        let stemGroup = try group(topology, localTick: 0)

        #expect(stemGroup.stemRepresentativeID == 1)
    }

    @Test("stem representative skips stemless and non-engravable members")
    func stemRepresentativeSkipsNonMembers() throws {
        let topology = try topology(notes: [
            // Stemless whole at the stem side: never a stem member.
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 0, duration: .whole),
            // Non-engravable eighth at the stem side: suppressed member.
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 2, duration: .eighth, isRhythmEngravable: false),
            Fixtures.makeNote(id: 3, localTick: 0, staffStep: 6, duration: .eighth)
        ])
        let stemGroup = try group(topology, localTick: 0)

        #expect(stemGroup.stemRepresentativeID == 3)
    }

    @Test("stem membership derives from duration and engraving semantics alone")
    func stemMembershipDerivesFromEngravingSemantics() throws {
        // With no per-note membership field, every stem-requiring engravable
        // head is a member; only stemless heads sit out.
        let topology = try topology(notes: [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 0, duration: .whole),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 2, duration: .eighth),
            Fixtures.makeNote(id: 3, localTick: 0, staffStep: 6, duration: .eighth)
        ])
        let stemGroup = try group(topology, localTick: 0)

        // Up-stem: the lowest stem member anchors the shared stem; the
        // stemless whole keeps its chord slot but never participates.
        #expect(stemGroup.memberNoteIDs == [1, 2, 3])
        #expect(stemGroup.stemRepresentativeID == 2)
    }

    @Test("equal staff steps tiebreak the stem representative by tiebreakOrder then ID")
    func stemRepresentativeTiebreaks() throws {
        // Members sort by staffStep, then tiebreakOrder, then ID; the up-stem
        // pick takes the stem-side (last) member of that ordering.
        let up = try topology(notes: [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, duration: .eighth, tiebreakOrder: 5),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 3, duration: .eighth, tiebreakOrder: 1)
        ])
        #expect(try group(up, localTick: 0).stemRepresentativeID == 1)

        let down = try topology(notes: [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, stem: .down, duration: .eighth, tiebreakOrder: 5),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 3, stem: .down, duration: .eighth, tiebreakOrder: 1)
        ])
        #expect(try group(down, localTick: 0).stemRepresentativeID == 2)

        // Identical staff step AND tiebreak order falls back to the event ID.
        let byID = try topology(notes: [
            Fixtures.makeNote(id: 9, localTick: 0, staffStep: 3, duration: .eighth, tiebreakOrder: 2),
            Fixtures.makeNote(id: 4, localTick: 0, staffStep: 3, duration: .eighth, tiebreakOrder: 2)
        ])
        #expect(try group(byID, localTick: 0).stemRepresentativeID == 9)
    }

    // MARK: Flag representative comparator (pinned order)

    @Test("flag representative picks the most required flag levels")
    func flagRepresentativePicksMostFlags() throws {
        let topology = try topology(notes: [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 1, duration: .eighth, tiebreakOrder: 0),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 5, duration: .sixteenth, tiebreakOrder: 9)
        ])
        let stemGroup = try group(topology, localTick: 0)

        // The sixteenth owns two flag levels and wins despite the lower
        // tiebreak order on the eighth.
        #expect(stemGroup.flagRepresentativeID == 2)
    }

    @Test("equal durations tiebreak the flag representative by tiebreakOrder then ID")
    func flagRepresentativeTiebreaks() throws {
        let byOrder = try topology(notes: [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 1, duration: .sixteenth, tiebreakOrder: 5),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 5, duration: .sixteenth, tiebreakOrder: 1)
        ])
        #expect(try group(byOrder, localTick: 0).flagRepresentativeID == 2)

        let byID = try topology(notes: [
            Fixtures.makeNote(id: 9, localTick: 0, staffStep: 1, duration: .sixteenth, tiebreakOrder: 2),
            Fixtures.makeNote(id: 4, localTick: 0, staffStep: 5, duration: .sixteenth, tiebreakOrder: 2)
        ])
        #expect(try group(byID, localTick: 0).flagRepresentativeID == 4)
    }

    @Test("a suppressed member never governs the flag representative but keeps its chord ID")
    func flagRepresentativeSkipsNonEngravableMembers() throws {
        let topology = try topology(notes: [
            Fixtures.makeNote(
                id: 1, localTick: 0, staffStep: 3,
                duration: .thirtySecond, durationTicks: 60
            ),
            // The suppressed sibling owns MORE flag levels — the member
            // the unfixed comparator would wrongly let govern the event.
            Fixtures.makeNote(
                id: 2, localTick: 0, staffStep: 5,
                duration: .sixtyFourth, durationTicks: 30,
                isRhythmEngravable: false
            )
        ])
        let stemGroup = try group(topology, localTick: 0)
        let index = try #require(topology.stemGroups.firstIndex(of: stemGroup))

        #expect(stemGroup.flagRepresentativeID == 1)
        // Chord membership is unchanged: every member ID still rides the
        // stem group and its timeline event.
        #expect(stemGroup.memberNoteIDs == [1, 2])
        #expect(topology.events[index].noteIDs == [1, 2])
        #expect(topology.events[index].role == .beamable(requiredBeamLevels: 3, durationTicks: 60))
    }

    @Test("a fully suppressed chord emits no flag representative")
    func suppressedChordHasNoFlagRepresentative() throws {
        let topology = try topology(notes: [
            Fixtures.makeNote(
                id: 1, localTick: 0, staffStep: 3,
                duration: .sixteenth, isRhythmEngravable: false
            )
        ])

        #expect(try group(topology, localTick: 0).flagRepresentativeID == nil)
        #expect(topology.events.first?.role == .boundary)
    }

    // MARK: Stem-group construction

    @Test("stem groups split by voice, stem direction and tick; member IDs are sorted")
    func stemGroupKeyBoundaries() throws {
        let topology = try topology(notes: [
            Fixtures.makeNote(id: 5, localTick: 0, staffStep: 1, duration: .eighth),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 5, duration: .eighth),
            Fixtures.makeNote(id: 3, localTick: 0, staffStep: 1, duration: .eighth, voice: .lower),
            Fixtures.makeNote(id: 4, localTick: 0, staffStep: 1, stem: .down, duration: .eighth),
            Fixtures.makeNote(id: 6, localTick: 480, staffStep: 1, duration: .eighth)
        ])

        // One tick, three (voice, direction) pairs → three groups plus the
        // later tick's own group.
        #expect(topology.stemGroups.count == 4)
        let upperUp = try #require(topology.stemGroups.first {
            $0.key == StemGroupKey(
                measureIndex: 0,
                localTick: 0,
                voice: .upper,
                stemDirection: .up
            )
        })
        #expect(upperUp.memberNoteIDs == [2, 5])
        #expect(topology.stemGroups.filter { $0.key.voice == .lower }.count == 1)
        #expect(topology.stemGroups.filter { $0.key.stemDirection == .down }.count == 1)
    }

    @Test("beamable events carry flag-representative levels and exact duration")
    func beamableEventRole() throws {
        let topology = try topology(notes: [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 1, duration: .eighth, durationTicks: 240),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 5, duration: .sixteenth, durationTicks: 120)
        ])
        let stemGroup = try group(topology, localTick: 0)
        let index = try #require(topology.stemGroups.firstIndex(of: stemGroup))

        #expect(topology.events[index].role == .beamable(requiredBeamLevels: 2, durationTicks: 120))
        #expect(topology.events[index].noteIDs == [1, 2])
        #expect(topology.events[index].absoluteTick == 0)
    }

    @Test("non-engravable or all-stemless groups emit boundary events")
    func boundaryEventRole() throws {
        let stemless = try topology(notes: [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 1, duration: .whole)
        ])
        #expect(stemless.events.first?.role == .boundary)
        #expect(stemless.stemGroups.first?.stemRepresentativeID == nil)

        let suppressed = try topology(notes: [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 1, duration: .sixteenth, isRhythmEngravable: false)
        ])
        #expect(suppressed.events.first?.role == .boundary)
    }

    // MARK: One VisibleFlagPlan per stem group

    @Test("isolated beamable groups get a canonical plan at the flag representative's duration")
    func isolatedGroupsGetCanonicalPlan() throws {
        let topology = try topology(notes: [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, duration: .sixteenth, durationTicks: 120),
            Fixtures.makeNote(id: 2, localTick: 480, staffStep: 3, duration: .eighth, durationTicks: 240),
            Fixtures.makeNote(id: 3, localTick: 960, staffStep: 3, duration: .thirtySecond, durationTicks: 60)
        ])

        #expect(try plan(topology, localTick: 0) == .canonical(.sixteenth))
        #expect(try plan(topology, localTick: 480) == .canonical(.eighth))
        #expect(try plan(topology, localTick: 960) == .canonical(.thirtySecond))
        #expect(topology.flagReservations == [
            1: .sixteenth,
            2: .eighth,
            3: .thirtySecond
        ])
    }

    @Test("fully beamed groups get none plans and no flag reservations")
    func beamedGroupsGetNonePlan() throws {
        let topology = try topology(notes: (0..<4).map {
            Fixtures.makeNote(id: $0 + 1, localTick: $0 * 120, staffStep: 3, duration: .sixteenth, durationTicks: 120)
        })

        #expect(topology.stemGroups.count == 4)
        #expect(topology.flagPlans == [.none, .none, .none, .none])
        #expect(topology.flagReservations.isEmpty)
        #expect(topology.topology.primaryGroups.count == 1)
    }

    @Test("boundary groups get none plans")
    func boundaryGroupsGetNonePlan() throws {
        let topology = try topology(notes: [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 1, duration: .whole),
            Fixtures.makeNote(id: 2, localTick: 480, staffStep: 3, duration: .sixteenth, isRhythmEngravable: false)
        ])

        #expect(try plan(topology, localTick: 0) == .none)
        #expect(try plan(topology, localTick: 480) == .none)
        #expect(topology.flagReservations.isEmpty)
    }

    @Test("flag plan arms map uncovered levels exactly")
    func flagPlanArms() {
        // No uncovered levels → none; all expected uncovered → canonical;
        // a proper subset → components carrying exactly the uncovered levels.
        #expect(VisibleFlagPlan(
            uncovered: [], expected: [0, 1], canonical: .sixteenth
        ) == .none)
        #expect(VisibleFlagPlan(
            uncovered: [0, 1], expected: [0, 1], canonical: .sixteenth
        ) == .canonical(.sixteenth))
        #expect(VisibleFlagPlan(
            uncovered: [1], expected: [0, 1], canonical: .sixteenth
        ) == .components([1]))

        // The reserved footprint the formatter measures: the canonical glyph
        // for full coverage, one eighth-component for any partial set.
        #expect(VisibleFlagPlan.none.reservedFlagDuration == nil)
        #expect(VisibleFlagPlan.canonical(.sixteenth).reservedFlagDuration == .sixteenth)
        #expect(VisibleFlagPlan.components([1, 2]).reservedFlagDuration == .eighth)
        #expect(VisibleFlagPlan.components([]).reservedFlagDuration == nil)
    }
}

extension StemTopologyTests {
    // MARK: Plan-driven formatter spacing

    /// One flag's ink extent at the shared stem axis of the given head,
    /// relative to the column's base X — mirrors the formatter's flag
    /// attachment math (`stemAnchorOffset − stemWidth/2 − attachmentOffset`).
    private func flagInk(
        duration: NotationFlagDuration,
        headStyle: PercussionNoteheadStyle,
        headDuration: NotationDuration,
        stem: NotationStemDirection = .up
    ) -> (min: CGFloat, max: CGFloat) {
        let style = NotationFormattingStyle.virgoDefault
        let head = PercussionGlyphMetrics.notehead(
            style: headStyle, duration: headDuration,
            stemDirection: stem, staffSpace: style.staffSpace
        )
        let flag = PercussionGlyphMetrics.flag(
            duration: duration, direction: stem, staffSpace: style.staffSpace
        )
        let anchorX = head.stemAnchorOffset.x - style.stemWidth / 2 - flag.attachmentOffset.x
        return (anchorX + flag.paintedBounds.minX, anchorX + flag.paintedBounds.maxX)
    }

    private func planFormat(_ input: ResolvedNotationInput) throws -> FormattedNotation {
        NotationFormatter.format(
            input,
            style: .virgoDefault,
            stemTopology: StemTopologyBuilder().build(input)
        )
    }

    @Test("plan-driven formatting reserves one flag extent at the shared stem axis")
    func planDrivenFlagReservation() throws {
        let notes = [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, duration: .sixteenth, durationTicks: 120)
        ]
        let input = try ResolvedNotationInput(
            ticksPerWholeNote: Fixtures.ticksPerWholeNote,
            measures: [measure()],
            notes: notes
        )
        let notation = try planFormat(input)
        let column = try Fixtures.column(notation, localTick: 0)
        let flag = flagInk(duration: .sixteenth, headStyle: .x, headDuration: .sixteenth)
        let head = PercussionGlyphMetrics.notehead(
            style: .x, duration: .sixteenth, stemDirection: .up,
            staffSpace: NotationFormattingStyle.virgoDefault.staffSpace
        ).paintedBounds

        #expect(abs(column.leftExtent - max(0, -min(head.minX, flag.min))) < 0.001)
        #expect(abs(column.rightExtent - max(0, max(head.maxX, flag.max))) < 0.001)
    }

    /// The chord column's expected ink extents: both heads' bounds plus
    /// exactly ONE flag extent at the shared (snare) stem axis — a second
    /// reservation at the hi-hat axis would widen it.
    private func expectedChordExtents() -> (left: CGFloat, right: CGFloat) {
        let style = NotationFormattingStyle.virgoDefault
        let snareHead = PercussionGlyphMetrics.notehead(
            style: .normal, duration: .sixteenth, stemDirection: .up, staffSpace: style.staffSpace
        ).paintedBounds
        let hiHatHead = PercussionGlyphMetrics.notehead(
            style: .x, duration: .sixteenth, stemDirection: .up, staffSpace: style.staffSpace
        ).paintedBounds
        let flag = flagInk(
            duration: .sixteenth, headStyle: .normal, headDuration: .sixteenth
        )
        return (
            left: max(0, -min(snareHead.minX, hiHatHead.minX, flag.min)),
            right: max(0, max(snareHead.maxX, hiHatHead.maxX, flag.max))
        )
    }

    @Test("same-tick snare + closed-hi-hat sixteenths reserve ONE flag extent")
    func chordReservesOneFlagExtent() throws {
        // Snare (.normal, lower staff step) + closed hi-hat (.x, higher) at
        // one tick: one stem group, one plan, one reservation on the stem
        // representative — the chord never doubles the flag ink.
        let notes = [
            Fixtures.makeNote(
                id: 1, localTick: 240, staffStep: 2, headStyle: .normal,
                duration: .sixteenth, durationTicks: 120, tiebreakOrder: 1
            ),
            Fixtures.makeNote(
                id: 2, localTick: 240, staffStep: 6, headStyle: .x,
                duration: .sixteenth, durationTicks: 120, tiebreakOrder: 2
            )
        ]
        let input = try ResolvedNotationInput(
            ticksPerWholeNote: Fixtures.ticksPerWholeNote,
            measures: [measure()],
            notes: notes
        )
        let topology = StemTopologyBuilder().build(input)

        #expect(topology.stemGroups.count == 1)
        #expect(topology.stemGroups.first?.memberNoteIDs == [1, 2])
        // The up-stem representative is the lowest head — the snare.
        #expect(topology.stemGroups.first?.stemRepresentativeID == 1)
        #expect(topology.flagPlans == [.canonical(.sixteenth)])
        #expect(topology.flagReservations == [1: .sixteenth])

        let notation = try planFormat(input)
        let column = try Fixtures.column(notation, localTick: 240)
        let expected = expectedChordExtents()
        #expect(abs(column.leftExtent - expected.left) < 0.001)
        #expect(abs(column.rightExtent - expected.right) < 0.001)
    }

    @Test("the public formatter is the plan-driven path")
    func publicFormatMatchesPlanPath() throws {
        // The public `format` builds the real stem topology itself: its
        // output must equal the internal plan-driven overload's on the same
        // input — an isolated sixteenth reserves its canonical flag, and a
        // fully beamed run reserves none.
        let isolated = [
            Fixtures.makeNote(id: 1, localTick: 240, staffStep: 3, duration: .sixteenth, durationTicks: 120)
        ]
        let beamed = (0..<4).map {
            Fixtures.makeNote(id: $0 + 1, localTick: $0 * 120, staffStep: 3, duration: .sixteenth, durationTicks: 120)
        }
        for notes in [isolated, beamed] {
            let input = try ResolvedNotationInput(
                ticksPerWholeNote: Fixtures.ticksPerWholeNote,
                measures: [measure()],
                notes: notes
            )
            #expect(try Fixtures.format(input) == planFormat(input))
        }
    }

    @Test("every primary beam group maps to exactly one formatted row")
    func everyBeamGroupMapsToOneRow() throws {
        // Eight beamed sixteenth groups across eight measures force a row
        // wrap; each group's member columns must share one row index.
        let measures = (0..<8).map { measure(index: $0, startTick: $0 * 1920) }
        let notes = measures.flatMap { measure in
            (0..<4).map { step in
                Fixtures.makeNote(
                    id: measure.index * 10 + step,
                    localTick: step * 120,
                    staffStep: 3,
                    duration: .sixteenth,
                    measureIndex: measure.index,
                    durationTicks: 120
                )
            }
        }
        let input = try ResolvedNotationInput(
            ticksPerWholeNote: Fixtures.ticksPerWholeNote,
            measures: measures,
            notes: notes
        )
        let topology = StemTopologyBuilder().build(input)
        let notation = try planFormat(input)

        #expect(topology.topology.primaryGroups.count == 8)
        #expect(Set(notation.measures.map { $0.rowIndex }).count > 1)
        for primaryGroup in topology.topology.primaryGroups {
            let rows = Set(primaryGroup.eventIndices.map { index -> Int in
                let event = topology.events[index]
                let formatted = notation.measures.first { $0.index == event.measureIndex }
                return formatted?.rowIndex ?? -1
            })
            #expect(rows.count == 1, "beam group spans rows \(String(describing: rows))")
        }
    }
}
