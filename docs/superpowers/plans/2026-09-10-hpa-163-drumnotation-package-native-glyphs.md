# HPA-163 DrumNotation Package Foundation and Native Glyphs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an independently testable local `DrumNotation` Swift package, replace Virgo's handwritten notehead/rest/flag/open-hi-hat primitives with Bravura/SMuFL rendering, and keep fixed horizontal geometry, beam topology and playhead behavior unchanged.

**Architecture:** Virgo keeps DTX/domain semantics, normalized rhythm, staff positions, fixed-grid placement, beam topology, playback and theme. `Virgo/layout/VirgoNotationAdapter.swift` is the single pure app-to-package conversion and paint-policy seam. `DrumNotation` owns the closed SMuFL catalog, pinned Bravura 1.392 resources, fitted primitive geometry, notehead anchors and native SwiftUI views. VexFlow 5.0.0 is documented as the reference; executable Node/VexFlow comparison tooling is deferred to HPA-166 unless a parity test there actually consumes it.

**Tech Stack:** Swift 5, SwiftUI, CoreText/CoreGraphics, Swift Package Manager, Swift Testing, `@vexflow-fonts/bravura` 1.0.2 / Bravura 1.392, existing Xcode 26.1.1 CI.

**Spec:** `docs/superpowers/specs/2026-09-10-hpa-163-drumnotation-package-native-glyphs-design.md`

## Global Constraints

- Exactly one PR for HPA-163; continue implementation on this draft PR.
- One `DrumNotation` library target and one package test target; no Core/UI split.
- No Node/jsdom/VexFlow tool directory in HPA-163.
- Package code must not import or accept Virgo `NoteType`, `DrumType`, `RenderedNoteHead`, `GameplayLayout`, `Palette`, `AppFonts` or raw DTX values.
- Keep macOS 14.0+, iOS/iPadOS 17.5+, Swift 5 and `TARGETED_DEVICE_FAMILY = 2`.
- Do not change `TabGrid`, note X mapping, row packing, DTX parsing, rhythm inference, beam grouping/topology or playhead routing.
- Keep all `xcodebuild` test runs non-parallel.
- Delete `DrumNoteheadGlyph` and handwritten notehead/rest/flag/open-articulation geometry; do not preserve source compatibility.
- Paint and `paintedBounds` must consume the same package metrics.
- Missing bundled font/metadata, accepted glyphs or required notehead anchors are programmer errors; fail loudly instead of drawing a fallback.

---

## File Map

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
- `Packages/DrumNotation/Tests/DrumNotationTests/PackageBoundaryTests.swift`
- `Packages/DrumNotation/Tests/DrumNotationTests/GlyphCatalogTests.swift`
- `Packages/DrumNotation/Tests/DrumNotationTests/BravuraGeometryTests.swift`
- `Packages/DrumNotation/Tests/DrumNotationTests/PrimitiveViewTests.swift`
- `Virgo/layout/VirgoNotationAdapter.swift`
- `VirgoTests/VirgoNotationAdapterTests.swift`

**Modify**

- `Virgo.xcodeproj/project.pbxproj`
- `.github/workflows/ci.yml`
- `Virgo/constants/Drum.swift`
- `Virgo/constants/DrumNotation.swift`
- `Virgo/layout/NotationLayout.swift`
- `Virgo/layout/NotationLayoutEngine.swift`
- `Virgo/layout/NotationLayoutEngine+Beams.swift`
- `Virgo/layout/NotationRhythmRendering.swift`
- `Virgo/views/NotationPrimitiveViews.swift`
- `Virgo/views/subviews/GameplaySheetMusicView.swift`
- `VirgoTests/DrumNotationCatalogTests.swift`
- `VirgoTests/DrumTypeExtensionsAndConstantsTests.swift`
- `VirgoTests/NotationLayoutDigest.swift`
- `VirgoTests/DrumTabGoldenTests.swift`
- `VirgoTests/DrumTabRenderProbeTests.swift`
- `VirgoTests/SwiftUIRenderingNotationTests.swift`
- layout tests/helpers that currently construct or inspect `DrumNoteheadGlyph` / `RenderedNoteHead.glyph`.

---

### Task 1: Establish the local package boundary and CI gate

**Files:**
- Create: `Packages/DrumNotation/Package.swift`
- Create: `Packages/DrumNotation/README.md`
- Create: `Packages/DrumNotation/Sources/DrumNotation/DrumNotation.swift`
- Create: `Packages/DrumNotation/Tests/DrumNotationTests/PackageBoundaryTests.swift`
- Modify: `Virgo.xcodeproj/project.pbxproj`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: importable local module `DrumNotation`.
- Produces: independent `swift test --package-path Packages/DrumNotation` gate.
- Consumes: no Virgo source.

- [ ] **Step 1: Write the failing independent package smoke**

Create `PackageBoundaryTests.swift` before the manifest exists:

```swift
import Testing
import DrumNotation

@Test("public DrumNotation module imports without Virgo")
func packageImports() {
    #expect(NotationDuration.quarter.rawValue == "quarter")
}
```

Run:

```bash
swift test --package-path Packages/DrumNotation
```

Expected: FAIL because the package/module/public type does not exist yet.

- [ ] **Step 2: Create the minimal package and public duration type**

Create `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DrumNotation",
    platforms: [.iOS("17.5"), .macOS(.v14)],
    products: [.library(name: "DrumNotation", targets: ["DrumNotation"])],
    targets: [
        .target(name: "DrumNotation"),
        .testTarget(name: "DrumNotationTests", dependencies: ["DrumNotation"])
    ],
    swiftLanguageVersions: [.v5]
)
```

Create `PrimitiveTypes.swift` with only:

```swift
public enum NotationDuration: String, CaseIterable, Sendable {
    case whole, half, quarter, eighth, sixteenth, thirtySecond, sixtyFourth
}
```

Run the package test again. Expected: PASS.

- [ ] **Step 3: Link the local package product to Virgo**

In `Virgo.xcodeproj/project.pbxproj` add:

- one `XCLocalSwiftPackageReference` for `Packages/DrumNotation`;
- one `XCSwiftPackageProductDependency` for `DrumNotation`;
- the product in the Virgo app target Frameworks build phase.

Do not alter Apollo package references, deployment floors or device-family settings.

Verify:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Expected: build succeeds with the empty package linked.

- [ ] **Step 4: Add the package test to the existing CI job**

Immediately before `Run unit tests` in `.github/workflows/ci.yml` add:

```yaml
      - name: Run DrumNotation package tests
        run: swift test --package-path Packages/DrumNotation
```

Do not create a new workflow.

- [ ] **Step 5: Commit**

```bash
git add Packages/DrumNotation Virgo.xcodeproj/project.pbxproj .github/workflows/ci.yml
git commit -m "build: add local DrumNotation package"
```

---

### Task 2: Vendor Bravura and implement the closed glyph catalog

**Files:**
- Modify: `Packages/DrumNotation/Package.swift`
- Modify: `Packages/DrumNotation/README.md`
- Modify: `Packages/DrumNotation/Sources/DrumNotation/Model/PrimitiveTypes.swift`
- Create: `Packages/DrumNotation/Sources/DrumNotation/Glyphs/SMuFLGlyphCatalog.swift`
- Add: `Packages/DrumNotation/Sources/DrumNotation/Resources/Bravura/*`
- Create: `Packages/DrumNotation/Tests/DrumNotationTests/GlyphCatalogTests.swift`

**Interfaces:**
- Produces: package semantic types and internal exact SMuFL selectors.
- Produces: package-owned Bravura 1.392 resources through `Bundle.module`.

- [ ] **Step 1: Vendor the VexFlow-matching Bravura assets**

Use `vexflow/vexflow-fonts` commit `b2bc3a6070225e4d395966b36de76c36a9429b1c`:

- `bravura/bravura.otf` blob `afa95d6caa68883c06a4f79981a6bdc95b135ad3` → `Resources/Bravura/Bravura.otf`;
- `bravura/metadata.json` blob `8de156e038f6183e4d70b0cee1d25db390405d29` → `Resources/Bravura/metadata.json`;
- `bravura/LICENSE.txt` blob `2ef86a39593a42e3971fb88314ed7d2b748d4ef4` → `Resources/Bravura/LICENSE.txt`.

Update the package target:

```swift
.target(
    name: "DrumNotation",
    resources: [.process("Resources")]
)
```

In `README.md`, record:

- VexFlow reference: 5.0.0;
- font reference: `@vexflow-fonts/bravura` 1.0.2 / Bravura 1.392;
- exact source commit above;
- no Node/VexFlow runtime or HPA-163 generator.

- [ ] **Step 2: Write red table-driven glyph selection tests**

`GlyphCatalogTests.swift` must assert these exact internal names/scalars via `@testable import DrumNotation`:

```text
normal whole -> noteheadWhole E0A2
normal half -> noteheadHalf E0A3
normal quarter/eighth/16/32/64 -> noteheadBlack E0A4
x whole -> noteheadXWhole E0A7
x half -> noteheadXHalf E0A8
x quarter/eighth/16/32/64 -> noteheadXBlack E0A9
diamond whole -> noteheadDiamondWhole E0D8
diamond half -> noteheadDiamondHalf E0D9
diamond quarter/eighth/16/32/64 -> noteheadDiamondBlack E0DB
rest whole/half/quarter/8/16/32/64 -> E4E3/E4E4/E4E5/E4E6/E4E7/E4E8/E4E9
flag 8/16/32/64 up/down -> E240/E241/E242/E243/E244/E245/E246/E247
open articulation -> pictOpen E7F8
```

Run:

```bash
swift test --package-path Packages/DrumNotation --filter GlyphCatalogTests
```

Expected: FAIL until the semantic types/catalog exist.

- [ ] **Step 3: Implement only the required public semantic types**

Add:

```swift
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
```

Import `CoreGraphics` in this file. Do not add app-domain enums.

- [ ] **Step 4: Implement the private closed SMuFL catalog**

`SMuFLGlyphCatalog.swift` uses exhaustive switches over package semantic enums. Keep raw glyph names/scalars internal. Do not expose arbitrary lookup by string.

Run `GlyphCatalogTests` again. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/DrumNotation
git commit -m "feat: add Bravura percussion glyph catalog"
```

---

### Task 3: Implement one correct font-to-local geometry transform

**Files:**
- Create: `Packages/DrumNotation/Sources/DrumNotation/Glyphs/BravuraFont.swift`
- Create: `Packages/DrumNotation/Tests/DrumNotationTests/BravuraGeometryTests.swift`

**Interfaces:**
- Produces: `PercussionGlyphMetrics.notehead/rest/flag/articulation` and `naturalFlagSize`.
- Produces: one internal fitted-glyph transform reused by paint and metrics.

- [ ] **Step 1: Write red resource/path tests**

Using `@testable import DrumNotation`, assert:

- `Bundle.module` resolves all three Bravura files;
- every accepted scalar resolves to a nonzero `CGGlyph`;
- every accepted glyph produces a nonempty `CTFontCreatePathForGlyph` path.

Run:

```bash
swift test --package-path Packages/DrumNotation --filter BravuraGeometryTests
```

Expected: FAIL until `BravuraFont` exists.

- [ ] **Step 2: Implement package-local resource loading with no app font registration**

`BravuraFont` must:

- load `Bravura.otf` and `metadata.json` only through `Bundle.module`;
- create/cache a private `CGFont` and decoded metadata using Swift static initialization;
- create `CTFont` values from that package font as needed;
- call `preconditionFailure` for a missing required file, accepted glyph or required notehead anchor;
- never call `AppFonts`, `Bundle.main` or bundle scanning.

- [ ] **Step 3: Write red notehead transform tests that catch missing translation**

For every notehead family × whole/half/black duration × both stem directions:

1. get the raw Bravura path bounds at the test font size;
2. read the source metadata anchor (`stemUpSE` or `stemDownNW`);
3. convert the anchor from staff spaces to the same font coordinate system using `unitsPerEm / 4`;
4. independently compute the expected local transform for `CGSize(width: 30, height: 20)`:

```swift
let scale = min(box.width / rawBounds.width, box.height / rawBounds.height)
let expectedAnchor = CGPoint(
    x: (rawAnchor.x - rawBounds.midX) * scale,
    y: -(rawAnchor.y - rawBounds.midY) * scale
)
```

Assert package `stemAnchorOffset` equals this point within 0.001.

Also obtain the transformed outline and assert the anchor lies in a narrow stroked edge band around the glyph outline:

```swift
let edgeBand = transformedPath.copy(
    strokingWithWidth: 1.0,
    lineCap: .round,
    lineJoin: .round,
    miterLimit: 10
)
#expect(edgeBand.contains(metrics.stemAnchorOffset))
```

If Bravura intentionally places a specific anchor just outside the outline by less than the stem thickness, widen only that fixture's epsilon and document the measured value; do not replace the test with a generic `isFinite` assertion.

- [ ] **Step 4: Implement the exact shared affine transform**

For raw path bounds `B` and scale `s`, use the same transform for path and anchors:

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

This maps the raw path-bounds center to local `(0, 0)` and flips Y. Apply this complete transform to the metadata anchor after converting it to font coordinates.

Implement:

```swift
public enum PercussionGlyphMetrics {
    public static func notehead(...) -> NoteheadMetrics
    public static func rest(...) -> PrimitiveGlyphMetrics
    public static func flag(...) -> FlagGlyphMetrics
    public static func articulation(...) -> PrimitiveGlyphMetrics
    public static func naturalFlagSize(...) -> CGSize
}
```

For flags, `attachmentOffset` is the transformed Bravura glyph origin relative to the centered local view. `naturalFlagSize` multiplies the font glyph's native staff-space width/height by caller-supplied `staffSpace`, preserving aspect ratio instead of using Virgo's old 8×8 frame.

- [ ] **Step 5: Add flag/rest/articulation bounds tests**

Assert each metric's `paintedBounds` equals the actual transformed path bounding box and fits its requested box. For flags, assert `attachmentOffset` transforms raw glyph origin `(0, 0)` through the same affine transform and remains on the expected stem-side portion of the glyph.

Run:

```bash
swift test --package-path Packages/DrumNotation --filter BravuraGeometryTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/DrumNotation/Sources/DrumNotation/Glyphs \
        Packages/DrumNotation/Tests/DrumNotationTests/BravuraGeometryTests.swift
git commit -m "feat: derive percussion geometry from Bravura"
```

---

### Task 4: Add package-native SwiftUI primitive views

**Files:**
- Create: `Packages/DrumNotation/Sources/DrumNotation/Rendering/PrimitiveViews.swift`
- Create: `Packages/DrumNotation/Tests/DrumNotationTests/PrimitiveViewTests.swift`

**Interfaces:**
- Consumes: exact fitted geometry from Task 3.
- Produces: four public primitive views; no second geometry path.

- [ ] **Step 1: Write red view-construction tests**

For every supported semantic combination, construct:

```swift
PercussionNoteheadView(style:duration:size:color:)
NotationRestGlyphView(duration:size:color:)
NotationFlagGlyphView(duration:direction:size:color:)
PercussionArticulationView(articulation:size:color:)
```

Through `@testable` internal test access, assert each view resolves the same fitted geometry/glyph selector used by `PercussionGlyphMetrics`.

Run:

```bash
swift test --package-path Packages/DrumNotation --filter PrimitiveViewTests
```

Expected: FAIL until the views exist.

- [ ] **Step 2: Implement the views from the fitted package path**

Use SwiftUI `Canvas`/`Path` to fill the font-derived path from Task 3. Do not rebuild glyph geometry in the view. `Color` and `CGSize` stay explicit caller inputs.

For flags, the package view is centered in its explicit box; placement relative to the stem attachment is handled by Virgo using `FlagGlyphMetrics.attachmentOffset`.

Run all package tests:

```bash
swift test --package-path Packages/DrumNotation
```

Expected: PASS without Virgo or Node.

- [ ] **Step 3: Commit**

```bash
git add Packages/DrumNotation/Sources/DrumNotation/Rendering \
        Packages/DrumNotation/Tests/DrumNotationTests/PrimitiveViewTests.swift
git commit -m "feat: render DrumNotation Bravura primitives"
```

---

### Task 5: Add the single Virgo adapter, size policy and pure flag commands

**Files:**
- Create: `Virgo/layout/VirgoNotationAdapter.swift`
- Create: `VirgoTests/VirgoNotationAdapterTests.swift`

**Interfaces:**
- Produces: exhaustive app→package semantic mappings.
- Produces: one size/bounds policy for heads/rests/flags/articulation.
- Produces: `FlagPaintCommand` consumed by both production and the render probe.

- [ ] **Step 1: Write red exhaustive semantic mapping tests**

Cover every `NoteType`, all seven `NoteInterval` values, both `StemDirection` values and every `NotationRestDuration`:

```swift
static func restDuration(for duration: NotationRestDuration) -> NotationDuration? {
    switch duration {
    case .fullMeasure: return .whole
    case .half: return .half
    case .quarter: return .quarter
    case .eighth: return .eighth
    case .sixteenth: return .sixteenth
    case .thirtySecond: return .thirtySecond
    case .sixtyFourth: return .sixtyFourth
    case .indeterminate: return nil
    }
}
```

The notehead family expectations are:

```text
bass/snare/highTom/midTom/lowTom -> normal
hiHat/hiHatPedal/openHiHat/crash/ride/china/splash -> x
cowbell -> diamond
```

Run:

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/VirgoNotationAdapterTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL until the adapter exists.

- [ ] **Step 2: Implement exhaustive conversion functions with no default branches**

`VirgoNotationAdapter` implements:

```swift
static func noteheadStyle(for: NoteType) -> PercussionNoteheadStyle
static func duration(for: NoteInterval) -> NotationDuration
static func stemDirection(for: StemDirection) -> NotationStemDirection
static func restDuration(for: NotationRestDuration) -> NotationDuration?
```

Map `.openHiHat` articulation directly to package `.open` at the only current call site; do not add an abstraction for unknown future articulations.

- [ ] **Step 3: Write red size-policy tests**

Assert:

```text
notehead size = style.noteHeadSize
fullMeasure/half rest size = fullMeasureRestWidth × fullMeasureRestHeight
quarter/eighth/16/32/64 rest size = restSymbolWidth × restSymbolHeight
open articulation size = articulationDiameter × articulationDiameter
flag size = package naturalFlagSize(... staffSpace: style.staffLineSpacing)
```

Explicitly assert canonical 16th/32nd/64th flag sizes are not the old `GameplayLayout.flagWidth × flagHeight` 8×8 box.

- [ ] **Step 4: Define and test pure flag paint commands**

Add:

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

Implement:

```swift
static func flagPaintCommands(
    flags: [RenderedFlag],
    heads: [RenderedNoteHead],
    style: NotationLayoutStyle
) -> [FlagPaintCommand]
```

For each head:

- expected levels = `Set(0..<head.interval.flagCount)`;
- actual levels = that head's `RenderedFlag.flagIndex` set;
- if equal, emit one command from level 0 using the head's canonical duration;
- otherwise emit one `.eighth` command per existing uncovered flag at its existing origin;
- preserve original `layout.flags` ordering.

For each emitted command:

1. choose size through the adapter flag policy;
2. get package `FlagGlyphMetrics`;
3. compute `center = origin - metrics.attachmentOffset`;
4. translate `metrics.paintedBounds` by `center` and store that exact absolute rect in the command.

Tests must cover fully isolated eighth/sixteenth/thirty-second/sixty-fourth notes and partially uncovered beam levels.

- [ ] **Step 5: Run adapter tests**

Run the same focused command. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Virgo/layout/VirgoNotationAdapter.swift VirgoTests/VirgoNotationAdapterTests.swift
git commit -m "feat: add Virgo notation package adapter"
```

---

### Task 6: Remove `DrumNoteheadGlyph` and cut layout geometry over to package metrics

**Files:**
- Modify: `Virgo/constants/Drum.swift`
- Modify: `Virgo/constants/DrumNotation.swift`
- Modify: `Virgo/layout/NotationLayout.swift`
- Modify: `Virgo/layout/NotationLayoutEngine.swift`
- Modify: `Virgo/layout/NotationLayoutEngine+Beams.swift`
- Modify: `Virgo/layout/NotationRhythmRendering.swift`
- Modify: affected layout/catalog test helpers.

**Interfaces:**
- Removes: app engraving glyph enum/plumbing.
- Makes: package metrics authoritative for stem anchors, ledger extents and painted bounds.

- [ ] **Step 1: Remove the obsolete app glyph vocabulary**

Delete:

- `DrumNoteheadGlyph` and all custom path/bounds/anchor helpers;
- `DrumNotationDefinition.glyph` and all initializer arguments;
- `RenderedNoteHead.glyph` and constructor arguments;
- `glyph: definition.glyph` in both `NotationLayoutEngine` construction paths.

Update test fixtures/builders that construct `RenderedNoteHead`.

Do not replace this with another app engraving enum.

- [ ] **Step 2: Normalize app-only settings symbols**

Change `DrumType.symbol` to:

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

Update `DrumTypeExtensionsAndConstantsTests` accordingly.

- [ ] **Step 3: Switch stem anchors and ledger bounds to the same notehead metrics**

In `NotationLayoutEngine+Beams.swift`, obtain once per head:

```swift
let metrics = VirgoNotationAdapter.noteheadMetrics(for: noteHead, style: style)
```

Use `metrics.stemAnchorOffset` translated by `noteHead.position` for `stemAnchor(for:style:)`.

Use `metrics.paintedBounds` translated by `noteHead.position` for ledger-line X extents.

Do not change beam grouping, event coverage or note X positions.

- [ ] **Step 4: Replace primitive painted-bounds guesses**

In `NotationRhythmRendering.swift`:

- `RenderedNoteHead.paintedBounds` → translated package `NoteheadMetrics.paintedBounds`;
- `RenderedRest.paintedBounds` → `restDuration(for:)`; return `.null` for hidden/indeterminate; otherwise use adapter size + package rest metrics;
- `RenderedArticulation.paintedBounds` → adapter size + package articulation metrics;
- delete old `RenderedFlag.paintedBounds` 8×8 logic.

In `NotationLayout.calculatePaintedBounds`, replace `flags.map { $0.paintedBounds(...) }` with:

```swift
VirgoNotationAdapter
    .flagPaintCommands(flags: flags, heads: noteHeads, style: style)
    .map(\.paintedBounds)
```

This is the only flag bounds source.

- [ ] **Step 5: Update layout tests to assert package-derived geometry**

Update `NotationLayoutEngineTests`, `NotationLayoutEngineChordAndBeamTests`, `NotationLayoutDefensiveGuardTests` and painted-bounds tests so they compare against adapter/package metrics, not deleted path helpers.

Add one integration assertion that the same `NoteheadMetrics` values determine:

- head `paintedBounds`;
- stem start;
- ledger-line horizontal extent.

- [ ] **Step 6: Run focused layout/model tests**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/DrumNotationCatalogTests \
  -only-testing:VirgoTests/DrumTypeExtensionsAndConstantsTests \
  -only-testing:VirgoTests/VirgoNotationAdapterTests \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -only-testing:VirgoTests/NotationLayoutEngineChordAndBeamTests \
  -only-testing:VirgoTests/NotationLayoutDefensiveGuardTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Expected: all selected suites PASS. Multiple `-only-testing:` constraints are intentionally cumulative in xcodebuild.

- [ ] **Step 7: Commit**

```bash
git add Virgo/constants Virgo/layout VirgoTests
git commit -m "refactor: replace app glyph geometry with DrumNotation metrics"
```

---

### Task 7: Cut production SwiftUI and the render probe over together

**Files:**
- Modify: `Virgo/views/NotationPrimitiveViews.swift`
- Modify: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Modify: `VirgoTests/SwiftUIRenderingNotationTests.swift`
- Modify: `VirgoTests/DrumTabRenderProbeTests.swift`

**Interfaces:**
- Production and probe consume the same `FlagPaintCommand` list.
- Package primitive views are the only notehead/rest/flag/open-articulation painters.

- [ ] **Step 1: Replace app primitive drawing**

In `NotationPrimitiveViews.swift`:

- delete `DrumNoteheadShape` and handwritten notehead paths;
- `NotationNoteHeadView` delegates to `PercussionNoteheadView` using adapter style/duration and existing head center;
- `NotationRestView` maps `RenderedRest.duration` through `restDuration(for:)`, skips `nil`, and delegates to `NotationRestGlyphView` using adapter rest size;
- `NotationArticulationView` delegates `.openHiHat` to `PercussionArticulationView(.open, ...)`;
- delete `FlagView` and its Bézier path;
- change `NotationFlagView` to accept one `FlagPaintCommand`, render `NotationFlagGlyphView` using command duration/direction/size, and `.position(command.center)`.

Keep stems, beams, ledger lines, bars, dots, tuplets, feel marks, warnings and stop marks unchanged.

- [ ] **Step 2: Make production consume the pure flag command list**

In `GameplayDrumNotationView`, compute once:

```swift
let flagCommands = VirgoNotationAdapter.flagPaintCommands(
    flags: layout.flags,
    heads: layout.noteHeads,
    style: style
)
```

Render `ForEach(flagCommands) { NotationFlagView(command: $0) }` in the same z-order slot previously occupied by `layout.flags`.

Do not teach `NotationFlagView` to search siblings.

- [ ] **Step 3: Make the raster probe consume the exact same flag commands**

Update `DrumTabRenderProbeTests.notationOverlay` to compute `flagPaintCommands` from its `NotationLayout` and render those commands in the same z-order as production.

Do not copy the collapse algorithm into the probe.

- [ ] **Step 4: Update wrapper/mount tests**

`SwiftUIRenderingNotationTests` should still prove:

- every app semantic notehead mounts;
- every printed supported rest mounts and preserves its accessibility label;
- hidden/indeterminate rest behavior stays non-painting;
- open-hi-hat articulation mounts with existing accessibility ownership;
- both flag directions and at least one canonical multi-hook flag mount;
- no yellow highlighting returns.

Do not inspect private raw font code points from Virgo tests.

- [ ] **Step 5: Run render-focused tests**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/SwiftUIRenderingNotationTests \
  -only-testing:VirgoTests/DrumTabRenderProbeTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Virgo/views VirgoTests/SwiftUIRenderingNotationTests.swift \
        VirgoTests/DrumTabRenderProbeTests.swift
git commit -m "feat: paint Virgo notation with Bravura primitives"
```

---

### Task 8: Reconcile digest/goldens and verify the HPA-163 boundary

**Files:**
- Modify: `VirgoTests/NotationLayoutDigest.swift`
- Modify: `VirgoTests/DrumTabGoldenTests.swift`
- Modify goldens only after reviewing expected metric changes.
- Modify: `Packages/DrumNotation/README.md` only for implemented factual corrections.

**Interfaces:**
- Goldens no longer serialize deleted `DrumNoteheadGlyph` identity.
- Geometry drift is accepted only where Bravura metrics intentionally replace handwritten metrics.

- [ ] **Step 1: Remove glyph identity from the layout digest**

Change the head digest from `glyph=... variant=...` to package-independent app semantics, for example:

```text
style=normal|x|diamond variant=<DrumNotationVariant>
```

Use `VirgoNotationAdapter.noteheadStyle(for: head.noteType).rawValue`; do not add a new field to `RenderedNoteHead` only for the digest.

- [ ] **Step 2: Keep hi-hat semantic coverage meaningful after glyph deletion**

Change `DrumTabGoldenTests.hiHatOpenClosedPedal` to assert all three expected variants directly:

```swift
let variants = Set(result.layout.noteHeads.map(\.variant))
#expect(variants == [.closedHiHat, .openHiHat, .pedalHiHat])
```

Do not recreate a `(glyph, variant)` pair after the glyph enum is removed.

- [ ] **Step 3: Run notation regression suites before regenerating any golden**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  -only-testing:VirgoTests/DrumTabRegressionInvariantTests \
  -only-testing:VirgoTests/DrumTabRenderProbeTests \
  -only-testing:VirgoTests/DrumTabPlayheadAlignmentTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Review every failure before changing a golden.

Allowed HPA-163 drift:

- serialized notehead style replacing old glyph identity;
- stem/beam/flag-origin values that move only because corrected Bravura anchors replace handwritten anchor guesses;
- painted-bounds/content-size values that move because bounds now match actual Bravura paint.

Reject/regress instead of accepting changes to:

- absolute tick/local tick;
- measure index or row;
- note-head X position;
- beam membership, level or kind;
- playhead routing/alignment.

- [ ] **Step 4: Regenerate only reviewed goldens when required**

Use the repository's existing golden-update mechanism. After generation, inspect `git diff VirgoTests/Goldens` and confirm every changed field fits the allowed list above before committing.

- [ ] **Step 5: Run fresh full verification**

```bash
rm -rf Packages/DrumNotation/.build
swift test --package-path Packages/DrumNotation

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

xcodebuild build \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

swiftlint lint
git diff --check main...HEAD
```

Expected: all commands pass and iOS-family targeting remains iPad-only.

- [ ] **Step 6: Run mechanical boundary checks**

```bash
grep -R -nE 'import Virgo|NoteType|DrumType|RenderedNoteHead|GameplayLayout|Palette|AppFonts|Bundle\.main' \
  Packages/DrumNotation/Sources Packages/DrumNotation/Tests || true

grep -R -nE 'vexflow|jsdom|node_modules' \
  Packages/DrumNotation/Package.swift Packages/DrumNotation/Sources Virgo Virgo.xcodeproj/project.pbxproj || true

find Packages/DrumNotation -type l -print
git grep -n 'DrumNoteheadGlyph' -- Virgo VirgoTests || true
```

Expected:

- no package dependency on Virgo/app theme/font bootstrap;
- no shipping/runtime Node/VexFlow dependency;
- no package symlink escaping the package;
- no remaining `DrumNoteheadGlyph` reference.

- [ ] **Step 7: Review final diff for scope**

```bash
git diff main...HEAD --stat
git diff main...HEAD -- Packages/DrumNotation Virgo/layout Virgo/views Virgo/constants .github/workflows/ci.yml
```

Reject any accidental change to formatting algorithms, beam topology, DTX/rhythm inference, package publication or a new renderer backend.

- [ ] **Step 8: Commit final reviewed test/doc changes on this PR**

```bash
git add Packages/DrumNotation VirgoTests
git commit -m "test: verify DrumNotation native glyph cutover"
```

---

## Completion Checklist

Before HPA-163 leaves draft:

- [ ] clean package tests pass independently;
- [ ] Bravura 1.392 OTF/metadata/license are package-owned and documented against VexFlow 5.0.0;
- [ ] no Node/jsdom/VexFlow toolchain exists in this PR;
- [ ] anchor tests exercise the full translate + scale + Y-flip transform and path-edge relationship;
- [ ] package metrics and primitive views share one geometry implementation;
- [ ] adapter maps `NotationRestDuration` explicitly and skips `.indeterminate`;
- [ ] flag sizes derive from Bravura natural staff-space geometry, not 8×8;
- [ ] `FlagPaintCommand` is the single flag-collapse policy for production and the render probe;
- [ ] notehead/rest/flag/articulation painted bounds come from the same package geometry that paints them;
- [ ] `DrumNoteheadGlyph` and its constructor/test plumbing are gone;
- [ ] digest/golden semantics no longer depend on that deleted glyph enum;
- [ ] note X, rows, tick identity, beam membership/topology and playhead alignment remain unchanged;
- [ ] full serial macOS tests, iPad simulator build, SwiftLint and `git diff --check` pass;
- [ ] HPA-164 still owns measured horizontal formatting;
- [ ] HPA-166 still owns final VexFlow beam/modifier/static-sheet parity and any executable VexFlow harness needed for it.
