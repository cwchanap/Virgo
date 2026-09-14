import Testing
@testable import Virgo

/// Shared helpers for notation layout rest and control tests.
/// Kept reusable across the rest-focused and control-focused test files.
/// Layout runs through the measured preparation route (HPA-164 Task 6).
struct NotationLayoutTestSupport {
    func layout(
        notes: [Note],
        controls: [NotationControlEvent] = [],
        minimumMeasureCount: Int = 1,
        style: NotationLayoutStyle = .gameplayDefault,
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition] = [:]
    ) -> NotationLayout {
        NotationSnapshotTestSupport().prepare(
            notes: notes,
            controls: controls,
            minimumMeasureCount: minimumMeasureCount,
            style: style,
            notePositionOverrides: notePositionOverrides
        ).layout
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
}
