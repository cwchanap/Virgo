import Testing
@testable import Virgo

/// Shared helpers for notation layout rest and control tests.
/// Kept reusable across the rest-focused and control-focused test files.
struct NotationLayoutTestSupport {
    func layout(
        notes: [Note],
        controls: [NotationControlEvent] = [],
        minimumMeasureCount: Int = 1,
        style: NotationLayoutStyle = .gameplayDefault,
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition] = [:]
    ) -> NotationLayout {
        NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                notes: notes,
                controlEvents: controls,
                timeSignature: .fourFour,
                minimumMeasureCount: minimumMeasureCount,
                style: style,
                notePositionOverrides: notePositionOverrides
            )
        )
    }

    func control(
        kind: NotationControlEventKind = .stop,
        measureNumber: Int = 1,
        measureOffset: Double = 0,
        originKind: NoteOriginKind = .manual,
        sourceLaneID: String? = nil,
        sourceNoteID: String? = nil,
        sourceGridPosition: Int? = nil,
        sourceGridSize: Int? = nil,
        normalizedMeasureIndex: Int? = nil,
        normalizedAbsoluteTick: Int? = nil,
        normalizedTickWithinMeasure: Int? = nil,
        normalizedTicksPerMeasure: Int? = nil,
        targetLaneID: String? = "1A"
    ) -> NotationControlEvent {
        NotationControlEvent(ChartControlEvent(
            kind: kind,
            measureNumber: measureNumber,
            measureOffset: measureOffset,
            originKind: originKind,
            sourceLaneID: sourceLaneID,
            sourceNoteID: sourceNoteID,
            sourceGridPosition: sourceGridPosition,
            sourceGridSize: sourceGridSize,
            normalizedMeasureIndex: normalizedMeasureIndex,
            normalizedAbsoluteTick: normalizedAbsoluteTick,
            normalizedTickWithinMeasure: normalizedTickWithinMeasure,
            normalizedTicksPerMeasure: normalizedTicksPerMeasure,
            targetLaneID: targetLaneID
        ))
    }

    func fallbackGridNote() -> Note {
        Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
    }

    /// Ten controls exercising every tie-breaker in `stopCandidateComesBefore`,
    /// so ordering and ID assertions stay stable regardless of input order.
    func stableSemanticTupleFixture() -> [NotationControlEvent] {
        let rows: [StableSemanticTupleRow] = [
            .init(kind: .stop, lane: "B", note: "B", gridPosition: 1, gridSize: 8,
                  measureIndex: 0, absoluteTick: 1, tick: 1, resolution: 4, target: "1A"),
            .init(kind: .stop, lane: "B", note: "B", gridPosition: 1, gridSize: 4,
                  measureIndex: 0, absoluteTick: 1, tick: 1, resolution: 4, target: "1A"),
            .init(kind: .stop, lane: "B", note: "B", gridPosition: 0, gridSize: 4,
                  measureIndex: 0, absoluteTick: 1, tick: 1, resolution: 4, target: "1A"),
            .init(kind: .stop, lane: "B", note: "A", gridPosition: 0, gridSize: 4,
                  measureIndex: 0, absoluteTick: 1, tick: 1, resolution: 4, target: "1A"),
            .init(kind: .stop, lane: "A", note: "A", gridPosition: 0, gridSize: 4,
                  measureIndex: 0, absoluteTick: 1, tick: 1, resolution: 4, target: "1A"),
            .init(kind: .stop, lane: "A", note: "A", gridPosition: 0, gridSize: 4,
                  measureIndex: 0, absoluteTick: 1, tick: 1, resolution: 4, target: "11"),
            .init(kind: .damp, lane: "A", note: "A", gridPosition: 0, gridSize: 4,
                  measureIndex: 0, absoluteTick: 1, tick: 1, resolution: 4, target: "11"),
            .init(kind: .choke, lane: "A", note: "A", gridPosition: 0, gridSize: 4,
                  measureIndex: 0, absoluteTick: 1, tick: 1, resolution: 4, target: "11"),
            .init(kind: .stop, lane: "Z", note: "Z", gridPosition: 9, gridSize: 9,
                  measureIndex: 0, absoluteTick: 0, tick: 0, resolution: 4, target: "1A"),
            .init(kind: .stop, lane: "Z", note: "Z", gridPosition: 9, gridSize: 9,
                  measureIndex: 1, absoluteTick: 4, tick: 0, resolution: 4, target: "1A")
        ]
        return rows.map { r in
            control(
                kind: r.kind,
                sourceLaneID: r.lane,
                sourceNoteID: r.note,
                sourceGridPosition: r.gridPosition,
                sourceGridSize: r.gridSize,
                normalizedMeasureIndex: r.measureIndex,
                normalizedAbsoluteTick: r.absoluteTick,
                normalizedTickWithinMeasure: r.tick,
                normalizedTicksPerMeasure: r.resolution,
                targetLaneID: r.target
            )
        }
    }
}

private struct StableSemanticTupleRow {
    let kind: NotationControlEventKind
    let lane: String
    let note: String
    let gridPosition: Int
    let gridSize: Int
    let measureIndex: Int
    let absoluteTick: Int
    let tick: Int
    let resolution: Int
    let target: String
}
