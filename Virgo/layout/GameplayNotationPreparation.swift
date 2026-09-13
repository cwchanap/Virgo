import CoreGraphics
import DrumNotation

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
    /// The measured formatter output produced on the one preparation route
    /// (HPA-164). Task 5 composes gameplay geometry from it.
    var formatted: FormattedNotation = FormattedNotation(measures: [])

    init(layout: NotationLayout, formatted: FormattedNotation = FormattedNotation(measures: [])) {
        self.layout = layout
        self.formatted = formatted
    }
}

/// Pure value boundary for timeline-native gameplay notation preparation.
/// Cancellation is best-effort resource cleanup only: the dominant work is
/// notation layout, which has no cooperative cancellation points, so an
/// abandoned worker may still run to completion. Correctness rests on the
/// caller's generation checks — a stale result is discarded regardless of
/// whether the worker finished or was cancelled.
///
/// The single preparation route (HPA-164 Task 4): both the detached initial
/// worker and the synchronous `cacheNotationLayout()` relayout run through
/// ``prepare(_:)``, which projects the snapshot through
/// `VirgoNotationAdapter.resolvedNotation`, maps the style through
/// `VirgoNotationAdapter.formattingStyle`, runs the measured
/// `NotationFormatter`, and composes the rendered layout. There is no second
/// style/formatting path.
struct GameplayNotationPreparer {
    static func prepare(_ request: GameplayNotationPreparationRequest) -> GameplayNotationPreparedState {
        // Trailing-measure expansion happens before package conversion so the
        // formatter sees the complete requested measure list.
        let expandedMeasures = NotationLayoutEngine().expandedRhythmMeasures(
            request.snapshot,
            minimumMeasureCount: request.minimumMeasureCount
        )
        do {
            let input = try VirgoNotationAdapter.resolvedNotation(
                snapshot: request.snapshot,
                expandedMeasures: expandedMeasures,
                notePositionOverrides: request.notePositionOverrides
            )
            let style = VirgoNotationAdapter.formattingStyle(
                rowWidth: request.style.rowWidth,
                style: request.style
            )
            let formatted = try NotationFormatter.format(input, style: style)
            return GameplayNotationPreparedState(
                layout: composeVirgoLayout(
                    snapshot: request.snapshot,
                    formatted: formatted,
                    request: request
                ),
                formatted: formatted
            )
        } catch {
            Logger.error("Measured notation preparation failed: \(error)")
            return GameplayNotationPreparedState(layout: .empty)
        }
    }

    /// HPA-164 Task 4 transitional composition: the measured formatter runs on
    /// the route and its output rides through this signature, but the rendered
    /// layout still comes from the existing snapshot composition with the old
    /// X sources. HPA-164 Task 5 replaces these internals with package
    /// geometry copied straight from `formatted`.
    private static func composeVirgoLayout(
        snapshot: RhythmLayoutSnapshot,
        formatted: FormattedNotation,
        request: GameplayNotationPreparationRequest
    ) -> NotationLayout {
        let input = NotationLayoutInput(
            timing: .timeline(snapshot),
            minimumMeasureCount: request.minimumMeasureCount,
            style: request.style,
            notePositionOverrides: request.notePositionOverrides
        )
        return NotationLayoutEngine().layout(input: input)
    }
}
