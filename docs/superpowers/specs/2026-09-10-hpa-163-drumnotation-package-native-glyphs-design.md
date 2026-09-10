# HPA-163 DrumNotation Package Foundation and Native Glyphs Design

**Issue:** HPA-163 — `[Notation] Create reusable DrumNotation package with VexFlow references and native glyphs`

**Scope:** PR 1 of the HPA-163 → HPA-164 → HPA-166 migration.

**Baseline reviewed:** `main` at `3f0a665a02f37256c17f1d2779bb0db630c9c907`.

## Context

Virgo's notation pipeline already has a useful semantic/layout boundary, but its visible primitive layer is still app-owned and partly handwritten:

- `DrumNoteheadGlyph` owns custom `CGPath` geometry and stem-anchor guesses.
- `NotationPrimitiveViews.swift` hand-draws noteheads, rests, flags, and the open-hi-hat circle.
- `NotationLayoutEngine+Beams.swift` consumes those app glyph bounds/anchors while building stems and ledger lines.
- `GameplayDrumNotationView` mounts those primitives inside the existing fixed-grid layout.
- app font registration is global (`AppFonts` + `Bundle.main` / bundle scanning).
- CI runs `VirgoTests`, but no independent package test command exists.

The next migration step should make the symbols and metrics trustworthy without mixing in HPA-164's spacing work or HPA-166's beam/modifier rewrite.

## Decision

Create one local Swift package at `Packages/DrumNotation/` and make it the owner of the accepted percussion glyph vocabulary, Bravura resources/metadata, glyph metrics, and SwiftUI glyph primitives. Virgo remains the owner of DTX/domain semantics, analyzed rhythm, staff positions, fixed horizontal layout, beam topology, playback, and theme.

The shipping dependency direction is intentionally one-way:

```text
Virgo DTX / rhythm / layout
        |
        v
VirgoNotationAdapter
        |
        v
DrumNotation semantic primitive inputs
        |
        +--> Bravura 1.482 + SMuFL metadata
        |
        v
native SwiftUI / CoreText glyph rendering
```

VexFlow is not a runtime dependency. A package-local development harness pins VexFlow 5.0.0 and commits reviewed reference output used to define the migration target.

## Alternatives considered

### A. Local package + narrow Virgo adapter — chosen

This creates the reusable boundary now, removes the handwritten symbol implementation in the same PR, and leaves layout ownership unchanged until the already-planned follow-up tickets.

### B. Refactor the app primitives first, extract a package later — rejected

This would reduce initial Xcode/SPM work, but it creates another migration boundary and encourages app types to leak into the would-be package API. It also adds an unnecessary extraction-only step between HPA-163 and HPA-164.

### C. Run VexFlow in a WebView or JavaScript runtime — rejected

It would make visual comparison easy but introduces a second shipping renderer, runtime JavaScript/font-loading behavior, and platform integration that Virgo does not need. VexFlow remains reference tooling only.

## Version and platform pins

- VexFlow: **5.0.0**.
- Bravura: **1.482**, the current stable Steinberg GitHub release reviewed for this design (published 2026-08-24).
- Bravura assets: `Bravura.otf` and the matching `Bravura.json` from the same release, plus the SIL OFL notice.
- Swift language mode: **Swift 5**.
- Package platforms: **macOS 14.0+** and **iOS/iPadOS 17.5+**.
- Virgo remains iPad-only for the iOS-family app target; do not add an iPhone destination.

The package contains no third-party Swift dependency. VexFlow and `jsdom` exist only below `Tools/vexflow/`.

## Package shape

Keep one product, one implementation target, and one test target:

```text
Packages/DrumNotation/
├── Package.swift
├── README.md
├── Sources/DrumNotation/
│   ├── Model/
│   │   └── PrimitiveTypes.swift
│   ├── Glyphs/
│   │   ├── SMuFLGlyphCatalog.swift
│   │   └── BravuraResources.swift
│   ├── Rendering/
│   │   ├── NotationGlyphView.swift
│   │   └── PrimitiveViews.swift
│   └── Resources/Bravura/
│       ├── Bravura.otf
│       ├── Bravura.json
│       └── OFL.txt
├── Tests/DrumNotationTests/
│   ├── GlyphCatalogTests.swift
│   ├── BravuraMetricsTests.swift
│   ├── PrimitiveViewTests.swift
│   └── Fixtures/VexFlow/
│       └── primitive-reference.json
└── Tools/vexflow/
    ├── README.md
    ├── package.json
    ├── package-lock.json
    ├── fixtures.json
    └── generate-reference.mjs
```

Do not split Models/Glyphs/Rendering into separate Swift targets. A single small module is easier to evolve through HPA-164 and HPA-166.

## Public API for PR 1

Expose semantic inputs, not Bravura/CoreText internals and not Virgo domain types.

```swift
public enum NotationDuration: String, CaseIterable, Sendable {
    case whole
    case half
    case quarter
    case eighth
    case sixteenth
    case thirtySecond
    case sixtyFourth
}

public enum PercussionNoteheadStyle: String, CaseIterable, Sendable {
    case normal
    case x
    case diamond
}

public enum NotationStemDirection: String, Sendable {
    case up
    case down
}

public enum PercussionArticulation: String, Sendable {
    case open
}

public struct NoteheadMetrics: Equatable, Sendable {
    public let bounds: CGRect
    public let stemAnchor: CGPoint
}

public enum PercussionGlyphMetrics {
    public static func notehead(
        style: PercussionNoteheadStyle,
        duration: NotationDuration,
        stemDirection: NotationStemDirection,
        size: CGSize
    ) -> NoteheadMetrics
}
```

Rendering entry points are equally small:

```swift
public struct PercussionNoteheadView: View {
    public init(
        style: PercussionNoteheadStyle,
        duration: NotationDuration,
        size: CGSize,
        color: Color = .primary
    )
}

public struct NotationRestGlyphView: View {
    public init(duration: NotationDuration, size: CGSize, color: Color = .primary)
}

public struct NotationFlagGlyphView: View {
    public init(
        duration: NotationDuration,
        direction: NotationStemDirection,
        size: CGSize,
        color: Color = .primary
    )
}

public struct PercussionArticulationView: View {
    public init(
        articulation: PercussionArticulation,
        size: CGSize,
        color: Color = .primary
    )
}
```

Raw `CTFont`, font-registration/cache types, decoded metadata structs, code points, and generic renderer protocols stay private.

### Why `duration` is package-owned

Virgo already knows normalized rhythm. The adapter translates the supported `NoteInterval`/`NotationRhythm` into `NotationDuration`; the package then chooses the correct SMuFL glyph. This keeps duration-specific glyph selection out of Virgo without moving the rhythm analyzer itself.

### Why there is no package `Position` model yet

HPA-163 is a primitive migration. Virgo still owns absolute `CGPoint` placement and the fixed grid. The package views render around their own local origin/size; existing app wrappers apply `.position(...)`. HPA-164 can introduce formatter-owned positions when horizontal geometry moves.

## Accepted percussion legend

This PR intentionally replaces the previous custom half-circle/bullseye/open-circle visual vocabulary.

| Virgo semantic family | Package notehead style | SMuFL duration family |
| --- | --- | --- |
| kick, snare, high/mid/floor tom | `.normal` | `noteheadWhole` / `noteheadHalf` / `noteheadBlack` |
| closed/open/pedal hi-hat, crash, ride, china, splash | `.x` | `noteheadXWhole` / `noteheadXHalf` / `noteheadXBlack` |
| cowbell | `.diamond` | `noteheadDiamondWhole` / `noteheadDiamondHalf` / `noteheadDiamondBlack` |

Open hi-hat remains an X-family notehead and receives the Bravura `pictOpen` percussion articulation (`U+E7F8`) above it. Closed hi-hat has no extra mark. Pedal hi-hat remains distinguished by its existing staff position and semantic identity.

Crash/ride/china/splash remain distinct app semantics and staff positions even when they share the X-family glyph. This PR does not invent additional pictograms solely to make every instrument visually unique.

## Glyph selection

The focused internal catalog resolves only the symbols needed by Virgo:

- normal noteheads: `noteheadWhole`, `noteheadHalf`, `noteheadBlack`;
- X noteheads: `noteheadXWhole`, `noteheadXHalf`, `noteheadXBlack`;
- diamond noteheads: `noteheadDiamondWhole`, `noteheadDiamondHalf`, `noteheadDiamondBlack`;
- rests: `restWhole`, `restHalf`, `restQuarter`, `rest8th`, `rest16th`, `rest32nd`, `rest64th`;
- flags: `flag8thUp/Down`, `flag16thUp/Down`, `flag32ndUp/Down`, `flag64thUp/Down`;
- open percussion articulation: `pictOpen`.

Do not expose an arbitrary "glyph by SMuFL name" API.

## Bravura resource and metric handling

`BravuraResources.swift` owns all resource access through `Bundle.module`.

Font registration uses `CTFontManagerRegisterFontsForURL(..., .process, ...)`. Re-registering is safe: `alreadyRegistered` and `duplicatedName` are accepted; any other registration failure fails fast because a missing/corrupt package resource is a packaging error, not recoverable app state.

`Bravura.json` is decoded once through Swift's thread-safe static initialization. The implementation only decodes metadata fields used by PR 1:

```swift
private struct BravuraMetadata: Decodable {
    let glyphsWithAnchors: [String: [String: [Double]]]
    let glyphBBoxes: [String: GlyphBBox]?
}
```

SMuFL metadata coordinates are in staff spaces. `PercussionGlyphMetrics.notehead(...)` scales the selected glyph's `stemUpSE` or `stemDownNW` anchor and bounding box to the requested `CGSize`. If an accepted notehead lacks the expected anchor, tests fail rather than silently restoring the old bounding-box guess.

The app's existing notehead size remains the requested size in this PR. HPA-164 may later change the sizing/formatting model.

## Flag compatibility boundary

Virgo currently creates one `RenderedFlag` for each uncovered beam level. HPA-163 must not rewrite that topology.

The package supports canonical isolated flag glyphs for eighth through sixty-fourth durations so the reference contract is complete. Virgo keeps the existing `RenderedFlag` array unchanged and adapts it at render time:

- group flags by `noteHeadID`;
- if a head has the complete uncovered level set `0..<head.interval.flagCount`, render only the level-0 item and choose the canonical Bravura glyph from the head duration (`flag8th`, `flag16th`, `flag32nd`, or `flag64th`);
- suppress the sibling level items in that fully-unbeamed case because the canonical glyph already contains all hooks;
- if only some levels are uncovered, keep every existing flag origin and render each as a single-level `flag8thUp/Down` component at that origin.

This changes only how existing `RenderedFlag` values paint; `buildFlags`, beam coverage, and beam grouping remain untouched. Any mixed/partial-beam composition mismatch against VexFlow is recorded as an expected HPA-166 delta.

This is the only intentional primitive-level compatibility exception. No new old/new toggle is introduced.

## VexFlow reference harness

`Tools/vexflow/` is reproducible development tooling:

```json
{
  "private": true,
  "type": "module",
  "dependencies": {
    "vexflow": "5.0.0",
    "jsdom": "21.1.2"
  },
  "scripts": {
    "reference": "node generate-reference.mjs"
  }
}
```

`fixtures.json` defines the complete PR-1 reference matrix: semantic notehead family, VexFlow duration, staff line, stem direction, rest/flag cases, and open-hi-hat articulation. `generate-reference.mjs` renders each case with VexFlow's Bravura music font and emits normalized geometry/semantic data to `Tests/DrumNotationTests/Fixtures/VexFlow/primitive-reference.json`.

The committed JSON contains:

- VexFlow version and music font;
- exact fixture input;
- resolved notehead glyph/type;
- notehead width/bounds and stem attachment location;
- rest/flag glyph/type;
- modifier/articulation position where present.

Reference generation is manual. Neither `swift test` nor the app build invokes npm, Node, network access, or VexFlow.

The tool README records the fixed migration options:

- two percussion voices: upper stems up, lower stems down;
- flat beams;
- standard duration strings (`w`, `h`, `q`, `8`, `16`, `32`, `64`);
- rests use VexFlow rest duration forms;
- dots/tuplets are captured for later formatter comparison but are not migrated in HPA-163;
- no horizontal displacement assertion for simultaneous heads in PR 1.

## Virgo adapter

Create `Virgo/notation/VirgoNotationAdapter.swift` as the only app-to-package translation seam introduced in this PR. It remains Virgo-owned and may expand in HPA-164.

Responsibilities:

- map `RenderedNoteHead.noteType` to `PercussionNoteheadStyle`;
- map supported `NoteInterval` / resolved `NotationRhythm` to `NotationDuration`;
- map app `StemDirection` to `NotationStemDirection`;
- expose package notehead metrics to the existing stem/ledger calculations;
- map `RenderedArticulationKind.openHiHat` to `.open`;
- derive isolated flag duration from the source rendered head without moving beam topology into the package.

It does not accept raw DTX text, mutate layout, or construct a parallel notation snapshot.

## App integration

`NotationPrimitiveViews.swift` remains the thin production mounting layer:

- `NotationNoteHeadView` delegates drawing to `PercussionNoteheadView`;
- `NotationRestView` delegates printed supported rests to `NotationRestGlyphView`;
- `NotationFlagView` delegates glyph drawing to `NotationFlagGlyphView`;
- `NotationArticulationView` delegates the open mark to `PercussionArticulationView`;
- stems, beams, ledger lines, measure bars, rhythm dots, tuplets, feel marks, warnings, and stop marks stay app-owned.

Delete `DrumNoteheadShape`, `DrumNoteheadGlyph.makePath`, custom rest paths, and `FlagView` once no production/test caller uses them.

`NotationLayoutEngine+Beams.swift` and any ledger-line metric caller switch from `noteHead.glyph.bounds/stemAnchorOffset` to `VirgoNotationAdapter` → package metrics. Horizontal X placement, stem grouping, beam topology, and playhead mapping remain unchanged.

## Tests

### Package tests

`swift test --package-path Packages/DrumNotation` owns app-independent assertions:

- every accepted semantic notehead/duration resolves to the expected SMuFL glyph family;
- every accepted glyph exists in bundled Bravura;
- Bravura metadata contains expected up/down stem anchors and finite bounds;
- resource loading/registration works without `VirgoApp` or `AppFonts`;
- rest and isolated flag selections cover the supported durations/directions;
- primitive views mount using package-local resources.

### Virgo tests

Keep app/domain responsibilities in Virgo:

- DTX lane and `NoteType` mapping remains in `DrumNotationCatalogTests`;
- add focused adapter mapping tests;
- update layout stem/ledger tests to assert package-derived anchors;
- keep `SwiftUIRenderingNotationTests` as wrapper/mounting smoke coverage;
- keep `DrumTabRenderProbeTests` as production ink coverage;
- keep existing golden/invariant/playhead suites to prove fixed-grid/timing behavior did not change.

Remove the old pure custom-path geometry tests instead of duplicating them.

## CI

Add an explicit package-test step to `.github/workflows/ci.yml` before the Virgo `xcodebuild test` step:

```bash
swift test --package-path Packages/DrumNotation
```

Keep the existing serial/non-parallel `xcodebuild` policy and existing iPad simulator build. Do not add a second workflow just for the package.

## Non-goals

HPA-163 does not:

- replace `TabGrid`, `tickWidth`, row packing, or playhead mapping;
- move `NotationLayoutEngine` wholesale into the package;
- change beam grouping, beam slope/topology, or stem-run selection;
- change DTX parsing, persistence, `NoteType`, scoring instrument identity, or rhythm analysis;
- migrate clefs, time signatures, bars, tuplets, warnings, feel marks, or stop semantics;
- add a generic SMuFL engine, arbitrary glyph API, renderer backend protocol, plugin system, release pipeline, or package publication;
- preserve compatibility with the superseded custom glyph enum/paths after migration;
- add a shipping renderer switch.

## Acceptance gates

HPA-163 is ready for implementation when the PR can satisfy all of these in one branch:

1. `Packages/DrumNotation` builds independently and `swift test --package-path Packages/DrumNotation` passes.
2. Virgo's app target links the local product on macOS and iPadOS.
3. Bravura 1.482 font + matching metadata are package-owned and loaded via `Bundle.module`.
4. Package public APIs mention no Virgo domain/design-system types.
5. VexFlow 5.0.0 reference inputs/options/output are committed and reproducible, but normal builds/tests do not execute VexFlow.
6. Noteheads, supported rests, open-hi-hat articulation, and isolated flags paint through the package's native Bravura primitives.
7. Existing stems/ledger lines consume package glyph anchors/metrics.
8. Old handwritten notehead/rest/flag/open-articulation geometry is deleted once replaced.
9. DTX identity, staff position, voice, normalized timing, fixed horizontal spacing, beam grouping, and playhead alignment remain unchanged.
10. Package tests, affected Virgo unit/render suites, full Virgo tests, and iPad build pass.

## Follow-up boundary

- **HPA-164:** move measured horizontal formatting/shared tick geometry into the package and expand the adapter to a formatter input/output boundary.
- **HPA-166:** move complete static sheet rendering plus VexFlow-style stem/beam/modifier behavior; remove the remaining split rendering architecture.

Do not pull either follow-up into HPA-163.

## External references

- VexFlow 5 guide: https://vexflow.github.io/vexflow-examples/guides/getting-started/
- VexFlow notehead implementation: https://github.com/0xfe/vexflow/blob/master/src/notehead.ts
- Bravura 1.482 release: https://github.com/steinbergmedia/bravura/releases/tag/bravura-1.482
- SMuFL noteheads: https://w3c.github.io/smufl/latest/tables/noteheads.html
- SMuFL rests: https://w3c.github.io/smufl/latest/tables/rests.html
- SMuFL flag classes: https://w3c.github.io/smufl/latest/specification/classes.html
- SMuFL percussion open glyph (`pictOpen`): https://w3c.github.io/smufl/releases/1.4/tables/percussion-playing-technique-pictograms.html
- SMuFL glyph bounding boxes / staff-space units: https://w3c.github.io/smufl/latest/specification/glyphbboxes.html
