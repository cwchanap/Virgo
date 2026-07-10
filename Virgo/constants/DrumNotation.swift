import CoreGraphics

enum NotationVoice: String, Hashable {
    case upper
    case lower

    static func voice(for drumType: DrumType) -> NotationVoice {
        DrumNotationCatalog.defaultDefinition(for: drumType)?.voice ?? .upper
    }
}

enum StemDirection: String, Hashable {
    case up
    case down
}

enum DrumNotationVariant: String, Hashable {
    case standard
    case leftBass
    case closedHiHat
    case openHiHat
    case pedalHiHat
    case leftCrash
    case crash
    case ride
    case highTom
    case midTom
    case floorTom
    case china
    case splash
}

enum DrumNoteheadGlyph: String, CaseIterable, Hashable {
    case filledCircle
    case filledDiamond
    case cross
    case bullseye
    case openCircle
    case leftHalfCircle
    case rightHalfCircle
    case lowerHalfCircle
    case hollowDiamond

    var legacySymbol: String {
        switch self {
        case .filledCircle: return "●"
        case .filledDiamond: return "◆"
        case .cross: return "×"
        case .bullseye: return "◉"
        case .openCircle: return "○"
        case .leftHalfCircle: return "◐"
        case .rightHalfCircle: return "◑"
        case .lowerHalfCircle: return "◒"
        case .hollowDiamond: return "◇"
        }
    }
}

struct DrumNotationLane: Hashable {
    let id: String
    let variant: DrumNotationVariant
}

struct DrumNotationDefinition: Hashable {
    let lanes: [DrumNotationLane]
    let noteType: NoteType
    let gameplayInstrument: DrumType
    let defaultPosition: GameplayLayout.NotePosition
    let glyph: DrumNoteheadGlyph
    let voice: NotationVoice
    let defaultStemDirection: StemDirection
    let defaultVariant: DrumNotationVariant
    let catalogOrder: Int
}

struct ResolvedDrumNotation: Hashable {
    let definition: DrumNotationDefinition
    let variant: DrumNotationVariant
    let usedLaneFallback: Bool
}

enum DrumNotationCatalog {
    static let definitions: [DrumNotationDefinition] = [
        DrumNotationDefinition(
            lanes: [
                DrumNotationLane(id: "13", variant: .standard),
                DrumNotationLane(id: "1C", variant: .leftBass)
            ],
            noteType: .bass,
            gameplayInstrument: .kick,
            defaultPosition: .belowLine2,
            glyph: .filledCircle,
            voice: .lower,
            defaultStemDirection: .down,
            defaultVariant: .standard,
            catalogOrder: 0
        ),
        DrumNotationDefinition(
            lanes: [DrumNotationLane(id: "12", variant: .standard)],
            noteType: .snare,
            gameplayInstrument: .snare,
            defaultPosition: .line3,
            glyph: .filledDiamond,
            voice: .upper,
            defaultStemDirection: .up,
            defaultVariant: .standard,
            catalogOrder: 1
        ),
        DrumNotationDefinition(
            lanes: [DrumNotationLane(id: "11", variant: .closedHiHat)],
            noteType: .hiHat,
            gameplayInstrument: .hiHat,
            defaultPosition: .line5,
            glyph: .cross,
            voice: .upper,
            defaultStemDirection: .up,
            defaultVariant: .closedHiHat,
            catalogOrder: 2
        ),
        DrumNotationDefinition(
            lanes: [DrumNotationLane(id: "18", variant: .openHiHat)],
            noteType: .openHiHat,
            gameplayInstrument: .hiHat,
            defaultPosition: .line5,
            glyph: .cross,
            voice: .upper,
            defaultStemDirection: .up,
            defaultVariant: .openHiHat,
            catalogOrder: 3
        ),
        DrumNotationDefinition(
            lanes: [DrumNotationLane(id: "1B", variant: .pedalHiHat)],
            noteType: .hiHatPedal,
            gameplayInstrument: .hiHatPedal,
            defaultPosition: .belowLine1,
            glyph: .cross,
            voice: .lower,
            defaultStemDirection: .down,
            defaultVariant: .pedalHiHat,
            catalogOrder: 4
        ),
        DrumNotationDefinition(
            lanes: [DrumNotationLane(id: "14", variant: .highTom)],
            noteType: .highTom,
            gameplayInstrument: .tom1,
            defaultPosition: .spaceBetween3And4,
            glyph: .leftHalfCircle,
            voice: .upper,
            defaultStemDirection: .up,
            defaultVariant: .highTom,
            catalogOrder: 5
        ),
        DrumNotationDefinition(
            lanes: [DrumNotationLane(id: "15", variant: .midTom)],
            noteType: .midTom,
            gameplayInstrument: .tom2,
            defaultPosition: .spaceBetween2And3,
            glyph: .rightHalfCircle,
            voice: .upper,
            defaultStemDirection: .up,
            defaultVariant: .midTom,
            catalogOrder: 6
        ),
        DrumNotationDefinition(
            lanes: [DrumNotationLane(id: "17", variant: .floorTom)],
            noteType: .lowTom,
            gameplayInstrument: .tom3,
            defaultPosition: .line2,
            glyph: .lowerHalfCircle,
            voice: .upper,
            defaultStemDirection: .up,
            defaultVariant: .floorTom,
            catalogOrder: 7
        ),
        DrumNotationDefinition(
            lanes: [
                DrumNotationLane(id: "1A", variant: .leftCrash),
                DrumNotationLane(id: "16", variant: .crash)
            ],
            noteType: .crash,
            gameplayInstrument: .crash,
            defaultPosition: .aboveLine5,
            glyph: .bullseye,
            voice: .upper,
            defaultStemDirection: .up,
            defaultVariant: .crash,
            catalogOrder: 8
        ),
        DrumNotationDefinition(
            lanes: [DrumNotationLane(id: "19", variant: .ride)],
            noteType: .ride,
            gameplayInstrument: .ride,
            defaultPosition: .spaceBetween4And5,
            glyph: .openCircle,
            voice: .upper,
            defaultStemDirection: .up,
            defaultVariant: .ride,
            catalogOrder: 9
        ),
        DrumNotationDefinition(
            lanes: [],
            noteType: .china,
            gameplayInstrument: .crash,
            defaultPosition: .aboveLine5,
            glyph: .bullseye,
            voice: .upper,
            defaultStemDirection: .up,
            defaultVariant: .china,
            catalogOrder: 10
        ),
        DrumNotationDefinition(
            lanes: [],
            noteType: .splash,
            gameplayInstrument: .crash,
            defaultPosition: .aboveLine5,
            glyph: .bullseye,
            voice: .upper,
            defaultStemDirection: .up,
            defaultVariant: .splash,
            catalogOrder: 11
        ),
        DrumNotationDefinition(
            lanes: [],
            noteType: .cowbell,
            gameplayInstrument: .cowbell,
            defaultPosition: .line4,
            glyph: .hollowDiamond,
            voice: .upper,
            defaultStemDirection: .up,
            defaultVariant: .standard,
            catalogOrder: 12
        )
    ]

    static func definition(for noteType: NoteType) -> DrumNotationDefinition? {
        definitions.first { $0.noteType == noteType }
    }

    static func defaultDefinition(for drumType: DrumType) -> DrumNotationDefinition? {
        definitions.first { $0.gameplayInstrument == drumType }
    }

    static func resolve(
        noteType: NoteType,
        sourceLaneID: String?
    ) -> ResolvedDrumNotation? {
        guard let definition = definition(for: noteType) else {
            return nil
        }

        guard let sourceLaneID, !sourceLaneID.isEmpty else {
            return ResolvedDrumNotation(
                definition: definition,
                variant: definition.defaultVariant,
                usedLaneFallback: false
            )
        }

        let normalizedLaneID = sourceLaneID.uppercased()
        if let lane = definition.lanes.first(where: { $0.id == normalizedLaneID }) {
            return ResolvedDrumNotation(
                definition: definition,
                variant: lane.variant,
                usedLaneFallback: false
            )
        }

        return ResolvedDrumNotation(
            definition: definition,
            variant: definition.defaultVariant,
            usedLaneFallback: true
        )
    }

    static func noteType(forLaneID laneID: String) -> NoteType? {
        let normalizedLaneID = laneID.uppercased()
        return definitions.first {
            $0.lanes.contains(where: { $0.id == normalizedLaneID })
        }?.noteType
    }
}
