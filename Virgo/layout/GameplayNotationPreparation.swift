import CoreGraphics

/// Immutable timeline inputs needed to prepare gameplay notation.
struct GameplayNotationPreparationRequest: Sendable {
    let snapshot: RhythmLayoutSnapshot
    let minimumMeasureCount: Int
    let style: NotationLayoutStyle
    let notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
}

/// Layout produced from one notation preparation request.
struct GameplayNotationPreparedState: Sendable {
    let layout: NotationLayout
}

/// Pure value boundary for timeline-native gameplay notation preparation.
/// Cancellation is best-effort resource cleanup only: the dominant work is
/// `NotationLayoutEngine.layout`, which has no cooperative cancellation
/// points, so an abandoned worker may still run to completion. Correctness
/// rests on the caller's generation checks — a stale result is discarded
/// regardless of whether the worker finished or was cancelled.
struct GameplayNotationPreparer {
    static func prepare(_ request: GameplayNotationPreparationRequest) -> GameplayNotationPreparedState {
        let input = NotationLayoutInput(
            timing: .timeline(request.snapshot),
            minimumMeasureCount: request.minimumMeasureCount,
            style: request.style,
            notePositionOverrides: request.notePositionOverrides
        )
        let layout = NotationLayoutEngine().layout(input: input)
        return GameplayNotationPreparedState(layout: layout)
    }
}
