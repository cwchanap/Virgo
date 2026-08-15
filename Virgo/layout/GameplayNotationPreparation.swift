import CoreGraphics

/// Immutable timeline inputs needed to prepare gameplay notation.
struct GameplayNotationPreparationRequest: Sendable {
    let snapshot: RhythmLayoutSnapshot
    let minimumMeasureCount: Int
    let style: NotationLayoutStyle
    let notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
    let beatPositionsByID: [UInt64: RhythmEventPosition]
}

/// Layout and beat coordinates produced from one notation preparation request.
struct GameplayNotationPreparedState: Sendable {
    let layout: NotationLayout
    let beatPositionsByID: [UInt64: CGPoint]
}

/// Pure value boundary for timeline-native gameplay notation preparation.
/// Cancellation is cooperative: an abandoned worker bails out early and its
/// result is discarded by the caller's cancellation/generation guards.
struct GameplayNotationPreparer {
    static func prepare(_ request: GameplayNotationPreparationRequest) -> GameplayNotationPreparedState {
        let input = NotationLayoutInput(
            timing: .timeline(request.snapshot),
            minimumMeasureCount: request.minimumMeasureCount,
            style: request.style,
            notePositionOverrides: request.notePositionOverrides
        )
        let layout = NotationLayoutEngine().layout(input: input)
        let measuresByIndex = Dictionary(
            uniqueKeysWithValues: layout.measures.map { ($0.measureIndex, $0) }
        )
        var beatPositions: [UInt64: CGPoint] = [:]
        for (beatID, position) in request.beatPositionsByID {
            guard !Task.isCancelled else { break }
            guard let measure = measuresByIndex[position.measureIndex] else { continue }
            beatPositions[beatID] = CGPoint(
                x: layout.tabGrid.xPosition(in: measure, localTick: position.localTick),
                y: GameplayLayout.StaffLinePosition.line3.absoluteY(for: measure.row)
            )
        }
        return GameplayNotationPreparedState(layout: layout, beatPositionsByID: beatPositions)
    }
}
