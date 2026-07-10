# Same-Time Drum Voices and Notehead/Stem Placement Design

- **Date:** 2026-07-10
- **Status:** Design approved; awaiting written-spec review
- **Scope:** Align simultaneous drum voices on one canonical time column, replace font-dependent notehead placement with deterministic vector geometry, and centralize drum notation identity without absorbing later beam or articulation tickets.
- **Linear:** [HPA-141](https://linear.app/cwchanap/issue/HPA-141/align-same-time-drum-voices-and-rewrite-noteheadstem-placement)
- **Parent:** [HPA-97](https://linear.app/cwchanap/issue/HPA-97/fix-drum-tab-rendering-spacing-beams-flags-rests-and-stop-note)

## 1. Context

HPA-139 and HPA-140 are complete. Imported notes now preserve raw DTX identity and normalized timing metadata, and `NotationLayoutEngine` now places notes and the purple playhead through one fixed `TabGrid` timeline.

HPA-141 addresses the next boundary. The current implementation first computes the correct grid x-coordinate, then `applyVoiceCollisionOffsets(...)` moves upper-voice heads right and lower-voice heads left. That makes simultaneous hits appear at different times even though HPA-140 assigned them the same tick.

The current renderer also has no stable notehead geometry contract:

- `NotationNoteHeadView` draws `DrumType.symbol` through a SwiftUI `Text` view.
- Different Unicode symbols have font-dependent bounds.
- Stem attachment is approximated by adding or subtracting one fixed x inset from the text center.
- Ledger lines use one generic notehead width rather than the selected glyph's bounds.
- `RenderedNoteHead` stores only the collapsed `DrumType`, so open/closed hi-hat and crash/china/splash identity is unavailable to downstream notation code.
- DTX lane mapping, `NoteType` to `DrumType` mapping, default staff positions, glyphs, voices, and stem directions are defined in separate switches.

The result is visually fragile and makes later beam and articulation work depend on duplicated or incomplete identity rules.

## 2. Goals

- Keep all notes assigned to the same normalized tick on exactly one x-coordinate.
- Make the HPA-140 `TabGrid` position the immutable notehead-center anchor.
- Separate upper and lower voices through stem side and direction, not notehead timing position.
- Give same-voice chords one shared stem and mixed-voice chords one stem per voice.
- Replace Unicode text metrics with vector versions of Virgo's existing glyph vocabulary.
- Define one exhaustive canonical drum notation catalog.
- Preserve source `NoteType`, DTX lane ID, DTX note ID, gameplay instrument, and notation variant independently from glyph appearance.
- Give stems, beams, ledger lines, and views one shared glyph-geometry contract.
- Preserve existing persistence, scoring, input, playback, fixed-grid, and playhead behavior.
- Add focused geometry and mapping regression coverage for the newly explicit contracts.

## 3. Non-Goals

- No new SwiftData fields, migration, or backfill.
- No change to scoring, MIDI/keyboard matching, `DrumBeat`, or audio behavior.
- No fixed-grid resolution, playhead, wrapping, or row-scrolling redesign from HPA-140.
- No beat-group beam topology, partial beams, hooks, flags, or tails; HPA-142 owns those behaviors.
- No visible open/closed/choke/stop/articulation marks; HPA-143 owns those primitives.
- No broad fixture or golden-image suite; HPA-144 owns that coverage.
- No tuplets, swing, dotted rhythm, compound meter, or variable measure length; HPA-145 owns those cases.
- No heuristic grace-note or displaced-note placement. A future displaced note must have explicit source metadata and its own design contract.
- No replacement with a music font or SMuFL dependency.

## 4. Approved Decisions

The approved design choices are:

1. **Voice-first stems:** upper voice always stems up from the right side; lower voice always stems down from the left side.
2. **Vectorized existing vocabulary:** retain Virgo's circle, diamond, cross, bullseye, half-circle, and hollow shapes, but draw them with deterministic vector geometry.
3. **Preserve variants now, render them later:** the catalog and rendered identity distinguish open/closed/pedal hi-hat, left bass, left crash, china, splash, and related variants, while HPA-143 remains responsible for visible articulation overlays.
4. **Geometry-first canonical map:** centralize identity and notation defaults before building rendered heads and stems.

## 5. Architecture

### 5.1 Canonical catalog

Add `Virgo/constants/DrumNotation.swift` as the focused notation domain file. It contains the exhaustive `DrumNotationCatalog`, `NotationVoice`, `StemDirection`, and the catalog's other value types. The existing voice and direction declarations move out of `NotationLayout.swift` so the catalog owns the concepts it publishes.

Define the lane and instrument records as:

```swift
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
```

`DrumNotationVariant` has the explicit cases `standard`, `leftBass`, `closedHiHat`, `openHiHat`, `pedalHiHat`, `leftCrash`, `crash`, `ride`, `highTom`, `midTom`, `floorTom`, `china`, and `splash`. A definition's `defaultVariant` is used for manual notes; a matching `DrumNotationLane` supplies a more specific source-lane variant.

Lane IDs remain uppercase strings in the catalog so the notation domain does not depend on the parser's `DTXLane` type. `DTXLane.noteType`, `DrumType.from(noteType:)`, default position lookup, voice lookup, stem direction, and rendered glyph lookup will delegate to this catalog rather than maintain independent switches.

`catalogOrder` gives same-time notes a deterministic ordering when several heads have identical geometry. It is not a timing offset.

### 5.2 Vector glyph geometry

`DrumNoteheadGlyph` is an exhaustive enum for the existing visual vocabulary:

- filled circle
- filled diamond
- cross
- bullseye
- open circle
- left-half circle
- right-half circle
- lower-half circle
- hollow diamond

Each glyph exposes deterministic Core Graphics geometry in normalized notehead coordinates:

```swift
enum DrumNoteheadGlyph: Hashable {
    // Exhaustive cases listed above.

    var normalizedBounds: CGRect { get }
    func makePath(in rect: CGRect) -> CGPath
    func stemAnchorOffset(direction: StemDirection, in size: CGSize) -> CGPoint
}
```

The renderer scales `normalizedBounds` into the style's notehead size, adds the returned anchor offset to the canonical center, and wraps `makePath(in:)` in a SwiftUI `Path`. Glyph bounds and left/right stem anchors are therefore computed from the same authored vector geometry and are never measured from a rendered font.

`NotationLayout` carries the resolved notehead size from `NotationLayoutStyle` so the SwiftUI view scales the path with the same dimensions used for stems and ledger lines. The SwiftUI notehead view renders that generated path. Beams, stems, ledger lines, and the view therefore consume one geometry definition.

Glyphs whose outline does not intersect the generic side midpoint use authored contact points. In particular, the cross uses a right/lower contact for an up-stem and a left/upper contact for a down-stem, and its stroked diagonal centerlines are inset so the final stroked path remains inside `normalizedBounds`.

### 5.3 Canonical time-column identity

Introduce a small integer key after each note is converted into the layout's resolved HPA-140 grid:

```swift
struct NotationTimeColumn: Hashable {
    let measureIndex: Int
    let tickWithinMeasure: Int
    let absoluteLayoutTick: Int
}
```

The key is computed as:

```swift
absoluteLayoutTick = measureIndex * tabGrid.ticksPerMeasure + tickWithinMeasure
```

This works for imported normalized notes, mixed imported/legacy notes, and manual notes because it is created after HPA-140 has resolved and scaled the layout grid.

### 5.4 Rendered notehead identity

Evolve `RenderedNoteHead` so downstream layout and rendering no longer depend on a collapsed glyph identity. Its stored contract is:

```swift
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
```

`sourceObjectID` replaces the current ambiguous `sourceNoteID` name for the SwiftData object identity. `sourceChipID` holds the raw DTX note ID when one exists.

The canonical center's x-coordinate is always the `TabGrid` mapping. No collision phase may mutate it.

### 5.5 Data flow

The layout flow becomes:

```text
Note
  -> DrumNotationCatalog resolution
  -> HPA-140 time-column and x mapping
  -> RenderedNoteHead with semantic identity and glyph geometry
  -> per-time-column, per-voice stem grouping
  -> existing beam/flag integration
  -> SwiftUI vector primitives
```

There is no intermediate stage that shifts notehead x for a voice collision.

## 6. Canonical Drum Legend

| DTX lane | `NoteType` | Gameplay instrument | Default position | Vector glyph | Voice/stem | Preserved variant |
|---|---|---|---|---|---|---|
| `13`, `1C` | `.bass` | `.kick` | below line 2 | filled circle | lower/down | bass or left bass |
| `12` | `.snare` | `.snare` | line 3 | filled diamond | upper/up | standard |
| `14` | `.highTom` | `.tom1` | space 3-4 | left-half circle | upper/up | high tom |
| `15` | `.midTom` | `.tom2` | space 2-3 | right-half circle | upper/up | mid tom |
| `17` | `.lowTom` | `.tom3` | line 2 | lower-half circle | upper/up | floor/low tom |
| `11` | `.hiHat` | `.hiHat` | line 5 | cross | upper/up | closed hi-hat |
| `18` | `.openHiHat` | `.hiHat` | line 5 | cross | upper/up | open hi-hat |
| `1B` | `.hiHatPedal` | `.hiHatPedal` | below line 1 | cross | lower/down | pedal hi-hat |
| `1A`, `16` | `.crash` | `.crash` | above line 5 | bullseye | upper/up | left crash or crash |
| `19` | `.ride` | `.ride` | space 4-5 | open circle | upper/up | ride |
| none | `.china` | `.crash` | above line 5 | bullseye | upper/up | china |
| none | `.splash` | `.crash` | above line 5 | bullseye | upper/up | splash |
| none | `.cowbell` | `.cowbell` | line 4 | hollow diamond | upper/up | standard |

For lane groups with distinct source meaning, such as `13` versus `1C` and `1A` versus `16`, the resolver derives the lane-specific `DrumNotationVariant` while keeping the shared base definition fields.

Raw DTX note IDs are preserved on the rendered identity but do not affect glyph selection in HPA-141 because the current parser has no validated note-ID-specific notation semantics.

## 7. Notehead Placement

### 7.1 Same-time definition

Two notes are simultaneous when their `NotationTimeColumn.absoluteLayoutTick` values are equal. The renderer must not use floating `measureOffset` proximity, a rounded x-coordinate, or source-array order to decide simultaneity.

### 7.2 X-coordinate invariant

For every rendered head:

```swift
head.position.x == tabGrid.xPosition(in: measure, tickIndex: head.timeColumn.tickWithinMeasure)
```

This equality is exact within the `CGFloat` values returned by the same mapping call. Same-time kick, snare, and hi-hat heads therefore share one center x-coordinate.

Remove the following collision-specific mechanisms:

- `VoiceCollisionColumn`
- `NoteHeadDraft` when it exists only to carry a collision column
- `applyVoiceCollisionOffsets(...)`
- `NotationLayoutStyle.voiceCollisionOffset`
- the extra `2 * voiceCollisionOffset` contribution in fixed-grid column-gap calculation

`minimumNoteColumnGap` remains the readability contract for distinct occupied time columns. Removing collision padding can compact a chart and alter wrapping, but the result remains deterministic and fixed-grid based.

### 7.3 Y-coordinate and overrides

The catalog provides the default staff position. Existing `DrumNotationSettingsManager` overrides remain keyed by `DrumType` and may replace only the resolved y-position/staff step.

An override must not change:

- canonical x
- source identity
- glyph
- notation variant
- voice
- stem direction

Open and closed hi-hat continue to move together because both use gameplay instrument `.hiHat` for settings compatibility.

### 7.4 Identical geometry

Each source note remains a distinct rendered identity even if multiple notes resolve to the same x, y, and glyph. Identical vectors may overdraw in deterministic catalog order. The renderer must not invent a horizontal displacement to expose duplicates.

## 8. Stem and Chord Geometry

### 8.1 Voice-first direction

- Upper voice always uses `.up` and the glyph's right-side anchor.
- Lower voice always uses `.down` and the glyph's left-side anchor.

Position overrides never flip a voice's direction. This replaces the current position-dependent upper-voice direction heuristic.

### 8.2 Stem grouping

Stem grouping uses this semantic key rather than rounded x values:

```swift
struct StemGroupKey: Hashable {
    let timeColumn: NotationTimeColumn
    let row: Int
    let voice: NotationVoice
}
```

Direction is determined by voice and is therefore not needed to distinguish groups. The resulting behavior is:

- same-time, same-voice heads share one stem;
- same-time upper and lower heads get two stems;
- different ticks never share a stem;
- notes on different rendered rows never share a stem.

The current chord-direction and beam-run-direction unification passes become unnecessary because every member of a voice has one stable direction.

### 8.3 Chord attachment and length

For an unbeamed up-stem chord:

- attach the stem at the right anchor of the lowest notehead;
- extend upward past the highest notehead.

For an unbeamed down-stem chord:

- attach the stem at the left anchor of the highest notehead;
- extend downward past the lowest notehead.

The opposite chord extreme is the authored visible glyph bound, not merely the notehead center, so the minimum extension clears the complete vector silhouette.

Stem length must satisfy both the default length and full chord coverage:

```text
required stem span = max(
  default stem length,
  chord vertical span + minimum extension beyond the opposite extreme
)
```

Add `NotationLayoutStyle.minimumStemExtensionPastChord` for the minimum extension beyond the opposite chord extreme rather than embedding an unexplained numeric literal.

### 8.4 Beam and flag interface

HPA-141 does not change which notes beam, how beam levels are selected, or how flags and hooks work. It changes the geometry interface they consume:

- beam endpoints use the same glyph stem-anchor helper as stems;
- beamed stems extend to the existing beam geometry;
- residual flags use the actual shared `RenderedStem.start.x` and `RenderedStem.end.y`, then apply the existing flag offsets;
- current beam grouping remains separated by voice and direction.

HPA-142 may later replace beam grouping and partial-beam behavior without needing to reinterpret notehead geometry.

### 8.5 Drawing order and ledger lines

Keep stems and beams behind noteheads so the vector head masks the attachment seam. Ledger-line length derives from the selected glyph's authored bounds plus `ledgerLineOverhang`, not from one generic text frame width.

## 9. Catalog Resolution and Error Handling

Resolution follows these rules:

1. If a note has a known lane matching its `NoteType`, use the lane-specific definition and variant.
2. If the lane is absent, unfamiliar, or mismatched but `NoteType` is known, use the `NoteType` default definition.
3. Preserve raw lane and note IDs regardless of exact or fallback resolution.
4. Do not drop a playable note merely because its source lane is unfamiliar.
5. Aggregate unfamiliar lane fallbacks into one warning per layout pass rather than logging once per note.
6. If a `NoteType` has no catalog definition, assert in debug, log the programming error, and skip only that unrenderable primitive.

Exhaustive catalog tests must make rule 6 unreachable in supported builds.

Manual notes and previously persisted notes with no HPA-139 source metadata resolve by `NoteType`. Invalid or mixed timing metadata continues through HPA-140's existing fallback-grid path before the notation catalog is involved.

## 10. Compatibility

- `Note` persistence is unchanged.
- Existing `Note` initializers remain source compatible.
- `DrumType` remains the gameplay/input/scoring identity.
- `DrumBeat` construction and input matching remain unchanged.
- Existing DTX lane behavior remains unchanged, including `1C -> .bass`.
- HPA-140 remains authoritative for tick resolution, note/playhead x mapping, measure width, and wrapping.
- `noteHeadPositionsByID` and `noteHeadIDsByTimePosition` continue to address every source note.
- Current performance behavior remains cached; vector geometry is pure value data and must not add per-frame observation or text measurement.
- Rendering remains compatible with macOS and iPadOS; no iPhone destination or layout is introduced.

## 11. Tests

### 11.1 Catalog coverage

Add `VirgoTests/DrumNotationCatalogTests.swift` with a focused `DrumNotationCatalogTests` suite asserting:

- every `NoteType` has exactly one default definition;
- every playable `DTXLane` resolves exactly once;
- `.bpm` and `.bgm` remain non-playable;
- `13` and `1C` both use `.bass`/`.kick` while preserving distinct lane variants;
- `11`, `18`, and `1B` preserve closed, open, and pedal hi-hat identity;
- `1A`, `16`, and `19` preserve left-crash, crash, and ride identity;
- `.china` and `.splash` retain their source `NoteType` while sharing `.crash` gameplay identity;
- catalog gameplay-instrument mappings match existing `DrumType.from(noteType:)` behavior;
- all glyph bounds and anchors are finite;
- every generated path stays within its authored bounds and each stem anchor contacts the glyph;
- up-stem anchors are on the right and down-stem anchors are on the left;
- known `NoteType` plus unknown lane falls back without losing raw identity.

### 11.2 Layout geometry

Update or add `NotationLayoutEngineTests` for:

- simultaneous kick, snare, and hi-hat centers exactly equal one another and the `TabGrid` x;
- four simultaneous kick/snare quarter-note pairs produce four unique x columns, not eight;
- near-equal source offsets resolving to one tick align exactly;
- distinct ticks on a 4,096-tick grid remain distinct and exactly grid aligned;
- adjacent occupied columns retain `minimumNoteColumnGap` without collision padding;
- same-time same-voice chords share one stem;
- same-time mixed voices create one upper/right/up stem and one lower/left/down stem;
- widely spread chords extend beyond the full chord span;
- custom position overrides change y and ledger lines but preserve x, identity, glyph, voice, and direction;
- identical-position duplicates remain individually addressable;
- ledger-line width follows glyph bounds;
- normalized offset-1 representations that resolve to one time column also share x.

Tests that currently require collision separation must be rewritten around the new contract, including:

- near-identical cross-voice heads splitting;
- simultaneous quarters producing one x per voice;
- kick left of snare at the same time;
- quantized same-column heads receiving opposite offsets.

Tests that currently use crash to exercise down-stem behavior must use a lower-voice instrument instead. Crash is upper voice and therefore up-stem under the approved policy.

### 11.3 Rendering and compatibility

- Add SwiftUI rendering smoke coverage for every vector glyph.
- Keep existing stem/beam/flag integration tests green after they are updated for voice-first direction.
- Keep DTX parser tests green after lane mapping delegates to the catalog.
- Keep HPA-140 fixed-grid, playhead, fallback, and wrapping regression suites green.
- Keep gameplay data-loading and scoring tests green to confirm identity separation does not alter gameplay behavior.

Broad screenshot fixtures and golden comparisons remain deferred to HPA-144. Verification requires a targeted manual sanity check of one mixed-voice chord on macOS or iPad, but does not commit golden coverage.

## 12. Verification

Run focused suites sequentially with parallel testing disabled and one shared DerivedData path:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/DrumNotationCatalogTests \
  -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData test

rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -only-testing:VirgoTests/NotationLayoutEngineChordAndBeamTests \
  -only-testing:VirgoTests/NotationLayoutNotePositionOverrideTests \
  -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData test

rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/DTXFileParserTests \
  -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData test
```

Then run the complete macOS unit target using the repository command with `-parallel-testing-enabled NO`, followed by:

- `rtk swiftlint lint`
- a macOS build
- an iPad-simulator compatibility build using an available iPad destination, never an iPhone destination
- a targeted visual sanity check for one same-time upper/lower chord

## 13. Acceptance Criteria

- Same-time kick, snare, and hi-hat notehead centers have exactly the same x-coordinate.
- Every rendered head's x-coordinate equals the HPA-140 `TabGrid` mapping for its integer time column.
- No collision or chord phase mutates notehead x.
- Same-time same-voice heads share one stem.
- Same-time upper and lower voices render separate stems on opposite glyph sides.
- Upper voice is consistently up/right and lower voice consistently down/left, including after note-position overrides.
- Stem geometry covers the full chord span and uses the same anchors as beam geometry.
- Vector glyph bounds, stem anchors, and ledger-line extents are deterministic across macOS and iPadOS.
- The canonical catalog is the sole authority for supported lane, `NoteType`, gameplay instrument, position, glyph, voice, direction, and variant mappings.
- Open, closed, and pedal hi-hat plus crash, china, splash, ride, tom, left-bass, and cowbell identity remains distinguishable in rendered data even when base glyphs are shared.
- Unknown source lanes with a known `NoteType` render through a conservative fallback rather than disappearing.
- Existing scoring, input, parser timing, fixed-grid, playhead, and fallback behavior remains unchanged.
- Focused suites and the full `VirgoTests` target pass with parallel testing disabled.

## 14. Risks and Mitigations

### Vector parity

Authored paths may initially look slightly different from the Unicode symbols. Preserve the same semantic silhouettes, test bounds and anchors as pure geometry, and perform one targeted visual sanity check.

### Wrapping changes

Removing collision padding can reduce tick width and change how many measures fit on a row. This is an intentional consequence of removing false horizontal voice separation; deterministic fixed-grid behavior remains unchanged.

### Catalog coupling

Parser, gameplay, settings, and renderer code all consume parts of the catalog. Keep the catalog as pure immutable value data, store lane IDs as strings, and expose narrow lookup APIs so parser code does not depend on SwiftUI views.

### Existing direction-dependent tests

Several tests currently rely on high crash using a down-stem. Rewrite those cases to assert the approved voice-first policy and use kick or pedal hi-hat for down-stem geometry.

### Deferred articulation visibility

Open/closed/china/splash identity will be present before all visible marks exist. Make the preserved variant explicit in `RenderedNoteHead` so HPA-143 can add overlays without another identity migration.

## 15. Implementation Footprint

- `Virgo/constants/DrumNotation.swift` (new canonical catalog and glyph/variant types)
- `Virgo/constants/Drum.swift` (delegate existing identity mappings)
- `Virgo/layout/gameplay.swift` (delegate the existing default-position facade)
- `Virgo/layout/NotationLayout.swift` (time-column and rendered-head contracts)
- `Virgo/layout/NotationLayoutEngine.swift` (remove offsets; build semantic heads and stems)
- `Virgo/layout/NotationLayoutEngine+TabGrid.swift` (remove collision padding)
- `Virgo/views/NotationPrimitiveViews.swift` (vector notehead rendering)
- `Virgo/views/subviews/GameplaySheetMusicView.swift` (pass resolved notehead size to the vector view)
- `Virgo/viewmodels/GameplayViewModel+Computations.swift` (follow the rendered source-identity rename)
- `Virgo/utilities/DTXFileParser.swift` (delegate lane identity without semantic changes)
- `VirgoTests/DrumNotationCatalogTests.swift` (new catalog/geometry coverage)
- `VirgoTests/NotationLayoutEngineTests.swift`
- `VirgoTests/NotationLayoutEngineChordAndBeamTests.swift`
- `VirgoTests/NotationLayoutNotePositionOverrideTests.swift`
- `VirgoTests/NotationLayoutOffsetNormalizationTests.swift`
- `VirgoTests/SwiftUIRenderingCoverageTests.swift`
- `VirgoTests/DrumTypeExtensionsAndConstantsTests.swift`
- `VirgoTests/DTXFileParserTests.swift`

This remains one implementation-plan-sized change because it rewrites one renderer boundary while explicitly leaving rhythmic grouping, articulation rendering, and broad golden coverage to their existing sibling tickets.
