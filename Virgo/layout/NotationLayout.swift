import CoreGraphics
import Foundation

struct NotationLayoutInput {
    let notes: [Note]
    let timeSignature: TimeSignature
    let minimumMeasureCount: Int
    let style: NotationLayoutStyle

    init(
        notes: [Note],
        timeSignature: TimeSignature,
        minimumMeasureCount: Int = 1,
        style: NotationLayoutStyle = .gameplayDefault
    ) {
        self.notes = notes
        self.timeSignature = timeSignature
        self.minimumMeasureCount = minimumMeasureCount
        self.style = style
    }
}

struct NotationLayoutStyle: Equatable {
    let minimumNoteColumnGap: CGFloat
    let minimumQuarterBeatGap: CGFloat
    let measurePadding: CGFloat
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
        measurePadding: 16,
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
    var measures: [RenderedMeasure]
    var noteHeads: [RenderedNoteHead]
    var stems: [RenderedStem]
    var beams: [RenderedBeam]
    var flags: [RenderedFlag]
    var ledgerLines: [RenderedLedgerLine]
    var measureBars: [RenderedMeasureBar]
    var beatLookup: [UInt64: CGPoint]
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
        measures: [],
        noteHeads: [],
        stems: [],
        beams: [],
        flags: [],
        ledgerLines: [],
        measureBars: [],
        beatLookup: [:],
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
