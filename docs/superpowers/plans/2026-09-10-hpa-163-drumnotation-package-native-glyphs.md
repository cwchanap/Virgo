# HPA-163 DrumNotation Package Foundation and Native Glyphs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Use TDD for behavior changes and keep all work on this HPA-163 branch/PR.

**Goal:** Add an independently testable local `DrumNotation` Swift package, pin the VexFlow 5.0.0/Bravura 1.392 reference contract, replace Virgo's handwritten notehead/rest/flag/open-hi-hat primitives with package-owned native glyph rendering, and preserve current DTX semantics, fixed horizontal geometry, beam topology, and playhead behavior.

**Architecture:** Virgo owns DTX/domain semantics, normalized rhythm, staff positions, fixed-grid placement, beam topology, playback, and theme. `VirgoNotationAdapter` exhaustively translates app values into a small package-owned primitive vocabulary. `DrumNotation` owns Bravura/SMuFL glyph selection, fitted glyph geometry, stem anchors, and SwiftUI primitive views. VexFlow is manual reference tooling only.

**Tech Stack:** Swift 5, SwiftUI, CoreText/CoreGraphics, Swift Package Manager, Swift Testing, VexFlow 5.0.0, jsdom 26.0.0, `@vexflow-fonts/bravura` 1.0.2 / Bravura 1.392, existing Xcode 26.1.1 CI.

**Spec:** `docs/superpowers/specs/2026-09-10-hpa-163-drumnotation-package-native-glyphs-design.md`

## Global constraints

- One ticket → one PR. This draft PR is the eventual implementation PR for HPA-163; do not merge the docs and open a second implementation PR.
- No runtime JavaScript/WebView, renderer toggle, compatibility layer, package publication, generic renderer protocol, or extra Swift target.
- Package source must not import/accept Virgo `NoteType`, `DrumType`, `DrumNotationVariant`, `RenderedNoteHead`, `GameplayLayout`, `Palette`, `AppFonts`, or raw DTX values.
- Keep macOS 14.0+, iOS/iPadOS 17.5+, and existing iPad-only `TARGETED_DEVICE_FAMILY = 2`.
- Do not change `TabGrid`, tick widths, row packing, playhead X mapping, DTX parsing, rhythm inference, beam grouping/topology, or stem-run selection.
- Keep repository `xcodebuild` tests non-parallel.
- Delete `DrumNoteheadGlyph` and the superseded handwritten geometry in this PR; do not preserve source compatibility.

## File map

**Create**
- `Packages/DrumNotation/Package.swift`
- `Packages/DrumNotation/README.md`
- `Packages/DrumNotation/Sources/DrumNotation/Model/PrimitiveTypes.swift`
- `Packages/DrumNotation/Sources/DrumNotation/Glyphs/SMuFLGlyphCatalog.swift`
- `Packages/DrumNotation/Sources/DrumNotation/Glyphs/BravuraFont.swift`
- `Packages/DrumNotation/Sources/DrumNotation/Rendering/PrimitiveViews.swift`
- `Packages/DrumNotation/Sources/DrumNotation/Resources/Bravura/Bravura.otf`
- `Packages/DrumNotation/Sources/DrumNotation/Resources/Bravura/metadata.json`
- `Packages/DrumNotation/Sources/DrumNotation/Resources/Bravura/LICENSE.txt`
- `Packages/DrumNotation/Tests/DrumNotationTests/GlyphCatalogTests.swift`
- `Packages/DrumNotation/Tests/DrumNotationTests/BravuraGeometryTests.swift`
- `Packages/DrumNotation/Tests/DrumNotationTests/PrimitiveViewTests.swift`
- `Packages/DrumNotation/Tests/DrumNotationTests/Fixtures/VexFlow/primitive-reference.json`
- `Packages/DrumNotation/Tools/vexflow/{README.md,package.json,package-lock.json,fixtures.json,generate-reference.mjs}`
- `Virgo/notation/VirgoNotationAdapter.swift`
- `VirgoTests/VirgoNotationAdapterTests.swift`

**Modify**
- `Virgo.xcodeproj/project.pbxproj`
- `.github/workflows/ci.yml`
- `Virgo/constants/Drum.swift`
- `Virgo/constants/DrumNotation.swift`
- `Virgo/layout/NotationLayout.swift`
- `Virgo/layout/NotationLayoutEngine.swift`
- `Virgo/layout/NotationLayoutEngine+Beams.swift`
- `Virgo/views/NotationPrimitiveViews.swift`
- `Virgo/views/subviews/GameplaySheetMusicView.swift`
- app tests/fixtures that currently construct or assert `DrumNoteheadGlyph`, including `DrumNotationCatalogTests`, `DrumTypeExtensionsAndConstantsTests`, layout tests, `SwiftUIRenderingNotationTests`, and `DrumTabRenderProbeTests`.

---

### Task 1: Establish the local package/build boundary

**Files:** package manifest/README, Xcode project, CI.

- [ ] **Step 1: Add a red independent-package smoke test**

Create `Packages/DrumNotation/Tests/DrumNotationTests/PackageBoundaryTests.swift`:

```swift
import Testing
@testable import DrumNotation

@Test("DrumNotation is independently importable")
func packageIsImportable() {
    #expect(true)
}
```

Run:

```bash
swift test --package-path Packages/DrumNotation
```

Expected: FAIL because no package manifest/target exists yet.

- [ ] **Step 2: Add the smallest package manifest**

Create one library product, one implementation target, and one test target:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DrumNotation",
    platforms: [.iOS("17.5"), .macOS(.v14)],
    products: [.library(name: "DrumNotation", targets: ["DrumNotation"])],
    targets: [
        .target(name: "DrumNotation", resources: [.process("Resources")]),
        .testTarget(
            name: "DrumNotationTests",
            dependencies: ["DrumNotation"],
            resources: [.process("Fixtures")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
```

Add the minimal source/resource directories required for SwiftPM discovery.

Run the same `swift test` command. Expected: PASS.

- [ ] **Step 3: Link the local package into the Virgo app target**

In `Virgo.xcodeproj/project.pbxproj`, add one `XCLocalSwiftPackageReference` pointing at `Packages/DrumNotation`, one `XCSwiftPackageProductDependency`, and the product in the Virgo Frameworks build phase. Leave Apollo and all deployment/device settings unchanged.

Verify:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

- [ ] **Step 4: Extend the existing CI workflow, not the workflow count**

Add immediately before Virgo unit tests:

```yaml
- name: Run DrumNotation package tests
  run: swift test --package-path Packages/DrumNotation
```

Do not alter the existing serial `xcodebuild test` or iPad build policy.

- [ ] **Step 5: Commit**

```bash
git add Packages/DrumNotation Virgo.xcodeproj/project.pbxproj .github/workflows/ci.yml
git commit -m "build: add local DrumNotation package"
```

---

### Task 2: Pin VexFlow and Bravura reference inputs

**Files:** package resources + `Tools/vexflow` + committed reference fixture.

- [ ] **Step 1: Vendor the exact VexFlow-matching Bravura assets**

Use `vexflow/vexflow-fonts` commit `b2bc3a6070225e4d395966b36de76c36a9429b1c`, where `bravura/package.json` is `@vexflow-fonts/bravura` 1.0.2 and `README.txt` identifies Bravura 1.392.

Copy exactly:

- `bravura/bravura.otf` (Git blob `afa95d6caa68883c06a4f79981a6bdc95b135ad3`) → `Resources/Bravura/Bravura.otf`;
- `bravura/metadata.json` (blob `8de156e038f6183e4d70b0cee1d25db390405d29`) → `Resources/Bravura/metadata.json`;
- `bravura/LICENSE.txt` (blob `2ef86a39593a42e3971fb88314ed7d2b748d4ef4`) → `Resources/Bravura/LICENSE.txt`.

Record those source identifiers in the package README. Do not vendor the WOFF2 or copy the font into the app bundle separately.

- [ ] **Step 2: Pin the reference tool**

Create `Tools/vexflow/package.json`:

```json
{
  "name": "virgo-drumnotation-vexflow-reference",
  "private": true,
  "type": "module",
  "scripts": { "reference": "node generate-reference.mjs" },
  "dependencies": {
    "jsdom": "26.0.0",
    "vexflow": "5.0.0"
  }
}
```

Run from `Packages/DrumNotation/Tools/vexflow`:

```bash
npm install --package-lock-only
```

Commit the lockfile; do not commit `node_modules`.

- [ ] **Step 3: Define the focused fixture matrix**

`fixtures.json` must include all three notehead families at whole/half/quarter, an additional short-duration case proving black-head reuse, both stem directions, isolated 8/16/32/64 flags, whole/half/quarter/8/16 rests, `pictOpen`, and one representative simultaneous upper/lower head pair. Use VexFlow note types `n`, `x`, and `d`; do not encode Virgo DTX lanes in the tool fixture.

- [ ] **Step 4: Generate deterministic VexFlow reference JSON**

`generate-reference.mjs` must:

1. initialize JSDOM;
2. load VexFlow 5.0.0 and select Bravura;
3. build/preformat the focused fixture cases;
4. read only stable public/resolved fields needed by HPA-163: fixture ID, duration, stem direction, resolved notehead/rest/flag code/family, width/bounds/attachment values available from VexFlow, and open modifier placement;
5. round numeric values to three decimals;
6. sort by fixture ID;
7. emit no timestamp or machine path;
8. write only `Tests/DrumNotationTests/Fixtures/VexFlow/primitive-reference.json`.

Header:

```json
{
  "reference": {
    "vexflow": "5.0.0",
    "musicFont": "Bravura",
    "beamPolicy": "flat"
  }
}
```

Run twice:

```bash
npm ci
npm run reference
cp ../../Tests/DrumNotationTests/Fixtures/VexFlow/primitive-reference.json /tmp/primitive-reference.json
npm run reference
diff -u /tmp/primitive-reference.json ../../Tests/DrumNotationTests/Fixtures/VexFlow/primitive-reference.json
```

Expected: `diff` exits 0.

- [ ] **Step 5: Prove the Swift package is independent of Node**

Remove `node_modules`, then run:

```bash
swift test --package-path Packages/DrumNotation
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/DrumNotation/Sources/DrumNotation/Resources \
        Packages/DrumNotation/Tools/vexflow \
        Packages/DrumNotation/Tests/DrumNotationTests/Fixtures
git commit -m "test: pin VexFlow and Bravura references"
```

---

### Task 3: Implement package semantic glyph selection and font-derived geometry

**Files:** `PrimitiveTypes.swift`, `SMuFLGlyphCatalog.swift`, `BravuraFont.swift`, package tests.

- [ ] **Step 1: Write red table-driven glyph-selection tests**

Cover:

```text
normal whole -> noteheadWhole (E0A2)
normal half -> noteheadHalf (E0A3)
normal quarter/eighth/16/32/64 -> noteheadBlack (E0A4)
x whole -> noteheadXWhole (E0A7)
x half -> noteheadXHalf (E0A8)
x quarter/eighth/16/32/64 -> noteheadXBlack (E0A9)
diamond whole -> noteheadDiamondWhole (E0D8)
diamond half -> noteheadDiamondHalf (E0D9)
diamond quarter/eighth/16/32/64 -> noteheadDiamondBlack (E0DB)
rests whole...64 -> E4E3...E4E9
flags 8/16/32/64 up/down -> E240...E247
open articulation -> pictOpen (E7F8)
```

Run:

```bash
swift test --package-path Packages/DrumNotation --filter GlyphCatalogTests
```

Expected: FAIL until package model/catalog implementation exists.

- [ ] **Step 2: Implement the minimal public model and private SMuFL catalog**

Add only:

```swift
public enum NotationDuration: String, CaseIterable, Sendable {
    case whole, half, quarter, eighth, sixteenth, thirtySecond, sixtyFourth
}

public enum PercussionNoteheadStyle: String, CaseIterable, Sendable {
    case normal, x, diamond
}

public enum NotationStemDirection: String, Sendable { case up, down }
public enum PercussionArticulation: String, Sendable { case open }

public struct NoteheadMetrics: Equatable, Sendable {
    public let paintedBounds: CGRect
    public let stemAnchorOffset: CGPoint
}
```

`SMuFLGlyphCatalog` is internal and uses exhaustive switches; do not expose arbitrary glyph-name lookup publicly.

Run the focused test again. Expected: PASS.

- [ ] **Step 3: Write red Bravura geometry/resource tests**

For every accepted notehead family and both directions, assert the package can:

- resolve the scalar to a nonzero Bravura glyph;
- obtain a nonempty font-derived path;
- fit painted bounds inside the requested `CGSize(width: 30, height: 20)`;
- return finite `stemAnchorOffset` from `stemUpSE`/`stemDownNW` metadata;
- load OTF + metadata through `Bundle.module` without `Bundle.main` or `AppFonts`.

Run:

```bash
swift test --package-path Packages/DrumNotation --filter BravuraGeometryTests
```

Expected: FAIL until geometry/resource loading exists.

- [ ] **Step 4: Implement `BravuraFont` as package-local lazy state**

Use `Bundle.module` to locate the OTF/metadata. Build a `CGFont`, then a `CTFont` at `CGFloat(cgFont.unitsPerEm)` so metadata staff-space anchors can be converted using `unitsPerEm / 4`.

For a requested box:

1. `CTFontGetGlyphsForCharacters` resolves the BMP SMuFL scalar;
2. `CTFontCreatePathForGlyph` gives the font-authored outline;
3. compute one uniform scale `min(box.width/rawBounds.width, box.height/rawBounds.height)`;
4. flip Y once for SwiftUI coordinates and center the transformed path on local origin `(0,0)`;
5. apply the same scale/Y transform to `stemUpSE` or `stemDownNW` metadata;
6. expose only `NoteheadMetrics` publicly.

Fail fast in tests for a missing bundled file, glyph, or expected notehead anchor. Do not register the font process-wide and do not add AppKit/UIKit-specific branches.

Run all package tests. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/DrumNotation/Sources/DrumNotation/Model \
        Packages/DrumNotation/Sources/DrumNotation/Glyphs \
        Packages/DrumNotation/Tests/DrumNotationTests
git commit -m "feat: add Bravura percussion glyph geometry"
```

---

### Task 4: Add package-native SwiftUI primitives

**Files:** `Rendering/PrimitiveViews.swift`, `PrimitiveViewTests.swift`.

- [ ] **Step 1: Write red primitive-construction tests**

Construct every supported public view from package-only semantic types and verify, through `@testable` internal selection hooks, that it resolves the glyph expected by Task 3. Cover notehead families, every rest duration, both flag directions for 8/16/32/64, and `.open`.

Run:

```bash
swift test --package-path Packages/DrumNotation --filter PrimitiveViewTests
```

Expected: FAIL until public views exist.

- [ ] **Step 2: Implement one font-outline renderer path**

Each public view obtains fitted font-derived geometry from `BravuraFont` and fills it with SwiftUI `Canvas`/`Path`. `Color` and requested `CGSize` are explicit inputs. Do not create renderer/backend protocols.

Required public views:

```text
PercussionNoteheadView(style:duration:size:color:)
NotationRestGlyphView(duration:size:color:)
NotationFlagGlyphView(duration:direction:size:color:)
PercussionArticulationView(articulation:size:color:)
```

Run:

```bash
swift test --package-path Packages/DrumNotation
```

Expected: PASS without Virgo, app font bootstrap, Node, or network.

- [ ] **Step 3: Commit**

```bash
git add Packages/DrumNotation/Sources/DrumNotation/Rendering \
        Packages/DrumNotation/Tests/DrumNotationTests/PrimitiveViewTests.swift
git commit -m "feat: render native DrumNotation primitives"
```

---

### Task 5: Cut Virgo over through one adapter and remove `DrumNoteheadGlyph`

**Files:** adapter, `Drum.swift`, `DrumNotation.swift`, layout model/engine/beams, primitive views/sheet view, affected tests.

- [ ] **Step 1: Write red exhaustive adapter tests**

Create `VirgoTests/VirgoNotationAdapterTests.swift` and assert every app enum case:

```swift
static func expectedStyle(_ noteType: NoteType) -> PercussionNoteheadStyle {
    switch noteType {
    case .bass, .snare, .highTom, .midTom, .lowTom:
        return .normal
    case .hiHat, .hiHatPedal, .openHiHat, .crash, .ride, .china, .splash:
        return .x
    case .cowbell:
        return .diamond
    }
}
```

Also test all seven `NoteInterval` values, both `StemDirection` cases, `.openHiHat`, and the flag render policy described in Step 6.

Run focused tests and expect compile failure because the adapter does not exist yet.

- [ ] **Step 2: Implement the adapter with exhaustive switches**

`Virgo/notation/VirgoNotationAdapter.swift`:

```swift
import CoreGraphics
import DrumNotation

enum VirgoNotationAdapter {
    static func noteheadStyle(for noteType: NoteType) -> PercussionNoteheadStyle {
        switch noteType {
        case .bass, .snare, .highTom, .midTom, .lowTom:
            return .normal
        case .hiHat, .hiHatPedal, .openHiHat, .crash, .ride, .china, .splash:
            return .x
        case .cowbell:
            return .diamond
        }
    }

    static func duration(for interval: NoteInterval) -> NotationDuration {
        switch interval {
        case .full: return .whole
        case .half: return .half
        case .quarter: return .quarter
        case .eighth: return .eighth
        case .sixteenth: return .sixteenth
        case .thirtysecond: return .thirtySecond
        case .sixtyfourth: return .sixtyFourth
        }
    }

    static func stemDirection(for direction: StemDirection) -> NotationStemDirection {
        switch direction {
        case .up: return .up
        case .down: return .down
        }
    }

    static func noteheadMetrics(for head: RenderedNoteHead, size: CGSize) -> NoteheadMetrics {
        PercussionGlyphMetrics.notehead(
            style: noteheadStyle(for: head.noteType),
            duration: duration(for: head.interval),
            stemDirection: stemDirection(for: head.stemDirection),
            size: size
        )
    }
}
```

No default branches.

- [ ] **Step 3: Remove the old engraving vocabulary from app models**

Make these exact structural changes:

- delete `DrumNoteheadGlyph` and all its path/bounds/anchor helpers from `DrumNotation.swift`;
- delete `glyph` from `DrumNotationDefinition` initializers;
- delete `glyph` from `RenderedNoteHead` in `NotationLayout.swift`;
- delete `glyph: definition.glyph` from both `RenderedNoteHead` construction paths in `NotationLayoutEngine.swift`;
- update test fixture helpers/expected structs to stop passing `DrumNoteheadGlyph`.

Do not replace it with another app engraving enum.

- [ ] **Step 4: Normalize settings symbols explicitly in `Drum.swift`**

Keep `DrumType.symbol` because settings/key-mapping views use it, but make it independent from score glyphs:

```swift
var symbol: String {
    switch self {
    case .kick, .snare, .tom1, .tom2, .tom3:
        return "●"
    case .hiHat, .hiHatPedal, .crash, .ride:
        return "×"
    case .cowbell:
        return "◇"
    }
}
```

Update `DrumTypeExtensionsAndConstantsTests` to these normalized expectations. Do not import `DrumNotation` into settings views.

- [ ] **Step 5: Switch stems/ledger lines to package metrics**

In `NotationLayoutEngine+Beams.swift`:

- replace `noteHead.glyph.stemAnchorOffset(...)` with `VirgoNotationAdapter.noteheadMetrics(...).stemAnchorOffset` translated from local center to `noteHead.position`;
- replace `noteHead.glyph.bounds(...)` ledger-line extent with the package `paintedBounds` translated to the head position;
- leave all tick/X/row/beam membership decisions unchanged.

Update layout tests to derive expected anchors/bounds from the adapter/package rather than removed custom-path constants.

- [ ] **Step 6: Replace notehead/rest/open-articulation/flag painting**

In `NotationPrimitiveViews.swift`:

- `NotationNoteHeadView` delegates to `PercussionNoteheadView` using adapter style/duration and existing size/position/accessibility label;
- `NotationRestView` delegates to `NotationRestGlyphView` using `RenderedRest.interval` and existing position;
- `NotationArticulationView` delegates `.openHiHat` to `PercussionArticulationView(.open, ...)`;
- delete `DrumNoteheadShape`, rest path builders, the open `Circle`, and handwritten `FlagView` Bézier geometry.

For flags, keep `buildFlags` unchanged. In `GameplayDrumNotationView`, build dictionaries for heads and sibling flags once per rendered layout and pass that context into `NotationFlagView`.

Use this pure render decision, covered by adapter/view tests:

```text
expected levels = 0..<sourceHead.interval.flagCount
actual levels = siblingFlags.flagIndex set

if actual == expected:
  only flagIndex 0 paints;
  choose package flag duration from sourceHead.interval;
  suppress sibling RenderedFlag items because the canonical SMuFL glyph contains all hooks
else:
  every existing uncovered RenderedFlag paints one package eighth-flag hook at its existing origin
```

This removes custom flag geometry without changing beam coverage/topology. HPA-166 owns exact mixed partial-beam composition.

- [ ] **Step 7: Run the focused cutover suites**

```bash
xcodebuild test \
  -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/DrumNotationCatalogTests \
  -only-testing:VirgoTests/DrumTypeExtensionsAndConstantsTests \
  -only-testing:VirgoTests/VirgoNotationAdapterTests \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -only-testing:VirgoTests/NotationLayoutEngineChordAndBeamTests \
  -only-testing:VirgoTests/NotationLayoutDefensiveGuardTests \
  -only-testing:VirgoTests/SwiftUIRenderingNotationTests \
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Virgo VirgoTests
git commit -m "feat: use DrumNotation native glyphs in Virgo"
```

---

### Task 6: Prove regression boundaries and finish the single PR

**Files:** package README, affected Virgo tests/goldens only where justified.

- [ ] **Step 1: Remove duplicated handwritten-path tests**

Delete tests whose only responsibility was `DrumNoteheadGlyph.makePath`, custom normalized bounds, even-odd fill, or custom stem-anchor geometry. Package glyph/geometry tests replace them.

Keep Virgo tests for DTX/catalog mapping, adapter mapping, mounted SwiftUI wrappers, production ink, timing, beam membership, and playhead alignment.

- [ ] **Step 2: Run notation regression suites before touching goldens**

```bash
xcodebuild test \
  -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  -only-testing:VirgoTests/DrumTabRegressionInvariantTests \
  -only-testing:VirgoTests/DrumTabRenderProbeTests \
  -only-testing:VirgoTests/DrumTabPlayheadAlignmentTests \
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300
```

If a golden changes, inspect it before updating. HPA-163 may change glyph identity/painted metric fields; it must not change absolute tick, measure/row, note X, beam membership/topology, or playhead routing.

- [ ] **Step 3: Run full package + app verification fresh**

```bash
rm -rf Packages/DrumNotation/.build
swift test --package-path Packages/DrumNotation

xcodebuild test \
  -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests \
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES -destination-timeout 300 \
  -derivedDataPath ./DerivedData

xcodebuild build \
  -project Virgo.xcodeproj -scheme Virgo \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

swiftlint lint
```

Expected: all commands pass; iOS-family target remains iPad-only.

- [ ] **Step 4: Run package-boundary audits**

```bash
grep -R -nE 'import Virgo|NoteType|DrumType|DrumNotationVariant|RenderedNoteHead|GameplayLayout|Palette|AppFonts|Bundle\.main' \
  Packages/DrumNotation/Sources Packages/DrumNotation/Tests || true

grep -R -nE 'vexflow|jsdom' \
  Packages/DrumNotation/Package.swift Packages/DrumNotation/Sources Virgo Virgo.xcodeproj/project.pbxproj || true

find Packages/DrumNotation -type l -print
git grep -n 'DrumNoteheadGlyph' -- Virgo VirgoTests || true
```

Expected:

- no app-domain/theme dependency in package Swift source;
- no shipping VexFlow/jsdom dependency;
- no package symlinks escaping into Virgo;
- no remaining `DrumNoteheadGlyph` production/test reference.

- [ ] **Step 5: Final README and diff review**

Document only implemented facts: supported platforms, Bravura 1.392 source/version, package test command, manual VexFlow reference command, and explicit HPA-164/HPA-166 follow-up boundary.

Review:

```bash
git diff main...HEAD --stat
git diff main...HEAD -- Packages/DrumNotation Virgo/layout Virgo/views Virgo/constants .github/workflows/ci.yml
git diff --check main...HEAD
```

Reject any accidental formatter/beam-topology/DTX/runtime-JS/publication expansion.

- [ ] **Step 6: Commit final test/doc adjustments on the same PR**

```bash
git add Packages/DrumNotation VirgoTests
git commit -m "test: verify DrumNotation package integration"
```

## Completion checklist

Before marking this same HPA-163 PR ready for review:

- [ ] clean `swift test --package-path Packages/DrumNotation` passes;
- [ ] full serial `VirgoTests` pass;
- [ ] generic iOS Simulator build passes with iPad-only target unchanged;
- [ ] SwiftLint and `git diff --check` pass;
- [ ] deterministic VexFlow 5.0.0 reference output is committed and Node-free during normal Swift tests;
- [ ] Bravura 1.392 OTF/metadata/license are package-owned from the pinned VexFlow font source;
- [ ] package APIs/sources contain no Virgo types/theme/font bootstrap;
- [ ] noteheads/rests/open articulation/flags paint from Bravura font glyphs;
- [ ] package metrics drive stem anchors and ledger bounds;
- [ ] `DrumNoteheadGlyph` and handwritten primitive geometry are gone;
- [ ] DTX identity, voice/staff placement, normalized ticks, note X, beam grouping, and playhead alignment are unchanged;
- [ ] HPA-164 remains responsible for measured horizontal formatting and HPA-166 for complete reusable beam/modifier rendering.
