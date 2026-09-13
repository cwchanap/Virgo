# HPA-164 Measured Formatting and Shared Tick Geometry Design

**Issue:** HPA-164 — `[Notation] Add measured formatting and shared tick geometry to DrumNotation`

**Scope:** Second PR in the HPA-163 → HPA-164 → HPA-166 migration. Move horizontal notation formatting and musical-position lookup into the existing `DrumNotation` package, cut Virgo over to that geometry, and delete the superseded fixed-grid notation renderer. Final beam-topology migration, tuplet/control/articulation parity, and the complete package-owned static sheet remain HPA-166.

**Baseline reviewed:** `main` at `8a29b68f7afeb29c162e2587fad26c192d71beda` after HPA-163 / PR #65 merged.

## Current state

HPA-163 established the package and Bravura primitive geometry but intentionally left horizontal layout in Virgo:

- `DrumNotation` owns Bravura resources, percussion glyph semantics, staff-space-scaled glyph metrics, and primitive SwiftUI views.
- `VirgoNotationAdapter` is the single app-to-package seam, but today it maps primitive types and flag-paint policy only.
- Virgo still owns `TabGrid`, one chart-wide `tickWidth`, measure sizing, row packing, note/rest/control X placement, and playhead X lookup.
- `NotationLayoutEngine` still contains both `.timeline(RhythmLayoutSnapshot)` and `.legacy(notes:controls:timeSignature:)` notation paths.
- Existing beam topology is timing/voice based and does not need formatted X coordinates, while stem/beam rendering does consume final X coordinates.
- HPA-581 already removed the old production `cachedBeatPositions` cache. HPA-164 must not recreate it.

The task is therefore horizontal engraving ownership and one geometry map, not a renderer rewrite.

## Decision

Add one deterministic measured formatter to the existing `DrumNotation` target and make its result the only notation X-coordinate authority.

```text
Virgo DTX / SwiftData / rhythm analysis
                |
                v
       RhythmLayoutSnapshot
                |
                +--> Virgo beam-topology prepass (X-independent)
                |
                v
       VirgoNotationAdapter
  - expands trailing measures
  - applies staff overrides
  - filters unsupported/unprinted formatter inputs
  - resolves visible flag footprint
  - maps one numeric formatting style
                |
                v
 DrumNotation.ResolvedNotationInput
                |
                v
      NotationFormatter.format
                |
                v
      DrumNotation.FormattedNotation
       |                         |
       |                         +--> position(measure, tick)
       |                                  |
       |                                  +--> live playhead / row lookup
       v
Virgo transitional composition
(Y, stems, beams, tuplets, controls, marks)
                |
                v
         one NotationLayout
```

There is no second formatter, no fallback `TabGrid`, no old/new feature flag, and no generalized constraint solver.

## Ownership and composition contract

The cutover is defined field-by-field so Virgo cannot accidentally retain a second X map.

| App/output value | Owner after HPA-164 | Composition rule |
| --- | --- | --- |
| `RenderedMeasure.row/xOffset/width` | package formatted measures | copy directly; do not recompute from app spacing formulas |
| logical onset X | package `logicalColumnX` | shared by every event at the same exact tick |
| visual notehead X | package `headCenterX` | copy by opaque integer note ID |
| stem/beam X | Virgo existing stem representative + package glyph anchor | keep one undisplaced stem axis; do **not** move the stem to a displaced head |
| note-attached dots/ledger/articulation X | Virgo from positioned head | follow `headCenterX`; they do not redefine timing X |
| `RenderedNoteHead.position.y` | Virgo | derive from formatted row + existing staff position/override |
| printed rest X | package | normal rests use logical column; full-measure rest is centered after width is known |
| control onset X | package logical position | Virgo keeps semantic/Y drawing; controls add no HPA-164 collision extent |
| live playhead X + row | package `position(measureIndex:localTick:)` | view model uses result directly; adds no X offset |
| trailing empty measures | Virgo before formatting | reuse current `expandedRhythmMeasures` policy, then convert them to package values |
| flag collision footprint | package, from Virgo-resolved visible flag duration | formatter measures the actual visible uncovered flag glyph horizontally |
| actual beam/stem/flag topology and drawing | Virgo | existing builders consume formatted heads; HPA-166 owns topology migration |
| measure bars | package measure bounds consumed by Virgo | no `TabGrid` end-X formula |
| no valid snapshot | no notation formatter | clear/install empty notation and use existing non-notation beat UI/runtime fallback |

`RhythmEventPosition` remains Virgo's musical identity. Package positions copy only measure/local ticks; absolute tick remains derivable from the owning measure.

## Stem axis and displaced heads

HPA-141 correctly removed voice-based timing offsets. HPA-164 introduces only the conventional same-stem staff-second displacement needed to avoid overlapping adjacent noteheads.

The critical distinction is:

- `logicalColumnX` is the musical onset/playhead coordinate;
- `headCenterX` is the visual center of an individual notehead and may be displaced;
- the shared stem remains on the **undisplaced stem-side axis**.

This matches the VexFlow reference: displaced noteheads move by roughly one head width minus half the stem width so they still overlap/touch the stem, while `getStemX()` remains based on the note's undisplaced/base X.

For HPA-164:

- up-stem seconds follow VexFlow's bottom-to-top displacement ordering;
- down-stem seconds follow VexFlow's top-to-bottom displacement ordering;
- mixed stem directions are never shifted apart merely because they represent different voices;
- non-adjacent same-stem heads remain centered unless a longer adjacent chain requires the reference alternation;
- current Virgo `stemRepresentative` stays the stem-axis owner: bottom stem-side head for up stems and top stem-side head for down stems. With the pinned displacement ordering, that representative remains undisplaced.

Do **not** add a public `stemColumnX` merely to duplicate this invariant. Add it only if implementation proves a supported chord cannot be expressed through the existing representative + package head geometry. Tests must prove both heads still touch the shared stem after displacement.

## Small public package model

Expose only values the HPA-164 formatter actually uses. Do not publish a package `NotationVoice`, engraving-support mirror, beat groups, tuplets, app diagnostics, or redundant absolute ticks.

Representative boundary:

```swift
public struct NotationTickPosition: Hashable, Sendable {
    public let measureIndex: Int
    public let localTick: Int
}

public struct ResolvedMeasure: Hashable, Sendable {
    public let index: Int
    public let startTick: Int
    public let durationTicks: Int
}

public struct ResolvedNote: Hashable, Sendable {
    public let id: Int
    public let position: NotationTickPosition
    public let stemDirection: NotationStemDirection
    public let staffStep: Int
    public let noteheadStyle: PercussionNoteheadStyle
    public let duration: NotationDuration
    public let dotCount: Int
    /// Nil when unflagged or fully covered by beams. When non-nil, this is the
    /// canonical visible flag glyph whose horizontal footprint must be reserved.
    public let visibleFlagDuration: NotationFlagDuration?
}

public struct ResolvedRest: Hashable, Sendable {
    public let id: Int
    public let position: NotationTickPosition
    public let duration: NotationDuration
    public let dotCount: Int
    public let isFullMeasure: Bool
}

public struct ResolvedControl: Hashable, Sendable {
    public let id: Int
    public let position: NotationTickPosition
}

public struct ResolvedNotationInput: Hashable, Sendable {
    public let ticksPerWholeNote: Int
    public let measures: [ResolvedMeasure]
    public let notes: [ResolvedNote]
    public let rests: [ResolvedRest]
    public let controls: [ResolvedControl]
}
```

Rules:

- `ResolvedNote.id` maps directly from `RhythmEventID.rawValue`; no stringification or parallel ID table.
- Controls use their `RhythmEventID.rawValue` as their opaque integer ID.
- Printed rests only enter package input; unprinted rests are filtered in Virgo rather than becoming invisible spacing anchors.
- Rest IDs may use a deterministic adapter-local integer namespace/index because note/rest/control IDs live in separate collections.
- `absoluteTick` is validated/derived as `measure.startTick + localTick`; it is not public input state.
- Unsupported-measure suppression stays in Virgo. The package formats only the visible/allowed formatter input it is given.

Virgo retains the full source `RhythmLayoutSnapshot` for voice, tuplets, warnings and control semantics used during transitional post-format composition.

## Visible flag footprint before formatting

Flags are the one modifier footprint HPA-164 must include because measured per-measure spacing removes the accidental slack provided by chart-wide `tickWidth`.

Do not move beam topology into `DrumNotation`. Instead, before package formatting, Virgo uses its existing X-independent `NotationBeamTopologyBuilder` inputs from the full snapshot to determine whether each stem group has visible uncovered flag levels.

The adapter then supplies only the horizontal paint intent needed by the formatter:

- unflagged or fully beam-covered stem → `visibleFlagDuration = nil`;
- all required levels uncovered → canonical duration-specific flag (`.eighth`, `.sixteenth`, `.thirtySecond`, `.sixtyFourth`);
- partially uncovered levels → `.eighth` component footprint, matching current `flagPaintCommands` component policy.

The topology prepass may use provisional row identity because beam groups are already measure-local; row wrapping cannot change whether a flag is covered.

The formatter uses `PercussionGlyphMetrics.flag(...)` plus the stem axis/attachment geometry to union the flag's horizontal painted bounds into its column extent. Actual flag objects and beam topology remain Virgo-owned after formatting.

Add a consistency test proving the pre-format visible flag classification agrees with the post-format `FlagPaintCommand` policy for isolated and partially-beamed examples.

## Numeric formatting style

Use one plain `Sendable` scalar style. The field `minimumInterColumnClearance` is intentionally **edge-to-edge clearance**, not a rename of the old center-to-center `minimumNoteColumnGap`.

```swift
public struct NotationFormattingStyle: Hashable, Sendable {
    public let availableRowWidth: CGFloat
    public let rowLeadingInset: CGFloat
    public let staffSpace: CGFloat
    public let stemWidth: CGFloat
    public let minimumInterColumnClearance: CGFloat
    public let minimumQuarterNoteSpacing: CGFloat
    public let measureSpacing: CGFloat
    public let leadingMeasureInset: CGFloat
    public let trailingMeasureInset: CGFloat
    public let rhythmDotRadius: CGFloat
    public let rhythmDotSpacing: CGFloat
}
```

Virgo's default mapping is explicit:

- `availableRowWidth` = resolved app row width, with the existing 900pt floor;
- `rowLeadingInset` = `GameplayLayout.leftMargin` = 100;
- `staffSpace` = current staff-line spacing = 20;
- `stemWidth` = 2;
- `minimumInterColumnClearance` = **8pt** at the default scale;
- `minimumQuarterNoteSpacing` = current `GameplayLayout.uniformSpacing` = 50;
- `measureSpacing` = 12;
- `leadingMeasureInset` = current bar + content lead = 52;
- `trailingMeasureInset` = 0;
- dot radius/spacing map from existing `NotationLayoutStyle`.

The 8pt clearance preserves the intent of the old 28pt center pitch for the common Bravura X-black head at staff-space 20: approximately 28pt legacy pitch − 20pt head width = 8pt edge clearance. Wider/narrower glyphs then expand/contract content-aware spacing rather than inheriting a fake fixed pitch.

This is a semantic conversion. Never map old `minimumNoteColumnGap = 28` directly into edge-to-edge clearance.

Only `VirgoNotationAdapter.formattingStyle(...)` may construct this package style. Both synchronous relayout (`cacheNotationLayout`) and detached initial preparation must route through the same adapter/preparer path; there is no second hand-written style mapping.

## Measured formatting algorithm

Use one deterministic left-to-right pass. No iterative constraint solver is needed.

### 1. Build exact logical columns

For each measure:

1. collect resolved notes, printed rests and controls by exact `localTick`;
2. create one logical time column per exact tick;
3. add explicit start (`0`) and end (`durationTicks`) anchors for empty/trailing measures;
4. keep caller IDs unchanged.

Controls participate in the tick map but contribute zero collision width in HPA-164.

### 2. Apply the closed staff-second displacement rule

Within each exact onset and stem direction, apply only the pinned VexFlow staff-second behavior described above. Store `headCenterX` separately from `logicalColumnX`. No voice-based X offsets exist.

### 3. Measure column geometry

Column extents union only horizontally material geometry needed before HPA-166:

- natural HPA-163 notehead bounds after displacement;
- rhythm dots;
- natural printed-rest bounds;
- visible uncovered flag bounds from `visibleFlagDuration`.

Keep these deferred:

- beams themselves;
- tuplet brackets/labels;
- stop/choke/damp marks;
- articulations (their app footprint is not a horizontal spacing driver here);
- warning/feel marks.

A full-measure rest retains its timing anchor but is visually centered only after final measure width is known.

### 4. Place columns by rhythm plus collision clearance

For adjacent anchors `a` and `b`:

```text
rhythmicGap = minimumQuarterNoteSpacing
              * (b - a)
              * 4
              / ticksPerWholeNote

collisionGap = left.rightExtent
               + minimumInterColumnClearance
               + right.leftExtent

requiredGap = max(rhythmicGap, collisionGap)
```

Use integer/rational-safe arithmetic until final `CGFloat` conversion. Collision expansion stays local to the affected interval.

### 5. Derive independent measure widths

Each measure starts at `rowLeadingInset`. Tick 0 is placed at:

```text
measure.x + leadingMeasureInset
```

The measure width is:

```text
leadingMeasureInset
+ formatted tick-0 → end-anchor span
+ trailingMeasureInset
```

Never compress below that collision-free width. An over-wide measure remains natural width and occupies a row alone.

### Locked default-density regression

At the default style, the existing `sixteenth-run-4-4` first measure must remain comfortably inside a 900pt row and has a hand-computable target width of **490pt**:

- 52pt leading inset;
- 15 adjacent X-black sixteenth columns at 28pt pitch (`10 + 8 + 10`); 
- final note → measure-end anchor = 18pt (`10 + 8`), larger than the 12.5pt sixteenth rhythmic baseline;
- total = `52 + 15*28 + 18 = 490`.

This replaces accidental preservation of the old 500pt `TabGrid` width with a stable behavioral contract. Use a small floating-point tolerance; do not regenerate goldens until this numeric invariant is green.

## Greedy row packing

Reuse the existing greedy policy, changing only width authority:

- start each row at `rowLeadingInset`;
- include `measureSpacing`;
- wrap before a complete measure would cross `availableRowWidth`;
- never split a measure;
- keep an over-wide first measure at natural width;
- row wrapping never changes exact tick identity or per-measure internal spacing.

All package X values already use final sheet-local coordinates. Virgo adds nothing afterward.

## Authoritative tick lookup

`FormattedNotation.position(measureIndex:localTick:)` is the only notation musical-position → row/X lookup.

Rules:

1. reject non-finite input; clamp only explicitly documented tiny boundary drift;
2. exact anchors return exact `logicalColumnX`;
3. between anchors, interpolate only inside the owning measure;
4. start/end anchors make empty/control-only/trailing measures resolvable;
5. never interpolate across measure or row boundaries;
6. displaced heads and centered full-measure rests never replace timing X.

There is intentionally no chart-wide X-per-tick scale after HPA-164.

## Virgo integration

### One preparation/composition route

Both initial detached preparation and synchronous relayout must call the same pure preparation operation:

```text
GameplayNotationPreparationRequest
  -> VirgoNotationAdapter.resolvedNotation(...)
  -> VirgoNotationAdapter.formattingStyle(...)
  -> NotationFormatter.format(...)
  -> Virgo transitional composition
  -> GameplayNotationPreparedState
```

`cacheNotationLayout()` may invoke that operation synchronously when required by the current test/resize flow, but it must not rebuild package style or call a parallel formatter/engine route.

### Transitional composition

After formatting:

- copy formatted measures directly;
- build noteheads with package `headCenterX` and app-owned Y;
- keep current `stemRepresentative` selection and derive shared stem/beam X from the **undisplaced representative** + package glyph stem anchor;
- place rests/controls from package timing/special visual geometry and app-owned semantic/Y data;
- run existing app beam/stem/flag/ledger/tuplet/mark builders without changing their topology;
- use formatted measure bounds for bars;
- retain immutable `FormattedNotation` for live playhead lookup.

The displaced-head regression must assert:

- the shifted head's center differs from `logicalColumnX`;
- the stem axis remains the undisplaced/base axis;
- both adjacent heads touch/overlap that stem according to the pinned reference;
- beam endpoints use the same stem axis;
- playhead X remains `logicalColumnX`.

## No-snapshot behavior

Delete the notation fallback in `cacheNotationLayout()` as part of the `.legacy` cutover:

- valid snapshot → package formatter path;
- no valid snapshot → empty notation + existing non-notation beat UI/runtime fallback;
- fatal rhythm behavior remains owned by the current rhythm runtime.

Do not synthesize a second notation input from `cachedNotes`.

## Fixed-grid deletion checklist

Delete or relocate every production dependency whose only owner is the old notation grid:

- `NotationLayoutTimingInput.legacy` / obsolete timing enum;
- `NotationLayoutInput(notes:controlEvents:timeSignature:...)`;
- `NotationLayoutEngine.layoutLegacy`;
- `TabGrid` / `TabGrid.fallback`;
- chart-wide `tickWidth` / compatibility `ticksPerMeasure`;
- `TabGrid.tickIndex(forBeatWithinMeasure:)`;
- `RenderedMeasure.contentStartX`;
- `NotationLayout.empty` fallback grid state;
- `buildTabGrid(...)` and fixed-grid measure builders;
- rest/control overloads taking `TabGrid`;
- `cacheNotationLayout()`'s old no-snapshot notation branch;
- fixed-grid beat-fraction notation lookup;
- fixed-grid-only tests/invariants.

Move useful pure timing helpers to their real owner instead of preserving a compatibility shell.

## Regression strategy before golden regeneration

Numeric/behavioral invariants land **before** text-golden updates:

- sparse measure width is strictly less than its intentionally dense neighbor for a named fixture;
- adjacent measured painted extents, including visible flags, are disjoint by at least `minimumInterColumnClearance` when rhythmic spacing does not already exceed it;
- `sixteenth-run-4-4` measure 0 is 490pt at the default style and its right edge remains inside the 900pt row;
- same-tick logical X is stable even when a notehead displaces;
- stem/beam X stays on the undisplaced stem axis;
- playhead at an event tick equals that event's logical X.

Only after these pass should raster/visual checks be accepted and all affected goldens regenerated.

## Legacy-test migration contract

HPA-164 remains exactly **one ticket → one PR**. The migration is large enough to deserve its own implementation task and commit, not a second PR.

Before deleting `.legacy`, run a complete repository search for `NotationLayoutInput(notes:` and append any newly discovered files to this disposition table.

| Current test file | HPA-164 disposition |
| --- | --- |
| `NotationLayoutEngineTests.swift` | move pure horizontal/measure-spacing cases to package tests; convert retained renderer/bounds cases to snapshot + preparer; delete fallback/tickWidth compatibility assertions |
| `NotationLayoutEngineChordAndBeamTests.swift` | keep as snapshot/preparer integration; migrate constructors; retain topology and new undisplaced-stem-axis regression |
| `NotationLayoutRestTests.swift` | move pure horizontal rest geometry to package tests; keep voice/rest rendering integration through snapshot |
| `NotationLayoutOffsetNormalizationTests.swift` | delete legacy-only normalization coverage when superseded by canonical timeline tests; relocate any still-valid timing assertion to its real owner |
| `NotationLayoutNotePositionOverrideTests.swift` | keep integration via adapter/preparer to prove override → staff step/Y mapping |
| `NotationLayoutEngineTabGridOverflowTests.swift` | delete fixed-grid overflow/LCM layout behavior; move any still-relevant timing-limit validation to rhythm-timeline tests |
| `BeamHookPreservationTests.swift` | keep app integration and migrate setup to snapshot/preparer; no topology-policy change |
| `RhythmLayoutSnapshotBuilderTests.swift` | remove legacy layout construction; keep snapshot/adapter semantic coverage |
| `RhythmRenderingTests.swift` | keep timeline integration; replace `TabGrid` X assertions with formatted logical-position lookup; tuplets/feel remain app-owned |

Do this as one dedicated migration/deletion commit before broad golden regeneration. Do not add a compatibility constructor merely to reduce the diff.

## Risks

### Risk 1: flag-footprint/topology drift

The formatter receives only a scalar visible-flag footprint classification, while actual topology/drawing remains in Virgo. If those policies diverge, spacing may reserve too much or too little width.

Mitigation: derive both from the same topology inputs, preserve current `flagPaintCommands` policy, and add isolated + partially-beamed consistency tests before cutover.

### Risk 2: legacy-test migration breadth

Deleting `.legacy` touches many old layout tests and can hide behavior loss behind mechanical rewrites.

Mitigation: use the explicit per-file disposition table, a dedicated commit, no compatibility shim, full serial suite before golden updates, and review deletions separately from expected geometry churn.

### Risk 3: golden churn masking geometry regressions

Every horizontal digest changes once `tickWidth` disappears.

Mitigation: land the non-vacuous numeric invariants above first, run raster/visual checks, then regenerate goldens and review only expected spacing/row/attachment changes.

## Explicit non-goals

- migrating beam topology itself into the package;
- package-owned tuplets, stop/choke/damp marks, articulations, warnings or feel-mark footprint;
- complete static notation view / staff / clef / meter extraction;
- DTX or rhythm-inference changes;
- virtualization, Canvas/Metal, pagination or another rendering backend;
- arbitrary pitched notation or broad VexFlow compatibility;
- compatibility renderer or old/new toggle.

## Acceptance criteria

- One existing `DrumNotation` target owns measured X geometry and tick lookup.
- Package input has no `NotationVoice`, engraving-support mirror, beat groups, tuplets, absolute tick, unprinted rests, or stringified note IDs.
- `visibleFlagDuration` reserves actual visible flag footprint without moving beam topology into the package.
- `minimumInterColumnClearance` is 8pt at the default scale and is not mapped from the old 28pt center pitch.
- `sixteenth-run-4-4` measure 0 is 490pt at default style and remains inside the 900pt row.
- Same-tick events share one logical column; mixed voices are not shifted apart.
- Same-stem seconds may displace noteheads, but shared stem/beam X remains on the undisplaced stem-side axis.
- All package X values share one sheet-local coordinate space with explicit `rowLeadingInset` and no post-format app offset.
- Dense measures no longer globally widen unrelated sparse measures.
- Adjacent note/dot/rest/visible-flag extents satisfy the formatter clearance invariant.
- `FormattedNotation.position(...)` is the only notation tick→row/X map used by the live playhead.
- Both synchronous relayout and detached preparation use the same adapter style + preparation/composition route.
- No valid snapshot means no notation formatter; existing non-notation beat fallback remains available.
- `.legacy`, `TabGrid`, `contentStartX`, old beat-fraction notation conversion, and compatibility-only overloads/tests are removed.
- `cachedBeatPositions` is not reintroduced.
- Numeric invariants pass before golden regeneration; package tests, visual/raster checks, full serial macOS tests, SwiftLint and iPad build pass.

## PR boundary

Exactly one PR for HPA-164. It owns the compact package formatter contract, measured columns/rows, visible flag footprint, authoritative tick geometry, explicit Virgo composition seam, and fixed-grid deletion. The legacy-test migration is a dedicated task/commit inside this PR. HPA-166 remains owner of beam-topology migration, tuplets/control/articulation parity, and the complete reusable static sheet.