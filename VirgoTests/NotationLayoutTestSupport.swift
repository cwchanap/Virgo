import Testing
import DrumNotation
@testable import Virgo

/// Shared helpers for notation engraving rest and control tests.
/// Kept reusable across the rest-focused and control-focused test files.
/// Geometry runs through the one preparation route ending in
/// `NotationEngraver.engrave` (HPA-166 Task 7).
struct NotationLayoutTestSupport {
    /// The `.ready` engraving for the given specs; test-failing on `.failed`.
    func engraved(
        notes: [Note],
        controls: [NotationControlEvent] = [],
        rests: [RhythmLayoutRest] = [],
        minimumMeasureCount: Int = 1,
        style: NotationLayoutStyle = .gameplayDefault,
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition] = [:]
    ) throws -> EngravedNotation {
        try NotationSnapshotTestSupport().requireEngraved(NotationSnapshotTestSupport().prepare(
            notes: notes,
            controls: controls,
            rests: rests,
            minimumMeasureCount: minimumMeasureCount,
            style: style,
            notePositionOverrides: notePositionOverrides
        ))
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
