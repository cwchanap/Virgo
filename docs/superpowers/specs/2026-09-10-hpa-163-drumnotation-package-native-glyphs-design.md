# HPA-163 DrumNotation Package Foundation and Native Glyphs Design

**Issue:** HPA-163 — `[Notation] Create reusable DrumNotation package with VexFlow references and native glyphs`

**Scope:** First PR in the existing HPA-163 → HPA-164 → HPA-166 notation migration. This PR establishes the reusable package and trustworthy primitives; it deliberately does not change horizontal formatting or beam topology.

**Baseline reviewed:** `main` at `3f0a665a02f37256c17f1d2779bb0db630c9c907`.

## Current state

Virgo already separates DTX/rhythm semantics from the final SwiftUI painting reasonably well, but visible notation primitives are still app-owned:

- `DrumNoteheadGlyph` defines handwritten `CGPath` noteheads and approximate stem anchors.
- `NotationPrimitiveViews.swift` hand-draws noteheads, rests, flags, and the open-hi-hat circle.
- `RenderedNoteHead` carries the app-specific glyph enum through the layout model.
- `NotationLayoutEngine+Beams.swift` uses that enum for stem attachment and ledger-line bounds.
- `AppFonts` loads fonts globally from app bundles.
- CI exercises `VirgoTests`, but there is no independent notation-package test command.

HPA-163 should replace those primitive-specific responsibilities without touching the fixed tick grid, row packing, playhead mapping, DTX parsing, or beam grouping.

## Decision

Create one local Swift package at `Packages/DrumNotation/` and make it the owner of:

- the small percussion glyph vocabulary needed by Virgo;
- the pinned Bravura font and matching SMuFL metadata;
- notehead glyph metrics and stem-attachment anchors;
- native SwiftUI/CoreText primitive rendering;
- committed VexFlow reference fixtures used to define expected engraving behavior.

Virgo remains the owner of DTX lane identity, `NoteType`/`DrumType`, scoring identity, notation variants, staff positions, voice, normalized rhythm, absolute positions, fixed-grid layout, beam topology, playback, and theme.

```text
Virgo DTX / rhythm / fixed layout
              |
              v
     VirgoNotationAdapter
              |
              v
 DrumNotation semantic primitives
      |                 |
      v                 v
 Bravura/SMuFL      SwiftUI/CoreText
```

VexFlow is reference tooling only. There is no shipping JavaScript, WebView, renderer toggle, or fallback path.

## Version and platform pins

Pin the reference stack to what VexFlow 5.0.0 actually used rather than mixing it with a newer Bravura release:

- **VexFlow 5.0.0**.
- **`@vexflow-fonts/bravura` 1.0.2 / Bravura 1.392**. The VexFlow 5.0.0 source depends on `@vexflow-fonts/bravura ^1.0.2`, and that font package identifies its asset as Bravura 1.392.
- Vendor the matching `bravura.otf`, `metadata.json`, and `LICENSE.txt` from the same VexFlow font source; record the upstream package/version and source commit in the package README.
- **jsdom 26.0.0** for the development reference harness, matching VexFlow 5.0.0's own development dependency generation rather than introducing an older DOM runtime.
- Swift language mode **Swift 5**.
- Package platforms **macOS 14.0+** and **iOS/iPadOS 17.5+**.
- Virgo remains iPad-only for the iOS-family target (`TARGETED_DEVICE_FAMILY = 2`).

The Swift package has no third-party Swift dependency.

## Package boundary

Keep one product, one implementation target, and one test target:

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
├── Tests/DrumNotationTests/
│   ├── GlyphCatalogTests.swift
│   ├── BravuraGeometryTests.swift
│   ├── PrimitiveViewTests.swift
│   └── Fixtures/VexFlow/primitive-reference.json
└── Tools/vexflow/
    ├── README.md
    ├── package.json
    ├── package-lock.json
    ├── fixtures.json
    └── generate-reference.mjs
```

Models/Glyphs/Rendering are folders, not separate modules. Publication, release automation, renderer protocols, and extra consumer targets are out of scope.

## Public primitive API

Expose semantic values and fitted metrics only. Raw SMuFL code points, `CGFont`/`CTFont`, decoded metadata, and cache state stay internal.

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
}
```

Public SwiftUI primitives mirror those inputs:

```swift
PercussionNoteheadView(style:duration:size:color:)
NotationRestGlyphView(duration:size:color:)
NotationFlagGlyphView(duration:direction:size:color:)
PercussionArticulationView(articulation:size:color:)
```

The requested `CGSize` is an explicit local rendering box. The package fits the Bravura glyph uniformly while preserving aspect ratio, centers it in that box, and exposes the transformed painted bounds/anchor. Virgo keeps absolute placement by applying its existing `.position(...)` values.

## Bravura loading and geometry

Do not depend on process-global app font registration. `BravuraFont.swift` loads the bundled OTF directly through `Bundle.module` into a lazily initialized `CGFont`/`CTFont` and keeps that state private.

For each accepted SMuFL scalar:

1. resolve the scalar to a Bravura `CGGlyph`;
2. obtain the native outline/bounds from CoreText/CoreGraphics;
3. fit the outline uniformly into the requested primitive box;
4. draw that font-derived path through SwiftUI `Canvas`/`Path`;
5. for noteheads, read `stemUpSE` or `stemDownNW` from the matching Bravura metadata and apply the same transform to produce `stemAnchorOffset`.

This uses font-authored outlines rather than handwritten geometry. It also avoids a second AppKit/UIKit renderer and avoids `Bundle.main` scanning.

If an accepted notehead lacks the expected Bravura anchor, package tests fail; do not silently restore the old bounding-box guess.

## Accepted percussion legend

Normalize the engraving vocabulary instead of preserving custom half-filled/circled symbols solely for compatibility:

| Virgo semantics | Package style | Duration-aware SMuFL family |
| --- | --- | --- |
| kick, snare, high/mid/floor tom | `.normal` | `noteheadWhole` / `noteheadHalf` / `noteheadBlack` |
| closed/open/pedal hi-hat, crash, ride, china, splash | `.x` | `noteheadXWhole` / `noteheadXHalf` / `noteheadXBlack` |
| cowbell | `.diamond` | `noteheadDiamondWhole` / `noteheadDiamondHalf` / `noteheadDiamondBlack` |

Open hi-hat uses the X-family head plus SMuFL `pictOpen` (`U+E7F8`) at the existing app-owned articulation position. Closed hi-hat has no extra mark. Pedal hi-hat remains distinct through its semantic identity, lower voice, and staff position.

Crash/ride/china/splash remain different app semantics and positions even when they share the X glyph family.

The focused catalog contains only the notehead families above, rests through 64th, flags through 64th in both directions, and `pictOpen`. Do not expose arbitrary "glyph by SMuFL name" lookup.

## Remove the old glyph enum cleanly

`DrumNoteheadGlyph` should not survive as a second engraving vocabulary.

In this PR:

- remove `DrumNotationDefinition.glyph`;
- remove `RenderedNoteHead.glyph`;
- remove the corresponding constructor plumbing from `NotationLayoutEngine.swift` and test fixtures;
- delete the handwritten path/bounds/stem-anchor helpers.

`DrumType.symbol` is still used by settings/key-mapping UI, but it is not score engraving. Keep that UI contract app-owned as a direct `DrumType` switch and normalize it to the same three visual families:

- kick/snare/toms → `●`;
- hi-hat/pedal/crash/ride → `×`;
- cowbell → `◇`.

This avoids importing `DrumNotation` into settings UI simply to paint a small text icon, while also removing the old bullseye/open/half-circle compatibility vocabulary.

## Virgo adapter

Create `Virgo/notation/VirgoNotationAdapter.swift` as the only app-to-package projection seam in HPA-163.

It performs exhaustive pure mappings:

- `NoteType` → `PercussionNoteheadStyle`;
- `NoteInterval` → `NotationDuration`;
- `StemDirection` → `NotationStemDirection`;
- `RenderedArticulationKind.openHiHat` → `.open`;
- `RenderedNoteHead` + current notehead box → package `NoteheadMetrics`.

The package never accepts `NoteType`, `DrumType`, `DrumNotationVariant`, `RenderedNoteHead`, `GameplayLayout`, `Palette`, `AppFonts`, or raw DTX values.

## Primitive cutover

`NotationPrimitiveViews.swift` remains the production mounting layer, but covered symbols delegate to package views:

- noteheads → `PercussionNoteheadView`;
- rests → `NotationRestGlyphView`;
- open-hi-hat articulation → `PercussionArticulationView`;
- flags → `NotationFlagGlyphView`.

Stems, beams, ledger lines, bars, dots, tuplets, feel marks, warnings, and stop marks remain Virgo-owned.

`NotationLayoutEngine+Beams.swift` replaces old glyph-bound/stem-anchor calls with `VirgoNotationAdapter` → package metrics. Absolute X positions, tick geometry, beam grouping, and playhead routing do not change.

## Flag compatibility boundary

Virgo currently emits one `RenderedFlag` per uncovered beam level. HPA-163 does not rewrite that topology.

At render time:

- group flags by `noteHeadID`;
- when the complete uncovered set is `0..<interval.flagCount`, render only the level-0 item using the canonical duration-specific Bravura flag (`8th`, `16th`, `32nd`, or `64th`) and suppress sibling levels;
- when only some levels are uncovered because other levels are beamed, preserve every existing flag origin and paint each uncovered level as one Bravura eighth-flag hook component.

Thus all handwritten flag Bézier paths disappear in HPA-163 without changing `buildFlags` or beam coverage. Exact mixed partial-beam modifier composition remains HPA-166 work and is documented as an expected reference delta.

## VexFlow reference harness

`Tools/vexflow/` pins:

```json
{
  "private": true,
  "type": "module",
  "dependencies": {
    "vexflow": "5.0.0",
    "jsdom": "26.0.0"
  },
  "scripts": {
    "reference": "node generate-reference.mjs"
  }
}
```

The fixture matrix covers:

- normal, X, and diamond heads across whole/half/black duration families;
- upper/down stem attachment cases;
- isolated 8th/16th/32nd/64th flags;
- whole/half/quarter/8th/16th rests plus the package-only 32nd/64th selection checks;
- open-hi-hat modifier treatment;
- representative simultaneous upper/lower percussion heads for glyph/vertical behavior only.

The generator renders/preformats those fixtures with VexFlow's Bravura music font and writes deterministic `primitive-reference.json`: pinned versions/options, fixture inputs, resolved glyph family/code, stable width/bounds/attachment values, and modifier/flag/rest selection. Numbers are normalized and no timestamp or absolute path is emitted.

Reference generation is manual. `swift test`, Xcode builds, and app runtime never invoke Node, npm, VexFlow, or the network.

## Tests and CI

Package tests own app-independent behavior:

- semantic style/duration → exact SMuFL glyph selection;
- every accepted glyph exists in the bundled Bravura 1.392 font;
- expected notehead anchors exist and transform to finite local metrics;
- package resources load without Virgo/AppFonts;
- rest/flag/articulation selection is complete;
- primitive views construct from package-only types.

Virgo tests own app integration:

- complete `NoteType`/DTX/catalog mapping;
- exhaustive adapter mapping;
- normalized `DrumType.symbol` settings icons;
- stem/ledger calculations through package metrics;
- SwiftUI wrapper mounting and production ink probe;
- existing golden/invariant/playhead suites proving fixed-grid/timing/beam membership did not move.

Delete old tests that only validate handwritten path geometry instead of duplicating them.

Add `swift test --package-path Packages/DrumNotation` to the existing CI workflow before the Virgo serial `xcodebuild test` step. Do not add a second workflow.

## Non-goals

HPA-163 does not:

- replace `TabGrid`, tick width, row packing, or playhead mapping;
- move the whole layout engine into the package;
- change beam grouping, beam slope/topology, or stem-run selection;
- change DTX parsing, scoring identity, persistence, or rhythm inference;
- migrate clefs, time signatures, measure bars, dots, tuplets, feel marks, warnings, or stop semantics;
- add MusicXML, pitched notation, a generic SMuFL framework, arbitrary glyph lookup, renderer protocols, publication tooling, or additional consumers;
- preserve source/API compatibility for the removed custom glyph types;
- add a shipping old/new renderer toggle.

## Acceptance gates

HPA-163 is complete only when the same PR demonstrates all of the following:

1. `Packages/DrumNotation` builds/tests independently with `swift test --package-path Packages/DrumNotation`.
2. Virgo links the local product for macOS and iPadOS without changing the iPad-only target family.
3. The package owns the VexFlow-matching Bravura 1.392 OTF, metadata, and OFL license through `Bundle.module`.
4. Package public APIs contain only package and Apple-framework types.
5. VexFlow 5.0.0/jsdom 26.0.0 reference inputs/options/output are deterministic and committed; normal builds/tests do not execute the tool.
6. Noteheads, supported rests, open-hi-hat articulation, and flags paint from Bravura/SMuFL rather than the old handwritten paths.
7. Stems and ledger lines consume package-derived notehead metrics/anchors.
8. `DrumNoteheadGlyph`, its render plumbing, and custom path tests are removed; settings symbols are explicitly app-owned and normalized.
9. DTX identity, gameplay instrument, voice, staff position, normalized timing, fixed horizontal coordinates, beam grouping, and playhead alignment remain unchanged.
10. Package tests, affected notation tests, full macOS Virgo tests, SwiftLint, and the existing iPad simulator build pass under the repository's non-parallel test policy.

## Follow-up boundary

- **HPA-164:** move measured horizontal formatting/shared tick geometry into `DrumNotation`.
- **HPA-166:** complete reusable static-sheet rendering and VexFlow-style stem/beam/modifier behavior.

Do not pull either follow-up into HPA-163.

## References

- VexFlow 5.0.0 release/source: https://github.com/vexflow/vexflow/tree/8879d09
- VexFlow 5.0.0 package manifest: https://github.com/vexflow/vexflow/blob/8879d09/package.json
- VexFlow notehead implementation: https://github.com/vexflow/vexflow/blob/8879d09/src/notehead.ts
- VexFlow note-type/glyph mapping: https://github.com/vexflow/vexflow/blob/8879d09/src/tables.ts
- VexFlow Bravura font package: https://github.com/vexflow/vexflow-fonts/tree/main/bravura
- SMuFL noteheads: https://w3c.github.io/smufl/latest/tables/noteheads.html
- SMuFL rests: https://w3c.github.io/smufl/latest/tables/rests.html
- SMuFL percussion pictograms: https://w3c.github.io/smufl/releases/1.4/tables/percussion-playing-technique-pictograms.html
