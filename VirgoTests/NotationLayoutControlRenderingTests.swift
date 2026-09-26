import Testing
import CoreGraphics
import DrumNotation
@testable import Virgo

/// Timeline control rendering through the measured preparation route
/// (HPA-164 Task 6; package engraving since HPA-166 Task 7). Legacy
/// semantic-timing resolution (manual projection, duplicate ordinals over
/// the semantic tuple) was deleted with the fixed grid: timeline controls
/// arrive with exact resolved positions and unique event IDs. The engraving
/// carries only final geometry — control kind, column position and row —
/// while the localized labels live in `GameplayNotationPresentation`.
@Suite("Notation Layout Control Rendering Tests")
struct NotationLayoutControlRenderingTests {
    private let support = NotationLayoutTestSupport()

    @Test("stop choke and damp preserve semantics while sharing plus-mark geometry")
    func controlKindsShareGeometryWithoutCollapsingSemantics() throws {
        let controls = NotationControlEventKind.allCases.map {
            support.control(kind: $0, measureOffset: 0.25)
        }
        let engraved = try support.engraved(
            notes: [support.fallbackGridNote()],
            controls: controls
        )

        #expect(
            engraved.controls.map(\.kind.rawValue)
                == NotationControlEventKind.allCases.map(\.rawValue)
        )
        // All three controls share one onset: same column X and measure.
        #expect(Set(engraved.controls.map(\.position)).count == 1)
        #expect(Set(engraved.controls.map(\.measureIndex)).count == 1)
        // Identity is the resolved event ID — never collapsed by kind or place.
        #expect(Set(engraved.controls.map(\.controlID)).count == 3)
    }

    @Test("missing and unknown targets omit geometry")
    func unresolvedTargetsOmitGeometry() throws {
        let controls = [
            support.control(measureOffset: 0.25, targetLaneID: nil),
            support.control(measureOffset: 0.5, targetLaneID: "ZZ")
        ]
        let engraved = try support.engraved(
            notes: [support.fallbackGridNote()],
            controls: controls
        )

        #expect(engraved.controls.isEmpty)
    }

    @Test("lane 1A resolves to Crash and follows the active crash position override")
    func crashTargetUsesPositionOverride() throws {
        let (engraved, presentation) = try NotationSnapshotTestSupport().requireReady(
            NotationSnapshotTestSupport().prepare(
                notes: [support.fallbackGridNote()],
                controls: [support.control(measureOffset: 0.25, targetLaneID: "1a")],
                notePositionOverrides: [.crash: .line3]
            )
        )
        let control = try #require(engraved.controls.first)

        // The mark sits one `stopMarkVerticalOffset` above the resolved
        // target staff step's row Y. `.line3` is the middle staff line —
        // pitch-ascending step 4 — so its row Y is the row's staff center.
        let staffCenterY = engraved.rows[control.rowIndex].staffCenterY
        #expect(control.position.y == staffCenterY - engraved.style.stopMarkVerticalOffset)
        #expect(
            presentation.accessibilityLabels[.control(control.controlID)] == "Stop Crash"
        )
    }

    @Test("only rendered open hi-hat heads produce articulation circles")
    func onlyOpenHiHatProducesArticulation() throws {
        let engraved = try support.engraved(notes: [
            Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .openHiHat, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0.5)
        ])
        let articulation = try #require(engraved.articulations.first)
        let openHead = try #require(
            engraved.noteHeads.first { $0.noteID == articulation.noteID }
        )

        #expect(engraved.articulations.count == 1)
        #expect(articulation.kind == .open)
        #expect(articulation.position.x == openHead.position.x)
        #expect(
            articulation.position.y
                == openHead.position.y - engraved.style.articulationVerticalOffset
        )
    }

    @Test("hi-hat variants and stop semantics expose distinct accessibility labels")
    func renderedAccessibilityLabelsAreSemantic() throws {
        let (engraved, presentation) = try NotationSnapshotTestSupport().requireReady(
            NotationSnapshotTestSupport().prepare(
                notes: [
                    Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0),
                    Note(interval: .quarter, noteType: .openHiHat, measureNumber: 1, measureOffset: 0.25),
                    Note(interval: .quarter, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0.5)
                ],
                controls: [support.control(kind: .damp, measureOffset: 0.75, targetLaneID: "1A")]
            )
        )
        let labels = Set(engraved.noteHeads.compactMap {
            presentation.accessibilityLabels[.note($0.noteID)]
        })
        let control = try #require(engraved.controls.first)

        #expect(labels == ["Closed hi-hat", "Open hi-hat", "Pedal hi-hat"])
        #expect(presentation.accessibilityLabels[.control(control.controlID)] == "Damp Crash")
    }

    @Test("control and articulation painted bounds participate in the layout union")
    func controlAndArticulationBoundsAreUnioned() throws {
        let engraved = try support.engraved(
            notes: [Note(interval: .quarter, noteType: .openHiHat, measureNumber: 1, measureOffset: 0)],
            controls: [support.control(targetLaneID: "1A")]
        )
        let control = try #require(engraved.controls.first)
        let articulation = try #require(engraved.articulations.first)

        // The cross mark's ink: mark square plus stroke width around the mark
        // center — the same rect the engraver unions (see
        // `NotationEngraver+Descriptors.collectControls`).
        let markExtent = engraved.style.stopMarkSize + engraved.style.stopMarkStrokeWidth
        let controlBounds = CGRect(
            x: control.position.x - markExtent / 2,
            y: control.position.y - markExtent / 2,
            width: markExtent,
            height: markExtent
        )
        // Glyph metrics are origin-centered, so the painted rect is the raw
        // bounds offset to the articulation's center (the same convention the
        // engraver and `DrumNotationView` share).
        let artMetrics = PercussionGlyphMetrics.articulation(
            articulation.kind,
            staffSpace: engraved.style.formatting.staffSpace
        )
        let artBounds = artMetrics.paintedBounds.offsetBy(
            dx: articulation.position.x,
            dy: articulation.position.y
        )

        #expect(engraved.paintedBounds.contains(controlBounds))
        #expect(engraved.paintedBounds.contains(artBounds))
    }
}
