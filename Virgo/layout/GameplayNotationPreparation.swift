import CoreGraphics
import DrumNotation

/// Immutable timeline inputs needed to prepare gameplay notation.
struct GameplayNotationPreparationRequest: Sendable {
    let snapshot: RhythmLayoutSnapshot
    let minimumMeasureCount: Int
    let style: NotationLayoutStyle
    let notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
}

/// The closed result of one notation preparation (HPA-166 Task 7): either the
/// package engraving plus its app presentation, or the failure. No
/// both-nil/both-set states.
enum GameplayNotationPreparedState: Sendable {
    /// Engraving plus its app presentation — installed together.
    case ready(EngravedNotation, GameplayNotationPresentation)
    /// The engraving produced nothing printable (no heads, rests, controls,
    /// or annotations) — the sheet falls back to its furniture layer.
    case unavailable
    /// Engraving threw; the failure drives the practice-unavailable sheet.
    case failed(GameplayNotationPreparationFailure)
}

/// App-owned presentation the package must never see: the feel/warning
/// overlay annotations plus the VoiceOver labels `DrumNotationView` resolves
/// per `NotationSemanticID` at paint time.
struct GameplayNotationPresentation: Equatable, Sendable {
    let annotations: GameplayNotationAnnotations
    let accessibilityLabels: [NotationSemanticID: String]
}

/// One engraving failure surfaced to the app: `detail` is the log/test
/// description of the thrown error; `userMessage` is the practice-unavailable
/// copy shown on the existing fatal sheet.
struct GameplayNotationPreparationFailure: Error, Equatable, Sendable {
    let detail: String
    let userMessage: String

    init(
        detail: String,
        userMessage: String = String(localized: "This chart's notation could not be prepared.")
    ) {
        self.detail = detail
        self.userMessage = userMessage
    }
}

/// Pure value boundary for timeline-native gameplay notation preparation.
/// Cancellation is best-effort resource cleanup only: the dominant work is
/// notation engraving, which has no cooperative cancellation points, so an
/// abandoned worker may still run to completion. Correctness rests on the
/// caller's generation checks — a stale result is discarded regardless of
/// whether the worker finished or was cancelled.
///
/// The single preparation route (HPA-166 Task 7): both the detached initial
/// worker and the synchronous `refreshNotationEngraving()` relayout run
/// through ``prepare(_:)``, which expands trailing measures, projects the
/// snapshot through `VirgoNotationProjection.resolvedNotation`, maps the
/// style through `VirgoNotationProjection.engravingStyle`, and runs the
/// package `NotationEngraver`. The app presentation (feel/warning
/// annotations + VoiceOver labels) is built alongside the engraving and
/// never enters the package. There is no second style/geometry path.
enum GameplayNotationPreparer {
    /// Bound per-measure arrays, synthesized rests, and row geometry with the
    /// same chart-wide limit used by canonical rhythm validation.
    static let maximumRenderableMeasureCount = RhythmLimits.maximumMeasureCount

    static func prepare(_ request: GameplayNotationPreparationRequest) -> GameplayNotationPreparedState {
        // Trailing-measure expansion happens before package conversion so the
        // engraver sees the complete requested measure list.
        let expandedMeasures = expandedRhythmMeasures(
            request.snapshot,
            minimumMeasureCount: request.minimumMeasureCount
        )
        do {
            let input = try VirgoNotationProjection.resolvedNotation(
                snapshot: request.snapshot,
                expandedMeasures: expandedMeasures,
                notePositionOverrides: request.notePositionOverrides
            )
            let engraved = try NotationEngraver.engrave(
                input,
                style: VirgoNotationProjection.engravingStyle(for: request.style)
            )
            let presentation = GameplayNotationPresentation(
                annotations: .build(
                    feel: request.snapshot.feel,
                    expandedMeasures: expandedMeasures,
                    engraved: engraved,
                    style: request.style
                ),
                accessibilityLabels: accessibilityLabels(
                    snapshot: request.snapshot,
                    input: input,
                    engraved: engraved
                )
            )
            guard hasPrintableNotation(engraved, annotations: presentation.annotations) else {
                return .unavailable
            }
            return .ready(engraved, presentation)
        } catch {
            let failure = GameplayNotationPreparationFailure(detail: "\(error)")
            Logger.error("Notation engraving failed: \(failure.detail)")
            return .failed(failure)
        }
    }

    /// Mirrors the legacy `hasRenderableContent`: heads, printed rests,
    /// controls, or app annotations (feel mark / rhythm warnings) — the
    /// cases that made the notation sheet render instead of the legacy
    /// furniture fallback.
    private static func hasPrintableNotation(
        _ engraved: EngravedNotation,
        annotations: GameplayNotationAnnotations
    ) -> Bool {
        !engraved.noteHeads.isEmpty
            || !engraved.rests.isEmpty
            || !engraved.controls.isEmpty
            || !annotations.feelMarks.isEmpty
            || !annotations.rhythmWarnings.isEmpty
    }

    // MARK: - Measure expansion

    /// Appends synthesized trailing measures up to `minimumMeasureCount`,
    /// reusing the last snapshot measure's signature/support so the sheet's
    /// tail keeps the chart's meter.
    static func expandedRhythmMeasures(
        _ snapshot: RhythmLayoutSnapshot,
        minimumMeasureCount: Int
    ) -> [RhythmMeasure] {
        var measures = snapshot.measures.sorted { $0.measureIndex < $1.measureIndex }
        let requestedCount = min(
            max(minimumMeasureCount, measures.count, 1),
            maximumRenderableMeasureCount
        )
        guard let template = measures.last else { return [] }
        while measures.count < requestedCount {
            let measureIndex = measures.count
            let durationTicks = nominalDurationTicks(
                timeSignature: template.timeSignature,
                ticksPerWholeNote: snapshot.ticksPerWholeNote
            ) ?? template.durationTicks
            let startTick = measures.last?.endTick ?? 0
            measures.append(RhythmMeasure(
                measureIndex: measureIndex,
                startTick: startTick,
                durationTicks: durationTicks,
                timeSignature: template.timeSignature,
                beatGroups: RhythmBeatGroupBuilder.groups(
                    timeSignature: template.timeSignature,
                    durationTicks: durationTicks,
                    ticksPerWholeNote: snapshot.ticksPerWholeNote
                ),
                engravingSupport: template.engravingSupport
            ))
        }
        return measures
    }

    private static func nominalDurationTicks(
        timeSignature: TimeSignature,
        ticksPerWholeNote: Int
    ) -> Int? {
        let product = ticksPerWholeNote.multipliedReportingOverflow(by: timeSignature.beatsPerMeasure)
        guard !product.overflow,
              timeSignature.noteValue > 0,
              product.partialValue.isMultiple(of: timeSignature.noteValue) else { return nil }
        return product.partialValue / timeSignature.noteValue
    }

    // MARK: - VoiceOver labels

    /// The app's VoiceOver copy per collision-safe `NotationSemanticID` —
    /// built at preparation time so `DrumNotationView` only resolves strings.
    /// Localized/app strings never enter `ResolvedNotationInput` or
    /// `EngravedNotation`.
    private static func accessibilityLabels(
        snapshot: RhythmLayoutSnapshot,
        input: ResolvedNotationInput,
        engraved: EngravedNotation
    ) -> [NotationSemanticID: String] {
        var labels: [NotationSemanticID: String] = [:]
        let notesByEventID = Dictionary(
            uniqueKeysWithValues: snapshot.notes.map { ($0.eventID.rawValue, $0) }
        )
        for note in input.notes {
            guard let source = notesByEventID[note.id] else { continue }
            labels[.note(note.id)] = noteAccessibilityLabel(
                noteType: source.noteType,
                variant: DrumNotationCatalog.resolve(
                    noteType: source.noteType,
                    sourceLaneID: source.sourceLaneID
                )?.variant
            )
        }
        for rest in engraved.rests {
            labels[.rest(rest.restID)] = restAccessibilityLabel(
                voice: rest.voice,
                duration: rest.duration,
                isFullMeasure: rest.isFullMeasure
            )
        }
        let controlsByEventID = Dictionary(
            uniqueKeysWithValues: snapshot.controls.map { ($0.eventID.rawValue, $0) }
        )
        for control in engraved.controls {
            guard let source = controlsByEventID[control.controlID],
                  let targetLaneID = source.event.targetLaneID,
                  let target = DrumNotationCatalog.resolveTarget(laneID: targetLaneID)
            else { continue }
            labels[.control(control.controlID)]
                = "\(control.kind.rawValue.capitalized) \(target.displayName)"
        }
        for tuplet in engraved.tuplets {
            let voiceName = tuplet.voice == .upper
                ? String(localized: "Upper")
                : String(localized: "Lower")
            labels[.tuplet(tuplet.tupletID)] = String(
                localized: "\(voiceName) voice tuplet, \(tuplet.ratio.actual) in the time of \(tuplet.ratio.normal)"
            )
        }
        return labels
    }

    private static func noteAccessibilityLabel(
        noteType: NoteType,
        variant: DrumNotationVariant?
    ) -> String {
        switch variant {
        case .closedHiHat:
            return "Closed hi-hat"
        case .openHiHat:
            return "Open hi-hat"
        case .pedalHiHat:
            return "Pedal hi-hat"
        default:
            return noteType.rawValue
        }
    }

    private static func restAccessibilityLabel(
        voice: NotationVoiceRole,
        duration: NotationDuration,
        isFullMeasure: Bool
    ) -> String {
        let voiceName: String
        switch voice {
        case .upper: voiceName = "Upper"
        case .lower: voiceName = "Lower"
        }
        let durationName: String
        if isFullMeasure {
            durationName = "full-measure"
        } else {
            switch duration {
            case .whole: durationName = "whole"
            case .half: durationName = "half"
            case .quarter: durationName = "quarter"
            case .eighth: durationName = "eighth"
            case .sixteenth: durationName = "sixteenth"
            case .thirtySecond: durationName = "thirty-second"
            case .sixtyFourth: durationName = "sixty-fourth"
            }
        }
        return "\(voiceName) voice \(durationName) rest"
    }
}

/// One installed notation unit (HPA-166 Task 7): the package engraving plus
/// the app-owned presentation built alongside it. Installed atomically by
/// `GameplayViewModel.installPreparedNotation(_:generation:)`.
struct GameplayNotationInstall: Equatable, Sendable {
    let engraving: EngravedNotation
    let presentation: GameplayNotationPresentation
}
