import CoreGraphics
import DrumNotation
import Foundation

struct NotationLayoutStyle: Equatable, Sendable {
    let minimumNoteColumnGap: CGFloat
    let minimumQuarterBeatGap: CGFloat
    let rowWidth: CGFloat
    let staffLineSpacing: CGFloat
    let noteHeadWidth: CGFloat
    let noteHeadHeight: CGFloat
    let stemLength: CGFloat
    let stemWidth: CGFloat
    let minimumStemExtensionPastChord: CGFloat
    let beamThickness: CGFloat
    let beamLevelSpacing: CGFloat
    let beamHookLength: CGFloat
    let ledgerLineOverhang: CGFloat
    let restSymbolWidth: CGFloat
    let restSymbolHeight: CGFloat
    let fullMeasureRestWidth: CGFloat
    let fullMeasureRestHeight: CGFloat
    let upperVoiceRestOffset: CGFloat
    let lowerVoiceRestOffset: CGFloat
    let stopMarkSize: CGFloat
    let stopMarkStrokeWidth: CGFloat
    let stopMarkVerticalOffset: CGFloat
    let articulationDiameter: CGFloat
    let articulationStrokeWidth: CGFloat
    let articulationVerticalOffset: CGFloat
    let rhythmDotRadius: CGFloat
    let rhythmDotSpacing: CGFloat
    let tupletLineWidth: CGFloat
    let tupletLabelSize: CGSize
    let tupletVerticalOffset: CGFloat
    let tupletHookLength: CGFloat
    let feelMarkSize: CGSize
    let feelMarkVerticalOffset: CGFloat
    let warningSize: CGSize
    let warningVerticalOffset: CGFloat

    var noteHeadSize: CGSize {
        CGSize(width: noteHeadWidth, height: noteHeadHeight)
    }

    static let gameplayDefault = NotationLayoutStyle(
        minimumNoteColumnGap: 28,
        minimumQuarterBeatGap: GameplayLayout.uniformSpacing,
        rowWidth: GameplayLayout.maxRowWidth,
        staffLineSpacing: GameplayLayout.staffLineSpacing,
        noteHeadWidth: GameplayLayout.beatColumnWidth,
        noteHeadHeight: GameplayLayout.drumSymbolFontSize,
        stemLength: GameplayLayout.stemHeight,
        stemWidth: GameplayLayout.stemWidth,
        minimumStemExtensionPastChord: GameplayLayout.staffLineSpacing / 2,
        beamThickness: 4,
        beamLevelSpacing: GameplayLayout.beamLevelSpacing,
        beamHookLength: 12,
        ledgerLineOverhang: 6,
        restSymbolWidth: 18,
        restSymbolHeight: 28,
        fullMeasureRestWidth: 18,
        fullMeasureRestHeight: 5,
        upperVoiceRestOffset: -GameplayLayout.staffLineSpacing,
        lowerVoiceRestOffset: GameplayLayout.staffLineSpacing,
        stopMarkSize: 14,
        stopMarkStrokeWidth: 2,
        stopMarkVerticalOffset: 18,
        articulationDiameter: 10,
        articulationStrokeWidth: 1.5,
        // pictOpen half (11.44) + noteheadXBlack half (10) + 2pt gap at staffSpace 20.
        articulationVerticalOffset: 24,
        rhythmDotRadius: 2.5,
        rhythmDotSpacing: 4,
        tupletLineWidth: 1.5,
        tupletLabelSize: CGSize(width: 14, height: 16),
        tupletVerticalOffset: 10,
        tupletHookLength: 6,
        feelMarkSize: CGSize(width: 72, height: 22),
        feelMarkVerticalOffset: 30,
        warningSize: CGSize(width: 180, height: 22),
        warningVerticalOffset: 56
    )

    func with(rowWidth newRowWidth: CGFloat) -> NotationLayoutStyle {
        NotationLayoutStyle(
            minimumNoteColumnGap: minimumNoteColumnGap,
            minimumQuarterBeatGap: minimumQuarterBeatGap,
            rowWidth: newRowWidth,
            staffLineSpacing: staffLineSpacing,
            noteHeadWidth: noteHeadWidth,
            noteHeadHeight: noteHeadHeight,
            stemLength: stemLength,
            stemWidth: stemWidth,
            minimumStemExtensionPastChord: minimumStemExtensionPastChord,
            beamThickness: beamThickness,
            beamLevelSpacing: beamLevelSpacing,
            beamHookLength: beamHookLength,
            ledgerLineOverhang: ledgerLineOverhang,
            restSymbolWidth: restSymbolWidth,
            restSymbolHeight: restSymbolHeight,
            fullMeasureRestWidth: fullMeasureRestWidth,
            fullMeasureRestHeight: fullMeasureRestHeight,
            upperVoiceRestOffset: upperVoiceRestOffset,
            lowerVoiceRestOffset: lowerVoiceRestOffset,
            stopMarkSize: stopMarkSize,
            stopMarkStrokeWidth: stopMarkStrokeWidth,
            stopMarkVerticalOffset: stopMarkVerticalOffset,
            articulationDiameter: articulationDiameter,
            articulationStrokeWidth: articulationStrokeWidth,
            articulationVerticalOffset: articulationVerticalOffset,
            rhythmDotRadius: rhythmDotRadius,
            rhythmDotSpacing: rhythmDotSpacing,
            tupletLineWidth: tupletLineWidth,
            tupletLabelSize: tupletLabelSize,
            tupletVerticalOffset: tupletVerticalOffset,
            tupletHookLength: tupletHookLength,
            feelMarkSize: feelMarkSize,
            feelMarkVerticalOffset: feelMarkVerticalOffset,
            warningSize: warningSize,
            warningVerticalOffset: warningVerticalOffset
        )
    }
}

struct NotationLayout: Sendable {
    var measures: [RenderedMeasure]
    var noteHeadSize: CGSize
    var noteHeads: [RenderedNoteHead]
    var rests: [RenderedRest] = []
    var stopNotes: [RenderedStopNote] = []
    var articulations: [RenderedArticulation] = []
    var stems: [RenderedStem]
    var beams: [RenderedBeam]
    var flags: [RenderedFlag]
    var ledgerLines: [RenderedLedgerLine]
    var measureBars: [RenderedMeasureBar]
    var rhythmDots: [RenderedRhythmDot] = []
    var tuplets: [RenderedTuplet] = []
    var feelMarks: [RenderedFeelMark] = []
    var rhythmWarnings: [RenderedRhythmWarning] = []
    var noteHeadPositionsByID: [UInt64: CGPoint]
    var noteHeadIDsByLayoutTick: [Int: Set<UInt64>]
    /// The measured formatter output this layout was composed from (HPA-164),
    /// installed for the live tick→X playhead lookup. Legacy compositions
    /// leave it empty.
    var formattedNotation: FormattedNotation = FormattedNotation(measures: [])
    var paintedBounds: CGRect = .null
    var totalHeight: CGFloat

    var hasPlayableContent: Bool { !noteHeads.isEmpty }

    var hasRenderableContent: Bool {
        hasPlayableContent
            || rests.contains(where: \.isPrinted)
            || !stopNotes.isEmpty
            || !feelMarks.isEmpty
            || !rhythmWarnings.isEmpty
    }

    /// Vertical translation needed to keep notation overlays inside the sheet's
    /// zero-based render bounds. Primitive coordinates remain staff-relative;
    /// the sheet applies this inset to the complete notation coordinate system.
    func topContentInset(style _: NotationLayoutStyle) -> CGFloat {
        guard !paintedBounds.isNull else { return 0 }
        return max(0, -paintedBounds.minY)
    }

    /// Minimum content width needed to contain all rendered primitives.
    var contentWidth: CGFloat {
        guard !paintedBounds.isNull else { return GameplayLayout.maxRowWidth }
        return max(GameplayLayout.maxRowWidth, paintedBounds.maxX + GameplayLayout.uniformSpacing)
    }

    static let empty = NotationLayout(
        measures: [],
        noteHeadSize: CGSize(
            width: NotationLayoutStyle.gameplayDefault.noteHeadWidth,
            height: NotationLayoutStyle.gameplayDefault.noteHeadHeight
        ),
        noteHeads: [],
        rests: [],
        stopNotes: [],
        articulations: [],
        stems: [],
        beams: [],
        flags: [],
        ledgerLines: [],
        measureBars: [],
        noteHeadPositionsByID: [:],
        noteHeadIDsByLayoutTick: [:],
        totalHeight: 0
    )
}

struct RenderedMeasure: Identifiable, Hashable, Sendable {
    let id: Int
    let measureIndex: Int
    let row: Int
    let xOffset: CGFloat
    let width: CGFloat
    let startTick: Int
    let durationTicks: Int

    init(
        id: Int,
        measureIndex: Int,
        row: Int,
        xOffset: CGFloat,
        width: CGFloat,
        startTick: Int = 0,
        durationTicks: Int = 0
    ) {
        self.id = id
        self.measureIndex = measureIndex
        self.row = row
        self.xOffset = xOffset
        self.width = width
        self.startTick = startTick
        self.durationTicks = durationTicks
    }
}

struct NotationTimeColumn: Hashable, Sendable {
    let measureIndex: Int
    let tickWithinMeasure: Int
    let absoluteLayoutTick: Int
}

/// Lookup key pairing a measure with an exact local tick; used to resolve
/// formatted column X for primitives (HPA-164).
struct MeasureTickKey: Hashable, Sendable {
    let measureIndex: Int
    let tick: Int
}

struct RenderedRest: Identifiable, Hashable, Sendable {
    let id: String
    let timeColumn: NotationTimeColumn
    let measureIndex: Int
    let row: Int
    let voice: NotationVoice
    let durationTicks: Int
    let duration: NotationRestDuration
    let visibility: NotationRestVisibility
    let position: CGPoint
    let rhythmPosition: RhythmEventPosition
    let rhythm: NotationRhythm
    let tupletID: RhythmTupletID?

    var isPrinted: Bool { visibility == .printed }

    var accessibilityLabel: String {
        "\(voice.accessibilityName) voice \(duration.accessibilityName) rest"
    }

    init(
        id: String,
        timeColumn: NotationTimeColumn,
        measureIndex: Int,
        row: Int,
        voice: NotationVoice,
        durationTicks: Int,
        duration: NotationRestDuration,
        visibility: NotationRestVisibility,
        position: CGPoint,
        rhythmPosition: RhythmEventPosition? = nil,
        rhythm: NotationRhythm? = nil,
        tupletID: RhythmTupletID? = nil
    ) {
        self.id = id
        self.timeColumn = timeColumn
        self.measureIndex = measureIndex
        self.row = row
        self.voice = voice
        self.durationTicks = durationTicks
        self.duration = duration
        self.visibility = visibility
        self.position = position
        self.rhythmPosition = rhythmPosition ?? RhythmEventPosition(
            measureIndex: timeColumn.measureIndex,
            localTick: timeColumn.tickWithinMeasure,
            absoluteTick: timeColumn.absoluteLayoutTick
        )
        self.rhythm = rhythm ?? duration.compatibilityRhythm
        self.tupletID = tupletID
    }
}

struct RenderedStopNote: Identifiable, Hashable, Sendable {
    let id: String
    let kind: NotationControlEventKind
    let sourceLaneID: String?
    let sourceNoteID: String?
    let targetLaneID: String
    let targetDisplayName: String
    let timeColumn: NotationTimeColumn
    let row: Int
    let position: CGPoint
    let eventID: RhythmEventID?
    let rhythmPosition: RhythmEventPosition

    var accessibilityLabel: String {
        "\(kind.rawValue.capitalized) \(targetDisplayName)"
    }

    init(
        id: String,
        kind: NotationControlEventKind,
        sourceLaneID: String?,
        sourceNoteID: String?,
        targetLaneID: String,
        targetDisplayName: String,
        timeColumn: NotationTimeColumn,
        row: Int,
        position: CGPoint,
        eventID: RhythmEventID? = nil,
        rhythmPosition: RhythmEventPosition? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sourceLaneID = sourceLaneID
        self.sourceNoteID = sourceNoteID
        self.targetLaneID = targetLaneID
        self.targetDisplayName = targetDisplayName
        self.timeColumn = timeColumn
        self.row = row
        self.position = position
        self.eventID = eventID
        self.rhythmPosition = rhythmPosition ?? RhythmEventPosition(
            measureIndex: timeColumn.measureIndex,
            localTick: timeColumn.tickWithinMeasure,
            absoluteTick: timeColumn.absoluteLayoutTick
        )
    }
}

enum RenderedArticulationKind: String, Hashable, Sendable {
    case openHiHat
}

struct RenderedArticulation: Identifiable, Hashable, Sendable {
    let id: String
    let kind: RenderedArticulationKind
    let sourceNoteHeadID: UInt64
    let row: Int
    let position: CGPoint
}

struct RenderedNoteHead: Identifiable, Hashable, Sendable {
    let id: UInt64
    let sourceLaneID: String?
    let sourceChipID: String?
    let noteType: NoteType
    let drumType: DrumType
    let variant: DrumNotationVariant
    let voice: NotationVoice
    let stemDirection: StemDirection
    let timeColumn: NotationTimeColumn
    let timePosition: Double
    let row: Int
    let position: CGPoint
    let staffStep: Int
    let interval: NoteInterval
    let catalogOrder: Int
    let eventID: RhythmEventID?
    let rhythmPosition: RhythmEventPosition
    let rhythmDurationTicks: Int?
    let rhythm: NotationRhythm
    let tupletID: RhythmTupletID?

    var measureIndex: Int { timeColumn.measureIndex }

    var accessibilityLabel: String {
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

    init(
        id: UInt64,
        sourceLaneID: String?,
        sourceChipID: String?,
        noteType: NoteType,
        drumType: DrumType,
        variant: DrumNotationVariant,
        voice: NotationVoice,
        stemDirection: StemDirection,
        timeColumn: NotationTimeColumn,
        timePosition: Double,
        row: Int,
        position: CGPoint,
        staffStep: Int,
        interval: NoteInterval,
        catalogOrder: Int,
        eventID: RhythmEventID? = nil,
        rhythmPosition: RhythmEventPosition? = nil,
        rhythmDurationTicks: Int? = nil,
        rhythm: NotationRhythm? = nil,
        tupletID: RhythmTupletID? = nil
    ) {
        self.id = id
        self.sourceLaneID = sourceLaneID
        self.sourceChipID = sourceChipID
        self.noteType = noteType
        self.drumType = drumType
        self.variant = variant
        self.voice = voice
        self.stemDirection = stemDirection
        self.timeColumn = timeColumn
        self.timePosition = timePosition
        self.row = row
        self.position = position
        self.staffStep = staffStep
        self.interval = interval
        self.catalogOrder = catalogOrder
        self.eventID = eventID
        self.rhythmPosition = rhythmPosition ?? RhythmEventPosition(
            measureIndex: timeColumn.measureIndex,
            localTick: timeColumn.tickWithinMeasure,
            absoluteTick: timeColumn.absoluteLayoutTick
        )
        self.rhythmDurationTicks = rhythmDurationTicks
        self.rhythm = rhythm ?? NotationRhythm(baseInterval: interval)
        self.tupletID = tupletID
    }
}

private extension NotationVoice {
    var accessibilityName: String {
        switch self {
        case .upper: return "Upper"
        case .lower: return "Lower"
        }
    }
}

private extension NotationRestDuration {
    var accessibilityName: String {
        switch self {
        case .fullMeasure: return "full-measure"
        case .half: return "half"
        case .quarter: return "quarter"
        case .eighth: return "eighth"
        case .sixteenth: return "sixteenth"
        case .thirtySecond: return "thirty-second"
        case .sixtyFourth: return "sixty-fourth"
        case .indeterminate: return "indeterminate"
        }
    }

    var compatibilityRhythm: NotationRhythm {
        switch self {
        case .fullMeasure: return NotationRhythm(baseInterval: .full)
        case .half: return NotationRhythm(baseInterval: .half)
        case .quarter: return NotationRhythm(baseInterval: .quarter)
        case .eighth: return NotationRhythm(baseInterval: .eighth)
        case .sixteenth: return NotationRhythm(baseInterval: .sixteenth)
        case .thirtySecond: return NotationRhythm(baseInterval: .thirtysecond)
        case .sixtyFourth: return NotationRhythm(baseInterval: .sixtyfourth)
        case .indeterminate:
            return NotationRhythm(
                baseInterval: .quarter,
                support: .indeterminate(.indeterminateTerminalDuration)
            )
        }
    }
}

struct RenderedStem: Identifiable, Hashable, Sendable {
    let id: String
    let noteHeadIDs: [UInt64]
    let direction: StemDirection
    let start: CGPoint
    let end: CGPoint
}

struct RenderedBeam: Identifiable, Hashable, Sendable {
    let id: String
    let noteHeadIDs: [UInt64]
    let direction: StemDirection
    let level: Int
    let kind: BeamSegmentKind
    let start: CGPoint
    let end: CGPoint
    let thickness: CGFloat
}

struct RenderedLedgerLine: Identifiable, Hashable, Sendable {
    let id: String
    let row: Int
    let start: CGPoint
    let end: CGPoint
}

struct RenderedFlag: Identifiable, Hashable, Sendable {
    let id: String
    let noteHeadID: UInt64
    let stemDirection: StemDirection
    let flagIndex: Int
    /// The flag glyph's SMuFL attachment point, not a view center: the stem's
    /// left edge at the level-0 stem tip (see
    /// `NotationLayoutEngine.flagStemOrigin`).
    let origin: CGPoint
}

struct RenderedMeasureBar: Identifiable, Hashable, Sendable {
    let id: String
    let row: Int
    let x: CGFloat
    let isFinal: Bool
}
