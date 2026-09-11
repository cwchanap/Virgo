# HPA-163 DrumNotation Package Foundation and Native Glyphs Design

**Issue:** HPA-163 — `[Notation] Create reusable DrumNotation package with VexFlow references and native glyphs`

**Scope:** First PR in the HPA-163 → HPA-164 → HPA-166 migration. Establish a reusable primitive-rendering package and correct primitive geometry without changing horizontal formatting or beam topology.

**Baseline reviewed:** `main` at `3f0a665a02f37256c17f1d2779bb0db630c9c907`.

## Current state

Virgo's normalized rhythm/layout pipeline is already reusable enough for this stage, but primitive engraving remains app-owned:

- `DrumNoteheadGlyph` defines handwritten notehead paths and approximate anchors.
- `RenderedNoteHead` carries that glyph enum through layout.
- `NotationPrimitiveViews.swift` hand-draws noteheads, rests, flags and the open-hi-hat circle.
- `NotationLayoutEngine+Beams.swift` uses app glyph geometry for stems and ledger lines.
- `NotationRhythmRendering.swift` still computes painted bounds from those handwritten frames, including an 8×8 flag rectangle.
- `DrumTabRenderProbeTests.notationOverlay` reconstructs the primitive stack separately from production.
- `AppFonts` is process-global app font registration and must not own package resources.

HPA-163 replaces those primitive-specific responsibilities only. DTX identity, rhythm inference, fixed X positions, rows, beam grouping/topology and playhead routing stay unchanged.

## Decision

Create one local Swift package at `Packages/DrumNotation/` with one library target and one test target.

`DrumNotation` owns:

- the closed percussion SMuFL vocabulary needed by Virgo;
- Bravura resources/metadata;
- font-derived primitive paths, painted bounds and attachment geometry;
- native SwiftUI primitive views.

Virgo owns:

- DTX/source identity, `NoteType`/`DrumType`, notation variants and scoring identity;
- voice, staff positions and overrides;
- normalized rhythm and absolute event positions;
- fixed-grid placement and row packing;
- beam topology, playback, scrolling/playhead and theme.

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

No WebView, shipping JavaScript, renderer protocol, fallback renderer, publication workflow or compatibility layer is added.

## Reference version policy

Pin the semantic reference without building unused tooling:

- **VexFlow 5.0.0** is the documented migration reference.
- **`@vexflow-fonts/bravura` 1.0.2 / Bravura 1.392** is the matching font lineage.
- Vendor `bravura.otf`, `metadata.json` and `LICENSE.txt` from `vexflow/vexflow-fonts` commit `b2bc3a6070225e4d395966b36de76c36a9429b1c`.
- Record those versions/source identifiers and the closed glyph table in `Packages/DrumNotation/README.md`.

Do **not** create `Tools/vexflow`, jsdom, a lockfile or generated reference JSON in HPA-163. The previous plan generated data no Swift test consumed. If executable VexFlow comparison is needed for mixed beams/modifiers, HPA-166 owns the minimal harness because that is where parity becomes an acceptance criterion.

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

Expose only semantic values and fitted metrics:

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

public struct FlagGlyphMetrics: Equatable, Sendable {
    public let paintedBounds: CGRect
    public let attachmentOffset: CGPoint
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
    ) -> FlagGlyphMetrics

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

Public SwiftUI primitives mirror those semantic inputs and explicit sizes:

```swift
PercussionNoteheadView(style:duration:size:color:)
NotationRestGlyphView(duration:size:color:)
NotationFlagGlyphView(duration:direction:size:color:)
PercussionArticulationView(articulation:size:color:)
```

Raw SMuFL scalars, font handles, decoded metadata and arbitrary glyph lookup stay internal.

## Closed percussion legend

| Virgo semantics | Package style | SMuFL family |
| --- | --- | --- |
| kick, snare, high/mid/floor tom | `.normal` | `noteheadWhole` / `noteheadHalf` / `noteheadBlack` |
| closed/open/pedal hi-hat, crash, ride, china, splash | `.x` | `noteheadXWhole` / `noteheadXHalf` / `noteheadXBlack` |
| cowbell | `.diamond` | `noteheadDiamondWhole` / `noteheadDiamondHalf` / `noteheadDiamondBlack` |

Open hi-hat uses the X-family head plus `pictOpen` (`U+E7F8`) at Virgo's existing articulation position. Pedal hi-hat remains distinct through semantic identity, lower voice and staff position.

The internal catalog contains only those heads, rests through 64th, flags through 64th in both directions and `pictOpen`.

## Bravura geometry transform

`BravuraFont.swift` loads package resources only through `Bundle.module` and keeps font/path state private.

For every glyph:

1. resolve the SMuFL scalar to a Bravura glyph;
2. obtain the raw font-authored path and raw bounds;
3. fit uniformly to the requested local box;
4. translate the raw bounds center to local `(0, 0)` and flip Y for SwiftUI;
5. apply the **same full affine transform** to every semantic attachment point.

For raw bounds `B` and scale `s`:

```swift
CGAffineTransform(
    a: s,
    b: 0,
    c: 0,
    d: -s,
    tx: -B.midX * s,
    ty: B.midY * s
)
```

### Notehead anchors

SMuFL `stemUpSE` / `stemDownNW` coordinates are relative to the glyph origin in staff spaces. Convert them into the same font-coordinate system (`unitsPerEm / 4` per staff space), then apply the exact path transform above, including the centering translation.

A scale/Y-flip-only anchor transform is incorrect because it ignores the raw path's position relative to the glyph origin.

`BravuraGeometryTests` must independently recompute the expected transformed anchor and compare with `NoteheadMetrics.stemAnchorOffset`. It must also assert the transformed anchor lies in a narrow stroked edge band around the transformed outline, with a fixture-specific epsilon only if Bravura intentionally offsets the anchor by stem thickness.

### Flag attachment

Current `RenderedFlag.origin` is a stem attachment point, not a SwiftUI view center. `FlagGlyphMetrics.attachmentOffset` is the transformed Bravura glyph origin relative to the centered package view. Virgo therefore places the view center at:

```text
RenderedFlag.origin - attachmentOffset
```

and translates the same local `paintedBounds` by that center. This keeps flag paint and layout bounds on one geometry contract.

Missing package resources, accepted glyphs or required notehead anchors are programmer/package errors. Fail loudly with a precondition; do not render blank fallback glyphs.

## Virgo adapter and size policy

Place the single app projection seam at `Virgo/layout/VirgoNotationAdapter.swift`, beside `RhythmLayoutSnapshotBuilder` and the other layout contracts.

It owns exhaustive pure mapping:

- `NoteType` → `PercussionNoteheadStyle`;
- `NoteInterval` → `NotationDuration`;
- `StemDirection` → `NotationStemDirection`;
- `NotationRestDuration` → `NotationDuration?`;
- `.fullMeasure` → `.whole`;
- `.indeterminate` → `nil` / no paint;
- `RenderedArticulationKind.openHiHat` → `.open`.

It also owns Virgo's size policy:

- notehead box = existing `style.noteHeadSize`;
- full-measure/half rest box = existing `fullMeasureRestWidth × fullMeasureRestHeight`;
- other rest box = existing `restSymbolWidth × restSymbolHeight`;
- open articulation box = existing `articulationDiameter × articulationDiameter`;
- flag box = `naturalFlagSize(..., staffSpace: style.staffLineSpacing)`, preserving the Bravura flag aspect instead of the old 8×8 frame.

The package never accepts Virgo types or theme values.

## Pure flag paint commands

Keep `NotationLayoutEngine.buildFlags` unchanged; it remains the source of uncovered beam levels.

Define an app-owned pure value:

```swift
struct FlagPaintCommand: Identifiable, Equatable {
    let id: String
    let center: CGPoint
    let duration: NotationDuration
    let direction: NotationStemDirection
    let size: CGSize
    let paintedBounds: CGRect
}
```

and:

```swift
static func flagPaintCommands(
    flags: [RenderedFlag],
    heads: [RenderedNoteHead],
    style: NotationLayoutStyle
) -> [FlagPaintCommand]
```

Policy per head:

- expected uncovered levels = `0..<head.interval.flagCount`;
- when actual uncovered levels exactly equal the expected set, emit one command from level 0 using the head's canonical duration-specific Bravura flag and suppress sibling level commands;
- otherwise emit one `.eighth` command per existing uncovered `RenderedFlag`, preserving each origin;
- preserve deterministic original `layout.flags` ordering.

Each command obtains package `FlagGlyphMetrics`, computes `center = origin - attachmentOffset`, and stores the translated package `paintedBounds`.

Both `GameplayDrumNotationView` and `DrumTabRenderProbeTests.notationOverlay` consume this same command list. `NotationFlagView` paints one command and never searches sibling flags itself.

## Painted-bounds cutover

Paint and layout bounds must use the same package metrics:

- `RenderedNoteHead.paintedBounds` translates the same `NoteheadMetrics.paintedBounds` used by stem/ledger geometry;
- `RenderedRest.paintedBounds` uses `restDuration(for:)`, Virgo's explicit rest box and package rest metrics;
- `RenderedArticulation.paintedBounds` uses Virgo's articulation box and package metrics;
- `NotationLayout.calculatePaintedBounds` unions `FlagPaintCommand.paintedBounds` instead of the old per-`RenderedFlag` 8×8 rectangle.

Delete `RenderedFlag.paintedBounds` if no caller remains.

Expected Bravura metric drift is acceptable; mismatch between actual paint and `layout.paintedBounds` is not.

## Remove the old glyph vocabulary

`DrumNoteheadGlyph` does not survive HPA-163. Remove:

- `DrumNotationDefinition.glyph`;
- `RenderedNoteHead.glyph`;
- constructor plumbing in `NotationLayoutEngine` and tests;
- custom path/bounds/anchor helpers;
- handwritten notehead/rest/flag/open-articulation painting.

`DrumType.symbol` stays app-owned for settings/key-mapping and becomes a direct normalized switch:

- kick/snare/toms → `●`;
- hi-hat/pedal/crash/ride → `×`;
- cowbell → `◇`.

This text icon is not part of score engraving.

## Production primitive cutover

`NotationPrimitiveViews.swift` stays the thin app mounting layer:

- noteheads → `PercussionNoteheadView`;
- printed supported rests → `NotationRestGlyphView`;
- open-hi-hat articulation → `PercussionArticulationView`;
- flags → `NotationFlagView(command:)` → `NotationFlagGlyphView`.

Stems, beams, ledger lines, bars, dots, tuplets, feel marks, warnings and stop marks remain Virgo-owned in HPA-163.

## Regression coverage

Package tests own:

- exact semantic → SMuFL scalar mapping;
- bundled Bravura resolution;
- raw path → fitted path transform;
- notehead anchor transform and path-edge relationship;
- flag attachment-offset transform;
- rest/flag/articulation fitted bounds;
- package primitive construction.

Virgo tests own:

- DTX/catalog semantics and variants;
- exhaustive adapter mapping, including `NotationRestDuration`;
- flag collapse/partial coverage as pure `FlagPaintCommand` data;
- stem/ledger use of package notehead metrics;
- package-derived painted bounds;
- production and probe consumption of the same flag commands;
- fixed-grid, beam-membership and playhead invariants.

Explicit compile/behavior edits:

- `NotationLayoutDigest.swift`: remove `head.glyph`; serialize derived package style plus app variant instead;
- `DrumTabGoldenTests.hiHatOpenClosedPedal`: assert the three variants directly, without `(glyph, variant)`;
- `DrumTabRenderProbeTests.notationOverlay`: render the same `FlagPaintCommand`s as production;
- `NotationRhythmRendering.swift`: replace old head/rest/flag/articulation bounds;
- all `RenderedNoteHead` builders/tests: remove `glyph` arguments.

Golden drift may include style identity, corrected stem/beam/flag-origin metrics and painted/content bounds. Reject changes to absolute tick, measure/row, note X, beam membership/topology or playhead routing.

## CI and verification

Add one existing-workflow step:

```bash
swift test --package-path Packages/DrumNotation
```

Keep existing serial Virgo tests and iPad simulator build. Do not add another workflow.

Multiple `-only-testing:` arguments are valid xcodebuild constraints and may be used together; do not replace them because of a false last-selector-only assumption.

## Non-goals

HPA-163 does not:

- replace `TabGrid`, tick width, row packing or playhead mapping;
- move the whole layout engine into the package;
- change beam grouping/topology/slope or stem-run selection;
- change DTX parsing, scoring, persistence or rhythm inference;
- move dots, tuplets, feel marks, warnings, controls, clefs or bars;
- add Node/jsdom/VexFlow execution tooling;
- add MusicXML, pitched notation, arbitrary glyph APIs, publication tooling or extra consumers.

## Acceptance gates

HPA-163 is complete only when the same PR proves:

1. `swift test --package-path Packages/DrumNotation` passes independently.
2. Virgo links the package on macOS/iPadOS with `TARGETED_DEVICE_FAMILY = 2` unchanged.
3. Bravura 1.392 OTF/metadata/license are package-owned from the pinned VexFlow font source.
4. Package public APIs contain only package/Apple-framework types.
5. README pins VexFlow 5.0.0, Bravura lineage and the closed glyph table; no Node/jsdom toolchain exists in this PR.
6. Notehead tests prove the complete translate + scale + Y-flip anchor transform and outline-edge relationship.
7. Flag metrics preserve the stem attachment origin and natural Bravura aspect.
8. Noteheads, rests, open articulation and flags paint from Bravura/SMuFL.
9. Stems, ledger lines and painted bounds use the same package metrics as paint.
10. `FlagPaintCommand` is the only collapse/partial-flag policy consumed by production and the raster probe.
11. `DrumNoteheadGlyph` and its render plumbing/tests are removed; settings symbols remain app-owned.
12. DTX identity, voice/staff placement, normalized timing, note X, beam membership/topology and playhead routing remain unchanged.
13. Package tests, affected notation tests, full serial macOS Virgo tests, SwiftLint and the iPad simulator build pass.

## Follow-up boundary

- **HPA-164:** measured horizontal formatting and authoritative tick geometry.
- **HPA-166:** final stem/beam/hook/modifier/static-sheet parity and, only if consumed by those checks, a minimal executable VexFlow comparison harness.

Do not pull either follow-up into HPA-163.
