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

extension DrumNoteheadGlyph {
    var normalizedBounds: CGRect {
        switch self {
        case .cross:
            return CGRect(x: 0.12, y: 0.12, width: 0.76, height: 0.76)
        default:
            return CGRect(x: 0.10, y: 0.10, width: 0.80, height: 0.80)
        }
    }

    var usesEvenOddFill: Bool {
        switch self {
        case .bullseye, .openCircle, .leftHalfCircle,
             .rightHalfCircle, .lowerHalfCircle, .hollowDiamond:
            return true
        case .filledCircle, .filledDiamond, .cross:
            return false
        }
    }

    func bounds(centeredAt center: CGPoint, size: CGSize) -> CGRect {
        let relativeBounds = scaledBounds(
            in: CGRect(
                x: -size.width / 2,
                y: -size.height / 2,
                width: size.width,
                height: size.height
            )
        )
        let minX = center.x + relativeBounds.minX
        let maxX = center.x + relativeBounds.maxX
        let minY = center.y + relativeBounds.minY
        let maxY = center.y + relativeBounds.maxY
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    func stemAnchorOffset(
        direction: StemDirection,
        in size: CGSize
    ) -> CGPoint {
        let bounds = scaledBounds(
            in: CGRect(
                x: -size.width / 2,
                y: -size.height / 2,
                width: size.width,
                height: size.height
            )
        )
        if self == .cross {
            let radius = crossStrokeWidth(in: bounds) / 2
            return direction == .up
                ? CGPoint(x: bounds.maxX, y: bounds.maxY - radius)
                : CGPoint(x: bounds.minX, y: bounds.minY + radius)
        }

        return CGPoint(x: direction == .up ? bounds.maxX : bounds.minX, y: bounds.midY)
    }

    func makePath(in rect: CGRect) -> CGPath {
        let bounds = scaledBounds(in: rect)

        switch self {
        case .filledCircle:
            return CGPath(ellipseIn: bounds, transform: nil)
        case .filledDiamond:
            return diamondPath(in: bounds)
        case .cross:
            let strokeWidth = crossStrokeWidth(in: bounds)
            let radius = strokeWidth / 2
            let diagonals = CGMutablePath()
            diagonals.move(to: CGPoint(x: bounds.minX + radius, y: bounds.minY + radius))
            diagonals.addLine(to: CGPoint(x: bounds.maxX - radius, y: bounds.maxY - radius))
            diagonals.move(to: CGPoint(x: bounds.maxX - radius, y: bounds.minY + radius))
            diagonals.addLine(to: CGPoint(x: bounds.minX + radius, y: bounds.maxY - radius))
            return diagonals.copy(
                strokingWithWidth: strokeWidth,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 2
            )
        case .bullseye:
            let inner = bounds.insetBy(dx: bounds.width * 0.20, dy: bounds.height * 0.20)
            let dot = bounds.insetBy(dx: bounds.width * 0.38, dy: bounds.height * 0.38)
            return compoundPath([
                CGPath(ellipseIn: bounds, transform: nil),
                CGPath(ellipseIn: inner, transform: nil),
                CGPath(ellipseIn: dot, transform: nil)
            ])
        case .openCircle:
            let inner = bounds.insetBy(dx: bounds.width * 0.20, dy: bounds.height * 0.20)
            return compoundPath([
                CGPath(ellipseIn: bounds, transform: nil),
                CGPath(ellipseIn: inner, transform: nil)
            ])
        case .leftHalfCircle, .rightHalfCircle, .lowerHalfCircle:
            let inner = bounds.insetBy(dx: bounds.width * 0.16, dy: bounds.height * 0.16)
            return compoundPath([
                CGPath(ellipseIn: bounds, transform: nil),
                CGPath(ellipseIn: inner, transform: nil),
                halfFillPath(in: inner)
            ])
        case .hollowDiamond:
            let inner = bounds.insetBy(dx: bounds.width * 0.24, dy: bounds.height * 0.24)
            return compoundPath([
                diamondPath(in: bounds),
                diamondPath(in: inner)
            ])
        }
    }
}

private extension DrumNoteheadGlyph {
    func crossStrokeWidth(in bounds: CGRect) -> CGFloat {
        min(bounds.width, bounds.height) * 0.16
    }

    func scaledBounds(in rect: CGRect) -> CGRect {
        let bounds = normalizedBounds
        return CGRect(
            x: rect.minX + bounds.minX * rect.width,
            y: rect.minY + bounds.minY * rect.height,
            width: bounds.width * rect.width,
            height: bounds.height * rect.height
        )
    }

    func diamondPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }

    func compoundPath(_ paths: [CGPath]) -> CGPath {
        let result = CGMutablePath()
        for path in paths {
            result.addPath(path)
        }
        return result
    }

    func halfFillPath(in rect: CGRect) -> CGPath {
        switch self {
        case .leftHalfCircle:
            return verticalHalfFillPath(in: rect, onLeft: true)
        case .rightHalfCircle:
            return verticalHalfFillPath(in: rect, onLeft: false)
        case .lowerHalfCircle:
            return lowerHalfFillPath(in: rect)
        case .filledCircle, .filledDiamond, .cross, .bullseye,
             .openCircle, .hollowDiamond:
            preconditionFailure("Half fill requested for a non-half-circle glyph")
        }
    }

    func verticalHalfFillPath(in rect: CGRect, onLeft: Bool) -> CGPath {
        let path = CGMutablePath()
        let radiusX = rect.width / 2
        let radiusY = rect.height / 2
        let kappa: CGFloat = 0.552_284_75
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let side = CGPoint(x: onLeft ? rect.minX : rect.maxX, y: rect.midY)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)
        let sign: CGFloat = onLeft ? -1 : 1

        path.move(to: top)
        path.addCurve(
            to: side,
            control1: CGPoint(x: top.x + sign * kappa * radiusX, y: top.y),
            control2: CGPoint(x: side.x, y: side.y - kappa * radiusY)
        )
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: side.x, y: side.y + kappa * radiusY),
            control2: CGPoint(x: bottom.x + sign * kappa * radiusX, y: bottom.y)
        )
        path.closeSubpath()
        return path
    }

    func lowerHalfFillPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let radiusX = rect.width / 2
        let radiusY = rect.height / 2
        let kappa: CGFloat = 0.552_284_75
        let left = CGPoint(x: rect.minX, y: rect.midY)
        let right = CGPoint(x: rect.maxX, y: rect.midY)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)

        path.move(to: left)
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: left.x, y: left.y + kappa * radiusY),
            control2: CGPoint(x: bottom.x - kappa * radiusX, y: bottom.y)
        )
        path.addCurve(
            to: right,
            control1: CGPoint(x: bottom.x + kappa * radiusX, y: bottom.y),
            control2: CGPoint(x: right.x, y: right.y + kappa * radiusY)
        )
        path.closeSubpath()
        return path
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
