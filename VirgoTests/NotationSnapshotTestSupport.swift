import Foundation
import Testing
import DrumNotation
@testable import Virgo

/// Maps plain `Note`/`NotationControlEvent` specs onto timeline snapshots so
/// retained layout tests exercise the one measured preparation route
/// (HPA-164 Task 6). Notes quantize onto a canonical whole-note tick grid;
/// measure spans follow the time signature via `RhythmBeatGroupBuilder`.
///
/// The legacy `NotationLayoutInput(notes:)` engine route this replaces was
/// deleted: fixed-grid quantization, LCM folding, and beat-fraction mapping
/// no longer exist by design, so tests relying on those behaviors were
/// removed rather than ported.
struct NotationSnapshotTestSupport {
    let ticksPerWholeNote: Int
    let timeSignature: TimeSignature

    init(
        ticksPerWholeNote: Int = 960,
        timeSignature: TimeSignature = .fourFour
    ) {
        self.ticksPerWholeNote = ticksPerWholeNote
        self.timeSignature = timeSignature
    }

    /// Canonical whole-note ticks per measure under the suite's time signature.
    var measureDurationTicks: Int {
        ticksPerWholeNote * timeSignature.beatsPerMeasure / timeSignature.noteValue
    }

    func durationTicks(of interval: NoteInterval) -> Int {
        switch interval {
        case .full: return ticksPerWholeNote
        case .half: return ticksPerWholeNote / 2
        case .quarter: return ticksPerWholeNote / 4
        case .eighth: return ticksPerWholeNote / 8
        case .sixteenth: return ticksPerWholeNote / 16
        case .thirtysecond: return ticksPerWholeNote / 32
        case .sixtyfourth: return ticksPerWholeNote / 64
        }
    }

    /// Builds a snapshot covering every note/control measure plus any
    /// trailing measures implied by `minimumMeasureCount`.
    func snapshot(
        notes: [Note] = [],
        controls: [NotationControlEvent] = [],
        rests: [RhythmLayoutRest] = [],
        minimumMeasureCount: Int = 1
    ) throws -> RhythmLayoutSnapshot {
        // Deterministic event IDs: notes 1...n, controls 10001...
        let layoutNotes: [RhythmLayoutNote] = notes.enumerated().map { index, note in
            let position = position(forMeasureNumber: note.measureNumber, measureOffset: note.measureOffset)
            return RhythmLayoutNote(
                eventID: RhythmEventID(rawValue: index + 1),
                sourceLaneID: note.sourceLaneID,
                sourceChipID: note.sourceNoteID,
                noteType: note.noteType,
                position: position,
                durationTicks: durationTicks(of: note.interval),
                rhythm: NotationRhythm(baseInterval: note.interval),
                tupletID: nil
            )
        }
        let layoutControls = controls.enumerated().map { index, event -> RhythmLayoutControl in
            let position = position(forMeasureNumber: event.measureNumber, measureOffset: event.measureOffset)
            return RhythmLayoutControl(
                eventID: RhythmEventID(rawValue: 10_001 + index),
                event: event,
                position: position
            )
        }
        let maxNoteMeasure = layoutNotes.map(\.position.measureIndex).max() ?? 0
        let maxControlMeasure = layoutControls.map(\.position.measureIndex).max() ?? 0
        let maxRestMeasure = rests.map(\.position.measureIndex).max() ?? 0
        let measureCount = max(
            maximumMeasureCountCandidate(minimum: minimumMeasureCount),
            maxNoteMeasure + 1,
            maxControlMeasure + 1,
            maxRestMeasure + 1
        )
        let measures = (0..<measureCount).map { index -> RhythmMeasure in
            let durationTicks = measureDurationTicks
            return RhythmMeasure(
                measureIndex: index,
                startTick: index * durationTicks,
                durationTicks: durationTicks,
                timeSignature: timeSignature,
                beatGroups: RhythmBeatGroupBuilder.groups(
                    timeSignature: timeSignature,
                    durationTicks: durationTicks,
                    ticksPerWholeNote: ticksPerWholeNote
                ),
                engravingSupport: .supported
            )
        }
        return try RhythmLayoutSnapshot(
            ticksPerWholeNote: ticksPerWholeNote,
            measures: measures,
            notes: layoutNotes,
            controls: layoutControls,
            rests: rests,
            feel: .straight
        )
    }

    /// Runs the specs through the production preparation route — the same
    /// `GameplayNotationPreparer.prepare` the view model drives (HPA-166
    /// Task 7). Returns the closed prepared-state enum; `.ready` carries
    /// the `EngravedNotation` + app presentation.
    func prepare(
        notes: [Note] = [],
        controls: [NotationControlEvent] = [],
        rests: [RhythmLayoutRest] = [],
        minimumMeasureCount: Int = 1,
        style: NotationLayoutStyle = .gameplayDefault,
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition] = [:]
    ) -> GameplayNotationPreparedState {
        guard let request = try? makeRequest(
            notes: notes,
            controls: controls,
            rests: rests,
            minimumMeasureCount: minimumMeasureCount,
            style: style,
            notePositionOverrides: notePositionOverrides
        ) else {
            Issue.record("Snapshot construction failed for test notes")
            return .failed(GameplayNotationPreparationFailure(
                detail: "snapshot construction failed"
            ))
        }
        return GameplayNotationPreparer.prepare(request)
    }

    /// The engraving + presentation out of a `.ready` prepared state; fails
    /// the test on `.failed`.
    func requireReady(
        _ prepared: GameplayNotationPreparedState,
        _ comment: Comment? = nil
    ) throws -> (engraved: EngravedNotation, presentation: GameplayNotationPresentation) {
        guard case let .ready(engraved, presentation) = prepared else {
            Issue.record(comment ?? "Expected .ready, got \(prepared)")
            throw PreparationNotReady()
        }
        return (engraved, presentation)
    }

    /// The engraving out of a `.ready` prepared state.
    func requireEngraved(
        _ prepared: GameplayNotationPreparedState,
        _ comment: Comment? = nil
    ) throws -> EngravedNotation {
        try requireReady(prepared, comment).engraved
    }

    struct PreparationNotReady: Error {}

    /// Runs the same snapshot construction through the package engraving
    /// route (HPA-166 Task 6): `DrumTabFixtureHarness.engrave` is the single
    /// seam — expanded measures, `VirgoNotationProjection`,
    /// `NotationEngraver` — so synthetic snapshots engrave exactly like the
    /// real-DTX fixtures.
    func engrave(
        notes: [Note] = [],
        controls: [NotationControlEvent] = [],
        rests: [RhythmLayoutRest] = [],
        minimumMeasureCount: Int = 1,
        style: NotationLayoutStyle = .gameplayDefault,
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition] = [:]
    ) throws -> EngravedNotation {
        try DrumTabFixtureHarness.engrave(
            snapshot: snapshot(
                notes: notes,
                controls: controls,
                rests: rests,
                minimumMeasureCount: minimumMeasureCount
            ),
            minimumMeasureCount: minimumMeasureCount,
            style: style,
            notePositionOverrides: notePositionOverrides
        ).engraved
    }

    private func makeRequest(
        notes: [Note],
        controls: [NotationControlEvent],
        rests: [RhythmLayoutRest],
        minimumMeasureCount: Int,
        style: NotationLayoutStyle,
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
    ) throws -> GameplayNotationPreparationRequest {
        GameplayNotationPreparationRequest(
            snapshot: try snapshot(
                notes: notes,
                controls: controls,
                rests: rests,
                minimumMeasureCount: minimumMeasureCount
            ),
            minimumMeasureCount: minimumMeasureCount,
            style: style,
            notePositionOverrides: notePositionOverrides
        )
    }

    private func maximumMeasureCountCandidate(minimum: Int) -> Int {
        min(max(minimum, 1), GameplayNotationPreparer.maximumRenderableMeasureCount)
    }

    private func position(
        forMeasureNumber measureNumber: Int,
        measureOffset: Double
    ) -> RhythmEventPosition {
        let timePosition = MeasureUtils.timePosition(
            measureNumber: measureNumber,
            measureOffset: measureOffset
        )
        let measureIndex = MeasureUtils.measureIndex(from: timePosition)
        let offset = timePosition - Double(measureIndex)
        // The measure end is exclusive: an onset rounding up to
        // measureDurationTicks would land on the end anchor and fail the
        // downstream `localTick < durationTicks` guards, so clamp inside.
        let localTick = min(
            max(Int((offset * Double(measureDurationTicks)).rounded()), 0),
            measureDurationTicks - 1
        )
        return RhythmEventPosition(
            measureIndex: measureIndex,
            localTick: localTick,
            absoluteTick: measureIndex * measureDurationTicks + localTick
        )
    }
}
