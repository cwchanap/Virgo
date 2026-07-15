import Testing
@testable import Virgo

@Suite("Notation Layout Control Rendering Tests")
struct NotationLayoutControlRenderingTests {
    private let support = NotationLayoutTestSupport()

    @Test("stop choke and damp preserve semantics while sharing plus-mark geometry")
    func controlKindsShareGeometryWithoutCollapsingSemantics() {
        let controls = NotationControlEventKind.allCases.map {
            support.control(
                kind: $0,
                originKind: .dtx,
                normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 1,
                normalizedTickWithinMeasure: 1,
                normalizedTicksPerMeasure: 4
            )
        }
        let result = support.layout(notes: [support.fallbackGridNote()], controls: controls)

        #expect(result.stopNotes.map(\.kind) == [.choke, .damp, .stop])
        #expect(Set(result.stopNotes.map(\.position)).count == 1)
        #expect(Set(result.stopNotes.map(\.timeColumn)).count == 1)
        #expect(Set(result.stopNotes.map(\.id)).count == 3)
    }

    @Test("missing and unknown targets preserve measure contribution but omit geometry")
    func unresolvedTargetsOmitGeometry() {
        let controls = [
            support.control(
                originKind: .dtx,
                normalizedMeasureIndex: 2,
                normalizedAbsoluteTick: 8,
                normalizedTickWithinMeasure: 0,
                normalizedTicksPerMeasure: 4,
                targetLaneID: nil
            ),
            support.control(
                originKind: .dtx,
                normalizedMeasureIndex: 2,
                normalizedAbsoluteTick: 9,
                normalizedTickWithinMeasure: 1,
                normalizedTicksPerMeasure: 4,
                targetLaneID: "ZZ"
            )
        ]
        let result = support.layout(notes: [], controls: controls)

        #expect(result.measures.count == 3)
        #expect(result.stopNotes.isEmpty)
    }

    @Test("lane 1A resolves to Crash and follows the active crash position override")
    func crashTargetUsesPositionOverride() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let result = support.layout(
            notes: [support.fallbackGridNote()],
            controls: [support.control(measureOffset: 0.25, targetLaneID: "1a")],
            style: style,
            notePositionOverrides: [.crash: .line3]
        )
        let stop = try #require(result.stopNotes.first)
        let expectedY = GameplayLayout.StaffLinePosition.line1.absoluteY(for: 0)
            + GameplayLayout.NotePosition.line3.yOffset
            - style.stopMarkVerticalOffset

        #expect(stop.targetLaneID == "1A")
        #expect(stop.targetDisplayName == "Crash")
        #expect(stop.position.y == expectedY)
    }

    @Test("controls never alter the note-driven grid wrapping or artifacts")
    func controlsDoNotFeedGridOrExistingArtifactBuilders() {
        let notes = [
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125),
            Note(interval: .quarter, noteType: .bass, measureNumber: 2, measureOffset: 0.5)
        ]
        let baseline = support.layout(notes: notes, minimumMeasureCount: 3)
        let withControls = support.layout(notes: notes, controls: [
            support.control(
                originKind: .dtx,
                normalizedMeasureIndex: 2,
                normalizedAbsoluteTick: 9,
                normalizedTickWithinMeasure: 1,
                normalizedTicksPerMeasure: 4
            )
        ], minimumMeasureCount: 3)

        #expect(withControls.tabGrid == baseline.tabGrid)
        #expect(withControls.measures == baseline.measures)
        #expect(withControls.noteHeads == baseline.noteHeads)
        #expect(Set(withControls.stems) == Set(baseline.stems))
        #expect(withControls.beams == baseline.beams)
        #expect(withControls.flags == baseline.flags)
        #expect(withControls.rests == baseline.rests)
        #expect(withControls.contentWidth == baseline.contentWidth)
    }

    @Test("control order and IDs use the full stable semantic tuple")
    func controlsUseStableSemanticTupleOrdering() {
        let events = support.stableSemanticTupleFixture()
        let ordered = support.layout(notes: [support.fallbackGridNote()], controls: events).stopNotes
        let shuffled = support
            .layout(notes: [support.fallbackGridNote()], controls: Array(events.reversed())).stopNotes

        #expect(ordered == shuffled)
        #expect(ordered.map(\.kind) == [.stop, .choke, .damp, .stop, .stop, .stop, .stop, .stop, .stop, .stop])
        #expect(ordered.map(\.targetLaneID) == ["1A", "11", "11", "11", "1A", "1A", "1A", "1A", "1A", "1A"])
        #expect(ordered.map(\.sourceLaneID) == ["Z", "A", "A", "A", "A", "B", "B", "B", "B", "Z"])
        #expect(ordered.map(\.sourceNoteID) == ["Z", "A", "A", "A", "A", "A", "B", "B", "B", "Z"])
        #expect(ordered.map(\.id) == [
            "control-m0-t0-kstop-target1A-source=s1:Z-id=s1:Z-gp=i9-gs=i9-duplicate-0",
            "control-m0-t240-kchoke-target11-source=s1:A-id=s1:A-gp=i0-gs=i4-duplicate-0",
            "control-m0-t240-kdamp-target11-source=s1:A-id=s1:A-gp=i0-gs=i4-duplicate-0",
            "control-m0-t240-kstop-target11-source=s1:A-id=s1:A-gp=i0-gs=i4-duplicate-0",
            "control-m0-t240-kstop-target1A-source=s1:A-id=s1:A-gp=i0-gs=i4-duplicate-0",
            "control-m0-t240-kstop-target1A-source=s1:B-id=s1:A-gp=i0-gs=i4-duplicate-0",
            "control-m0-t240-kstop-target1A-source=s1:B-id=s1:B-gp=i0-gs=i4-duplicate-0",
            "control-m0-t240-kstop-target1A-source=s1:B-id=s1:B-gp=i1-gs=i4-duplicate-0",
            "control-m0-t240-kstop-target1A-source=s1:B-id=s1:B-gp=i1-gs=i8-duplicate-0",
            "control-m1-t0-kstop-target1A-source=s1:Z-id=s1:Z-gp=i9-gs=i9-duplicate-0"
        ])
    }

    @Test("exact duplicate controls receive deterministic duplicate ordinals")
    func duplicateControlsReceiveStableOrdinals() {
        let duplicate = support.control(
            kind: .choke,
            sourceLaneID: "55",
            sourceNoteID: "0A",
            sourceGridPosition: 1,
            sourceGridSize: 4,
            normalizedMeasureIndex: 0,
            normalizedAbsoluteTick: 1,
            normalizedTickWithinMeasure: 1,
            normalizedTicksPerMeasure: 4,
            targetLaneID: "1A"
        )
        let first = support
            .layout(notes: [support.fallbackGridNote()], controls: [duplicate, duplicate]).stopNotes
        let second = support
            .layout(notes: [support.fallbackGridNote()], controls: [duplicate, duplicate]).stopNotes

        #expect(first == second)
        #expect(first.map(\.id) == [
            "control-m0-t240-kchoke-target1A-source=s2:55-id=s2:0A-gp=i1-gs=i4-duplicate-0",
            "control-m0-t240-kchoke-target1A-source=s2:55-id=s2:0A-gp=i1-gs=i4-duplicate-1"
        ])
    }

    @Test("control IDs canonically distinguish nil literals and embedded delimiters")
    func controlIDsUseCollisionFreeOptionalStringEncoding() {
        let events = [
            support.control(sourceLaneID: nil, sourceNoteID: "nil"),
            support.control(sourceLaneID: "nil", sourceNoteID: nil),
            support.control(sourceLaneID: "A-idB", sourceNoteID: "C"),
            support.control(sourceLaneID: "A", sourceNoteID: "B-idC")
        ]

        let ordered = support.layout(notes: [support.fallbackGridNote()], controls: events).stopNotes
        let shuffled = support
            .layout(notes: [support.fallbackGridNote()], controls: Array(events.reversed())).stopNotes

        #expect(ordered == shuffled)
        #expect(Set(ordered.map(\.id)).count == events.count)
        #expect(ordered.map(\.id) == [
            "control-m0-t0-kstop-target1A-source=n-id=s3:nil-gp=n-gs=n-duplicate-0",
            "control-m0-t0-kstop-target1A-source=s1:A-id=s5:B-idC-gp=n-gs=n-duplicate-0",
            "control-m0-t0-kstop-target1A-source=s5:A-idB-id=s1:C-gp=n-gs=n-duplicate-0",
            "control-m0-t0-kstop-target1A-source=s3:nil-id=n-gp=n-gs=n-duplicate-0"
        ])
    }

    @Test("only rendered open hi-hat heads produce articulation circles")
    func onlyOpenHiHatProducesArticulation() throws {
        let result = support.layout(notes: [
            Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .openHiHat, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0.5)
        ])
        let articulation = try #require(result.articulations.first)
        let openHead = try #require(result.noteHeads.first { $0.variant == .openHiHat })

        #expect(result.articulations.count == 1)
        #expect(articulation.kind == .openHiHat)
        #expect(articulation.sourceNoteHeadID == openHead.id)
        #expect(articulation.id == "openHiHat-head-\(openHead.id)")
        #expect(articulation.row == openHead.row)
        #expect(articulation.position.x == openHead.position.x)
        #expect(
            articulation.position.y
                == openHead.position.y - NotationLayoutStyle.gameplayDefault.articulationVerticalOffset
        )
    }

    @Test("hi-hat variants and stop semantics expose distinct accessibility labels")
    func renderedAccessibilityLabelsAreSemantic() throws {
        let result = support.layout(notes: [
            Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .openHiHat, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0.5)
        ], controls: [support.control(kind: .damp, measureOffset: 0.75, targetLaneID: "1A")])
        let labels = Set(result.noteHeads.map(\.accessibilityLabel))
        let stop = try #require(result.stopNotes.first)

        #expect(labels == ["Closed hi-hat", "Open hi-hat", "Pedal hi-hat"])
        #expect(stop.accessibilityLabel == "Damp Crash")
    }
}
