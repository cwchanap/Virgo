# Same-Time Drum Voices and Notehead/Stem Placement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox - [ ] syntax for tracking.

**Goal:** Keep simultaneous drum hits on one exact HPA-140 time column while introducing a single drum-notation catalog, deterministic vector noteheads, and readable per-voice stems.

**Architecture:** Resolve every Note through a pure DrumNotationCatalog before layout, then preserve the resolved source identity, glyph, voice, direction, and integer time column on RenderedNoteHead. The fixed grid remains the only x mapper; vector glyph geometry supplies notehead bounds and stem anchors used by heads, ledger lines, stems, beams, and flags.

**Tech Stack:** Swift 5.9, SwiftUI, Core Graphics, SwiftData model inputs, Swift Testing, Xcode file-system-synchronized groups, xcodebuild, SwiftLint.

## Global Constraints

- Follow the approved design in docs/superpowers/specs/2026-07-10-same-time-drum-voices-notehead-stem-placement-design.md.
- Run every repository shell command through rtk.
- Use CodeGraph before raw code search or file reads during execution.
- Keep iOS-family builds iPad-only. Never add or select an iPhone destination.
- Support macOS 14.0+ and the existing iPadOS target without adding dependencies or a music font.
- Do not change SwiftData fields, migration behavior, scoring, input matching, DrumBeat semantics, audio, or persisted settings.
- Preserve HPA-140 tick resolution, fixed-grid mapping, purple playhead alignment, fallback behavior, and deterministic wrapping.
- Leave beam grouping, partial beams, hooks, and flag semantics to HPA-142.
- Preserve articulation variants as data only; visible articulation, choke, stop, and rest primitives remain HPA-143 scope.
- Leave broad screenshot and golden-fixture coverage to HPA-144.
- Leave tuplets, swing, dotted rhythms, compound meter, and variable measure length to HPA-145.
- Use Swift Testing, not XCTest, for new unit coverage.
- Disable parallel testing on every xcodebuild test command.
- Run Xcode verification sequentially when commands share ./DerivedData.
- Respect SwiftLint limits: line 120/150, function 50/100, type 300/600, file 600/1000.
- Virgo.xcodeproj uses file-system-synchronized groups. Add new files on disk only; do not edit project.pbxproj.

## File Structure

### New files

- Virgo/constants/DrumNotation.swift — pure catalog records, lane/type/instrument resolution, variants, voice/direction, legacy symbol compatibility, and vector glyph geometry.
- VirgoTests/DrumNotationCatalogTests.swift — exhaustive catalog and pure Core Graphics geometry tests.

### Existing production files

- Virgo/constants/Drum.swift:139-190 — delegate legacy symbol and NoteType-to-DrumType facades to the catalog.
- Virgo/layout/gameplay.swift:239-259 — delegate default DrumType staff positions to the catalog.
- Virgo/utilities/DTXFileParser.swift:139-151,154-202 — delegate lane and normalized voice lookup without changing parser semantics.
- Virgo/layout/NotationLayout.swift:47-138,199-244 — move voice/direction types, remove collision-only style fields, add NotationTimeColumn, and expand RenderedNoteHead.
- Virgo/layout/NotationLayoutEngine.swift:6-386,390-654,700-856 — resolve catalog identities, remove x mutation, group stems semantically, and share vector anchors with beams/flags/ledger lines.
- Virgo/layout/NotationLayoutEngine+TabGrid.swift:137-146 — remove collision-inflated column spacing.
- Virgo/views/NotationPrimitiveViews.swift:38-48 — replace Text noteheads with paths from the resolved glyph.
- Virgo/views/subviews/GameplaySheetMusicView.swift:246-278 — pass the layout's resolved notehead size to vector views.
- Virgo/viewmodels/GameplayViewModel+Computations.swift:241 — consume RenderedNoteHead.sourceObjectID after the identity rename.

### Existing test files

- VirgoTests/DrumTypeExtensionsAndConstantsTests.swift — retain facade compatibility coverage.
- VirgoTests/DTXFileParserTests.swift — retain lane and normalization behavior.
- VirgoTests/NotationLayoutEngineTests.swift — replace split-x assertions and hard-coded stem inset assertions.
- VirgoTests/NotationLayoutEngineChordAndBeamTests.swift — replace direction-unification assumptions and verify shared anchor seams.
- VirgoTests/NotationLayoutNotePositionOverrideTests.swift — assert overrides change y only.
- VirgoTests/NotationLayoutOffsetNormalizationTests.swift — assert normalized representations share both time column and x.
- VirgoTests/SwiftUIRenderingCoverageTests.swift — mount every vector notehead and update RenderedNoteHead fixtures.

---

### Task 1: Canonical Drum Notation Catalog

**Files:**
- Create: Virgo/constants/DrumNotation.swift
- Create: VirgoTests/DrumNotationCatalogTests.swift
- Modify: Virgo/constants/Drum.swift:139-190
- Modify: Virgo/layout/NotationLayout.swift:121-138
- Modify: Virgo/layout/gameplay.swift:239-259
- Modify: Virgo/utilities/DTXFileParser.swift:139-151,154-202
- Test: VirgoTests/DrumTypeExtensionsAndConstantsTests.swift
- Test: VirgoTests/DTXFileParserTests.swift

**Interfaces:**
- Consumes: NoteType, DrumType, GameplayLayout.NotePosition, NormalizedNotationVoice, and uppercase DTX lane strings.
- Produces: DrumNotationLane, DrumNotationDefinition, ResolvedDrumNotation, DrumNotationVariant, DrumNoteheadGlyph, NotationVoice, StemDirection, DrumNotationCatalog.definition(for:), DrumNotationCatalog.defaultDefinition(for:), DrumNotationCatalog.resolve(noteType:sourceLaneID:), and DrumNotationCatalog.noteType(forLaneID:).

- [ ] **Step 1: Write the failing catalog tests**

Create VirgoTests/DrumNotationCatalogTests.swift with the following coverage:

~~~swift
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
}
~~~

- [ ] **Step 2: Run the new suite and verify the red state**

Run:

~~~bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/DrumNotationCatalogTests \
  -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData test
~~~

Expected: FAIL to compile because DrumNotationCatalog and its value types do not exist.

- [ ] **Step 3: Add the catalog records and exhaustive table**

Create Virgo/constants/DrumNotation.swift with these declarations and values:

~~~swift
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
~~~

Remove NotationVoice and StemDirection from Virgo/layout/NotationLayout.swift after moving them into this file.

- [ ] **Step 4: Delegate all compatibility facades to the catalog**

In Virgo/constants/Drum.swift, replace DrumType.symbol and DrumType.from(noteType:) with:

~~~swift
var symbol: String {
    DrumNotationCatalog.defaultDefinition(for: self)?.glyph.legacySymbol ?? "?"
}

static func from(noteType: NoteType) -> DrumType? {
    DrumNotationCatalog.definition(for: noteType)?.gameplayInstrument
}
~~~

Delete noteTypeToDrumTypeMap.

In Virgo/layout/gameplay.swift, replace DrumType.notePosition with:

~~~swift
var notePosition: GameplayLayout.NotePosition {
    guard let position = DrumNotationCatalog.defaultDefinition(for: self)?.defaultPosition else {
        assertionFailure("Missing default notation position for \(self)")
        return .line3
    }
    return position
}
~~~

In Virgo/utilities/DTXFileParser.swift, replace DTXLane.noteType with:

~~~swift
var noteType: NoteType? {
    DrumNotationCatalog.noteType(forLaneID: rawValue)
}
~~~

Replace NormalizedRhythmicEvent.voiceCandidate(for:) with:

~~~swift
private static func voiceCandidate(for noteType: NoteType) -> NormalizedNotationVoice {
    guard let voice = DrumNotationCatalog.definition(for: noteType)?.voice else {
        assertionFailure("Missing notation voice for \(noteType)")
        return .upper
    }
    return voice == .lower ? .lower : .upper
}
~~~

- [ ] **Step 5: Run catalog, facade, and parser tests**

Run these commands sequentially:

~~~bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/DrumNotationCatalogTests \
  -only-testing:VirgoTests/DrumTypeExtensionsAndConstantsTests \
  -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData test

rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/DTXFileParserTests \
  -only-testing:VirgoTests/DTXNormalizationTests \
  -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData test
~~~

Expected: PASS. Existing symbol, lane, parser, and default-position behavior remains unchanged.

- [ ] **Step 6: Commit the catalog**

~~~bash
rtk git add Virgo/constants/DrumNotation.swift Virgo/constants/Drum.swift \
  Virgo/layout/NotationLayout.swift Virgo/layout/gameplay.swift \
  Virgo/utilities/DTXFileParser.swift VirgoTests/DrumNotationCatalogTests.swift
rtk git commit -m "feat: add canonical drum notation catalog"
~~~

---

### Task 2: Deterministic Vector Glyph Geometry

**Files:**
- Modify: Virgo/constants/DrumNotation.swift
- Modify: VirgoTests/DrumNotationCatalogTests.swift

**Interfaces:**
- Consumes: DrumNoteheadGlyph, StemDirection, CGSize, CGPoint, CGRect.
- Produces: normalizedBounds, usesEvenOddFill, makePath(in:), bounds(centeredAt:size:), and stemAnchorOffset(direction:in:) on DrumNoteheadGlyph.

- [ ] **Step 1: Add failing geometry tests**

Append these tests to DrumNotationCatalogTests:

~~~swift
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
~~~

- [ ] **Step 2: Run the geometry tests and verify the red state**

Run:

~~~bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/DrumNotationCatalogTests \
  -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData test
~~~

Expected: FAIL to compile because the geometry properties and methods do not exist.

- [ ] **Step 3: Implement authored bounds, anchors, and paths**

Add this extension and its private helpers to Virgo/constants/DrumNotation.swift:

~~~swift
extension DrumNoteheadGlyph {
    var normalizedBounds: CGRect {
        switch self {
        case .cross:
            return CGRect(x: 0.12, y: 0.12, width: 0.76, height: 0.76)
        case .filledDiamond, .hollowDiamond:
            return CGRect(x: 0.10, y: 0.10, width: 0.80, height: 0.80)
        case .filledCircle, .bullseye, .openCircle,
             .leftHalfCircle, .rightHalfCircle, .lowerHalfCircle:
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
        let frame = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        return scaledBounds(in: frame)
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
        max(min(bounds.width, bounds.height) * 0.16, 1)
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
~~~

- [ ] **Step 4: Run the geometry suite**

Run:

~~~bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/DrumNotationCatalogTests \
  -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData test
~~~

Expected: PASS for every catalog and vector geometry test.

- [ ] **Step 5: Commit vector geometry**

~~~bash
rtk git add Virgo/constants/DrumNotation.swift VirgoTests/DrumNotationCatalogTests.swift
rtk git commit -m "feat: add deterministic drum notehead geometry"
~~~

---

### Task 3: Resolved Noteheads and Immutable Time Columns

**Files:**
- Modify: Virgo/layout/NotationLayout.swift:71-138,199-211
- Modify: Virgo/layout/NotationLayoutEngine.swift:6-386,636-654
- Modify: Virgo/layout/NotationLayoutEngine+TabGrid.swift:137-146
- Modify: Virgo/views/NotationPrimitiveViews.swift:38-48
- Modify: Virgo/views/subviews/GameplaySheetMusicView.swift:246-278
- Modify: Virgo/viewmodels/GameplayViewModel+Computations.swift:241
- Modify: VirgoTests/NotationLayoutEngineTests.swift:416-630
- Modify: VirgoTests/NotationLayoutOffsetNormalizationTests.swift:22-40
- Modify: VirgoTests/SwiftUIRenderingCoverageTests.swift:184-265

**Interfaces:**
- Consumes: DrumNotationCatalog.resolve(noteType:sourceLaneID:), DrumNoteheadGlyph geometry, and HPA-140 TabGrid.
- Produces: NotationTimeColumn and the exact expanded RenderedNoteHead contract from the approved design. NotationLayout carries the resolved notehead size so SwiftUI scales the same geometry used by layout. Rendered heads retain canonical grid x, sourceObjectID, source lane/chip IDs, NoteType, DrumType, glyph, variant, voice, direction, staff position, and interval.

- [ ] **Step 1: Replace split-x tests with exact-column and identity tests**

In NotationLayoutEngineTests, delete the old methods named:

- nearIdenticalSimultaneousOffsetsKeepFixedGridWidth
- nearIdenticalCrossVoiceOffsetsSplitHeadsWithinFixedGridWidth
- denseAdjacentCrossVoiceColumnsPreserveReadableFinalGap
- simultaneousQuarterNotesSplitVoicesWithinFixedGridWidth
- kickAndSnareAtSameTimeGetSeparateVoices
- nearIdenticalCrossVoiceOffsetsSplitByQuantizedColumn

Add these replacements:

~~~swift
@Test("same-time kick snare and hi-hat share the exact grid column")
func sameTimeKickSnareAndHiHatShareExactGridColumn() throws {
    let notes = [
        Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.25),
        Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.25),
        Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0.25)
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )
    let heads = layout.noteHeads
    let firstHead = try #require(heads.first)
    let measure = try #require(
        layout.measures.first { $0.measureIndex == firstHead.timeColumn.measureIndex }
    )
    let expectedX = layout.tabGrid.xPosition(
        in: measure,
        tickIndex: firstHead.timeColumn.tickWithinMeasure
    )

    #expect(heads.count == 3)
    #expect(heads.allSatisfy { $0.timeColumn == firstHead.timeColumn })
    #expect(heads.allSatisfy { $0.position.x == expectedX })
    #expect(Set(heads.map(\.position.x)).count == 1)
}

@Test("near-equal offsets resolving to one tick share x")
func nearEqualOffsetsResolvingToOneTickShareX() throws {
    let notes = [
        Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.25),
        Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: 0.249_999_999_999_999_97
        )
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )
    let kick = try #require(layout.noteHeads.first { $0.drumType == .kick })
    let snare = try #require(layout.noteHeads.first { $0.drumType == .snare })

    #expect(kick.timeColumn == snare.timeColumn)
    #expect(kick.position.x == snare.position.x)
}

@Test("simultaneous quarter pairs produce four time columns")
func simultaneousQuarterPairsProduceFourTimeColumns() {
    let notes = (0..<4).flatMap { index in
        [
            Note(
                interval: .quarter,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: Double(index) / 4
            ),
            Note(
                interval: .quarter,
                noteType: .bass,
                measureNumber: 1,
                measureOffset: Double(index) / 4
            )
        ]
    }
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )

    #expect(layout.noteHeads.count == 8)
    #expect(Set(layout.noteHeads.map(\.timeColumn)).count == 4)
    #expect(Set(layout.noteHeads.map(\.position.x)).count == 4)
}

@Test("cross-voice chords do not inflate fixed-grid metrics")
func crossVoiceChordsDoNotInflateFixedGridMetrics() {
    let style = NotationLayoutStyle.gameplayDefault
    let singleVoice = [
        Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
        Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.0625)
    ]
    let mixedVoice = singleVoice + [
        Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0),
        Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0.0625)
    ]

    let singleLayout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: singleVoice, timeSignature: .fourFour, style: style)
    )
    let mixedLayout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: mixedVoice, timeSignature: .fourFour, style: style)
    )
    let columns = Array(Set(mixedLayout.noteHeads.map(\.position.x))).sorted()

    #expect(mixedLayout.tabGrid.tickWidth == singleLayout.tabGrid.tickWidth)
    #expect(mixedLayout.tabGrid.measureWidth == singleLayout.tabGrid.measureWidth)
    #expect(columns.count == 2)
    #expect(columns[1] - columns[0] >= style.minimumNoteColumnGap)
}

@Test("rendered head preserves source and notation identity")
func renderedHeadPreservesSourceAndNotationIdentity() throws {
    let note = Note(
        interval: .quarter,
        noteType: .openHiHat,
        measureNumber: 1,
        measureOffset: 0,
        originKind: .dtx,
        sourceLaneID: "18",
        sourceNoteID: "A1"
    )
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
    )
    let head = try #require(layout.noteHeads.first)

    #expect(head.sourceObjectID == ObjectIdentifier(note))
    #expect(head.sourceLaneID == "18")
    #expect(head.sourceChipID == "A1")
    #expect(head.noteType == .openHiHat)
    #expect(head.drumType == .hiHat)
    #expect(head.glyph == .cross)
    #expect(head.variant == .openHiHat)
    #expect(head.voice == .upper)
    #expect(head.stemDirection == .up)
}

@Test("unknown lane fallback preserves raw rendered identity")
func unknownLaneFallbackPreservesRawRenderedIdentity() throws {
    let note = Note(
        interval: .quarter,
        noteType: .ride,
        measureNumber: 1,
        measureOffset: 0,
        originKind: .dtx,
        sourceLaneID: "AA",
        sourceNoteID: "7F"
    )
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
    )
    let head = try #require(layout.noteHeads.first)

    #expect(head.sourceObjectID == ObjectIdentifier(note))
    #expect(head.sourceLaneID == "AA")
    #expect(head.sourceChipID == "7F")
    #expect(head.noteType == .ride)
    #expect(head.drumType == .ride)
    #expect(head.variant == .ride)
}

@Test("identical heads retain distinct identities and lookup entries")
func identicalHeadsRetainDistinctIdentitiesAndLookupEntries() {
    let notes = [
        Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
        Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )
    let heads = layout.noteHeads
    let renderedIDs = Set(heads.map(\.id))
    let timeKey = NotationLayout.timePositionKey(0)

    #expect(heads.count == 2)
    #expect(renderedIDs.count == 2)
    #expect(Set(heads.map(\.sourceObjectID)).count == 2)
    #expect(layout.noteHeadPositionsByID.count == 2)
    #expect(layout.noteHeadIDsByTimePosition[timeKey] == renderedIDs)
}

@Test("ledger width follows authored glyph bounds")
func ledgerWidthFollowsAuthoredGlyphBounds() throws {
    let style = NotationLayoutStyle.gameplayDefault
    let note = Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0)
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: [note], timeSignature: .fourFour, style: style)
    )
    let head = try #require(layout.noteHeads.first)
    let ledger = try #require(layout.ledgerLines.first)
    let glyphBounds = head.glyph.bounds(
        centeredAt: head.position,
        size: layout.noteHeadSize
    )

    #expect(ledger.start.x == glyphBounds.minX - style.ledgerLineOverhang)
    #expect(ledger.end.x == glyphBounds.maxX + style.ledgerLineOverhang)
}
~~~

Extend offsetOneNoteCollisionColumnUsesNormalizedMeasure in NotationLayoutOffsetNormalizationTests with:

~~~swift
#expect(snare.timeColumn == kick.timeColumn)
#expect(snare.position.x == kick.position.x)
~~~

- [ ] **Step 2: Run the layout tests and verify the red state**

Run:

~~~bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -only-testing:VirgoTests/NotationLayoutOffsetNormalizationTests \
  -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData test
~~~

Expected: FAIL because RenderedNoteHead has no expanded identity or timeColumn and because mixed voices still receive x offsets and extra grid padding.

- [ ] **Step 3: Add the integer time-column and rendered identity contracts**

In Virgo/layout/NotationLayout.swift, add NotationTimeColumn and replace RenderedNoteHead with:

~~~swift
struct NotationTimeColumn: Hashable {
    let measureIndex: Int
    let tickWithinMeasure: Int
    let absoluteLayoutTick: Int
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
}
~~~

Add `var noteHeadSize: CGSize` to `NotationLayout`, set it to
`CGSize(width: input.style.noteHeadWidth, height: input.style.noteHeadHeight)` in the
engine's `NotationLayout` initializer, and use the gameplay-default size in
`NotationLayout.empty`.

Remove voiceCollisionOffset from NotationLayoutStyle, gameplayDefault, and with(rowWidth:). Keep stemXInset until Task 4 replaces it with authored anchors.

- [ ] **Step 4: Rewrite notehead construction and delete x-mutating passes**

In Virgo/layout/NotationLayoutEngine.swift:

1. Delete VoiceCollisionColumn and NoteHeadDraft.
2. Delete containsCrossVoiceCollision.
3. Delete applyVoiceCollisionOffsets.
4. Delete applyChordDirectionUnification.
5. Delete applyBeamRunDirectionUnification.
6. Delete the position-dependent stemDirection helper.
7. Delete notePosition(for:overrides:) after buildNoteHeads resolves the override directly.
8. Add the small build records and replace buildNoteHeads with these size-limited helpers:

~~~swift
private struct NoteHeadPlacement {
    let timeColumn: NotationTimeColumn
    let timePosition: Double
    let row: Int
    let center: CGPoint
    let staffStep: Int
}

private struct BuiltNoteHead {
    let head: RenderedNoteHead
    let fallbackLaneID: String?
}

private func buildNoteHeads(
    notes: [Note],
    measures: [RenderedMeasure],
    tabGrid: TabGrid,
    input: NotationLayoutInput
) -> [RenderedNoteHead] {
    let measuresByIndex = Dictionary(
        uniqueKeysWithValues: measures.map { ($0.measureIndex, $0) }
    )
    var fallbackLaneIDs: Set<String> = []
    let heads = notes.enumerated().compactMap { index, note -> RenderedNoteHead? in
        guard let built = buildNoteHead(
            index: index,
            note: note,
            measuresByIndex: measuresByIndex,
            tabGrid: tabGrid,
            input: input
        ) else { return nil }
        if let laneID = built.fallbackLaneID {
            fallbackLaneIDs.insert(laneID)
        }
        return built.head
    }

    if !fallbackLaneIDs.isEmpty {
        Logger.warning(
            "Drum notation used NoteType fallback for source lanes: "
                + fallbackLaneIDs.sorted().joined(separator: ", ")
        )
    }

    return sortedNoteHeads(heads)
}

private func buildNoteHead(
    index: Int,
    note: Note,
    measuresByIndex: [Int: RenderedMeasure],
    tabGrid: TabGrid,
    input: NotationLayoutInput
) -> BuiltNoteHead? {
    guard let resolved = DrumNotationCatalog.resolve(
        noteType: note.noteType,
        sourceLaneID: note.sourceLaneID
    ) else {
        assertionFailure("Missing drum notation definition for \(note.noteType)")
        Logger.error("Skipping note with missing notation definition: \(note.noteType)")
        return nil
    }
    let definition = resolved.definition
    let drumType = definition.gameplayInstrument
    let position = input.notePositionOverrides[drumType] ?? definition.defaultPosition
    guard let placement = noteHeadPlacement(
        for: note,
        position: position,
        measuresByIndex: measuresByIndex,
        tabGrid: tabGrid
    ) else { return nil }

    let head = RenderedNoteHead(
        id: UInt64(index),
        sourceObjectID: ObjectIdentifier(note),
        sourceLaneID: note.sourceLaneID,
        sourceChipID: note.sourceNoteID,
        noteType: note.noteType,
        drumType: drumType,
        glyph: definition.glyph,
        variant: resolved.variant,
        voice: definition.voice,
        stemDirection: definition.defaultStemDirection,
        timeColumn: placement.timeColumn,
        timePosition: placement.timePosition,
        row: placement.row,
        position: placement.center,
        staffStep: placement.staffStep,
        interval: note.interval,
        catalogOrder: definition.catalogOrder
    )
    let fallbackLaneID = resolved.usedLaneFallback
        ? note.sourceLaneID?.uppercased()
        : nil
    return BuiltNoteHead(head: head, fallbackLaneID: fallbackLaneID)
}

private func noteHeadPlacement(
    for note: Note,
    position: GameplayLayout.NotePosition,
    measuresByIndex: [Int: RenderedMeasure],
    tabGrid: TabGrid
) -> NoteHeadPlacement? {
    let timePosition = MeasureUtils.timePosition(
        measureNumber: note.measureNumber,
        measureOffset: note.measureOffset
    )
    let measureIndex = MeasureUtils.measureIndex(from: timePosition)
    guard let measure = measuresByIndex[measureIndex] else { return nil }
    let tickIndex = tickWithinMeasure(for: note, ticksPerMeasure: tabGrid.ticksPerMeasure)
    let timeColumn = NotationTimeColumn(
        measureIndex: measureIndex,
        tickWithinMeasure: tickIndex,
        absoluteLayoutTick: measureIndex * tabGrid.ticksPerMeasure + tickIndex
    )
    let center = CGPoint(
        x: tabGrid.xPosition(in: measure, tickIndex: tickIndex),
        y: GameplayLayout.StaffLinePosition.line1.absoluteY(for: measure.row)
            + position.yOffset
    )
    return NoteHeadPlacement(
        timeColumn: timeColumn,
        timePosition: timePosition,
        row: measure.row,
        center: center,
        staffStep: staffStep(for: position)
    )
}

private func sortedNoteHeads(_ heads: [RenderedNoteHead]) -> [RenderedNoteHead] {
    heads.sorted {
        if $0.timeColumn.absoluteLayoutTick != $1.timeColumn.absoluteLayoutTick {
            return $0.timeColumn.absoluteLayoutTick < $1.timeColumn.absoluteLayoutTick
        }
        if $0.catalogOrder != $1.catalogOrder {
            return $0.catalogOrder < $1.catalogOrder
        }
        return $0.id < $1.id
    }
}
~~~

- [ ] **Step 5: Remove collision-inflated grid spacing**

In Virgo/layout/NotationLayoutEngine+TabGrid.swift, replace requiredGridColumnGap with:

~~~swift
func requiredGridColumnGap(
    notes: [Note],
    ticksPerMeasure: Int,
    input: NotationLayoutInput
) -> CGFloat {
    input.style.minimumNoteColumnGap
}
~~~

Retain the existing signature in HPA-141 to minimize call-site churn.

- [ ] **Step 6: Render resolved vector glyphs and use glyph ledger bounds**

In Virgo/views/NotationPrimitiveViews.swift, add the shape and replace NotationNoteHeadView:

~~~swift
private struct DrumNoteheadShape: Shape {
    let glyph: DrumNoteheadGlyph

    func path(in rect: CGRect) -> Path {
        Path(glyph.makePath(in: rect))
    }
}

struct NotationNoteHeadView: View, Equatable {
    let noteHead: RenderedNoteHead
    let size: CGSize

    var body: some View {
        DrumNoteheadShape(glyph: noteHead.glyph)
            .fill(
                Palette.chalk,
                style: FillStyle(eoFill: noteHead.glyph.usesEvenOddFill)
            )
            .frame(
                width: size.width,
                height: size.height
            )
            .position(noteHead.position)
    }
}
~~~

In GameplaySheetMusicView.drumNotationView, pass the size stored on the layout:

~~~swift
ForEach(notationLayout.noteHeads) { noteHead in
    NotationNoteHeadView(noteHead: noteHead, size: notationLayout.noteHeadSize)
        .equatable()
}
~~~

In buildLedgerLines, replace the generic noteHeadWidth calculation with:

~~~swift
let glyphBounds = noteHead.glyph.bounds(
    centeredAt: noteHead.position,
    size: CGSize(width: style.noteHeadWidth, height: style.noteHeadHeight)
)

return RenderedLedgerLine(
    id: "ledger_\(noteHead.id)_\(step)",
    row: noteHead.row,
    start: CGPoint(
        x: glyphBounds.minX - style.ledgerLineOverhang,
        y: y
    ),
    end: CGPoint(
        x: glyphBounds.maxX + style.ledgerLineOverhang,
        y: y
    )
)
~~~

In GameplayViewModel+Computations.swift, change:

~~~swift
let renderedSourceIDs = Set(cachedNotationLayout.noteHeads.map(\.sourceObjectID))
~~~

- [ ] **Step 7: Update SwiftUI rendering fixtures**

Inside SwiftUIRenderingCoverageTests, add this helper:

~~~swift
private func makeRenderedHead(
    id: UInt64 = 42,
    glyph: DrumNoteheadGlyph = .filledDiamond
) -> RenderedNoteHead {
    let note = Note(
        interval: .quarter,
        noteType: .snare,
        measureNumber: 1,
        measureOffset: 0
    )
    return RenderedNoteHead(
        id: id,
        sourceObjectID: ObjectIdentifier(note),
        sourceLaneID: nil,
        sourceChipID: nil,
        noteType: .snare,
        drumType: .snare,
        glyph: glyph,
        variant: .standard,
        voice: .upper,
        stemDirection: .up,
        timeColumn: NotationTimeColumn(
            measureIndex: 0,
            tickWithinMeasure: 0,
            absoluteLayoutTick: 0
        ),
        timePosition: 0,
        row: 0,
        position: CGPoint(x: 60, y: 60),
        staffStep: -4,
        interval: .quarter,
        catalogOrder: 1
    )
}
~~~

Replace testNotationPrimitiveViewsRenderExpectedSymbols with:

~~~swift
@Test("Notation primitive mounts every vector notehead")
func testNotationPrimitiveMountsEveryVectorNotehead() async throws {
    try await TestSetup.withTestSetup {
        for (index, glyph) in DrumNoteheadGlyph.allCases.enumerated() {
            let noteHead = makeRenderedHead(id: UInt64(index), glyph: glyph)
            SwiftUITestUtilities.assertViewWithEnvironment(
                NotationNoteHeadView(
                    noteHead: noteHead,
                    size: CGSize(width: 30, height: 20)
                ),
                size: CGSize(width: 120, height: 120)
            )
        }
    }
}
~~~

Use makeRenderedHead() in testNotationPrimitivesDoNotRenderYellowHighlighting instead of its old RenderedNoteHead initializer, and pass `CGSize(width: 30, height: 20)` to its NotationNoteHeadView initializer.

- [ ] **Step 8: Run the rendered-head and fixed-grid suites**

Run sequentially:

~~~bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -only-testing:VirgoTests/NotationLayoutOffsetNormalizationTests \
  -only-testing:VirgoTests/NotationLayoutEngineTabGridOverflowTests \
  -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData test

rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/SwiftUIRenderingCoverageTests \
  -only-testing:VirgoTests/GameplayViewModelComputationsTests \
  -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData test
~~~

Expected: PASS. The existing fine-grid distinct-tick regression remains green, all same-tick heads use one x, and vector notehead views mount without text symbols.

- [ ] **Step 9: Commit immutable rendered noteheads**

~~~bash
rtk git add Virgo/layout/NotationLayout.swift Virgo/layout/NotationLayoutEngine.swift \
  Virgo/layout/NotationLayoutEngine+TabGrid.swift Virgo/views/NotationPrimitiveViews.swift \
  Virgo/views/subviews/GameplaySheetMusicView.swift \
  Virgo/viewmodels/GameplayViewModel+Computations.swift \
  VirgoTests/NotationLayoutEngineTests.swift \
  VirgoTests/NotationLayoutOffsetNormalizationTests.swift \
  VirgoTests/SwiftUIRenderingCoverageTests.swift
rtk git commit -m "feat: align drum noteheads on canonical time columns"
~~~

---

### Task 4: Voice-First Stem Groups and Shared Beam Anchors

**Files:**
- Modify: Virgo/layout/gameplay.swift:133
- Modify: Virgo/layout/NotationLayout.swift:71-118
- Modify: Virgo/layout/NotationLayoutEngine.swift:19-24,390-636,700-856
- Modify: VirgoTests/NotationLayoutEngineTests.swift:626-1113
- Modify: VirgoTests/NotationLayoutEngineChordAndBeamTests.swift:126-521
- Modify: VirgoTests/NotationLayoutNotePositionOverrideTests.swift:51-70

**Interfaces:**
- Consumes: RenderedNoteHead.timeColumn, glyph geometry, canonical voice/direction, RenderedStem.noteHeadIDs, and existing RenderedBeam/RenderedFlag types.
- Produces: StemGroupKey, stemRepresentative(in:), glyphBounds(for:style:), stemAnchor(for:style:), and unbeamedStemEndY(for:start:style:). Stem and beam endpoints use one anchor calculation. Beam-run membership, levels, and flag counts remain unchanged.

- [ ] **Step 1: Write failing stem, chord-span, override, and beam-seam tests**

Replace overrideFlipsStemDirection in NotationLayoutNotePositionOverrideTests with:

~~~swift
@Test("Position override preserves canonical upper-voice stem direction")
func positionOverridePreservesCanonicalStemDirection() throws {
    let snare = Note(
        interval: .quarter,
        noteType: .snare,
        measureNumber: 1,
        measureOffset: 0
    )
    let defaultLayout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: [snare], timeSignature: .fourFour)
    )
    let overriddenLayout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(
            notes: [snare],
            timeSignature: .fourFour,
            notePositionOverrides: [.snare: .aboveLine9]
        )
    )
    let defaultHead = try #require(defaultLayout.noteHeads.first)
    let head = try #require(overriddenLayout.noteHeads.first)

    #expect(head.position.y != defaultHead.position.y)
    #expect(head.position.x == defaultHead.position.x)
    #expect(head.sourceObjectID == defaultHead.sourceObjectID)
    #expect(head.sourceLaneID == defaultHead.sourceLaneID)
    #expect(head.sourceChipID == defaultHead.sourceChipID)
    #expect(head.noteType == defaultHead.noteType)
    #expect(head.drumType == defaultHead.drumType)
    #expect(head.glyph == defaultHead.glyph)
    #expect(head.variant == defaultHead.variant)
    #expect(head.voice == .upper)
    #expect(head.voice == defaultHead.voice)
    #expect(head.stemDirection == .up)
    #expect(head.stemDirection == defaultHead.stemDirection)
    #expect(head.position.y == GameplayLayout.NotePosition.aboveLine9.absoluteY(for: 0))
}
~~~

Add these tests to NotationLayoutEngineChordAndBeamTests:

~~~swift
@Test("Same-time mixed voices use disjoint stems on opposite glyph sides")
func sameTimeMixedVoicesUseDisjointOppositeStems() throws {
    let style = NotationLayoutStyle.gameplayDefault
    let notes = [
        Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
        Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0)
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )
    let upperHead = try #require(layout.noteHeads.first { $0.voice == .upper })
    let lowerHead = try #require(layout.noteHeads.first { $0.voice == .lower })
    let upperStem = try #require(layout.stems.first { $0.noteHeadIDs.contains(upperHead.id) })
    let lowerStem = try #require(layout.stems.first { $0.noteHeadIDs.contains(lowerHead.id) })
    let size = CGSize(width: style.noteHeadWidth, height: style.noteHeadHeight)
    let upperOffset = upperHead.glyph.stemAnchorOffset(direction: .up, in: size)
    let lowerOffset = lowerHead.glyph.stemAnchorOffset(direction: .down, in: size)
    let expectedUpperStart = CGPoint(
        x: upperHead.position.x + upperOffset.x,
        y: upperHead.position.y + upperOffset.y
    )
    let expectedLowerStart = CGPoint(
        x: lowerHead.position.x + lowerOffset.x,
        y: lowerHead.position.y + lowerOffset.y
    )

    #expect(upperHead.position.x == lowerHead.position.x)
    #expect(upperStem.direction == .up)
    #expect(lowerStem.direction == .down)
    #expect(Set(upperStem.noteHeadIDs).isDisjoint(with: Set(lowerStem.noteHeadIDs)))
    #expect(upperStem.start == expectedUpperStart)
    #expect(lowerStem.start == expectedLowerStart)
}

@Test("Unbeamed stem covers a tall same-voice chord")
func unbeamedStemCoversTallSameVoiceChord() throws {
    let style = NotationLayoutStyle.gameplayDefault
    let notes = [
        Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0),
        Note(interval: .quarter, noteType: .lowTom, measureNumber: 1, measureOffset: 0)
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(
            notes: notes,
            timeSignature: .fourFour,
            notePositionOverrides: [.crash: .aboveLine9, .tom3: .belowLine6]
        )
    )
    let stem = try #require(layout.stems.first)
    let highestVisibleY = try #require(
        layout.noteHeads.map {
            $0.glyph.bounds(centeredAt: $0.position, size: layout.noteHeadSize).minY
        }.min()
    )
    let lowestHead = try #require(
        layout.noteHeads.max(by: { $0.position.y < $1.position.y })
    )
    let lowestOffset = lowestHead.glyph.stemAnchorOffset(
        direction: .up,
        in: layout.noteHeadSize
    )
    let expectedStart = CGPoint(
        x: lowestHead.position.x + lowestOffset.x,
        y: lowestHead.position.y + lowestOffset.y
    )

    #expect(layout.stems.count == 1)
    #expect(stem.direction == .up)
    #expect(stem.start == expectedStart)
    #expect(stem.end.y <= highestVisibleY - style.minimumStemExtensionPastChord)
    #expect(stem.start.y - stem.end.y >= style.stemLength)
}

@Test("Unbeamed lower-voice stem covers a tall chord from the left")
func unbeamedLowerVoiceStemCoversTallChordFromLeft() throws {
    let style = NotationLayoutStyle.gameplayDefault
    let notes = [
        Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0),
        Note(interval: .quarter, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0)
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(
            notes: notes,
            timeSignature: .fourFour,
            notePositionOverrides: [.kick: .aboveLine9, .hiHatPedal: .belowLine6]
        )
    )
    let stem = try #require(layout.stems.first)
    let lowestVisibleY = try #require(
        layout.noteHeads.map {
            $0.glyph.bounds(centeredAt: $0.position, size: layout.noteHeadSize).maxY
        }.max()
    )
    let highestHead = try #require(
        layout.noteHeads.min(by: { $0.position.y < $1.position.y })
    )
    let highestOffset = highestHead.glyph.stemAnchorOffset(
        direction: .down,
        in: layout.noteHeadSize
    )
    let expectedStart = CGPoint(
        x: highestHead.position.x + highestOffset.x,
        y: highestHead.position.y + highestOffset.y
    )

    #expect(layout.stems.count == 1)
    #expect(stem.direction == .down)
    #expect(stem.start == expectedStart)
    #expect(stem.end.y >= lowestVisibleY + style.minimumStemExtensionPastChord)
    #expect(stem.end.y - stem.start.y >= style.stemLength)
}

@Test("Shared-chord flags originate from the rendered stem")
func sharedChordFlagsOriginateFromRenderedStem() throws {
    let notes = [
        Note(interval: .sixteenth, noteType: .hiHat, measureNumber: 1, measureOffset: 0),
        Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0)
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )
    let stem = try #require(layout.stems.first)
    let firstFlag = try #require(layout.flags.first { $0.flagIndex == 0 })
    let secondFlag = try #require(layout.flags.first { $0.flagIndex == 1 })

    #expect(layout.stems.count == 1)
    #expect(layout.beams.isEmpty)
    #expect(layout.flags.count == 2)
    #expect(firstFlag.origin.x == stem.start.x + GameplayLayout.flagXOffset)
    #expect(firstFlag.origin.y == stem.end.y)
    #expect(secondFlag.origin.x == firstFlag.origin.x)
    #expect(secondFlag.origin.y == stem.end.y + GameplayLayout.flagVerticalSpacing)
}

@Test("Beam endpoint uses the shared chord stem anchor")
func beamEndpointUsesSharedChordStemAnchor() throws {
    let notes = [
        Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0),
        Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
        Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125)
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )
    let firstColumn = try #require(
        layout.noteHeads.map(\.timeColumn).min(by: {
            $0.absoluteLayoutTick < $1.absoluteLayoutTick
        })
    )
    let firstIDs = Set(
        layout.noteHeads
            .filter { $0.timeColumn == firstColumn }
            .map(\.id)
    )
    let firstStem = try #require(
        layout.stems.first { !firstIDs.isDisjoint(with: Set($0.noteHeadIDs)) }
    )
    let beam = try #require(layout.beams.first { $0.level == 0 })

    #expect(beam.start.x == firstStem.start.x)
}
~~~

- [ ] **Step 2: Run the focused stem tests and verify the red state**

Run:

~~~bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineChordAndBeamTests \
  -only-testing:VirgoTests/NotationLayoutNotePositionOverrideTests \
  -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData test
~~~

Expected: FAIL because stems still use stemXInset, tall unbeamed chords use a fixed representative length, and beam endpoints can use an arbitrary head in a chord.

- [ ] **Step 3: Replace stem inset style with a chord-extension contract**

In NotationLayoutStyle:

1. Remove stemXInset.
2. Remove the now-unused GameplayLayout.stemXOffset constant.
3. Add let minimumStemExtensionPastChord: CGFloat.
4. Set gameplayDefault to GameplayLayout.staffLineSpacing / 2.
5. Copy minimumStemExtensionPastChord in with(rowWidth:).

The default values must read:

~~~swift
stemLength: GameplayLayout.stemHeight,
stemWidth: GameplayLayout.stemWidth,
minimumStemExtensionPastChord: GameplayLayout.staffLineSpacing / 2,
beamThickness: 4,
~~~

- [ ] **Step 4: Add semantic grouping and shared anchor helpers**

At the top of NotationLayoutEngine, add:

~~~swift
private struct StemGroupKey: Hashable {
    let timeColumn: NotationTimeColumn
    let row: Int
    let voice: NotationVoice
}
~~~

Replace stemStart(for:style:) with:

~~~swift
private func stemAnchor(
    for noteHead: RenderedNoteHead,
    style: NotationLayoutStyle
) -> CGPoint {
    let offset = noteHead.glyph.stemAnchorOffset(
        direction: noteHead.stemDirection,
        in: CGSize(width: style.noteHeadWidth, height: style.noteHeadHeight)
    )
    return CGPoint(
        x: noteHead.position.x + offset.x,
        y: noteHead.position.y + offset.y
    )
}

private func glyphBounds(
    for noteHead: RenderedNoteHead,
    style: NotationLayoutStyle
) -> CGRect {
    noteHead.glyph.bounds(
        centeredAt: noteHead.position,
        size: CGSize(width: style.noteHeadWidth, height: style.noteHeadHeight)
    )
}

private func stemRepresentative(
    in noteHeads: [RenderedNoteHead]
) -> RenderedNoteHead? {
    guard let direction = noteHeads.first?.stemDirection else {
        return nil
    }
    let ordered = noteHeads.sorted {
        if $0.position.y != $1.position.y {
            return $0.position.y < $1.position.y
        }
        if $0.catalogOrder != $1.catalogOrder {
            return $0.catalogOrder < $1.catalogOrder
        }
        return $0.id < $1.id
    }
    return direction == .up ? ordered.last : ordered.first
}

private func unbeamedStemEndY(
    for noteHeads: [RenderedNoteHead],
    start: CGPoint,
    style: NotationLayoutStyle
) -> CGFloat {
    guard let direction = noteHeads.first?.stemDirection else {
        return start.y
    }
    switch direction {
    case .up:
        let highestVisibleY = noteHeads.map {
            glyphBounds(for: $0, style: style).minY
        }.min() ?? start.y
        return min(
            start.y - style.stemLength,
            highestVisibleY - style.minimumStemExtensionPastChord
        )
    case .down:
        let lowestVisibleY = noteHeads.map {
            glyphBounds(for: $0, style: style).maxY
        }.max() ?? start.y
        return max(
            start.y + style.stemLength,
            lowestVisibleY + style.minimumStemExtensionPastChord
        )
    }
}
~~~

- [ ] **Step 5: Rewrite stem groups and point beam/flag geometry at the shared anchor**

In buildStems:

1. Group heads needing stems by StemGroupKey(timeColumn:row:voice:).
2. Select stemRepresentative(in:) for each group.
3. Compute start with stemAnchor(for:style:).
4. Keep the current outermost-beam selection.
5. For unbeamed groups, call unbeamedStemEndY(for:start:style:).
6. Build stable IDs from absoluteLayoutTick, row, voice, and direction.

The return block must have this form:

~~~swift
let grouped = Dictionary(grouping: headsNeedingStems) { head in
    StemGroupKey(
        timeColumn: head.timeColumn,
        row: head.row,
        voice: head.voice
    )
}

return grouped.compactMap { key, group in
    guard let representative = stemRepresentative(in: group) else {
        Logger.error("Empty stem group for \(key)")
        return nil
    }
    let start = stemAnchor(for: representative, style: style)
    let candidateBeams = group.flatMap { beamsByNoteHeadID[$0.id] ?? [] }
    let outermostBeam = representative.stemDirection == .up
        ? candidateBeams.min(by: { $0.start.y < $1.start.y })
        : candidateBeams.max(by: { $0.start.y < $1.start.y })
    let endY: CGFloat
    if let outermostBeam,
       let beamY = beamEndY(
           for: representative,
           beam: outermostBeam,
           style: style
       ) {
        endY = beamY
    } else {
        endY = unbeamedStemEndY(for: group, start: start, style: style)
    }

    return RenderedStem(
        id: "stem_\(key.timeColumn.absoluteLayoutTick)_r\(key.row)_"
            + "\(key.voice.rawValue)_\(representative.stemDirection.rawValue)",
        noteHeadIDs: group.map(\.id).sorted(),
        direction: representative.stemDirection,
        start: start,
        end: CGPoint(x: start.x, y: endY)
    )
}
~~~

In beamEndY, replace the old stemStart lookup with the shared helper:

~~~swift
let stemX = stemAnchor(for: noteHead, style: style).x
~~~

In buildFlags, keep the existing coveredLevelsByNoteHead calculation, then replace the old stem-end index, FlagGroupKey, and return expression with this block. The full RenderedStem is indexed so a mixed-glyph chord's flag representative cannot recompute a different x from the stem representative:

~~~swift
var stemByNoteHeadID: [UInt64: RenderedStem] = [:]
for stem in stems {
    for noteHeadID in stem.noteHeadIDs {
        stemByNoteHeadID[noteHeadID] = stem
    }
}

let flaggedHeads = noteHeads.filter { $0.interval.needsFlag }
var bestByKey: [StemGroupKey: RenderedNoteHead] = [:]
for head in flaggedHeads {
    let key = StemGroupKey(
        timeColumn: head.timeColumn,
        row: head.row,
        voice: head.voice
    )
    if let existing = bestByKey[key],
       existing.interval.flagCount >= head.interval.flagCount {
        continue
    }
    bestByKey[key] = head
}
let representatives = Set(bestByKey.values.map(\.id))

return flaggedHeads
    .filter { representatives.contains($0.id) }
    .flatMap { noteHead -> [RenderedFlag] in
        let coveredLevels = coveredLevelsByNoteHead[noteHead.id] ?? 0
        let totalFlags = noteHead.interval.flagCount
        guard coveredLevels < totalFlags else { return [] }
        guard let stem = stemByNoteHeadID[noteHead.id] else {
            Logger.error("Missing rendered stem for flagged head \(noteHead.id)")
            return []
        }
        let flagOrigin = CGPoint(
            x: stem.start.x + GameplayLayout.flagXOffset,
            y: stem.end.y
        )

        return (coveredLevels..<totalFlags).map { flagIndex in
            let flagLevel = flagIndex - coveredLevels
            let yMultiplier = coveredLevels == 0
                ? CGFloat(flagLevel)
                : CGFloat(flagLevel + 1)
            let yOffset = stem.direction == .up
                ? yMultiplier * GameplayLayout.flagVerticalSpacing
                : -yMultiplier * GameplayLayout.flagVerticalSpacing

            return RenderedFlag(
                id: "flag_\(noteHead.id)_\(flagIndex)",
                noteHeadID: noteHead.id,
                stemDirection: stem.direction,
                flagIndex: flagIndex,
                origin: CGPoint(x: flagOrigin.x, y: flagOrigin.y + yOffset)
            )
        }
    }
~~~

In beams(for:style:), derive the first and last chord groups from levelHeads' first and last time columns, choose stemRepresentative(in:) for each group, and use their shared anchors:

~~~swift
let firstColumn = firstHead.timeColumn
let lastColumn = lastHead.timeColumn
guard firstColumn != lastColumn else {
    return nil
}
let firstChord = noteHeads.filter { $0.timeColumn == firstColumn }
let lastChord = noteHeads.filter { $0.timeColumn == lastColumn }
guard let firstRepresentative = stemRepresentative(in: firstChord),
      let lastRepresentative = stemRepresentative(in: lastChord) else {
    return nil
}
let sharedY = sharedBeamY(for: noteHeads, level: level, style: style)
let start = CGPoint(
    x: stemAnchor(for: firstRepresentative, style: style).x,
    y: sharedY
)
let end = CGPoint(
    x: stemAnchor(for: lastRepresentative, style: style).x,
    y: sharedY
)
guard abs(end.x - start.x) > BeamGroupingConstants.comparisonTolerance else {
    return nil
}
~~~

Keep beamRuns, beamSegments, sharedBeamY, beam levels, RenderedBeam fields, and flag counts unchanged.

- [ ] **Step 6: Rewrite legacy direction and inset expectations**

Make these exact test changes:

- Rename highCrashStemPointsDown to highCrashStemPointsUp; assert the crash head and stem are `.up`, then assert the rendered stem uses the glyph-derived anchor below.
- In downStemBeamsAlignToDownStemXCoordinates, allDownStemBeamedNotesReachBeam, and downStemSixteenthNotesReachOutermostBeam, replace every `.crash` note with `.bass`, retain the beam-count/level assertions, and assert `.down`.
- Rename downStemCrashFlagHasDownDirection to lowerVoiceBassFlagHasDownDirection, replace its note with `.bass`, and retain the `.down` flag assertion.
- Replace every style.stemXInset expectation in highCrashStemPointsUp, snareStemPointsUp, consecutiveSixteenthsCreateTwoBeamLevels, consecutiveEighthsCreateOneBeamLevel, downStemBeamsAlignToDownStemXCoordinates, allUpStemBeamedNotesReachBeam, allDownStemBeamedNotesReachBeam, allSixteenthBeamedNotesReachBothBeamLevels, and downStemSixteenthNotesReachOutermostBeam with the glyph-derived assertion below.
- Keep sameTimeSameVoiceDuplicateEighthsDoNotCreateZeroLengthBeam; additionally assert two rendered head IDs, one unique timeColumn, one shared stem, and no beam.
- Keep differentVoiceNotesAtSameTimeGetSeparateStems; additionally assert the two stem noteHeadID sets are disjoint.
- Rename sameVoiceChordWithMixedDirectionsSharesOneStem to canonicalUpperVoiceChordSharesOneUpStem and assert the shared stem is `.up` with both IDs.
- Rename sameVoiceChordWithMixedDirectionsYieldsSingleBeamGroup to canonicalUpperVoiceChordYieldsSingleBeamGroup and retain one beam/two stems while asserting all beam/stem directions are `.up`.
- Rename chordUnificationDoesNotSplitBeamRunWithAdjacentSoloNote to canonicalUpperVoiceChordAndSoloFormOneBeam; remove the unification commentary, retain the one-beam membership checks, and assert every upper head is `.up`.
- Rename beamRunUnificationPrefersFarthestFromMiddle to canonicalUpperVoiceIgnoresDistanceFromMiddle; retain the three-head beam and assert its direction set is exactly `[.up]`.
- In downStemBeamsAreHorizontalAtCorrectExtremum and secondaryBeamStacksBelowPrimaryBeamForDownStems, replace `.crash` sequences with `.bass` and retain the down-branch Y assertions.
- Rename sameVoiceChordWithMixedDirectionsDoesNotDuplicateFlags to canonicalUpperVoiceChordDoesNotDuplicateFlags; retain crash plus snare, one shared stem, no beams, and exactly one flag.
- Rename stemlessNoteDoesNotDriveChordStemDirection to stemlessHeadIsExcludedFromSharedStemMembership. Require the crash and snare heads plus the one rendered stem, assert the crash ID is absent, the snare ID is present, and the stem is `.up`.
- In downStemMultiFlagStacksTowardNoteHead, replace the isolated `.crash` with `.hiHatPedal` and retain the two-flag negative-y stacking assertions.
- Keep all remaining flag-count, residual-flag, beam-level, and zero-length-beam expectations unchanged.

Use this assertion form for every former stemXInset check:

~~~swift
let anchorOffset = noteHead.glyph.stemAnchorOffset(
    direction: noteHead.stemDirection,
    in: CGSize(width: style.noteHeadWidth, height: style.noteHeadHeight)
)
let expectedAnchor = CGPoint(
    x: noteHead.position.x + anchorOffset.x,
    y: noteHead.position.y + anchorOffset.y
)
#expect(stem.start == expectedAnchor)
~~~

- [ ] **Step 7: Run all focused HPA-141 suites**

Run sequentially:

~~~bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/DrumNotationCatalogTests \
  -only-testing:VirgoTests/DrumTypeExtensionsAndConstantsTests \
  -only-testing:VirgoTests/DTXFileParserTests \
  -only-testing:VirgoTests/DTXNormalizationTests \
  -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData test

rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -only-testing:VirgoTests/NotationLayoutEngineChordAndBeamTests \
  -only-testing:VirgoTests/NotationLayoutNotePositionOverrideTests \
  -only-testing:VirgoTests/NotationLayoutOffsetNormalizationTests \
  -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData test

rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/SwiftUIRenderingCoverageTests \
  -only-testing:VirgoTests/GameplayViewModelComputationsTests \
  -only-testing:VirgoTests/GameplayViewModelVisualUpdatesTests \
  -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData test
~~~

Expected: PASS with no split-x, direction, anchor, parser, rendering, playhead, or scoring regressions.

- [ ] **Step 8: Run full verification**

Run each command only after the previous one exits:

~~~bash
rtk xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests \
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData

rtk swiftlint lint

rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' build
~~~

After the shell commands pass, call XcodeBuildMCP session_show_defaults. If its simulator is not an iPad, call session_set_defaults with projectPath `Virgo.xcodeproj`, scheme `Virgo`, and one iPad name returned by the MCP simulator list. Then call build_sim with those defaults. Never choose an iPhone entry.

Expected:

- Full VirgoTests: PASS with zero failures.
- SwiftLint: exit 0 with no newly introduced violations.
- macOS build: BUILD SUCCEEDED.
- XcodeBuildMCP iPad simulator build: BUILD SUCCEEDED and the target remains device family 2.

- [ ] **Step 9: Perform the targeted visual sanity check**

Using XcodeBuildMCP:

1. Call session_show_defaults.
2. Set projectPath to Virgo.xcodeproj, scheme to Virgo, and an available iPad simulator if defaults are missing.
3. Build and run the app on that iPad simulator.
4. Open the bundled Soukyuu e no Shouka chart from Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx and enter gameplay.
5. Inspect a simultaneous upper/lower chord and confirm all heads share one vertical time column, upper stems attach right/up, lower stems attach left/down, vector glyphs remain recognizable, and ledger lines meet glyph bounds.
6. Capture one screenshot as temporary verification evidence only; do not add it to the repository.

Expected: the visual check matches the geometry assertions and does not introduce HPA-144 golden assets.

- [ ] **Step 10: Commit voice-first stem geometry**

~~~bash
rtk git add Virgo/layout/gameplay.swift Virgo/layout/NotationLayout.swift \
  Virgo/layout/NotationLayoutEngine.swift \
  VirgoTests/NotationLayoutEngineTests.swift \
  VirgoTests/NotationLayoutEngineChordAndBeamTests.swift \
  VirgoTests/NotationLayoutNotePositionOverrideTests.swift
rtk git commit -m "feat: route drum stems by notation voice"
~~~

- [ ] **Step 11: Confirm the final branch state**

Run:

~~~bash
rtk git status --short --branch
rtk git log -4 --oneline
~~~

Expected: the worktree is clean and the latest four feature commits are catalog, vector geometry, canonical columns, and voice-first stems.
