# HPA-163 DrumNotation Package Foundation and Native Glyphs Design

**Issue:** HPA-163 — `[Notation] Create reusable DrumNotation package with VexFlow references and native glyphs`

**Scope:** First PR in the existing HPA-163 → HPA-164 → HPA-166 migration. Establish the reusable package and trustworthy primitive geometry without changing horizontal formatting or beam topology.

**Baseline reviewed:** `main` at `3f0a665a02f37256c17f1d2779bb0db630c9c907`.

## Current state

Virgo already separates normalized rhythm from final painting, but primitive engraving is still app-owned:

- `DrumNoteheadGlyph` defines handwritten notehead paths and approximate stem anchors.
- `RenderedNoteHead` carries that app-specific glyph enum through layout.
- `NotationPrimitiveViews.swift` hand-draws noteheads, rests, flags, and the open-hi-hat circle.
- `NotationLayoutEngine+Beams.swift` uses glyph bounds/anchors for stems and ledger lines.
- `RenderedNoteHead/RenderedRest/RenderedFlag/RenderedArticulation.paintedBounds` still describe the handwritten shapes.
- `DrumTabRenderProbeTests.notationOverlay` rebuilds the primitive stack separately from production.
- `AppFonts` is process-global app font registration and is the wrong ownership boundary for Bravura.

HPA-163 should replace those primitive-specific responsibilities while keeping DTX identity, rhythm inference, `TabGrid`, rows, beam grouping, and playhead routing unchanged.

## Decision

Create one local Swift package at `Packages/DrumNotation/` with one library target and one test target. The package owns:

- the closed percussion glyph vocabulary needed by Virgo;
- pinned Bravura font resources and matching SMuFL metadata;
- font-derived primitive geometry and notehead stem anchors;
- native SwiftUI/CoreText/CoreGraphics primitive rendering.

Virgo owns:

- DTX/source identities, `NoteType`/`DrumType`, notation variants and scoring identity;
- voice, staff positions and user position overrides;
- normalized rhythm and absolute event positions;
- fixed-grid horizontal placement and row packing;
- beam topology, playback, scrolling/playhead policy and theme.

Dependency direction stays one-way:

```text
Virgo DTX / rhythm / fixed layout
              |
              v
Virgo/layout/VirgoNotationAdapter
              |
              v
 DrumNotation semantic primitives
      |                 |
      v                 v
 Bravura/SMuFL      SwiftUI/CoreText
```

No WebView, shipping JavaScript, renderer protocol, fallback renderer, publication workflow, or compatibility layer is introduced.

## Reference version policy

Use VexFlow as the semantic reference, but do not build a Node reference harness in HPA-163.

- Pin **VexFlow 5.0.0** in documentation as the migration reference.
- Pin **`@vexflow-fonts/bravura` 1.0.2 / Bravura 1.392**, matching the Bravura lineage used by VexFlow 5.0.0.
- Vendor `bravura.otf`, `metadata.json`, and `LICENSE.txt` from `vexflow/vexflow-fonts` commit `b2bc3a6070225e4d395966b36de76c36a9429b1c`.
- Record the VexFlow version, Bravura package/version, source commit and closed glyph mapping table in `Packages/DrumNotation/README.md`.

HPA-163 has a small closed glyph table, so a Node/jsdom generator whose output no Swift test reads is YAGNI. If executable VexFlow comparison is needed for mixed beams/modifiers, add the minimal harness in HPA-166 where those comparisons become acceptance criteria.

## Package shape

```text
Packages/DrumNotation/
├── Package.swift
├── README.md
├── Sources/DrumNotation/
│   ├── Model/PrimitiveTypes.swift
│   ├── Glyphs/SMuFLGlyphCatalog.swift
│   ├── Glyphs/BravuraFont.swift
│   ├── Rendering/PrimitiveViews.swift
│   └── Resources/Bravura/
│       ├── Bravura.otf
│       ├── metadata.json
│       └── LICENSE.txt
└── Tests/DrumNotationTests/
    ├── PackageBoundaryTests.swift
    ├── GlyphCatalogTests.swift
    ├── BravuraGeometryTests.swift
    └── PrimitiveViewTests.swift
```

Models/Glyphs/Rendering are folders, not separate modules.

## Public primitive API

Expose only semantic values and metrics needed by Virgo:

```swift
public enum NotationDuration: String, CaseIterable, Sendable {
    case whole, half, quarter, eighth, sixteenth, thirtySecond, sixtyFourth
}

public enum PercussionNoteheadStyle: String, CaseIterable, Sendable {
    case normal, x, diamond
}

public enum NotationStemDirection: String, Sendable {
    case up, down
}

public enum PercussionArticulation: String, Sendable {
    case open
}

public struct PrimitiveGlyphMetrics: Equatable, Sendable {
    public let paintedBounds: CGRect
}

public struct NoteheadMetrics: Equatable, Sendable {
    public let paintedBounds: CGRect
    public let stemAnchorOffset: CGPoint
}

public enum PercussionGlyphMetrics {
    public static func notehead(
        style: PercussionNoteheadStyle,
        duration: NotationDuration,
        stemDirection: NotationStemDirection,
        size: CGSize
    ) -> NoteheadMetrics

    public static func rest(
        duration: NotationDuration,
        size: CGSize
    ) -> PrimitiveGlyphMetrics

    public static func flag(
        duration: NotationDuration,
        direction: NotationStemDirection,
        size: CGSize
    ) -> PrimitiveGlyphMetrics

    public static func articulation(
        _ articulation: PercussionArticulation,
        size: CGSize
    ) -> PrimitiveGlyphMetrics

    public static func naturalFlagSize(
        duration: NotationDuration,
        direction: NotationStemDirection,
        staffSpace: CGFloat
    ) -> CGSize
}
```

Public views mirror the same semantic inputs and explicit sizes:

```swift
PercussionNoteheadView(style:duration:size:color:)
NotationRestGlyphView(duration:size:color:)
NotationFlagGlyphView(duration:direction:size:color:)
PercussionArticulationView(articulation:size:color:)
```

Raw SMuFL code points, `CGFont`/`CTFont`, decoded metadata and generic glyph lookup remain internal.

## Closed percussion legend

| Virgo semantics | Package style | SMuFL family |
| --- | --- | --- |
| kick, snare, high/mid/floor tom | `.normal` | `noteheadWhole` / `noteheadHalf` / `noteheadBlack` |
| closed/open/pedal hi-hat, crash, ride, china, splash | `.x` | `noteheadXWhole` / `noteheadXHalf` / `noteheadXBlack` |
| cowbell | `.diamond` | `noteheadDiamondWhole` / `noteheadDiamondHalf` / `noteheadDiamondBlack` |

Open hi-hat uses the X-family head plus SMuFL `pictOpen` (`U+E7F8`) at Virgo's existing articulation position. Closed hi-hat has no extra mark. Pedal hi-hat remains distinguished by semantic identity, lower voice and staff position.

The internal catalog contains only those heads, rests through 64th, flags through 64th in both directions, and `pictOpen`.

## Bravura geometry transform

`BravuraFont.swift` loads package resources through `Bundle.module` and creates package-private font/path state. Do not route through `AppFonts` or `Bundle.main`.

For a glyph:

1. resolve the SMuFL scalar to a Bravura glyph;
2. obtain its font-authored path and raw font-coordinate bounds;
3. compute one uniform scale to fit the requested box;
4. build one affine transform that translates the raw path bounds to the requested local center, scales uniformly, and flips the Y axis for SwiftUI coordinates;
5. transform the path with that exact affine transform;
6. for noteheads, convert `stemUpSE`/`stemDownNW` from SMuFL staff-space coordinates into font coordinates relative to the glyph origin, then apply the **same complete affine transform including the centering translation**.

The anchor must not be transformed with scale/Y-flip alone. SMuFL anchors are glyph-origin coordinates, so omitting the path-centering translation would shift stems, beams, flags and ledger geometry away from the painted head.

Missing required package resources, accepted glyphs or required notehead anchors are programmer/package errors. Fail loudly with a precondition rather than rendering a blank fallback.

### Geometry tests

For every accepted notehead family × duration family × both stem directions:

- independently transform the metadata anchor using the raw font path bounds and compare it with `NoteheadMetrics.stemAnchorOffset`;
- assert the transformed anchor is on/within a small epsilon of the stem-side painted-path extent and within the perpendicular painted span;
- assert the fitted path is nonempty and its bounds are inside the requested box;
- assert the package metrics are the values consumed by Virgo stem, ledger and painted-bounds code.

These tests must pin translation correctness, not merely `isFinite`.

## Virgo adapter and size policy

Place the app projection beside the existing layout seams at:

`Virgo/layout/VirgoNotationAdapter.swift`

It owns exhaustive pure conversion and the one app sizing policy:

- `NoteType` → `PercussionNoteheadStyle`;
- `NoteInterval` → `NotationDuration`;
- `StemDirection` → `NotationStemDirection`;
- `NotationRestDuration` → `NotationDuration?`;
- `.indeterminate` rest → `nil` / no paint;
- `.fullMeasure` rest → `.whole` glyph;
- `RenderedArticulationKind.openHiHat` → `.open`;
- notehead box = existing `NotationLayoutStyle.noteHeadSize`;
- whole/full-measure/half rest box = existing `fullMeasureRestWidth × fullMeasureRestHeight`;
- other rest box = existing `restSymbolWidth × restSymbolHeight`;
- articulation box = existing `articulationDiameter × articulationDiameter`;
- flag box = `PercussionGlyphMetrics.naturalFlagSize(..., staffSpace: style.staffLineSpacing)`, preserving Bravura's natural flag aspect instead of squeezing canonical flags into the old `8×8` frame.

The package never accepts Virgo types or theme values.

## Pure flag paint commands

Keep `NotationLayoutEngine.buildFlags` unchanged. It remains the source of uncovered beam levels.

Do not put sibling-collapse logic inside `GameplayDrumNotationView` or `NotationFlagView`. Define one pure app-owned value and function in `VirgoNotationAdapter.swift`:

```swift
struct FlagPaintCommand: Identifiable, Equatable {
    let id: String
    let origin: CGPoint
    let duration: NotationDuration
    let direction: NotationStemDirection
    let size: CGSize
}

static func flagPaintCommands(
    flags: [RenderedFlag],
    heads: [RenderedNoteHead],
    style: NotationLayoutStyle
) -> [FlagPaintCommand]
```

Policy per head:

- expected uncovered levels = `0..<head.interval.flagCount`;
- if actual uncovered levels exactly equal that set, emit one command from the level-0 flag using the head's canonical duration-specific Bravura flag and suppress sibling level commands;
- otherwise emit one `.eighth` flag command per existing uncovered `RenderedFlag`, preserving each original origin;
- preserve deterministic original `layout.flags` ordering.

Both production `GameplayDrumNotationView` and `DrumTabRenderProbeTests.notationOverlay` consume this same command list. `NotationFlagView` paints one command and never searches sibling flags itself.

This removes the production/test fork while leaving beam topology for HPA-166.

## Painted-bounds cutover

Painting and bounds must use the same package metrics.

Update app bounds so:

- `RenderedNoteHead.paintedBounds` translates the same `NoteheadMetrics.paintedBounds` used for stem/ledger geometry;
- `RenderedRest.paintedBounds` translates package rest metrics using `restDuration(for:)` and the adapter rest size;
- `RenderedArticulation.paintedBounds` translates package articulation metrics;
- flag bounds in `NotationLayout.calculatePaintedBounds` are calculated from `VirgoNotationAdapter.flagPaintCommands(...)` and package flag metrics, not from the old `RenderedFlag` 8×8 rectangle.

Delete `RenderedFlag.paintedBounds` if no caller remains.

This allows expected visual metric drift while preventing paint outside `layout.paintedBounds`, which feeds content width/height and clipping decisions.

## Remove the old glyph vocabulary

`DrumNoteheadGlyph` does not survive this PR.

Remove:

- `DrumNotationDefinition.glyph`;
- `RenderedNoteHead.glyph`;
- constructor plumbing in `NotationLayoutEngine.swift` and test fixtures;
- custom notehead path/bounds/anchor helpers;
- handwritten rest/flag/open-articulation drawing.

`DrumType.symbol` remains app-owned for settings/key-mapping UI and becomes a direct normalized switch:

- kick/snare/toms → `●`;
- hi-hat/pedal/crash/ride → `×`;
- cowbell → `◇`.

This text icon is not a second score-engraving vocabulary.

## Production primitive cutover

`NotationPrimitiveViews.swift` stays as the thin app mounting layer:

- noteheads delegate to `PercussionNoteheadView`;
- printed supported rests delegate to `NotationRestGlyphView`;
- open-hi-hat articulation delegates to `PercussionArticulationView`;
- `NotationFlagView` accepts one `FlagPaintCommand` and delegates to `NotationFlagGlyphView`.

Stems, beams, ledger lines, bars, dots, tuplets, feel marks, warnings and stop marks stay Virgo-owned in HPA-163.

## Regression coverage

Package tests own:

- exact semantic → SMuFL scalar mapping;
- bundled font/resource resolution;
- raw-path → fitted-path transform;
- notehead anchor translation/edge relationship;
- primitive metric/view construction.

Virgo tests own:

- DTX/catalog semantics and variants;
- exhaustive adapter mappings, including `NotationRestDuration`;
- `FlagPaintCommand` collapse/partial coverage behavior;
- stem and ledger use of package notehead metrics;
- package-derived painted bounds for heads/rests/flags/articulation;
- production and probe use of the same flag commands;
- existing fixed-grid, beam-membership and playhead invariants.

Explicit compile/behavior edits include:

- `VirgoTests/NotationLayoutDigest.swift`: remove `head.glyph`; serialize package style/variant semantics instead;
- `VirgoTests/DrumTabGoldenTests.swift`: preserve open/closed/pedal distinction through variant without relying on removed glyph identity;
- `VirgoTests/DrumTabRenderProbeTests.swift`: consume `flagPaintCommands` just like production;
- `Virgo/layout/NotationRhythmRendering.swift`: replace old head/rest/flag/articulation bounds with package-derived metrics;
- tests/fixtures constructing `RenderedNoteHead`: remove `glyph` arguments.

Golden changes may include glyph semantic identity and stem/beam/flag-origin/painted-bound metric drift caused by corrected Bravura anchors. Reject changes to absolute tick, measure/row placement, note X, beam membership/topology or playhead routing.

## CI and verification

Add one step to the existing workflow:

```bash
swift test --package-path Packages/DrumNotation
```

Keep existing serial/non-parallel Virgo tests and the existing iPad simulator build. Do not create a second workflow.

Focused `xcodebuild` verification may use multiple `-only-testing:` selectors; xcodebuild supports combining multiple test constraint options. Do not rewrite the plan around a false last-selector-only assumption.

## Non-goals

HPA-163 does not:

- replace `TabGrid`, tick width, row packing or playhead mapping;
- move the whole layout engine into the package;
- change beam grouping/topology/slope or stem-run selection;
- change DTX parsing, scoring, persistence or rhythm inference;
- move dots, tuplets, feel marks, warnings, stop/choke/damp semantics, clefs or bars;
- add an executable VexFlow/Node harness; that belongs in HPA-166 if needed for beam/modifier parity;
- add MusicXML, pitched notation, arbitrary glyph APIs, publication tooling or extra consumers.

## Acceptance gates

HPA-163 is complete only when the same PR proves:

1. `Packages/DrumNotation` independently passes `swift test --package-path Packages/DrumNotation`.
2. Virgo links it on macOS/iPadOS without changing `TARGETED_DEVICE_FAMILY = 2`.
3. Bravura 1.392 OTF/metadata/license are package-owned from the pinned VexFlow font source.
4. Public package APIs contain only package/Apple-framework types.
5. README pins VexFlow 5.0.0, Bravura lineage and the closed glyph mapping; no Node/jsdom runtime/toolchain exists in HPA-163.
6. Notehead anchor tests prove the full path-centering transform, not just finite coordinates.
7. Noteheads, rests, open articulation and flags paint from Bravura/SMuFL.
8. Stems, ledger lines and painted bounds consume the same package metrics as paint.
9. `FlagPaintCommand` is the single collapse/partial-flag policy consumed by production and the render probe.
10. `DrumNoteheadGlyph` and its render plumbing/tests are removed; settings symbols stay explicitly app-owned.
11. DTX identity, voice/staff placement, normalized timing, note X, beam membership/topology and playhead routing remain unchanged.
12. Package tests, affected notation tests, full serial macOS Virgo tests, SwiftLint and existing iPad simulator build pass.

## Follow-up boundary

- **HPA-164:** measured horizontal formatting and authoritative tick geometry.
- **HPA-166:** final stem/beam/hook/modifier/static-sheet parity; add a minimal VexFlow execution harness there only if it is used by parity tests/review evidence.

Do not pull either follow-up into HPA-163.
