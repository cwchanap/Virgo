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
/// both-nil/both-set states — and no "empty" third state: a printable-empty
/// engraving is a failure, while a genuinely notation-free flow (no track,
/// no timeline snapshot) clears the installation before preparation runs.
enum GameplayNotationPreparedState: Sendable {
    /// Engraving plus its app presentation — installed together.
    case ready(EngravedNotation, GameplayNotationPresentation)
    /// Engraving threw or produced nothing printable; the failure drives the
    /// practice-unavailable sheet.
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
                let failure = GameplayNotationPreparationFailure(
                    detail: "engraving produced no printable notation "
                        + "(no heads, rests, controls, or annotations)"
                )
                Logger.error("Notation engraving produced no printable notation")
                return .failed(failure)
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
            let kindName = controlKindAccessibilityName(control.kind)
            let targetName = noteTypeAccessibilityName(target.definition.noteType)
            labels[.control(control.controlID)]
                = String(localized: "\(kindName) \(targetName)")
        }
        for tuplet in engraved.tuplets {
            let voiceName = voiceAccessibilityName(tuplet.voice)
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
            return String(localized: "Closed hi-hat")
        case .openHiHat:
            return String(localized: "Open hi-hat")
        case .pedalHiHat:
            return String(localized: "Pedal hi-hat")
        default:
            return noteTypeAccessibilityName(noteType)
        }
    }

    // swiftlint:disable cyclomatic_complexity
    /// The spoken instrument name for one `NoteType` — every case is an
    /// explicit localized string so VoiceOver copy never falls through to a
    /// raw `rawValue`.
    private static func noteTypeAccessibilityName(_ noteType: NoteType) -> String {
        switch noteType {
        case .bass: return String(localized: "Bass")
        case .snare: return String(localized: "Snare")
        case .highTom: return String(localized: "High Tom")
        case .midTom: return String(localized: "Mid Tom")
        case .lowTom: return String(localized: "Low Tom")
        case .hiHat: return String(localized: "Hi-Hat")
        case .hiHatPedal: return String(localized: "Hi-Hat Pedal")
        case .openHiHat: return String(localized: "Open Hi-Hat")
        case .crash: return String(localized: "Crash")
        case .ride: return String(localized: "Ride")
        case .china: return String(localized: "China")
        case .splash: return String(localized: "Splash")
        case .cowbell: return String(localized: "Cowbell")
        }
    }
    // swiftlint:enable cyclomatic_complexity

    /// The spoken mark name for one control kind — explicit localized cases
    /// instead of a capitalized `rawValue`.
    private static func controlKindAccessibilityName(_ kind: NotationControlKind) -> String {
        switch kind {
        case .stop: return String(localized: "Stop")
        case .choke: return String(localized: "Choke")
        case .damp: return String(localized: "Damp")
        }
    }

    /// The spoken staff-voice name shared by rest and tuplet labels.
    private static func voiceAccessibilityName(_ voice: NotationVoiceRole) -> String {
        switch voice {
        case .upper: return String(localized: "Upper")
        case .lower: return String(localized: "Lower")
        }
    }

    /// The spoken duration name for one printed rest — the full-measure
    /// wording is its own case rather than a duration lookup.
    private static func restDurationAccessibilityName(
        _ duration: NotationDuration,
        isFullMeasure: Bool
    ) -> String {
        if isFullMeasure {
            return String(localized: "full-measure")
        }
        switch duration {
        case .whole: return String(localized: "whole")
        case .half: return String(localized: "half")
        case .quarter: return String(localized: "quarter")
        case .eighth: return String(localized: "eighth")
        case .sixteenth: return String(localized: "sixteenth")
        case .thirtySecond: return String(localized: "thirty-second")
        case .sixtyFourth: return String(localized: "sixty-fourth")
        }
    }

    private static func restAccessibilityLabel(
        voice: NotationVoiceRole,
        duration: NotationDuration,
        isFullMeasure: Bool
    ) -> String {
        let voiceName = voiceAccessibilityName(voice)
        let durationName = restDurationAccessibilityName(duration, isFullMeasure: isFullMeasure)
        return String(localized: "\(voiceName) voice \(durationName) rest")
    }
}

/// One installed notation unit (HPA-166 Task 7): the package engraving plus
/// the app-owned presentation built alongside it. Installed atomically by
/// `GameplayViewModel.installPreparedNotation(_:generation:)`.
struct GameplayNotationInstall: Equatable, Sendable {
    let engraving: EngravedNotation
    let presentation: GameplayNotationPresentation
}
