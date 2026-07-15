import Testing
import CoreGraphics
@testable import Virgo

@Suite("Drum Notation Catalog Tests")
struct DrumNotationCatalogTests {
    private struct ExpectedDefinition {
        let noteType: NoteType
        let drumType: DrumType
        let position: GameplayLayout.NotePosition
        let glyph: DrumNoteheadGlyph
        let voice: NotationVoice
        let direction: StemDirection
        let variant: DrumNotationVariant
        let order: Int
    }

    @Test("Target lane resolution preserves definition and display name")
    func targetLaneResolutionPreservesDefinitionAndDisplayName() throws {
        let target = try #require(DrumNotationCatalog.resolveTarget(laneID: "1A"))
        let lowercaseTarget = try #require(DrumNotationCatalog.resolveTarget(laneID: "1a"))

        #expect(target.definition == DrumNotationCatalog.definition(for: .crash))
        #expect(target.laneID == "1A")
        #expect(target.displayName == "Crash")
        #expect(lowercaseTarget == target)
        #expect(DrumNotationCatalog.resolveTarget(laneID: "ZZ") == nil)
    }

    @Test("Every NoteType has exactly one default definition")
    func everyNoteTypeHasExactlyOneDefinition() throws {
        #expect(DrumNotationCatalog.definitions.count == NoteType.allCases.count)
        #expect(Set(DrumNotationCatalog.definitions.map(\.noteType)).count == NoteType.allCases.count)

        for noteType in NoteType.allCases {
            let matches = DrumNotationCatalog.definitions.filter { $0.noteType == noteType }
            #expect(matches.count == 1)
            _ = try #require(DrumNotationCatalog.definition(for: noteType))
        }
    }

    @Test("Every playable DTX lane resolves once")
    func everyPlayableLaneResolvesOnce() {
        let expected: [String: NoteType] = [
            "11": .hiHat,
            "12": .snare,
            "13": .bass,
            "14": .highTom,
            "15": .midTom,
            "16": .crash,
            "17": .lowTom,
            "18": .openHiHat,
            "19": .ride,
            "1A": .crash,
            "1B": .hiHatPedal,
            "1C": .bass
        ]

        let catalogLaneIDs = DrumNotationCatalog.definitions
            .flatMap(\.lanes)
            .map(\.id)

        #expect(catalogLaneIDs.count == Set(catalogLaneIDs).count)
        #expect(Set(catalogLaneIDs) == Set(expected.keys))

        for (laneID, noteType) in expected {
            #expect(DrumNotationCatalog.noteType(forLaneID: laneID) == noteType)
            #expect(DTXLane(rawValue: laneID)?.noteType == noteType)
        }

        #expect(DTXLane.bpm.noteType == nil)
        #expect(DTXLane.bgm.noteType == nil)
    }

    @Test("Lane-specific variants survive shared instrument mappings")
    func laneSpecificVariantsRemainDistinct() throws {
        let leftBass = try #require(
            DrumNotationCatalog.resolve(noteType: .bass, sourceLaneID: "1C")
        )
        let bass = try #require(
            DrumNotationCatalog.resolve(noteType: .bass, sourceLaneID: "13")
        )
        let openHat = try #require(
            DrumNotationCatalog.resolve(noteType: .openHiHat, sourceLaneID: "18")
        )
        let closedHat = try #require(
            DrumNotationCatalog.resolve(noteType: .hiHat, sourceLaneID: "11")
        )
        let pedalHat = try #require(
            DrumNotationCatalog.resolve(noteType: .hiHatPedal, sourceLaneID: "1B")
        )
        let leftCrash = try #require(
            DrumNotationCatalog.resolve(noteType: .crash, sourceLaneID: "1A")
        )
        let crash = try #require(
            DrumNotationCatalog.resolve(noteType: .crash, sourceLaneID: "16")
        )
        let ride = try #require(
            DrumNotationCatalog.resolve(noteType: .ride, sourceLaneID: "19")
        )

        #expect(leftBass.variant == .leftBass)
        #expect(bass.variant == .standard)
        #expect(openHat.variant == .openHiHat)
        #expect(closedHat.variant == .closedHiHat)
        #expect(pedalHat.variant == .pedalHiHat)
        #expect(leftCrash.variant == .leftCrash)
        #expect(crash.variant == .crash)
        #expect(ride.variant == .ride)
        #expect(openHat.definition.gameplayInstrument == closedHat.definition.gameplayInstrument)
        #expect(leftCrash.definition.gameplayInstrument == crash.definition.gameplayInstrument)
    }

    @Test("Known NoteType falls back when its source lane is unfamiliar")
    func knownNoteTypeFallsBackForUnknownLane() throws {
        let resolved = try #require(
            DrumNotationCatalog.resolve(noteType: .ride, sourceLaneID: "AA")
        )

        #expect(resolved.definition.noteType == .ride)
        #expect(resolved.definition.gameplayInstrument == .ride)
        #expect(resolved.variant == .ride)
        #expect(resolved.usedLaneFallback)
    }

    @Test("Voice and default stem direction are canonical")
    func voiceAndDirectionAreCanonical() {
        for definition in DrumNotationCatalog.definitions {
            let expectedDirection: StemDirection = definition.voice == .upper ? .up : .down
            #expect(definition.defaultStemDirection == expectedDirection)
        }

        #expect(DrumNotationCatalog.definition(for: .bass)?.voice == .lower)
        #expect(DrumNotationCatalog.definition(for: .hiHatPedal)?.voice == .lower)
        #expect(DrumNotationCatalog.definition(for: .crash)?.voice == .upper)
        #expect(DrumNotationCatalog.definition(for: .snare)?.voice == .upper)
    }

    @Test("Approved legend is exhaustive and keeps compatibility mappings")
    func approvedLegendIsExhaustive() throws {
        let expected = [
            ExpectedDefinition(
                noteType: .bass, drumType: .kick, position: .belowLine2,
                glyph: .filledCircle, voice: .lower, direction: .down, variant: .standard, order: 0
            ),
            ExpectedDefinition(
                noteType: .snare, drumType: .snare, position: .line3,
                glyph: .filledDiamond, voice: .upper, direction: .up, variant: .standard, order: 1
            ),
            ExpectedDefinition(
                noteType: .hiHat, drumType: .hiHat, position: .line5,
                glyph: .cross, voice: .upper, direction: .up, variant: .closedHiHat, order: 2
            ),
            ExpectedDefinition(
                noteType: .openHiHat, drumType: .hiHat, position: .line5,
                glyph: .cross, voice: .upper, direction: .up, variant: .openHiHat, order: 3
            ),
            ExpectedDefinition(
                noteType: .hiHatPedal, drumType: .hiHatPedal, position: .belowLine1,
                glyph: .cross, voice: .lower, direction: .down, variant: .pedalHiHat, order: 4
            ),
            ExpectedDefinition(
                noteType: .highTom, drumType: .tom1, position: .spaceBetween3And4,
                glyph: .leftHalfCircle, voice: .upper, direction: .up, variant: .highTom, order: 5
            ),
            ExpectedDefinition(
                noteType: .midTom, drumType: .tom2, position: .spaceBetween2And3,
                glyph: .rightHalfCircle, voice: .upper, direction: .up, variant: .midTom, order: 6
            ),
            ExpectedDefinition(
                noteType: .lowTom, drumType: .tom3, position: .line2,
                glyph: .lowerHalfCircle, voice: .upper, direction: .up, variant: .floorTom, order: 7
            ),
            ExpectedDefinition(
                noteType: .crash, drumType: .crash, position: .aboveLine5,
                glyph: .bullseye, voice: .upper, direction: .up, variant: .crash, order: 8
            ),
            ExpectedDefinition(
                noteType: .ride, drumType: .ride, position: .spaceBetween4And5,
                glyph: .openCircle, voice: .upper, direction: .up, variant: .ride, order: 9
            ),
            ExpectedDefinition(
                noteType: .china, drumType: .crash, position: .aboveLine5,
                glyph: .bullseye, voice: .upper, direction: .up, variant: .china, order: 10
            ),
            ExpectedDefinition(
                noteType: .splash, drumType: .crash, position: .aboveLine5,
                glyph: .bullseye, voice: .upper, direction: .up, variant: .splash, order: 11
            ),
            ExpectedDefinition(
                noteType: .cowbell, drumType: .cowbell, position: .line4,
                glyph: .hollowDiamond, voice: .upper, direction: .up, variant: .standard, order: 12
            )
        ]

        #expect(Set(DrumNotationCatalog.definitions.map(\.catalogOrder)).count == expected.count)

        for item in expected {
            let definition = try #require(DrumNotationCatalog.definition(for: item.noteType))
            #expect(definition.gameplayInstrument == item.drumType)
            #expect(definition.defaultPosition == item.position)
            #expect(definition.glyph == item.glyph)
            #expect(definition.voice == item.voice)
            #expect(definition.defaultStemDirection == item.direction)
            #expect(definition.defaultVariant == item.variant)
            #expect(definition.catalogOrder == item.order)
            #expect(DrumType.from(noteType: item.noteType) == item.drumType)
        }
    }

    @Test("Every glyph has finite normalized bounds and a nonempty path")
    func everyGlyphHasFiniteBoundsAndPath() {
        let drawingRect = CGRect(x: 0, y: 0, width: 30, height: 20)

        for glyph in DrumNoteheadGlyph.allCases {
            let bounds = glyph.normalizedBounds
            #expect(bounds.minX.isFinite)
            #expect(bounds.minY.isFinite)
            #expect(bounds.width.isFinite)
            #expect(bounds.height.isFinite)
            #expect(bounds.minX >= 0)
            #expect(bounds.minY >= 0)
            #expect(bounds.maxX <= 1)
            #expect(bounds.maxY <= 1)
            #expect(bounds.width > 0)
            #expect(bounds.height > 0)

            let path = glyph.makePath(in: drawingRect)
            let expectedBounds = glyph.bounds(
                centeredAt: CGPoint(x: drawingRect.midX, y: drawingRect.midY),
                size: drawingRect.size
            )
            let pathBounds = path.boundingBoxOfPath
            #expect(!path.isEmpty)
            #expect(!pathBounds.isNull)
            #expect(abs(pathBounds.minX - expectedBounds.minX) < 0.001)
            #expect(abs(pathBounds.maxX - expectedBounds.maxX) < 0.001)
            #expect(abs(pathBounds.minY - expectedBounds.minY) < 0.001)
            #expect(abs(pathBounds.maxY - expectedBounds.maxY) < 0.001)
        }
    }

    @Test("Stem anchors use opposite glyph sides")
    func stemAnchorsUseOppositeSides() {
        let center = CGPoint(x: 100, y: 60)
        let size = CGSize(width: 30, height: 20)

        for glyph in DrumNoteheadGlyph.allCases {
            let upOffset = glyph.stemAnchorOffset(direction: .up, in: size)
            let downOffset = glyph.stemAnchorOffset(direction: .down, in: size)
            let up = CGPoint(x: center.x + upOffset.x, y: center.y + upOffset.y)
            let down = CGPoint(x: center.x + downOffset.x, y: center.y + downOffset.y)
            let bounds = glyph.bounds(centeredAt: center, size: size)

            #expect(up.x == bounds.maxX)
            #expect(down.x == bounds.minX)
            #expect(up.x > center.x)
            #expect(down.x < center.x)

            if glyph == .cross {
                #expect(up.y > bounds.midY)
                #expect(down.y < bounds.midY)
            } else {
                #expect(up.y == bounds.midY)
                #expect(down.y == bounds.midY)
            }

            let frame = CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            let path = glyph.makePath(in: frame)
            #expect(path.contains(CGPoint(x: up.x - 0.01, y: up.y), using: .evenOdd))
            #expect(path.contains(CGPoint(x: down.x + 0.01, y: down.y), using: .evenOdd))
        }
    }

    @Test("Cross geometry stays inside authored bounds at small sizes")
    func crossGeometryStaysInsideAuthoredBoundsAtSmallSizes() {
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let expectedBounds = DrumNoteheadGlyph.cross.bounds(
            centeredAt: CGPoint(x: rect.midX, y: rect.midY),
            size: rect.size
        )
        let pathBounds = DrumNoteheadGlyph.cross.makePath(in: rect).boundingBoxOfPath
        let up = DrumNoteheadGlyph.cross.stemAnchorOffset(direction: .up, in: rect.size)
        let down = DrumNoteheadGlyph.cross.stemAnchorOffset(direction: .down, in: rect.size)

        #expect(abs(pathBounds.minX - expectedBounds.minX) < 0.001)
        #expect(abs(pathBounds.maxX - expectedBounds.maxX) < 0.001)
        #expect(abs(pathBounds.minY - expectedBounds.minY) < 0.001)
        #expect(abs(pathBounds.maxY - expectedBounds.maxY) < 0.001)
        #expect(up.y > 0)
        #expect(down.y < 0)
    }

    @Test("Cross geometry collapses to its center at zero size")
    func crossGeometryCollapsesToItsCenterAtZeroSize() {
        let center = CGPoint(x: 7, y: 11)
        let rect = CGRect(origin: center, size: .zero)
        let expectedBounds = DrumNoteheadGlyph.cross.bounds(centeredAt: center, size: .zero)
        let pathBounds = DrumNoteheadGlyph.cross.makePath(in: rect).boundingBoxOfPath
        let up = DrumNoteheadGlyph.cross.stemAnchorOffset(direction: .up, in: .zero)
        let down = DrumNoteheadGlyph.cross.stemAnchorOffset(direction: .down, in: .zero)

        if !pathBounds.isNull {
            #expect(abs(pathBounds.minX - expectedBounds.minX) < 0.001)
            #expect(abs(pathBounds.maxX - expectedBounds.maxX) < 0.001)
            #expect(abs(pathBounds.minY - expectedBounds.minY) < 0.001)
            #expect(abs(pathBounds.maxY - expectedBounds.maxY) < 0.001)
        }
        #expect(up == .zero)
        #expect(down == .zero)
    }
}
