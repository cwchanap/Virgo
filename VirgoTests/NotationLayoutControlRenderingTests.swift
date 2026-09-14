import Testing
@testable import Virgo

/// Timeline control rendering through the measured preparation route
/// (HPA-164 Task 6). Legacy semantic-timing resolution (manual projection,
/// duplicate ordinals over the semantic tuple) was deleted with the fixed
/// grid: timeline controls arrive with exact resolved positions and unique
/// event IDs.
@Suite("Notation Layout Control Rendering Tests")
struct NotationLayoutControlRenderingTests {
    private let support = NotationLayoutTestSupport()

    @Test("stop choke and damp preserve semantics while sharing plus-mark geometry")
    func controlKindsShareGeometryWithoutCollapsingSemantics() {
        let controls = NotationControlEventKind.allCases.map {
            support.control(kind: $0, measureOffset: 0.25)
        }
        let result = support.layout(notes: [support.fallbackGridNote()], controls: controls)

        #expect(result.stopNotes.map(\.kind) == NotationControlEventKind.allCases)
        #expect(Set(result.stopNotes.map(\.position)).count == 1)
        #expect(Set(result.stopNotes.map(\.timeColumn)).count == 1)
        #expect(Set(result.stopNotes.map(\.id)).count == 3)
    }

    @Test("missing and unknown targets omit geometry")
    func unresolvedTargetsOmitGeometry() {
        let controls = [
            support.control(measureOffset: 0.25, targetLaneID: nil),
            support.control(measureOffset: 0.5, targetLaneID: "ZZ")
        ]
        let result = support.layout(notes: [], controls: controls)

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

    @Test("control and articulation painted bounds participate in the layout union")
    func controlAndArticulationBoundsAreUnioned() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let result = support.layout(
            notes: [Note(interval: .quarter, noteType: .openHiHat, measureNumber: 1, measureOffset: 0)],
            controls: [support.control(targetLaneID: "1A")],
            style: style
        )
        let stop = try #require(result.stopNotes.first)
        let articulation = try #require(result.articulations.first)

        #expect(result.paintedBounds.contains(stop.paintedBounds(style: style)))
        #expect(result.paintedBounds.contains(articulation.paintedBounds(style: style)))
    }
}
