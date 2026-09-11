# HPA-163 DrumNotation Package Foundation and Native Glyphs Design

**Issue:** HPA-163 — `[Notation] Create reusable DrumNotation package with VexFlow references and native glyphs`

**Scope:** First PR in the HPA-163 → HPA-164 → HPA-166 migration. Establish the local package, correct Bravura primitive geometry, and cut Virgo over to it without changing horizontal formatting or beam topology.

**Baseline reviewed:** `main` at `3f0a665a02f37256c17f1d2779bb0db630c9c907`.

## Current state

Virgo already has a usable rhythm/layout separation, but visible percussion engraving is still app-owned:

- `DrumNoteheadGlyph` carries nine handwritten notehead shapes plus custom bounds/anchor math.
- `RenderedNoteHead` carries that app glyph enum through layout.
- `NotationPrimitiveViews.swift` hand-draws noteheads, rests, flags and the open-hi-hat circle.
- `NotationLayoutEngine+Beams.swift` consumes the handwritten head bounds/anchors for stems, beams and ledger lines.
- `NotationRhythmRendering.swift` computes painted bounds from the same handwritten frames, including an 8×8 flag rectangle.
- `DrumTabRenderProbeTests.notationOverlay` reconstructs a subset of production layers separately.
- `AppFonts` scans app `.ttf` resources and is not an appropriate owner for package-local Bravura `.otf` resources.

HPA-163 replaces those primitive-specific responsibilities only. DTX identity, rhythm inference, fixed X positions, rows, beam grouping/topology and playhead routing stay in Virgo.

## Decision

Create one local Swift package at `Packages/DrumNotation/` with one library target and one test target.

`DrumNotation` owns:

- the closed percussion SMuFL vocabulary Virgo needs;
- Bravura font/metadata/license resources;
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

Pin the semantic reference without carrying unused tooling:

- **VexFlow 5.0.0** is the documented migration reference.
- **`@vexflow-fonts/bravura` 1.0.2 / Bravura 1.392** is the matching font lineage.
- Vendor `bravura.otf`, `metadata.json` and `LICENSE.txt` from `vexflow/vexflow-fonts` commit `b2bc3a6070225e4d395966b36de76c36a9429b1c`.
- Record those versions/source identifiers and the closed glyph table in `Packages/DrumNotation/README.md`.

Do **not** create `Tools/vexflow`, jsdom, a lockfile or generated reference JSON in HPA-163. The previous plan generated data no Swift test consumed. If executable VexFlow comparison becomes useful for mixed beams/modifiers, HPA-166 owns the smallest harness whose output its parity tests actually consume.

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
    └── BravuraGeometryTests.swift
```

Models/Glyphs/Rendering are folders, not separate modules. HPA-163 does not add another product or target.

## Staff-space scaling is the only primitive sizing model

Do not fit SMuFL glyphs into Virgo's legacy hand-drawn frames. Those frames were authored for custom paths and distort duration-specific Bravura glyphs — especially whole noteheads and rests.

Every package geometry/rendering entry point takes one engraving scale:

```swift
staffSpace: CGFloat
```

For Virgo HPA-163 callers:

```swift
staffSpace = style.staffLineSpacing
```

The legacy `NotationLayoutStyle.noteHeadSize`, `restSymbolWidth/Height`, `fullMeasureRestWidth/Height`, `articulationDiameter`, `GameplayLayout.flagWidth/Height` remain only where still required by the pre-HPA-164 app layout contract. They are **not** glyph sizing inputs.

For a Bravura font whose `unitsPerEm` is `U`, one SMuFL staff space is `U / 4` font units, so every glyph uses the same scale:

```swift
let scale = staffSpace / (CGFloat(unitsPerEm) / 4)
```

No per-glyph `min(box.width / width, box.height / height)` fit exists.

## Public primitive API

Expose semantic values and natural staff-scaled metrics only:

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
        staffSpace: CGFloat
    ) -> NoteheadMetrics

    public static func rest(
        duration: NotationDuration,
        staffSpace: CGFloat
    ) -> PrimitiveGlyphMetrics

    public static func flag(
        duration: NotationDuration,
        direction: NotationStemDirection,
        staffSpace: CGFloat
    ) -> FlagGlyphMetrics

    public static func articulation(
        _ articulation: PercussionArticulation,
        staffSpace: CGFloat
    ) -> PrimitiveGlyphMetrics
}
```

Public SwiftUI primitives use the same scale, so paint and metrics cannot diverge through a second sizing path:

```swift
PercussionNoteheadView(style:duration:staffSpace:color:)
NotationRestGlyphView(duration:staffSpace:color:)
NotationFlagGlyphView(duration:direction:staffSpace:color:)
PercussionArticulationView(articulation:staffSpace:color:)
```

Raw SMuFL scalars, font handles, decoded metadata and arbitrary glyph lookup stay internal.

## Closed percussion legend

| Virgo semantics | Package style | SMuFL family |
| --- | --- | --- |
| kick, snare, high/mid/floor tom | `.normal` | `noteheadWhole` / `noteheadHalf` / `noteheadBlack` |
| closed/open/pedal hi-hat, crash, ride, china, splash | `.x` | `noteheadXWhole` / `noteheadXHalf` / `noteheadXBlack` |
| cowbell | `.diamond` | `noteheadDiamondWhole` / `noteheadDiamondHalf` / `noteheadDiamondBlack` |

Open hi-hat uses the X-family head plus `pictOpen` (`U+E7F8`) at Virgo's existing articulation position. Pedal hi-hat remains distinct through semantic identity, lower voice and staff position.

The old half-circle/bullseye/open-circle shapes do not encode unique musical identities that would be lost: crash/china/splash already share the same app glyph and position today, while kick/snare/toms/hats/ride retain their instrument identity and staff positions after the visual family is normalized. Do not restore the legacy shapes later as a compatibility requirement.

The internal catalog contains only those heads, rests through 64th, flags through 64th in both directions and `pictOpen`.

## Bravura geometry transform

`BravuraFont.swift` loads package resources only through `Bundle.module` and keeps font/path state private.

For every accepted glyph:

1. resolve the SMuFL scalar to a Bravura glyph;
2. obtain the raw font-authored path and raw bounds;
3. scale by the single staff-space factor above;
4. translate the scaled raw bounds center to local `(0, 0)` and flip Y for SwiftUI;
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

The resulting `paintedBounds` is the transformed path's natural bounds; no caller-supplied frame truncates it.

### Notehead anchors

SMuFL `stemUpSE` / `stemDownNW` coordinates are relative to the glyph origin in staff spaces. Convert them into font units (`unitsPerEm / 4` per staff space), then apply the exact path transform above, including centering translation.

`BravuraGeometryTests` independently recompute the transformed anchor and assert equality within 0.001. They also assert the anchor lies in a narrow stroked edge band around the transformed outline; widen the band only for a documented Bravura anchor offset smaller than the stem thickness.

Missing package resources, accepted glyphs or required notehead anchors are programmer/package errors. Fail loudly with a precondition; do not draw blank fallback glyphs.

### Flag attachment

Current `RenderedFlag.origin` is a stem attachment point, not a view center. `FlagGlyphMetrics.attachmentOffset` is the transformed Bravura attachment/origin relative to the centered package view. Virgo places one flag view at:

```text
center = RenderedFlag.origin - attachmentOffset
```

and translates the same local `paintedBounds` by that center. Paint and layout bounds therefore use one geometry contract.

## Virgo adapter

Place the single app projection seam at `Virgo/layout/VirgoNotationAdapter.swift`, beside `RhythmLayoutSnapshotBuilder` and other layout contracts.

It owns exhaustive pure mapping:

- `NoteType` → `PercussionNoteheadStyle`;
- `NoteInterval` → `NotationDuration`;
- `StemDirection` → `NotationStemDirection`;
- `NotationRestDuration` → `NotationDuration?`;
- `.fullMeasure` → `.whole`;
- `.indeterminate` → `nil` / no paint;
- `RenderedArticulationKind.openHiHat` → `.open`.

For every primitive call it passes only:

```swift
staffSpace: style.staffLineSpacing
```

There is no separate notehead/rest/flag/articulation size policy in HPA-163.

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
    let staffSpace: CGFloat
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
- when actual uncovered levels exactly equal that expected set, emit one command from level 0 using the head's canonical duration-specific Bravura flag and suppress sibling level commands;
- otherwise emit one `.eighth` command per existing uncovered `RenderedFlag`, preserving each origin;
- preserve deterministic original `layout.flags` ordering.

Each command obtains package `FlagGlyphMetrics(staffSpace:)`, computes `center = origin - attachmentOffset`, and stores the translated package `paintedBounds`.

Both `GameplayDrumNotationView` and `DrumTabRenderProbeTests.notationOverlay` consume this same command list. `NotationFlagView` paints one command and never searches sibling flags itself.

## Natural flags require a bounded stem-length adaptation

HPA-163 adopts natural Bravura flag size, so isolated 32nd/64th flags can no longer rely on the old 8×8 handwritten hook. Do not knowingly ship flag/head overlap as an intermediate state.

Only **unbeamed flagged stems** receive a minimum length adaptation. Beam topology, beam-attached stem selection and `buildFlags` remain unchanged.

For a canonical flag's local `FlagGlyphMetrics`, convert its painted bounds into coordinates relative to the attachment point:

```swift
let relativeBounds = metrics.paintedBounds.offsetBy(
    dx: -metrics.attachmentOffset.x,
    dy: -metrics.attachmentOffset.y
)
```

The flag extent back toward the notehead is:

```swift
switch direction {
case .up:
    inwardExtent = max(0, relativeBounds.maxY)
case .down:
    inwardExtent = max(0, -relativeBounds.minY)
}
```

Virgo's effective stem length for an unbeamed flagged head is:

```swift
max(
    style.stemLength,
    inwardExtent + style.minimumStemExtensionPastChord
)
```

For a stem group, use the maximum required length among its flagged members. `unbeamedStemEndY` uses this effective length in place of the fixed 75pt minimum while retaining the existing chord-clearance calculation.

Partially beamed uncovered levels still paint one natural eighth-hook component from the beam-attached stem. The visual/raster gate below must cover at least one partially beamed example.

This is a geometry adaptation caused directly by the primitive cutover, not a beam-topology rewrite. HPA-166 still owns final stem/beam/modifier parity.

## Painted-bounds cutover

Paint and layout bounds must use the same staff-scaled package metrics:

- `RenderedNoteHead.paintedBounds` translates the same `NoteheadMetrics.paintedBounds` used by stem/ledger geometry;
- `RenderedRest.paintedBounds` uses `restDuration(for:)` and package rest metrics;
- `RenderedArticulation.paintedBounds` uses package articulation metrics;
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

## Visual and raster verification

Text goldens alone are not sufficient because this PR intentionally changes the geometry they serialize.

### Automated paint/bounds contract

Extend the existing macOS raster-test support so each migrated primitive is rendered in isolation at a known position. For representative cases including a whole notehead, whole rest, quarter rest, 64th flag and open articulation:

- assert at least one non-transparent pixel occurs inside the reported translated `paintedBounds`;
- assert no non-transparent pixel occurs outside `paintedBounds` expanded by a 1pt antialiasing tolerance;
- use the production wrapper/package view, not an alternate test renderer.

This replaces a tautological `@testable` assertion that merely asks the view and metrics function for the same geometry.

### Human visual gate before golden regeneration

Add a small macOS-only `RenderRasterProbe` helper that writes a rendered SwiftUI fixture row as PNG. Before updating goldens, render a representative row containing:

- whole/quarter normal heads;
- X and diamond heads;
- whole/quarter/16th rests;
- isolated 8th and 64th flags;
- one partially beamed hook;
- open hi-hat articulation.

Write it below `FileManager.default.temporaryDirectory` as `hpa-163-bravura-preview.png`, log the exact absolute path from the test, inspect that logged file, and record the visual result in the PR verification notes. Do not commit image goldens.

Only after this visual gate passes may text goldens be regenerated.

## Regression coverage and topology gate

Package tests own:

- exact semantic → SMuFL scalar mapping;
- bundled Bravura resolution;
- staff-space scaling of raw paths;
- notehead anchor transform and path-edge relationship;
- flag attachment transform;
- rest/flag/articulation natural painted bounds.

Virgo tests own:

- DTX/catalog semantics and variants;
- exhaustive adapter mapping, including `NotationRestDuration`;
- flag collapse/partial coverage as pure `FlagPaintCommand` data;
- effective isolated-flag stem length;
- stem/ledger use of package notehead metrics;
- package-derived painted bounds;
- production/probe consumption of the same flag commands;
- fixed-grid, beam-membership and playhead invariants.

Explicit compile/behavior edits:

- `NotationLayoutDigest.swift`: remove `head.glyph`; serialize derived package style plus app variant instead;
- `DrumTabGoldenTests.hiHatOpenClosedPedal`: assert the three variants directly, without `(glyph, variant)`;
- `DrumTabRenderProbeTests.notationOverlay`: render the same `FlagPaintCommand`s as production;
- `NotationRhythmRendering.swift`: replace old head/rest/flag/articulation bounds;
- all `RenderedNoteHead` builders/tests: remove `glyph` arguments.

### Hook segments must not disappear silently

Anchor X changes affect rendered hook length even though topology membership is built separately. Add a focused test around `BeamBuildResult` for fixtures containing forward/backward hooks:

- count hook `BeamTopologySegment`s by primary group/level/kind;
- count rendered hook `RenderedBeam`s by the same group/level/kind contract;
- assert every topology hook produces one non-zero rendered hook.

If this assertion fails after the anchor cutover, stop before regenerating goldens. Do not bless the disappearance as generic metric drift and do not change topology in HPA-163. Resolve the rendering geometry while preserving the existing topology segment.

Golden drift may include derived style identity, corrected stem/beam/flag coordinates and painted/content bounds. Reject changes to absolute tick, measure/row, note X, topology membership, beam level/kind, hook segment count or playhead routing.

## SwiftLint and CI

Update `.swiftlint.yml` so `included:` also contains:

```yaml
  - Packages
```

The package follows the same line/function/type/file-size rules as app code.

Add one package-test step to the existing CI test job:

```bash
swift test --package-path Packages/DrumNotation
```

Keep existing serial Virgo tests and iPad simulator build. Do not add another workflow.

The current CI job skips draft PRs. Therefore:

1. while PR #65 remains draft, all implementation verification is local;
2. after local package/full-macOS/iPad/lint/golden verification passes, mark the same PR ready for review;
3. require the existing GitHub Actions checks, including the new package-test step, to pass before HPA-163 is considered complete.

## Golden regeneration contract

When intentional Bravura geometry changes require golden updates, use the repository's actual environment-forwarding contract:

```bash
TEST_RUNNER_VIRGO_UPDATE_GOLDENS=1 xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300
```

That regeneration run is expected to **fail after writing** so CI cannot self-approve changed goldens. Review every `VirgoTests/Goldens/*.txt` diff, then rerun the same suite without `TEST_RUNNER_VIRGO_UPDATE_GOLDENS=1` and require it to pass.

Do not use bare `VIRGO_UPDATE_GOLDENS=1` with `xcodebuild`; that variable is only suitable for an Xcode scheme test-action environment.

## Risks and explicit decisions

### Staff-space scale replaces legacy frame scale

Risk: natural Bravura bounds are wider/taller than old hand-drawn frames, so painted/content bounds and stem/ledger attachment coordinates will move.

Decision: this is intentional. Preserve musical positions/ticks and fixed note X, not the old glyph dimensions. The visual/raster gate must pass before updating text goldens.

### Natural flags can require longer isolated stems

Risk: natural 32nd/64th flags are much taller than the old 8×8 hook.

Decision: extend only unbeamed flagged stems enough to keep the natural flag clear of the head/chord using the formula above. Do not shrink flags back into the legacy frame and do not rewrite beam topology.

### Anchor X changes can affect hook rendering

Risk: a correct new stem anchor can make the old hook endpoint computation degenerate even though topology still requests a hook.

Decision: topology hook count is invariant in HPA-163. A missing rendered hook is a blocking geometry bug, not an acceptable golden drift.

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
5. All primitive geometry is scaled by one `staffSpace`, not fitted to legacy boxes.
6. Notehead anchors use the same transform as the painted path and satisfy edge tests.
7. Natural isolated flags remain clear of noteheads through the bounded unbeamed-stem adaptation.
8. Noteheads/rests/flags/open articulation paint from Bravura and their raster ink stays within reported package-derived bounds.
9. Production and `DrumTabRenderProbeTests.notationOverlay` consume the same pure flag paint commands.
10. `DrumNoteheadGlyph` and handwritten primitive geometry are removed; settings symbols remain app-owned and normalized.
11. Absolute ticks, measure/row, note X, beam topology membership/level/kind, hook segment count and playhead routing remain unchanged.
12. `.swiftlint.yml` includes `Packages`; package tests, full serial macOS tests, iPad build, SwiftLint and `git diff --check` pass locally.
13. The representative temp PNG is inspected before golden regeneration, with its logged path/result recorded in PR verification notes.
14. The PR is marked ready and the existing GitHub Actions checks pass before completion.

## Follow-up boundary

- **HPA-164:** move measured horizontal formatting/shared tick geometry into `DrumNotation`; extend the adapter created here.
- **HPA-166:** complete reusable static-sheet rendering and VexFlow-style stem/beam/modifier behavior; add executable VexFlow tooling only if parity checks consume it.

Do not pull either follow-up into HPA-163.
