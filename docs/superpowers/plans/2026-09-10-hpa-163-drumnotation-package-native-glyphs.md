# HPA-163 DrumNotation Package Foundation and Native Glyphs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create an independently testable local `DrumNotation` Swift package, pin the VexFlow/Bravura reference contract, replace Virgo's handwritten percussion glyph primitives with native package-owned Bravura/SMuFL rendering, and preserve the current fixed spacing and beam topology.

**Architecture:** Virgo keeps DTX/domain semantics, normalized rhythm, positions, fixed-grid layout, and beam topology. `VirgoNotationAdapter` converts existing rendered app values into a small package-owned primitive vocabulary; `DrumNotation` owns glyph selection, Bravura resources/metadata, metrics, and SwiftUI glyph primitives. VexFlow is development-only reference tooling with committed output.

**Tech Stack:** Swift 5, SwiftUI, CoreText/CoreGraphics, Swift Package Manager, Swift Testing, Bravura 1.482 / SMuFL, VexFlow 5.0.0 + Node/jsdom reference tooling, Xcode 26.1.1 CI.

**Spec:** `docs/superpowers/specs/2026-09-10-hpa-163-drumnotation-package-native-glyphs-design.md`

## Global Constraints

- Exactly one PR for HPA-163.
- Keep VexFlow pinned to 5.0.0 and out of the shipping app/package dependency graph.
- Pin Bravura 1.482 and use `Bravura.otf` plus matching `Bravura.json` from that release.
- `DrumNotation` has one library product/module, one implementation target, and one test target.
- Package APIs must not import or accept Virgo `Note`, `DrumType`, `NoteType`, `GameplayLayout`, `Palette`, `AppFonts`, or raw DTX types.
- Keep macOS 14.0+ and iOS/iPadOS 17.5+; Virgo stays iPad-only for iOS-family builds.
- Do not change `TabGrid`, tick spacing, row packing, playhead X mapping, beam grouping/topology, DTX parsing, or rhythm inference.
- Keep `xcodebuild` tests non-parallel as required by the repository.
- Delete superseded handwritten notehead/rest/flag/open-articulation paths in this PR; do not add a renderer toggle or compatibility layer.
- Do not create publication/release automation, extra package targets, generic renderer protocols, or abstractions for hypothetical consumers.

---

## File map

**Create**
- `Packages/DrumNotation/Package.swift` — package/product/target/resource declaration.
- `Packages/DrumNotation/README.md` — supported primitive scope, versions, reference-tool command.
- `Packages/DrumNotation/Sources/DrumNotation/Model/PrimitiveTypes.swift` — public duration/style/direction/articulation and metric value types.
- `Packages/DrumNotation/Sources/DrumNotation/Glyphs/SMuFLGlyphCatalog.swift` — private accepted SMuFL names/code points and semantic selection.
- `Packages/DrumNotation/Sources/DrumNotation/Glyphs/BravuraResources.swift` — `Bundle.module` font registration, metadata decode, metrics.
- `Packages/DrumNotation/Sources/DrumNotation/Rendering/NotationGlyphView.swift` — private common Bravura glyph renderer.
- `Packages/DrumNotation/Sources/DrumNotation/Rendering/PrimitiveViews.swift` — public notehead/rest/flag/open-articulation SwiftUI primitives.
- `Packages/DrumNotation/Sources/DrumNotation/Resources/Bravura/Bravura.otf` — pinned Bravura 1.482 font.
- `Packages/DrumNotation/Sources/DrumNotation/Resources/Bravura/Bravura.json` — matching font metadata.
- `Packages/DrumNotation/Sources/DrumNotation/Resources/Bravura/OFL.txt` — SIL OFL notice from the same release.
- `Packages/DrumNotation/Tests/DrumNotationTests/PackageBoundaryTests.swift` — independent package import smoke test.
- `Packages/DrumNotation/Tests/DrumNotationTests/GlyphCatalogTests.swift` — semantic-to-SMuFL mapping tests.
- `Packages/DrumNotation/Tests/DrumNotationTests/BravuraMetricsTests.swift` — resource/anchor/bounds tests.
- `Packages/DrumNotation/Tests/DrumNotationTests/PrimitiveViewTests.swift` — package-only rendering smoke tests.
- `Packages/DrumNotation/Tests/DrumNotationTests/Fixtures/VexFlow/primitive-reference.json` — committed reference output.
- `Packages/DrumNotation/Tools/vexflow/README.md` — regeneration contract/options.
- `Packages/DrumNotation/Tools/vexflow/package.json` and `package-lock.json` — exact reference tool dependencies.
- `Packages/DrumNotation/Tools/vexflow/fixtures.json` — focused percussion fixture matrix.
- `Packages/DrumNotation/Tools/vexflow/generate-reference.mjs` — manual reference generator.
- `Virgo/notation/VirgoNotationAdapter.swift` — only app-to-package translation seam.
- `VirgoTests/VirgoNotationAdapterTests.swift` — complete app-to-package mapping and flag-render rule tests.

**Modify**
- `Virgo.xcodeproj/project.pbxproj` — add local Swift package reference/product to Virgo target.
- `.github/workflows/ci.yml` — execute independent package tests.
- `Virgo/constants/DrumNotation.swift` — remove visual path geometry and keep app semantic/DTX catalog responsibilities.
- `Virgo/layout/NotationLayoutEngine+Beams.swift` — consume package-backed notehead metrics; preserve beam/flag topology.
- `Virgo/views/NotationPrimitiveViews.swift` — delegate covered primitives to package views and delete custom paths.
- `Virgo/views/subviews/GameplaySheetMusicView.swift` — build source-head/sibling-flag lookup context for flag rendering; preserve layer order.
- `VirgoTests/DrumNotationCatalogTests.swift` — keep app mapping tests and remove moved pure path tests.
- `VirgoTests/NotationLayoutEngineTests.swift`, `VirgoTests/NotationLayoutEngineChordAndBeamTests.swift`, `VirgoTests/NotationLayoutDefensiveGuardTests.swift` — update anchor expectations.
- `VirgoTests/SwiftUIRenderingNotationTests.swift` — wrapper/mounting smoke coverage.
- `VirgoTests/DrumTabRenderProbeTests.swift` — preserve production ink probe after primitive replacement.

---

### Task 1: Scaffold the package and wire the build boundary

**Files:**
- Create: `Packages/DrumNotation/Package.swift`
- Create: `Packages/DrumNotation/README.md`
- Create: `Packages/DrumNotation/Tests/DrumNotationTests/PackageBoundaryTests.swift`
- Modify: `Virgo.xcodeproj/project.pbxproj`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: importable local module `DrumNotation`.
- Produces: independent command `swift test --package-path Packages/DrumNotation`.
- Consumes: no Virgo source.

- [ ] **Step 1: Create a failing package smoke test before the implementation target exists**

Create `Packages/DrumNotation/Tests/DrumNotationTests/PackageBoundaryTests.swift`:

```swift
import Testing
@testable import DrumNotation

@Test("DrumNotation package is independently importable")
func packageIsImportable() {
    #expect(true)
}
```

- [ ] **Step 2: Run the package test and verify the package boundary is missing**

Run:

```bash
swift test --package-path Packages/DrumNotation
```

Expected: failure because `Package.swift` / target sources are not yet present.

- [ ] **Step 3: Add the minimal manifest and empty module marker**

Create `Packages/DrumNotation/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DrumNotation",
    platforms: [
        .iOS("17.5"),
        .macOS(.v14)
    ],
    products: [
        .library(name: "DrumNotation", targets: ["DrumNotation"])
    ],
    targets: [
        .target(
            name: "DrumNotation",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DrumNotationTests",
            dependencies: ["DrumNotation"],
            resources: [.process("Fixtures")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
```

Create `Packages/DrumNotation/Sources/DrumNotation/DrumNotation.swift` with only the module documentation comment, and create empty `.keep` files below `Resources/` and test `Fixtures/` until real assets land in later tasks.

- [ ] **Step 4: Run the package smoke test**

Run:

```bash
swift test --package-path Packages/DrumNotation
```

Expected: PASS without building or importing Virgo.

- [ ] **Step 5: Link the local package product to Virgo**

Add an `XCLocalSwiftPackageReference` for `Packages/DrumNotation` and an `XCSwiftPackageProductDependency` for `DrumNotation`, then add the product to the Virgo app target's Frameworks build phase. Do not modify `TARGETED_DEVICE_FAMILY`, deployment targets, or the existing Apollo remote package.

Verify:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Expected: Virgo builds with the local product linked.

- [ ] **Step 6: Add the package test to existing CI**

Add this step immediately before `Run unit tests` in `.github/workflows/ci.yml`:

```yaml
      - name: Run DrumNotation package tests
        run: swift test --package-path Packages/DrumNotation
```

Do not create a new workflow and do not alter the existing non-parallel app test command.

- [ ] **Step 7: Commit the build boundary**

```bash
git add Packages/DrumNotation Virgo.xcodeproj/project.pbxproj .github/workflows/ci.yml
git commit -m "build: add local DrumNotation package"
```

---

### Task 2: Pin the VexFlow reference contract and fixtures

**Files:**
- Create: `Packages/DrumNotation/Tools/vexflow/package.json`
- Create: `Packages/DrumNotation/Tools/vexflow/package-lock.json`
- Create: `Packages/DrumNotation/Tools/vexflow/fixtures.json`
- Create: `Packages/DrumNotation/Tools/vexflow/generate-reference.mjs`
- Create: `Packages/DrumNotation/Tools/vexflow/README.md`
- Create: `Packages/DrumNotation/Tests/DrumNotationTests/Fixtures/VexFlow/primitive-reference.json`

**Interfaces:**
- Produces: reviewed immutable reference data consumed by package tests as fixture input.
- Produces: manual regeneration command `npm ci && npm run reference`.
- Does not run during Swift tests or app build.

- [ ] **Step 1: Define the exact reference dependencies**

Create `package.json`:

```json
{
  "name": "virgo-drumnotation-vexflow-reference",
  "private": true,
  "type": "module",
  "scripts": {
    "reference": "node generate-reference.mjs"
  },
  "dependencies": {
    "jsdom": "21.1.2",
    "vexflow": "5.0.0"
  }
}
```

Run `npm install --package-lock-only` from `Packages/DrumNotation/Tools/vexflow/` and commit the generated lockfile.

- [ ] **Step 2: Add the focused fixture matrix**

`fixtures.json` must include:

```json
{
  "options": {
    "musicFont": "Bravura",
    "upperStemDirection": "up",
    "lowerStemDirection": "down",
    "beamPolicy": "flat"
  },
  "noteheads": [
    {"id":"normal-whole","style":"normal","duration":"w","line":3,"stem":"up"},
    {"id":"normal-half","style":"normal","duration":"h","line":3,"stem":"up"},
    {"id":"normal-quarter","style":"normal","duration":"q","line":3,"stem":"up"},
    {"id":"x-quarter","style":"x","duration":"q","line":5,"stem":"up"},
    {"id":"diamond-quarter","style":"diamond","duration":"q","line":4,"stem":"up"}
  ],
  "flags": ["8","16","32","64"],
  "rests": ["w","h","q","8","16"],
  "articulations": ["open"],
  "simultaneous": [
    {"id":"kick-hat","lower":"normal","upper":"x"}
  ]
}
```

Expand normal/X/diamond notehead entries to cover every duration-specific glyph family selected by the package; do not add DTX lane IDs.

- [ ] **Step 3: Implement the deterministic reference generator**

`generate-reference.mjs` must:

1. initialize a JSDOM document;
2. load VexFlow 5.0.0 with Bravura;
3. render each fixture to an SVG backend;
4. call `preFormat()`/formatting before reading notehead geometry;
5. serialize only stable primitive fields (fixture ID, duration, stem direction, resolved notehead type/glyph code, width/bounds, stem attachment coordinates, rest/flag type, articulation/modifier position);
6. round numeric output to three decimals;
7. sort output by fixture ID;
8. write only `Tests/DrumNotationTests/Fixtures/VexFlow/primitive-reference.json`.

The output header must contain:

```json
{
  "reference": {
    "vexflow": "5.0.0",
    "musicFont": "Bravura",
    "beamPolicy": "flat"
  }
}
```

No timestamp belongs in the output, so regenerating without dependency/fixture changes produces no diff.

- [ ] **Step 4: Generate and review the reference output**

Run:

```bash
cd Packages/DrumNotation/Tools/vexflow
npm ci
npm run reference
git diff -- ../../Tests/DrumNotationTests/Fixtures/VexFlow/primitive-reference.json
```

Expected: reference JSON contains every fixture and no machine-specific absolute path or timestamp.

- [ ] **Step 5: Document the reference contract**

In `Tools/vexflow/README.md`, record:

- VexFlow 5.0.0 is the migration reference, not a shipping dependency;
- Bravura is the selected VexFlow music font;
- upper voice stems up, lower voice stems down;
- flat-beam policy;
- exact duration encodings;
- dots/tuplets are captured only as later-ticket references;
- simultaneous fixture X positions are not acceptance criteria in HPA-163;
- mixed/partial-beam flag composition remains an expected HPA-166 delta.

- [ ] **Step 6: Prove Swift tests do not require Node**

Temporarily move `node_modules` out of the tool directory or remove it after generation, then run:

```bash
swift test --package-path Packages/DrumNotation
```

Expected: PASS; SwiftPM reads only committed fixture data.

- [ ] **Step 7: Commit the reference contract**

```bash
git add Packages/DrumNotation/Tools/vexflow \
        Packages/DrumNotation/Tests/DrumNotationTests/Fixtures/VexFlow
git commit -m "test: pin VexFlow percussion references"
```

---

### Task 3: Add Bravura resources, semantic glyph catalog, and metrics

**Files:**
- Create: `Packages/DrumNotation/Sources/DrumNotation/Model/PrimitiveTypes.swift`
- Create: `Packages/DrumNotation/Sources/DrumNotation/Glyphs/SMuFLGlyphCatalog.swift`
- Create: `Packages/DrumNotation/Sources/DrumNotation/Glyphs/BravuraResources.swift`
- Add: `Packages/DrumNotation/Sources/DrumNotation/Resources/Bravura/Bravura.otf`
- Add: `Packages/DrumNotation/Sources/DrumNotation/Resources/Bravura/Bravura.json`
- Add: `Packages/DrumNotation/Sources/DrumNotation/Resources/Bravura/OFL.txt`
- Create: `Packages/DrumNotation/Tests/DrumNotationTests/GlyphCatalogTests.swift`
- Create: `Packages/DrumNotation/Tests/DrumNotationTests/BravuraMetricsTests.swift`

**Interfaces:**
- Produces: `NotationDuration`, `PercussionNoteheadStyle`, `NotationStemDirection`, `PercussionArticulation`.
- Produces: `NoteheadMetrics` and `PercussionGlyphMetrics.notehead(style:duration:stemDirection:size:)`.
- Keeps SMuFL code points and font/metadata decoder private.

- [ ] **Step 1: Add failing semantic selection tests**

Write table-driven tests that assert:

```swift
#expect(testGlyphName(style: .normal, duration: .whole) == "noteheadWhole")
#expect(testGlyphName(style: .normal, duration: .half) == "noteheadHalf")
#expect(testGlyphName(style: .normal, duration: .quarter) == "noteheadBlack")
#expect(testGlyphName(style: .x, duration: .half) == "noteheadXHalf")
#expect(testGlyphName(style: .x, duration: .sixteenth) == "noteheadXBlack")
#expect(testGlyphName(style: .diamond, duration: .whole) == "noteheadDiamondWhole")
#expect(testGlyphName(style: .diamond, duration: .thirtySecond) == "noteheadDiamondBlack")
```

Also assert rest and flag selection across the complete supported duration/direction matrix and `.open` → `pictOpen`.

Expose glyph names to tests with `@testable import` internal helpers; do not make raw glyph lookup public.

- [ ] **Step 2: Run package tests and confirm missing semantic types/catalog**

```bash
swift test --package-path Packages/DrumNotation --filter GlyphCatalogTests
```

Expected: compile failure until the model/catalog exists.

- [ ] **Step 3: Implement the small public semantic model**

Add the exact public enums and `NoteheadMetrics` from the design spec. Do not add app instrument/DTX enums.

- [ ] **Step 4: Implement the accepted private SMuFL catalog**

Define an internal `SMuFLGlyph` with canonical name + Unicode scalar and explicit selector switches. At minimum include:

```swift
case noteheadWhole = 0xE0A2
case noteheadHalf = 0xE0A3
case noteheadBlack = 0xE0A4
case noteheadXWhole = 0xE0A7
case noteheadXHalf = 0xE0A8
case noteheadXBlack = 0xE0A9
case noteheadDiamondWhole = 0xE0D8
case noteheadDiamondHalf = 0xE0D9
case noteheadDiamondBlack = 0xE0DB
case restWhole = 0xE4E3
case restHalf = 0xE4E4
case restQuarter = 0xE4E5
case rest8th = 0xE4E6
case rest16th = 0xE4E7
case rest32nd = 0xE4E8
case rest64th = 0xE4E9
case flag8thUp = 0xE240
case flag8thDown = 0xE241
case flag16thUp = 0xE242
case flag16thDown = 0xE243
case flag32ndUp = 0xE244
case flag32ndDown = 0xE245
case flag64thUp = 0xE246
case flag64thDown = 0xE247
case pictOpen = 0xE7F8
```

Quarter and shorter noteheads share the black member of their family.

- [ ] **Step 5: Add pinned Bravura 1.482 assets**

Download `Bravura.otf`, `Bravura.json`, and the matching OFL notice from the Bravura 1.482 release, place them only under package `Resources/Bravura/`, and record the upstream release/tag in `Packages/DrumNotation/README.md`.

Verify no duplicate copy is added under `Virgo/Resources/Fonts`.

- [ ] **Step 6: Add failing resource and anchor tests**

Tests must call only package APIs and assert:

```swift
let metrics = PercussionGlyphMetrics.notehead(
    style: .normal,
    duration: .quarter,
    stemDirection: .up,
    size: CGSize(width: 30, height: 20)
)
#expect(metrics.bounds.width > 0)
#expect(metrics.bounds.height > 0)
#expect(metrics.stemAnchor.x.isFinite)
#expect(metrics.stemAnchor.y.isFinite)
```

Repeat for `.down` and all three notehead families. Add a resource test that resolves the package font/metadata through the internal `BravuraResources` helper without any call to Virgo `AppFonts`.

- [ ] **Step 7: Implement package-local font registration and metadata scaling**

`BravuraResources` should:

- resolve `Bravura.otf` / `Bravura.json` through `Bundle.module`;
- register the OTF with CoreText process scope;
- accept only `alreadyRegistered` / `duplicatedName` as benign;
- decode `glyphsWithAnchors` and optional `glyphBBoxes` once;
- scale SMuFL staff-space coordinates into the requested local primitive size;
- select `stemUpSE` or `stemDownNW` for notehead attachment;
- fail a test if an accepted glyph lacks the required anchor.

Do not expose `CTFont` or decoded metadata publicly.

- [ ] **Step 8: Run the focused package tests**

```bash
swift test --package-path Packages/DrumNotation \
  --filter GlyphCatalogTests
swift test --package-path Packages/DrumNotation \
  --filter BravuraMetricsTests
```

Expected: PASS.

- [ ] **Step 9: Commit the native glyph foundation**

```bash
git add Packages/DrumNotation/Sources Packages/DrumNotation/Tests/DrumNotationTests
git commit -m "feat: add Bravura percussion glyph catalog"
```

---

### Task 4: Implement native SwiftUI primitive views

**Files:**
- Create: `Packages/DrumNotation/Sources/DrumNotation/Rendering/NotationGlyphView.swift`
- Create: `Packages/DrumNotation/Sources/DrumNotation/Rendering/PrimitiveViews.swift`
- Create: `Packages/DrumNotation/Tests/DrumNotationTests/PrimitiveViewTests.swift`

**Interfaces:**
- Consumes: semantic types and internal SMuFL selector from Task 3.
- Produces: `PercussionNoteheadView`, `NotationRestGlyphView`, `NotationFlagGlyphView`, `PercussionArticulationView`.

- [ ] **Step 1: Add failing view construction tests**

For every supported enum combination, construct the public view with a fixed size and assert its internal selected glyph through an `@testable` test hook. Include noteheads, rests, flags in both directions, and `.open`.

Do not add pixel goldens; the app already has a differential render probe and font rasterization can vary across Xcode/macOS.

- [ ] **Step 2: Run the focused test and confirm views are missing**

```bash
swift test --package-path Packages/DrumNotation --filter PrimitiveViewTests
```

Expected: compile failure until the rendering types exist.

- [ ] **Step 3: Implement one private glyph renderer**

`NotationGlyphView` accepts internal `SMuFLGlyph`, explicit `CGSize`, and `Color`; it ensures Bravura registration and renders the selected Unicode scalar with Bravura centered in the requested local frame.

Keep coordinate normalization in this one file. Do not add a renderer protocol or separate AppKit/UIKit backend.

- [ ] **Step 4: Implement the four public primitive wrappers**

Each wrapper only maps semantic input to one internal glyph and delegates to `NotationGlyphView`.

For flags, canonical isolated durations map to the matching `flag8th` / `flag16th` / `flag32nd` / `flag64th` glyph. Reject whole/half/quarter for flag construction in the package's internal selector.

- [ ] **Step 5: Run all package tests**

```bash
swift test --package-path Packages/DrumNotation
```

Expected: PASS without Virgo, Node, or app font registration.

- [ ] **Step 6: Commit package rendering**

```bash
git add Packages/DrumNotation/Sources/DrumNotation/Rendering \
        Packages/DrumNotation/Tests/DrumNotationTests/PrimitiveViewTests.swift
git commit -m "feat: render native percussion glyph primitives"
```

---

### Task 5: Add the Virgo adapter and cut production primitives over

**Files:**
- Create: `Virgo/notation/VirgoNotationAdapter.swift`
- Create: `VirgoTests/VirgoNotationAdapterTests.swift`
- Modify: `Virgo/constants/DrumNotation.swift`
- Modify: `Virgo/layout/NotationLayoutEngine+Beams.swift`
- Modify: `Virgo/views/NotationPrimitiveViews.swift`
- Modify: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Modify: `VirgoTests/DrumNotationCatalogTests.swift`

**Interfaces:**
- Consumes: current `RenderedNoteHead`, `RenderedRest`, `RenderedFlag`, `RenderedArticulation` and package public values.
- Produces: one app-owned translation seam; existing production wrapper view names stay stable.
- Preserves: current `NotationLayout` coordinates, layer order, beam topology, DTX mapping.

- [ ] **Step 1: Add failing adapter mapping tests**

Assert the complete semantic legend:

```swift
#expect(VirgoNotationAdapter.noteheadStyle(for: .bass) == .normal)
#expect(VirgoNotationAdapter.noteheadStyle(for: .snare) == .normal)
#expect(VirgoNotationAdapter.noteheadStyle(for: .highTom) == .normal)
#expect(VirgoNotationAdapter.noteheadStyle(for: .hiHat) == .x)
#expect(VirgoNotationAdapter.noteheadStyle(for: .openHiHat) == .x)
#expect(VirgoNotationAdapter.noteheadStyle(for: .crash) == .x)
#expect(VirgoNotationAdapter.noteheadStyle(for: .ride) == .x)
#expect(VirgoNotationAdapter.noteheadStyle(for: .cowbell) == .diamond)
```

Cover all `NoteType` cases, all supported `NoteInterval` → `NotationDuration` mappings, both stem directions, and open-hi-hat articulation. Add a pure adapter test for the flag render rule: a fully-unbeamed sixteenth suppresses level 1 and renders one `.sixteenth` glyph at level 0, while a partially-uncovered level renders one `.eighth` component without altering its origin.

- [ ] **Step 2: Run focused app tests and confirm adapter is missing**

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/VirgoNotationAdapterTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO test
```

Expected: compile failure until the adapter exists.

- [ ] **Step 3: Implement `VirgoNotationAdapter` with pure static conversions**

Keep it dependency-light:

```swift
import CoreGraphics
import DrumNotation

enum VirgoNotationAdapter {
    static func noteheadStyle(for noteType: NoteType) -> PercussionNoteheadStyle { ... }
    static func duration(for interval: NoteInterval) -> NotationDuration { ... }
    static func stemDirection(for direction: StemDirection) -> NotationStemDirection { ... }

    static func noteheadMetrics(
        for head: RenderedNoteHead,
        size: CGSize
    ) -> NoteheadMetrics {
        PercussionGlyphMetrics.notehead(
            style: noteheadStyle(for: head.noteType),
            duration: duration(for: head.interval),
            stemDirection: stemDirection(for: head.stemDirection),
            size: size
        )
    }
}
```

The ellipses above stand for the exhaustive switches covered by the table-driven adapter tests; do not add defaults that hide a new app enum case.

Do not pass `NoteType` or `RenderedNoteHead` into the package itself.

- [ ] **Step 4: Switch stem and ledger calculations to package metrics**

In `NotationLayoutEngine+Beams.swift`:

- `stemAnchor(for:style:)` gets the local `stemAnchor` from `VirgoNotationAdapter.noteheadMetrics(...)` and translates it around `noteHead.position`;
- ledger-line bounds use the returned package `bounds` translated around `noteHead.position`;
- keep every X/tick/beam-group decision unchanged.

Add/adjust assertions in `NotationLayoutEngineTests`, `NotationLayoutEngineChordAndBeamTests`, and `NotationLayoutDefensiveGuardTests` so expected anchors are obtained through the adapter/package contract rather than the removed `DrumNoteheadGlyph` path helper.

- [ ] **Step 5: Replace the production notehead/rest/articulation views**

In `NotationPrimitiveViews.swift`:

- delete `DrumNoteheadShape`;
- make `NotationNoteHeadView` instantiate `PercussionNoteheadView`, then apply the existing `.position(noteHead.position)` and accessibility label;
- replace `quarterRestPath` / `hookedRestPath` and full/half rectangles with `NotationRestGlyphView` using the existing `RenderedRest.position`;
- replace the open-hi-hat `Circle` with `PercussionArticulationView(articulation: .open, ...)`;
- preserve `Palette.chalk` only as an explicit `color:` passed at the app wrapper boundary.

Do not move `Palette` into the package.

- [ ] **Step 6: Replace flag drawing without changing flag topology**

Delete `FlagView` and the custom Bézier path.

Build `headsByID` and `flagsByHeadID` once in `GameplayDrumNotationView`, and pass the source head plus its sibling flags into `NotationFlagView`.

Use this exact render-time rule:

```swift
let expectedLevels = Set(0..<sourceHead.interval.flagCount)
let actualLevels = Set(siblingFlags.map(\.flagIndex))

if actualLevels == expectedLevels {
    // Canonical isolated flag: one SMuFL glyph contains all hooks.
    guard flag.flagIndex == 0 else { return EmptyView() }
    return NotationFlagGlyphView(
        duration: VirgoNotationAdapter.duration(for: sourceHead.interval),
        direction: VirgoNotationAdapter.stemDirection(for: flag.stemDirection),
        size: flagSize,
        color: Palette.chalk
    )
}

// Partial coverage: preserve the current per-level origin/topology.
return NotationFlagGlyphView(
    duration: .eighth,
    direction: VirgoNotationAdapter.stemDirection(for: flag.stemDirection),
    size: flagSize,
    color: Palette.chalk
)
```

Implement this in an `@ViewBuilder` helper (or equivalent view composition) so the `EmptyView` and glyph branches remain type-safe.

Keep the current `RenderedFlag` array and `buildFlags` logic unchanged. Do not persist new flag state solely for rendering. Mixed/partial-beam composition remains a documented HPA-166 delta.

- [ ] **Step 7: Remove superseded visual geometry from the app catalog**

In `DrumNotation.swift`, keep:

- DTX lane resolution;
- `NoteType`/`DrumType`;
- voice and default stem direction;
- staff positions and position overrides;
- semantic variants.

Remove `DrumNoteheadGlyph.makePath`, `normalizedBounds`, `usesEvenOddFill`, `stemAnchorOffset`, and the old half-filled/bullseye/open-circle path vocabulary once no caller remains. If the `glyph` field on `DrumNotationDefinition` is redundant after the adapter owns visual-family projection, remove it and update affected initializers in the same PR rather than preserving compatibility.

- [ ] **Step 8: Run focused adapter/layout/render tests**

```bash
xcodebuild test \
  -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/DrumNotationCatalogTests \
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

- [ ] **Step 9: Commit the production cutover**

```bash
git add Virgo VirgoTests
git commit -m "feat: use DrumNotation native glyphs in Virgo"
```

---

### Task 6: Reconcile regression coverage and prove layout behavior did not move

**Files:**
- Modify: `VirgoTests/DrumNotationCatalogTests.swift`
- Modify: `VirgoTests/SwiftUIRenderingNotationTests.swift`
- Modify: `VirgoTests/DrumTabRenderProbeTests.swift`
- Review/run unchanged: `VirgoTests/DrumTabGoldenTests.swift`
- Review/run unchanged: `VirgoTests/DrumTabRegressionInvariantTests.swift`
- Review/run unchanged: `VirgoTests/DrumTabPlayheadAlignmentTests.swift`

**Interfaces:**
- Package owns primitive/glyph/metric correctness.
- Virgo owns app mapping, production mounting, layout/timing invariants.

- [ ] **Step 1: Delete duplicate custom-path tests from Virgo**

Remove tests whose only purpose is `DrumNoteheadGlyph.makePath`, custom normalized bounds, or custom stem-anchor geometry. Do not recreate them under new names in Virgo; package tests from Tasks 3–4 replace them.

- [ ] **Step 2: Keep wrapper/mounting tests app-focused**

Update `SwiftUIRenderingNotationTests` so it still proves:

- every app semantic notehead can mount through `NotationNoteHeadView`;
- supported printed rests mount with the same semantic accessibility labels;
- open-hi-hat ownership/label behavior remains correct;
- both flag directions mount;
- no yellow highlighting returns.

The test should not reach into Bravura's private raw glyph catalog.

- [ ] **Step 3: Keep the production differential ink probe**

Update `DrumTabRenderProbeTests` only as required by the flag wrapper signature/package-backed primitives. Preserve the production layer order and keep the probe comparing live ink instead of storing pixel goldens.

- [ ] **Step 4: Run the full notation regression set**

Run:

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

Expected:
- invariant and playhead suites PASS with no horizontal/timing change;
- golden diffs, if any, are limited to visual/glyph identity fields that the digest intentionally records. Do not regenerate a geometry/timing golden merely to hide a spacing/beam change.

- [ ] **Step 5: Inspect any golden diff before accepting it**

If a golden changes, verify all of these remain byte-equivalent where represented:

- time column / absolute tick;
- measure row and X placement;
- beam membership/topology;
- playhead X routing.

Only the superseded glyph identity/metric portions may change under HPA-163.

- [ ] **Step 6: Commit test migration only after the invariants prove the boundary**

```bash
git add VirgoTests
git commit -m "test: cover DrumNotation package integration"
```

---

### Task 7: Final cross-platform verification and documentation cleanup

**Files:**
- Modify: `Packages/DrumNotation/README.md`
- Modify only when verification finds a factual mismatch: design spec / implementation plan.
- No feature expansion.

**Interfaces:**
- Produces: an independently buildable package and a Virgo app integration ready for HPA-164.

- [ ] **Step 1: Run all package tests from a clean package build**

```bash
rm -rf Packages/DrumNotation/.build
swift test --package-path Packages/DrumNotation
```

Expected: PASS with no app host and no Node install.

- [ ] **Step 2: Run the full Virgo macOS unit suite with repository CI settings**

```bash
xcodebuild test \
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
```

Expected: PASS.

- [ ] **Step 3: Verify the iPad-only build**

```bash
xcodebuild build \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

Expected: PASS with existing `TARGETED_DEVICE_FAMILY = 2`.

- [ ] **Step 4: Run lint**

```bash
swiftlint lint
```

Expected: no new errors.

- [ ] **Step 5: Verify package isolation mechanically**

Run:

```bash
grep -R -nE 'import Virgo|NoteType|DrumType|GameplayLayout|Palette|AppFonts|Bundle\.main' \
  Packages/DrumNotation/Sources Packages/DrumNotation/Tests || true
```

Expected: no package source dependency on app-owned symbols. Test fixture prose may mention reference concepts, but Swift source must remain clean.

Also verify:

```bash
find Packages/DrumNotation -type l -print
grep -R -n '\.\./\.\./Virgo' Packages/DrumNotation || true
```

Expected: no symlink or path escape into Virgo.

- [ ] **Step 6: Verify the shipping target has no VexFlow dependency**

Run:

```bash
grep -R -nE 'vexflow|jsdom' \
  Packages/DrumNotation/Package.swift \
  Packages/DrumNotation/Sources Virgo Virgo.xcodeproj/project.pbxproj || true
```

Expected: no shipping source/manifest/Xcode dependency; references appear only in docs/tooling/tests where intended.

- [ ] **Step 7: Finish the package README**

Document only implemented facts:

- supported platforms;
- current primitive scope;
- Bravura 1.482 resource ownership;
- package test command;
- manual VexFlow reference regeneration command;
- explicit statement that layout/formatting and full beam rendering remain HPA-164/HPA-166 work.

- [ ] **Step 8: Review the final diff against the ticket boundary**

Use:

```bash
git diff main...HEAD --stat
git diff main...HEAD -- \
  Virgo/layout Virgo/views Packages/DrumNotation .github/workflows/ci.yml
```

Reject any change that introduces:
- new horizontal spacing/tick rules;
- new beam-group logic;
- whole-layout extraction;
- app domain copies inside the package;
- runtime JS/WebView;
- package publication infrastructure.

- [ ] **Step 9: Commit any final README correction produced by the verification review**

```bash
git add Packages/DrumNotation/README.md
git commit -m "docs: document DrumNotation package boundary"
```

The PR remains a single HPA-163 implementation PR even though it contains multiple reviewable commits.

---

## Completion checklist

Before marking HPA-163 ready for review:

- [ ] `swift test --package-path Packages/DrumNotation` passes from a clean package build.
- [ ] Full `VirgoTests` pass with parallel testing disabled.
- [ ] Generic iOS Simulator build passes and remains iPad-only.
- [ ] VexFlow reference output is committed, deterministic, and regeneration-only.
- [ ] Bravura 1.482 font/metadata/license live only in package resources.
- [ ] Package Swift sources have no Virgo/domain/theme dependency.
- [ ] Handwritten notehead/rest/flag/open-articulation paths are removed.
- [ ] Existing DTX identity, voice/staff placement, normalized ticks, grid X positions, beam topology, and playhead alignment are unchanged.
- [ ] No renderer toggle, generic backend protocol, publication workflow, or extra target was added.
- [ ] PR description links HPA-163 and explicitly leaves measured formatting to HPA-164 and complete beam/modifier rendering to HPA-166.
