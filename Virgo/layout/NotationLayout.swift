import CoreGraphics
import Foundation

struct TabGrid: Equatable {
    static let fallbackTicksPerMeasure = 960

    let ticksPerMeasure: Int
    let tickWidth: CGFloat
    let leftPadding: CGFloat
    let measureWidth: CGFloat

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
            ticksPerMeasure: fallbackTicksPerMeasure,
            tickWidth: fallbackTickWidth,
            leftPadding: fallbackLeftPadding,
            measureWidth: measureWidth(
                ticksPerMeasure: fallbackTicksPerMeasure,
                tickWidth: fallbackTickWidth,
                leftPadding: fallbackLeftPadding
            )
        )
    }()

    func xPosition(in measure: RenderedMeasure, tickIndex: Int) -> CGFloat {
        let clampedTick = min(max(tickIndex, 0), ticksPerMeasure)
        return measure.xOffset + leftPadding + CGFloat(clampedTick) * tickWidth
    }

    func tickIndex(forBeatWithinMeasure beatWithinMeasure: Double, beatsPerMeasure: Int) -> Int {
        guard beatWithinMeasure.isFinite, beatsPerMeasure > 0 else { return 0 }
        let clampedBeat = min(max(beatWithinMeasure, 0), Double(beatsPerMeasure))
        return Int((clampedBeat / Double(beatsPerMeasure) * Double(ticksPerMeasure)).rounded())
    }
}

struct NotationLayoutInput {
    let notes: [Note]
    let controlEvents: [NotationControlEvent]
    let timeSignature: TimeSignature
    let minimumMeasureCount: Int
    let style: NotationLayoutStyle
    /// Per-drum overrides for the staff position used to render note heads, ledger lines, and stems.
    /// Drums omitted here fall back to `DrumType.notePosition`.
    let notePositionOverrides: [DrumType: GameplayLayout.NotePosition]

    init(
        notes: [Note],
        controlEvents: [NotationControlEvent] = [],
        timeSignature: TimeSignature,
        minimumMeasureCount: Int = 1,
        style: NotationLayoutStyle = .gameplayDefault,
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition] = [:]
    ) {
        self.notes = notes
        self.controlEvents = controlEvents
        self.timeSignature = timeSignature
        self.minimumMeasureCount = minimumMeasureCount
        self.style = style
        self.notePositionOverrides = notePositionOverrides
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

    var isPrinted: Bool { visibility == .printed }

    var accessibilityLabel: String {
        "\(voice.accessibilityName) voice \(duration.accessibilityName) rest"
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

    var accessibilityLabel: String {
        "\(kind.rawValue.capitalized) \(targetDisplayName)"
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
