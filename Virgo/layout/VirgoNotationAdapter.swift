import CoreGraphics
import DrumNotation

/// The primitive app-to-package mapping seam between Virgo's DTX/notation
/// domain and the `DrumNotation` package: noteheads, durations, stem
/// directions, and rest durations — one value in, one value out, no view
/// construction and no rendering. Style mapping and the snapshot→input
/// projection live in ``VirgoNotationProjection``; the preparation route
/// that drives both lives in `GameplayNotationPreparation` (HPA-166 Task 7).
///
/// The flag/stem-geometry helpers and `FlagPaintCommand` belonged to the
/// disconnected legacy `Rendered*` model and were deleted with it in Task 8 —
/// production rendering reads the package `EngravedNotation` instead.
enum VirgoNotationAdapter {
    static func noteheadStyle(for noteType: NoteType) -> PercussionNoteheadStyle {
        switch noteType {
        case .bass, .snare, .highTom, .midTom, .lowTom:
            return .normal
        case .hiHat, .hiHatPedal, .openHiHat, .crash, .ride, .china, .splash:
            return .x
        case .cowbell:
            return .diamond
        }
    }

    static func duration(for interval: NoteInterval) -> NotationDuration {
        switch interval {
        case .full:
            return .whole
        case .half:
            return .half
        case .quarter:
            return .quarter
        case .eighth:
            return .eighth
        case .sixteenth:
            return .sixteenth
        case .thirtysecond:
            return .thirtySecond
        case .sixtyfourth:
            return .sixtyFourth
        }
    }

    static func stemDirection(_ direction: StemDirection) -> NotationStemDirection {
        switch direction {
        case .up:
            return .up
        case .down:
            return .down
        }
    }

    static func restDuration(_ duration: NotationRestDuration) -> NotationDuration? {
        switch duration {
        case .fullMeasure:
            return .whole
        case .half:
            return .half
        case .quarter:
            return .quarter
        case .eighth:
            return .eighth
        case .sixteenth:
            return .sixteenth
        case .thirtySecond:
            return .thirtySecond
        case .sixtyFourth:
            return .sixtyFourth
        case .indeterminate:
            return nil
        }
    }
}
