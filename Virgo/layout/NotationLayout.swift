import CoreGraphics
import Foundation

struct TabGrid: Equatable {
    static let fallbackTicksPerMeasure = 960

    let ticksPerWholeNote: Int
    let tickWidth: CGFloat
    let leftPadding: CGFloat
    private let legacyTicksPerMeasure: Int?

    /// Fixed-measure compatibility wrapper. Timeline layout uses each
    /// `RenderedMeasure.durationTicks` instead.
    var ticksPerMeasure: Int { legacyTicksPerMeasure ?? ticksPerWholeNote }

    /// Fixed-measure compatibility wrapper. Timeline measures own their width.
    var measureWidth: CGFloat {
        Self.measureWidth(
            ticksPerMeasure: ticksPerMeasure,
            tickWidth: tickWidth,
            leftPadding: leftPadding
        )
    }

    init(
        ticksPerWholeNote: Int,
        tickWidth: CGFloat,
        leftPadding: CGFloat
    ) {
        self.ticksPerWholeNote = ticksPerWholeNote
        self.tickWidth = tickWidth
        self.leftPadding = leftPadding
        legacyTicksPerMeasure = nil
    }

    init(
        legacyTicksPerMeasure: Int,
        ticksPerWholeNote: Int? = nil,
        tickWidth: CGFloat,
        leftPadding: CGFloat
    ) {
        self.ticksPerWholeNote = ticksPerWholeNote ?? legacyTicksPerMeasure
        self.tickWidth = tickWidth
        self.leftPadding = leftPadding
        self.legacyTicksPerMeasure = legacyTicksPerMeasure
    }

    static func measureWidth(
        ticksPerMeasure: Int,
        tickWidth: CGFloat,
        leftPadding: CGFloat
    ) -> CGFloat {
        leftPadding + CGFloat(ticksPerMeasure) * tickWidth
    }

    static let fallback: TabGrid = {
        let fallbackTickWidth = GameplayLayout.uniformSpacing / CGFloat(fallbackTicksPerMeasure / 4)
        let fallbackLeftPadding = GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing
        return TabGrid(
            legacyTicksPerMeasure: fallbackTicksPerMeasure,
            tickWidth: fallbackTickWidth,
            leftPadding: fallbackLeftPadding
        )
    }()

    func xPosition(in measure: RenderedMeasure, localTick: Int) -> CGFloat {
        let clampedTick = min(max(localTick, 0), measure.durationTicks)
        return measure.contentStartX + CGFloat(clampedTick) * tickWidth
    }

    /// Fixed-measure compatibility wrapper. Timeline callers pass `localTick`.
    func xPosition(in measure: RenderedMeasure, tickIndex: Int) -> CGFloat {
        let clampedTick = min(max(tickIndex, 0), ticksPerMeasure)
        return measure.contentStartX + CGFloat(clampedTick) * tickWidth
    }

    /// Fixed-measure compatibility wrapper for legacy beat fractions.
    func tickIndex(forBeatWithinMeasure beatWithinMeasure: Double, beatsPerMeasure: Int) -> Int {
        guard beatWithinMeasure.isFinite, beatsPerMeasure > 0 else { return 0 }
        let clampedBeat = min(max(beatWithinMeasure, 0), Double(beatsPerMeasure))
        return Int((clampedBeat / Double(beatsPerMeasure) * Double(ticksPerMeasure)).rounded())
    }
}

enum NotationLayoutTimingInput {
    case timeline(RhythmLayoutSnapshot)
    case legacy(notes: [Note], controls: [NotationControlEvent], timeSignature: TimeSignature)
}

struct NotationLayoutInput {
    let timing: NotationLayoutTimingInput
    let minimumMeasureCount: Int
    let style: NotationLayoutStyle
    /// Per-drum overrides for the staff position used to render note heads, ledger lines, and stems.
    /// Drums omitted here fall back to `DrumType.notePosition`.
    let notePositionOverrides: [DrumType: GameplayLayout.NotePosition]

    var notes: [Note] {
        guard case let .legacy(notes, _, _) = timing else { return [] }
        return notes
    }

    var controlEvents: [NotationControlEvent] {
        guard case let .legacy(_, controls, _) = timing else { return [] }
        return controls
    }

    var timeSignature: TimeSignature {
        switch timing {
        case let .timeline(snapshot):
            return snapshot.measures.first?.timeSignature ?? .fourFour
        case let .legacy(_, _, timeSignature):
            return timeSignature
        }
    }

    init(
        timing: NotationLayoutTimingInput,
        minimumMeasureCount: Int = 1,
        style: NotationLayoutStyle = .gameplayDefault,
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition] = [:]
    ) {
        self.timing = timing
        self.minimumMeasureCount = minimumMeasureCount
        self.style = style
        self.notePositionOverrides = notePositionOverrides
    }

    init(
        notes: [Note],
        controlEvents: [NotationControlEvent] = [],
        timeSignature: TimeSignature,
        minimumMeasureCount: Int = 1,
        style: NotationLayoutStyle = .gameplayDefault,
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition] = [:]
    ) {
        self.init(
            timing: .legacy(notes: notes, controls: controlEvents, timeSignature: timeSignature),
            minimumMeasureCount: minimumMeasureCount,
            style: style,
            notePositionOverrides: notePositionOverrides
        )
    }
}

struct NotationLayoutStyle: Equatable {
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
        articulationVerticalOffset: 18
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
            articulationVerticalOffset: articulationVerticalOffset
        )
    }
}

struct NotationLayout {
    var tabGrid: TabGrid
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
    var noteHeadPositionsByID: [UInt64: CGPoint]
    var noteHeadIDsByLayoutTick: [Int: Set<UInt64>]
    var totalHeight: CGFloat

    var hasPlayableContent: Bool { !noteHeads.isEmpty }

    var hasRenderableContent: Bool {
        hasPlayableContent || rests.contains(where: \.isPrinted) || !stopNotes.isEmpty
    }

    /// Vertical translation needed to keep notation overlays inside the sheet's
    /// zero-based render bounds. Primitive coordinates remain staff-relative;
    /// the sheet applies this inset to the complete notation coordinate system.
    func topContentInset(style: NotationLayoutStyle) -> CGFloat {
        let minimumArticulationY = articulations
            .map {
                $0.position.y
                    - style.articulationDiameter / 2
                    - style.articulationStrokeWidth / 2
            }
            .min() ?? 0
        let minimumStopY = stopNotes
            .map {
                $0.position.y
                    - style.stopMarkSize / 2
                    - style.stopMarkStrokeWidth / 2
            }
            .min() ?? 0
        return max(0, -min(minimumArticulationY, minimumStopY))
    }

    /// Minimum content width needed to contain all rendered primitives.
    var contentWidth: CGFloat {
        let primitiveMaxX = [
            noteHeads.map(\.position.x),
            measureBars.map(\.x),
            beams.flatMap { [$0.start.x, $0.end.x] },
            ledgerLines.flatMap { [$0.start.x, $0.end.x] },
            stems.flatMap { [$0.start.x, $0.end.x] }
        ]
        .flatMap { $0 }
        .max()

        guard let maxX = primitiveMaxX else {
            return GameplayLayout.maxRowWidth
        }

        return max(GameplayLayout.maxRowWidth, maxX + GameplayLayout.uniformSpacing)
    }

    static let empty = NotationLayout(
        tabGrid: .fallback,
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

struct RenderedMeasure: Identifiable, Hashable {
    let id: Int
    let measureIndex: Int
    let row: Int
    let xOffset: CGFloat
    let width: CGFloat
    let startTick: Int
    let durationTicks: Int

    var contentStartX: CGFloat { xOffset + GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing }

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

struct NotationTimeColumn: Hashable {
    let measureIndex: Int
    let tickWithinMeasure: Int
    let absoluteLayoutTick: Int
}

struct RenderedRest: Identifiable, Hashable {
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

struct RenderedStopNote: Identifiable, Hashable {
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

enum RenderedArticulationKind: String, Hashable {
    case openHiHat
}

struct RenderedArticulation: Identifiable, Hashable {
    let id: String
    let kind: RenderedArticulationKind
    let sourceNoteHeadID: UInt64
    let row: Int
    let position: CGPoint
}

struct RenderedNoteHead: Identifiable, Hashable {
    let id: UInt64
    let sourceObjectID: ObjectIdentifier
    let sourceLaneID: String?
    let sourceChipID: String?
    let noteType: NoteType
    let drumType: DrumType
    let glyph: DrumNoteheadGlyph
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
        sourceObjectID: ObjectIdentifier,
        sourceLaneID: String?,
        sourceChipID: String?,
        noteType: NoteType,
        drumType: DrumType,
        glyph: DrumNoteheadGlyph,
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
        self.sourceObjectID = sourceObjectID
        self.sourceLaneID = sourceLaneID
        self.sourceChipID = sourceChipID
        self.noteType = noteType
        self.drumType = drumType
        self.glyph = glyph
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

struct RenderedStem: Identifiable, Hashable {
    let id: String
    let noteHeadIDs: [UInt64]
    let direction: StemDirection
    let start: CGPoint
    let end: CGPoint
}

struct RenderedBeam: Identifiable, Hashable {
    let id: String
    let noteHeadIDs: [UInt64]
    let direction: StemDirection
    let level: Int
    let kind: BeamSegmentKind
    let start: CGPoint
    let end: CGPoint
    let thickness: CGFloat
}

struct RenderedLedgerLine: Identifiable, Hashable {
    let id: String
    let row: Int
    let start: CGPoint
    let end: CGPoint
}

struct RenderedFlag: Identifiable, Hashable {
    let id: String
    let noteHeadID: UInt64
    let stemDirection: StemDirection
    let flagIndex: Int
    let origin: CGPoint
}

struct RenderedMeasureBar: Identifiable, Hashable {
    let id: String
    let row: Int
    let x: CGFloat
    let isFinal: Bool
}
