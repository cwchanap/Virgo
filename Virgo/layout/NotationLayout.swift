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

    static let fallback = TabGrid(
        ticksPerMeasure: fallbackTicksPerMeasure,
        tickWidth: GameplayLayout.uniformSpacing / CGFloat(fallbackTicksPerMeasure / 4),
        leftPadding: GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing,
        measureWidth: measureWidth(
            ticksPerMeasure: fallbackTicksPerMeasure,
            tickWidth: GameplayLayout.uniformSpacing / CGFloat(fallbackTicksPerMeasure / 4),
            leftPadding: GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing
        )
    )

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
    let timeSignature: TimeSignature
    let minimumMeasureCount: Int
    let style: NotationLayoutStyle
    /// Per-drum overrides for the staff position used to render note heads, ledger lines, and stems.
    /// Drums omitted here fall back to `DrumType.notePosition`.
    let notePositionOverrides: [DrumType: GameplayLayout.NotePosition]

    init(
        notes: [Note],
        timeSignature: TimeSignature,
        minimumMeasureCount: Int = 1,
        style: NotationLayoutStyle = .gameplayDefault,
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition] = [:]
    ) {
        self.notes = notes
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
    let stemXInset: CGFloat
    let beamThickness: CGFloat
    let beamLevelSpacing: CGFloat
    let ledgerLineOverhang: CGFloat
    let voiceCollisionOffset: CGFloat

    static let gameplayDefault = NotationLayoutStyle(
        minimumNoteColumnGap: 28,
        minimumQuarterBeatGap: GameplayLayout.uniformSpacing,
        rowWidth: GameplayLayout.maxRowWidth,
        staffLineSpacing: GameplayLayout.staffLineSpacing,
        noteHeadWidth: GameplayLayout.beatColumnWidth,
        noteHeadHeight: GameplayLayout.drumSymbolFontSize,
        stemLength: GameplayLayout.stemHeight,
        stemWidth: GameplayLayout.stemWidth,
        stemXInset: GameplayLayout.stemXOffset,
        beamThickness: 4,
        beamLevelSpacing: GameplayLayout.beamLevelSpacing,
        ledgerLineOverhang: 6,
        voiceCollisionOffset: 8
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
            stemXInset: stemXInset,
            beamThickness: beamThickness,
            beamLevelSpacing: beamLevelSpacing,
            ledgerLineOverhang: ledgerLineOverhang,
            voiceCollisionOffset: voiceCollisionOffset
        )
    }
}

enum NotationVoice: String, Hashable {
    case upper
    case lower

    static func voice(for drumType: DrumType) -> NotationVoice {
        switch drumType {
        case .kick, .hiHatPedal:
            return .lower
        case .crash, .hiHat, .tom1, .snare, .tom2, .tom3, .ride, .cowbell:
            return .upper
        }
    }
}

enum StemDirection: String, Hashable {
    case up
    case down
}

struct NotationLayout {
    var tabGrid: TabGrid
    var measures: [RenderedMeasure]
    var noteHeads: [RenderedNoteHead]
    var stems: [RenderedStem]
    var beams: [RenderedBeam]
    var flags: [RenderedFlag]
    var ledgerLines: [RenderedLedgerLine]
    var measureBars: [RenderedMeasureBar]
    var noteHeadPositionsByID: [UInt64: CGPoint]
    var noteHeadIDsByTimePosition: [Int: Set<UInt64>]
    var totalHeight: CGFloat

    static func timePositionKey(_ timePosition: Double) -> Int {
        Int((timePosition * 1_000_000).rounded())
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
        noteHeads: [],
        stems: [],
        beams: [],
        flags: [],
        ledgerLines: [],
        measureBars: [],
        noteHeadPositionsByID: [:],
        noteHeadIDsByTimePosition: [:],
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

struct RenderedNoteHead: Identifiable, Hashable {
    let id: UInt64
    let sourceNoteID: ObjectIdentifier
    let drumType: DrumType
    let voice: NotationVoice
    let timePosition: Double
    let measureIndex: Int
    let row: Int
    let position: CGPoint
    let staffStep: Int
    let stemDirection: StemDirection
    let interval: NoteInterval
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
