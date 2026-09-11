# HPA-163 DrumNotation Package Foundation and Native Glyphs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one independently testable local `DrumNotation` package, replace Virgo's handwritten notehead/rest/flag/open-hi-hat primitives with staff-space-scaled Bravura/SMuFL rendering, and preserve existing fixed horizontal timing/beam topology while keeping paint and reported geometry in one contract.

**Architecture:** Virgo keeps DTX/domain semantics, normalized rhythm, staff positions, fixed-grid placement, beam topology, playback and theme. `Virgo/layout/VirgoNotationAdapter.swift` is the single pure app-to-package mapping/policy seam. `DrumNotation` owns the closed SMuFL catalog, Bravura 1.392 resources, staff-scaled primitive geometry, notehead anchors and native SwiftUI views. VexFlow 5.0.0 is documented as the semantic reference; executable Node/VexFlow tooling is deferred to HPA-166 unless a parity test there consumes it.

**Tech Stack:** Swift 5, SwiftUI, CoreText/CoreGraphics, Swift Package Manager, Swift Testing, `@vexflow-fonts/bravura` 1.0.2 / Bravura 1.392, existing Xcode 26.1.1 CI.

**Spec:** `docs/superpowers/specs/2026-09-10-hpa-163-drumnotation-package-native-glyphs-design.md`

## Global Constraints

- Exactly one PR for HPA-163; continue implementation on this draft PR.
- One `DrumNotation` library target and one package test target; no Core/UI split.
- No Node/jsdom/VexFlow tool directory in HPA-163.
- Package code must not import or accept Virgo `NoteType`, `DrumType`, `RenderedNoteHead`, `GameplayLayout`, `Palette`, `AppFonts` or raw DTX values.
- Keep macOS 14.0+, iOS/iPadOS 17.5+, Swift 5 and `TARGETED_DEVICE_FAMILY = 2`.
- Scale every Bravura primitive from one `staffSpace`; never squeeze glyphs into legacy hand-drawn frames.
- Do not change `TabGrid`, note X mapping, row packing, DTX parsing, rhythm inference, beam grouping/topology or playhead routing.
- A bounded length increase for **unbeamed flagged stems only** is allowed so natural 32nd/64th flags do not collide with their head/chord.
- Keep all `xcodebuild` test runs non-parallel.
- Delete `DrumNoteheadGlyph` and handwritten notehead/rest/flag/open-articulation geometry; do not preserve source compatibility.
- Paint and `paintedBounds` must consume the same package metrics.
- Missing bundled font/metadata, accepted glyphs or required notehead anchors are programmer errors; fail loudly instead of drawing a fallback.
- `.swiftlint.yml` must include `Packages` so the new module follows existing size/style rules.

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
- `Virgo/layout/VirgoNotationAdapter.swift`
- `VirgoTests/VirgoNotationAdapterTests.swift`

**Modify**

- `.swiftlint.yml`
- `.github/workflows/ci.yml`
- `Virgo.xcodeproj/project.pbxproj`
- `Virgo/constants/Drum.swift`
- `Virgo/constants/DrumNotation.swift`
- `Virgo/layout/NotationLayout.swift`
- `Virgo/layout/NotationLayoutEngine.swift`
- `Virgo/layout/NotationLayoutEngine+Beams.swift`
- `Virgo/layout/NotationRhythmRendering.swift`
- `Virgo/views/NotationPrimitiveViews.swift`
- `Virgo/views/subviews/GameplaySheetMusicView.swift`
- `VirgoTests/RenderRasterProbe.swift`
- `VirgoTests/DrumNotationCatalogTests.swift`
- `VirgoTests/DrumTypeExtensionsAndConstantsTests.swift`
- `VirgoTests/NotationLayoutDigest.swift`
- `VirgoTests/DrumTabGoldenTests.swift`
- `VirgoTests/DrumTabRenderProbeTests.swift`
- `VirgoTests/SwiftUIRenderingNotationTests.swift`
- affected layout tests/helpers that construct or inspect `DrumNoteheadGlyph` / `RenderedNoteHead.glyph`.

---

### Task 1: Establish the local package boundary, lint scope and CI gate

**Files:**
- Create: `Packages/DrumNotation/Package.swift`
- Create: `Packages/DrumNotation/README.md`
- Create: `Packages/DrumNotation/Sources/DrumNotation/Model/PrimitiveTypes.swift`
- Create: `Packages/DrumNotation/Tests/DrumNotationTests/PackageBoundaryTests.swift`
- Modify: `Virgo.xcodeproj/project.pbxproj`
- Modify: `.swiftlint.yml`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: importable local module `DrumNotation`.
- Produces: independent `swift test --package-path Packages/DrumNotation` gate.
- Consumes: no Virgo source.

- [ ] **Step 1: Write a red public-package smoke test**

Create `PackageBoundaryTests.swift`:

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

Expected: FAIL because no package/module/public type exists yet.

- [ ] **Step 2: Add the smallest package manifest and public duration type**

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

Create `PrimitiveTypes.swift` with:

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

Leave Apollo, deployment floors and device-family settings unchanged.

Verify:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Expected: build succeeds with the package linked.

- [ ] **Step 4: Put package Swift under existing SwiftLint rules**

Change `.swiftlint.yml` from:

```yaml
included:
  - Virgo
  - VirgoTests
  - VirgoUITests
```

to:

```yaml
included:
  - Virgo
  - VirgoTests
  - VirgoUITests
  - Packages
```

Run:

```bash
swiftlint lint
```

Expected: no new errors.

- [ ] **Step 5: Add package tests to the existing CI job**

Immediately before `Run unit tests` in `.github/workflows/ci.yml` add:

```yaml
      - name: Run DrumNotation package tests
        run: swift test --package-path Packages/DrumNotation
```

Do not create a second workflow or alter the serial app-test command.

- [ ] **Step 6: Commit**

```bash
git add Packages/DrumNotation Virgo.xcodeproj/project.pbxproj \
  .swiftlint.yml .github/workflows/ci.yml
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

- [ ] **Step 1: Vendor the exact VexFlow-matching Bravura assets**

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

- semantic reference: VexFlow 5.0.0;
- font reference: `@vexflow-fonts/bravura` 1.0.2 / Bravura 1.392;
- exact source commit above;
- no Node/VexFlow runtime or HPA-163 generator;
- the normal/X/diamond percussion legend and the fact that old half-circle/bullseye/open-circle shapes are intentionally retired.

- [ ] **Step 2: Write red table-driven glyph selection tests**

`GlyphCatalogTests.swift` must assert these internal names/scalars via `@testable import DrumNotation`:

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

Expected: FAIL until semantic types/catalog exist.

- [ ] **Step 3: Implement only required public semantic/metric types**

Add:

```swift
import CoreGraphics

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

Do not add app-domain enums or arbitrary public SMuFL lookup.

- [ ] **Step 4: Implement the private closed SMuFL catalog**

`SMuFLGlyphCatalog.swift` uses exhaustive switches over package semantic enums. Raw glyph names/scalars stay internal.

Run `GlyphCatalogTests` again. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/DrumNotation
git commit -m "feat: add Bravura percussion glyph catalog"
```

---

### Task 3: Implement staff-space-scaled Bravura geometry

**Files:**
- Create: `Packages/DrumNotation/Sources/DrumNotation/Glyphs/BravuraFont.swift`
- Create: `Packages/DrumNotation/Tests/DrumNotationTests/BravuraGeometryTests.swift`

**Interfaces:**
- Produces: `PercussionGlyphMetrics.notehead/rest/flag/articulation`.
- Produces: one internal path transform reused by paint and metrics.
- Input scale: `staffSpace: CGFloat` only.

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

- [ ] **Step 2: Implement package-local resource loading**

`BravuraFont` must:

- load `Bravura.otf` and `metadata.json` only through `Bundle.module`;
- create/cache a private `CGFont` and decoded metadata using Swift static initialization;
- create `CTFont` values from that package font as needed;
- call `preconditionFailure` for a missing required file, accepted glyph or required notehead anchor;
- never call `AppFonts`, `Bundle.main` or bundle scanning.

- [ ] **Step 3: Write red staff-space scale tests**

For each accepted notehead/rest/flag/articulation at `staffSpace = 20`, independently calculate:

```swift
let scale = staffSpace / (CGFloat(cgFont.unitsPerEm) / 4)
```

Assert the package path/bounds use that exact scale. In particular, test `noteheadWhole`, `noteheadBlack`, `restWhole` and `restQuarter` so a future implementation cannot reintroduce width/height fitting into the old 30×20, 18×5 or 18×28 frames.

- [ ] **Step 4: Write red notehead-anchor transform tests that catch missing translation**

For every normal/X/diamond duration family × both stem directions:

1. obtain the raw Bravura path bounds;
2. read source metadata `stemUpSE` or `stemDownNW`;
3. convert the anchor from staff spaces into font units (`unitsPerEm / 4`);
4. independently compute the transformed local anchor:

```swift
let expectedAnchor = CGPoint(
    x: (rawAnchor.x - rawBounds.midX) * scale,
    y: -(rawAnchor.y - rawBounds.midY) * scale
)
```

Assert `metrics.stemAnchorOffset` equals this point within 0.001.

Also assert the transformed anchor lies in a narrow stroked edge band around the transformed outline:

```swift
let edgeBand = transformedPath.copy(
    strokingWithWidth: 1.0,
    lineCap: .round,
    lineJoin: .round,
    miterLimit: 10
)
#expect(edgeBand.contains(metrics.stemAnchorOffset))
```

If one documented Bravura anchor sits just outside the outline by less than the stem thickness, widen only that fixture's band by the measured amount.

- [ ] **Step 5: Write red flag attachment tests**

Treat the Bravura flag glyph origin as the stem attachment reference. For 8th/16th/32nd/64th in both directions, assert `FlagGlyphMetrics.attachmentOffset` is the transformed font origin relative to the centered local path and that translating by:

```text
center = stemAttachmentOrigin - attachmentOffset
```

puts the flag attachment back exactly on the requested stem origin.

- [ ] **Step 6: Implement the single transform and public metrics API**

For raw path bounds `B` and staff scale `s`, use:

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

Implement:

```swift
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

No `CGSize` primitive sizing API and no `naturalFlagSize` helper.

- [ ] **Step 7: Run all package tests**

```bash
swift test --package-path Packages/DrumNotation
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Packages/DrumNotation/Sources/DrumNotation/Glyphs \
  Packages/DrumNotation/Tests/DrumNotationTests/BravuraGeometryTests.swift
git commit -m "feat: add staff-scaled Bravura geometry"
```

---

### Task 4: Add package-native SwiftUI primitives from the same geometry

**Files:**
- Create: `Packages/DrumNotation/Sources/DrumNotation/Rendering/PrimitiveViews.swift`
- Modify: `Packages/DrumNotation/Tests/DrumNotationTests/PackageBoundaryTests.swift`

**Interfaces:**
- Consumes: internal fitted paths + public semantic values from Tasks 2–3.
- Produces: four public SwiftUI primitive views.

- [ ] **Step 1: Extend the public API smoke test**

Construct, but do not introspect private geometry from, each public view:

```swift
let _ = PercussionNoteheadView(
    style: .normal,
    duration: .quarter,
    staffSpace: 20
)
let _ = NotationRestGlyphView(duration: .quarter, staffSpace: 20)
let _ = NotationFlagGlyphView(
    duration: .sixteenth,
    direction: .up,
    staffSpace: 20
)
let _ = PercussionArticulationView(articulation: .open, staffSpace: 20)
```

Run package tests. Expected: compile failure until the views exist.

- [ ] **Step 2: Implement views as thin path painters**

Each view:

- selects the internal SMuFL glyph through the same catalog used by metrics;
- asks `BravuraFont` for the same staff-space-scaled transformed path;
- fills the path with caller-supplied `Color` (default `.primary`);
- does not introduce another size/transform path, renderer protocol or AppKit/UIKit branch.

Public initializers are:

```text
PercussionNoteheadView(style:duration:staffSpace:color:)
NotationRestGlyphView(duration:staffSpace:color:)
NotationFlagGlyphView(duration:direction:staffSpace:color:)
PercussionArticulationView(articulation:staffSpace:color:)
```

- [ ] **Step 3: Run package tests + lint**

```bash
swift test --package-path Packages/DrumNotation
swiftlint lint
```

Expected: PASS / no new lint errors.

- [ ] **Step 4: Commit**

```bash
git add Packages/DrumNotation
git commit -m "feat: render native DrumNotation primitives"
```

---

### Task 5: Add the Virgo adapter, flag commands and isolated-flag stem policy

**Files:**
- Create: `Virgo/layout/VirgoNotationAdapter.swift`
- Create: `VirgoTests/VirgoNotationAdapterTests.swift`
- Modify later in this task only if needed for test visibility: no production renderer yet.

**Interfaces:**
- Produces: exhaustive app-to-package mapping.
- Produces: `FlagPaintCommand` data shared by production and raster probe.
- Produces: effective minimum stem length for natural isolated flags.

- [ ] **Step 1: Write red exhaustive semantic mapping tests**

Cover every `NoteType`, all seven `NoteInterval`s, both `StemDirection`s, and every `NotationRestDuration`.

Required rest mapping:

```text
fullMeasure -> whole
half -> half
quarter -> quarter
eighth -> eighth
sixteenth -> sixteenth
thirtySecond -> thirtySecond
sixtyFourth -> sixtyFourth
indeterminate -> nil
```

Required notehead mapping:

```text
bass/snare/highTom/midTom/lowTom -> normal
hiHat/hiHatPedal/openHiHat/crash/ride/china/splash -> x
cowbell -> diamond
```

- [ ] **Step 2: Implement exhaustive pure conversions**

`VirgoNotationAdapter` must expose package mappings without default branches and use:

```swift
static func staffSpace(for style: NotationLayoutStyle) -> CGFloat {
    style.staffLineSpacing
}
```

Do not recreate the former per-primitive size policy.

- [ ] **Step 3: Write red flag-command tests**

Define:

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

Test:

1. isolated eighth emits one `.eighth` command;
2. isolated sixteenth/32nd/64th each emit exactly one canonical duration command from flag level 0 and suppress sibling levels;
3. a partially beamed note emits one `.eighth` command for every uncovered existing `RenderedFlag` and preserves each origin;
4. order matches original `layout.flags` order;
5. each command's `center` + package attachment offset recovers the original `RenderedFlag.origin`.

- [ ] **Step 4: Implement `flagPaintCommands`**

Signature:

```swift
static func flagPaintCommands(
    flags: [RenderedFlag],
    heads: [RenderedNoteHead],
    style: NotationLayoutStyle
) -> [FlagPaintCommand]
```

Use package `FlagGlyphMetrics` at `style.staffLineSpacing`. `NotationFlagView` must not own sibling/grouping logic later.

- [ ] **Step 5: Write red isolated-flag stem-clearance tests**

For isolated 8th/16th/32nd/64th heads in both stem directions, compute package flag metrics relative to attachment:

```swift
let relativeBounds = metrics.paintedBounds.offsetBy(
    dx: -metrics.attachmentOffset.x,
    dy: -metrics.attachmentOffset.y
)
```

Then:

```swift
let inwardExtent: CGFloat
switch direction {
case .up:
    inwardExtent = max(0, relativeBounds.maxY)
case .down:
    inwardExtent = max(0, -relativeBounds.minY)
}

let expected = max(
    style.stemLength,
    inwardExtent + style.minimumStemExtensionPastChord
)
```

Assert the adapter returns that minimum. Also assert quarter/half/full notes do not lengthen the default stem policy.

- [ ] **Step 6: Implement the minimum-stem helper**

Add a pure helper that returns the maximum required canonical-flag stem length across the members of one unbeamed stem group. It may inspect `NoteInterval.flagCount`; it must not change beam grouping or `buildFlags`.

- [ ] **Step 7: Run the adapter suite**

```bash
xcodebuild test \
  -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/VirgoNotationAdapterTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Virgo/layout/VirgoNotationAdapter.swift \
  VirgoTests/VirgoNotationAdapterTests.swift
git commit -m "feat: add DrumNotation adapter policies"
```

---

### Task 6: Remove the old glyph vocabulary and cut layout geometry over

**Files:**
- Modify: `Virgo/constants/Drum.swift`
- Modify: `Virgo/constants/DrumNotation.swift`
- Modify: `Virgo/layout/NotationLayout.swift`
- Modify: `Virgo/layout/NotationLayoutEngine.swift`
- Modify: `Virgo/layout/NotationLayoutEngine+Beams.swift`
- Modify: `Virgo/layout/NotationRhythmRendering.swift`
- Modify: affected layout/catalog test helpers.

**Interfaces:**
- Consumes: `VirgoNotationAdapter`, package metrics.
- Preserves: ticks, X/row placement, beam topology.

- [ ] **Step 1: Remove `DrumNoteheadGlyph` structurally**

Delete:

- the `DrumNoteheadGlyph` enum and all path/bounds/anchor helpers;
- `DrumNotationDefinition.glyph` and initializer arguments;
- `RenderedNoteHead.glyph`;
- `glyph: definition.glyph` from both `RenderedNoteHead` construction paths;
- test fixture/builder arguments that exist only for the removed enum.

Do not add another app engraving enum.

- [ ] **Step 2: Normalize app-only settings symbols**

Keep `DrumType.symbol`, but make it independent from score glyphs:

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

- [ ] **Step 3: Switch head bounds and stem anchors to package metrics**

In `NotationLayoutEngine+Beams.swift`, replace old glyph helpers with `VirgoNotationAdapter` → `PercussionGlyphMetrics.notehead(... staffSpace: style.staffLineSpacing)`.

Use one returned `NoteheadMetrics` object for:

- `stemAnchor(for:style:)`;
- `glyphBounds(for:style:)` / ledger extents;
- `RenderedNoteHead.paintedBounds(style:)`.

Translate local metrics by `noteHead.position`. Do not compute a second bounds approximation.

- [ ] **Step 4: Extend only unbeamed flagged stems enough for natural flags**

In `unbeamedStemEndY`, replace the fixed `style.stemLength` minimum with the adapter's maximum required stem length for the stem group. Keep the existing chord-clearance branch:

```text
up:   min(start.y - effectiveStemLength,
          highestVisibleY - minimumStemExtensionPastChord)
down: max(start.y + effectiveStemLength,
          lowestVisibleY + minimumStemExtensionPastChord)
```

Do not change `sharedBeamBaseY`, beam grouping or stem representative selection in this task.

- [ ] **Step 5: Cut rest/articulation/flag painted bounds over**

In `NotationRhythmRendering.swift`:

- `RenderedRest.paintedBounds` uses `VirgoNotationAdapter.restDuration(for:)`; `.indeterminate` returns `.null`; otherwise translate package rest metrics at `style.staffLineSpacing` around `rest.position`;
- `RenderedArticulation.paintedBounds` translates package `.open` metrics around its app-owned position;
- `NotationLayout.calculatePaintedBounds` obtains `FlagPaintCommand`s from the adapter and unions their `paintedBounds` instead of `RenderedFlag.paintedBounds`;
- delete `RenderedFlag.paintedBounds` once unused.

- [ ] **Step 6: Update explicit compile/golden serializers**

`NotationLayoutDigest.swift` must remove `head.glyph`. Serialize the derived package notehead style plus existing app `variant` instead, so goldens preserve semantic visual identity without the deleted enum.

`DrumTabGoldenTests.hiHatOpenClosedPedal` must assert the three variants directly rather than `(glyph, variant)` pairs.

Remove pure tests that only validated the handwritten path enum; package geometry tests replace them.

- [ ] **Step 7: Run focused layout/catalog suites**

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
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300
```

Expected: PASS. Repeated `-only-testing:` constraints are intentional and cumulative.

- [ ] **Step 8: Commit**

```bash
git add Virgo VirgoTests
git commit -m "feat: use DrumNotation geometry in layout"
```

---

### Task 7: Cut production painting over and add a real raster/visual gate

**Files:**
- Modify: `Virgo/views/NotationPrimitiveViews.swift`
- Modify: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Modify: `VirgoTests/RenderRasterProbe.swift`
- Modify: `VirgoTests/SwiftUIRenderingNotationTests.swift`
- Modify: `VirgoTests/DrumTabRenderProbeTests.swift`

**Interfaces:**
- Production and probe share `FlagPaintCommand` data.
- Raster assertions verify actual ink against package-derived bounds.

- [ ] **Step 1: Replace handwritten production primitives**

In `NotationPrimitiveViews.swift`:

- notehead wrapper → `PercussionNoteheadView(... staffSpace: style.staffLineSpacing or supplied staffSpace, color: Palette.chalk)`;
- rest wrapper → `NotationRestGlyphView` from `restDuration(for:)`;
- open-hi-hat wrapper → `PercussionArticulationView(.open, staffSpace: ...)`;
- flag wrapper becomes `NotationFlagView(command:)` and delegates one command to `NotationFlagGlyphView`.

Delete:

- `DrumNoteheadShape`;
- quarter/hooked rest path builders and full/half rest rectangles;
- open articulation `Circle`;
- handwritten `FlagView` Bézier path and flag-center correction.

Keep stems, beams, ledger lines, bars, dots, tuplets, feel marks, warnings and stop marks app-owned.

- [ ] **Step 2: Make production and probe consume identical flag commands**

`GameplayDrumNotationView` computes once:

```swift
let flagCommands = VirgoNotationAdapter.flagPaintCommands(
    flags: layout.flags,
    heads: layout.noteHeads,
    style: style
)
```

and renders those commands.

Change `DrumTabRenderProbeTests.notationOverlay` to call the exact same helper and render the same commands. Do not copy collapse/group logic into the test.

- [ ] **Step 3: Extend raster helper with PNG output**

In the existing macOS-only `RenderRasterProbe.swift`, add a small helper alongside `rasterizeView`:

```swift
@MainActor
func writeRasterPNG<V: View>(
    _ view: V,
    size: CGSize,
    url: URL
) throws {
    let renderer = ImageRenderer(
        content: view.frame(width: size.width, height: size.height)
    )
    renderer.scale = 1
    guard let cgImage = renderer.cgImage else {
        throw RenderRasterProbeError.missingCGImage
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw RenderRasterProbeError.missingPNGData
    }
    try data.write(to: url)
}
```

Add `missingPNGData` to the test error enum and `import AppKit` inside the macOS conditional.

- [ ] **Step 4: Add non-tautological ink-inside-bounds tests**

In `SwiftUIRenderingNotationTests`, render representative **production wrappers** in isolation at known positions using `rasterizeView`:

- whole normal notehead;
- quarter normal/X/diamond heads;
- whole rest;
- quarter rest;
- isolated 64th flag command;
- open-hi-hat articulation.

For each case:

1. obtain the same translated `paintedBounds` production layout uses;
2. assert at least one pixel with `alpha > 20` is inside the bounds;
3. expand the bounds by 1pt for antialias tolerance;
4. assert no `alpha > 20` pixel exists outside the expanded bounds.

Use the existing scale-1 raster convention so SwiftUI point coordinates correspond to sampled pixels.

Do **not** replace this with `@testable` checks that the view and metrics function selected the same path; that would only prove both called the same helper.

- [ ] **Step 5: Add one representative visual-preview test**

Construct one fixture row containing:

- whole + quarter normal heads;
- X + diamond heads;
- whole + quarter + 16th rests;
- isolated 8th + 64th flags;
- one partially beamed uncovered hook;
- open hi-hat articulation.

Write the mounted row to:

```swift
FileManager.default.temporaryDirectory
    .appendingPathComponent("hpa-163-bravura-preview.png")
```

using `writeRasterPNG` and assert the file is non-empty.

- [ ] **Step 6: Run raster suites, then inspect the PNG before any golden rewrite**

```bash
xcodebuild test \
  -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/SwiftUIRenderingNotationTests \
  -only-testing:VirgoTests/DrumTabRenderProbeTests \
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300
```

Expected: PASS.

Open `hpa-163-bravura-preview.png` from the temporary directory and visually verify:

- whole/black noteheads have consistent staff-relative scale;
- rests are not vertically/horizontally squashed;
- 64th flag clears its notehead;
- partially beamed hook remains attached;
- open-hi-hat mark is visible and unclipped.

Record the inspection result in PR verification notes. Do not commit PNG goldens.

- [ ] **Step 7: Commit**

```bash
git add Virgo/views VirgoTests
git commit -m "feat: render Bravura percussion primitives"
```

---

### Task 8: Lock topology/goldens, run full verification, then leave draft

**Files:**
- Modify only justified `VirgoTests/Goldens/*.txt` after visual/raster gates pass.
- Modify tests if a missing topology assertion is needed.
- No feature expansion.

- [ ] **Step 1: Add the rendered-hook preservation test before updating goldens**

For existing hook fixtures, use `BeamBuildResult` to compare:

- topology `BeamTopologySegment`s whose kind is `.forwardHook` / `.backwardHook`, grouped by primary group + level + kind;
- rendered `RenderedBeam`s with the same level/kind.

Assert every topology hook produces exactly one non-zero rendered hook.

This protects the case where new notehead anchor X values make the current `beamEndpoint` distance collapse to zero and silently drop a topology-requested hook.

If this test fails, stop. HPA-163 must preserve topology; do not regenerate goldens around a missing hook. Correct rendering geometry while keeping the topology segment intact.

- [ ] **Step 2: Run notation regression suites before changing goldens**

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

Expected: non-golden invariants pass. Golden mismatches are expected where Bravura geometry/style identity changed.

- [ ] **Step 3: Classify every golden difference before regeneration**

Allowed drift:

- derived package style identity replacing `DrumNoteheadGlyph`;
- stem/beam/flag coordinates caused by corrected anchors and isolated-stem extension;
- painted/content bounds caused by natural staff-space glyph size.

Must remain unchanged:

- absolute tick and local tick;
- measure index and row;
- note onset X;
- beam topology membership;
- beam level and kind;
- hook segment count per topology group;
- playhead routing.

Any change in the forbidden set is a blocker, not a golden-update candidate.

- [ ] **Step 4: Regenerate intentional goldens using the exact repository contract**

Only after Task 7 visual/raster checks pass and Step 3 classifies the diff, run:

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

Expected: goldens are rewritten **and the command exits failing by design**. That failure is not a regression; the golden helper intentionally prevents self-approving updates.

Review:

```bash
git diff -- VirgoTests/Goldens
```

Do not use bare `VIRGO_UPDATE_GOLDENS=1` with `xcodebuild`.

Then rerun without the update variable:

```bash
xcodebuild test \
  -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300
```

Expected: PASS.

- [ ] **Step 5: Run fresh full local verification while the PR is still draft**

CI intentionally skips draft PRs, so these local commands are required before changing draft state:

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
git diff --check main...HEAD
```

Expected: all commands pass; iOS-family target remains iPad-only.

- [ ] **Step 6: Run package-boundary audits**

```bash
grep -R -nE 'import Virgo|NoteType|DrumType|RenderedNoteHead|GameplayLayout|Palette|AppFonts|Bundle\.main' \
  Packages/DrumNotation/Sources Packages/DrumNotation/Tests || true

grep -R -nE 'vexflow|jsdom' \
  Packages/DrumNotation/Package.swift Packages/DrumNotation/Sources \
  Virgo Virgo.xcodeproj/project.pbxproj || true

find Packages/DrumNotation -type l -print
git grep -n 'DrumNoteheadGlyph' -- Virgo VirgoTests || true
```

Expected:

- no app-domain/theme dependency in package Swift source;
- no shipping VexFlow/jsdom dependency;
- no package symlinks escaping into Virgo;
- no remaining `DrumNoteheadGlyph` production/test reference.

- [ ] **Step 7: Review scope and commit final test/golden/doc adjustments**

```bash
git diff main...HEAD --stat
git diff main...HEAD -- \
  Packages/DrumNotation Virgo/layout Virgo/views Virgo/constants \
  VirgoTests .swiftlint.yml .github/workflows/ci.yml
```

Reject any accidental:

- measured horizontal formatter work;
- beam-topology rewrite;
- DTX/rhythm-inference change;
- runtime JS/WebView;
- second package product/target;
- publication/release infrastructure.

Commit only justified final changes:

```bash
git add Packages/DrumNotation Virgo VirgoTests .swiftlint.yml .github/workflows/ci.yml
git commit -m "test: verify DrumNotation primitive migration"
```

- [ ] **Step 8: Mark this same PR ready and require CI**

After all local verification above is fresh and green, mark PR #65 ready for review. This triggers the existing `ready_for_review` workflow event and removes the draft-job guard.

Require the GitHub Actions checks to run successfully, including the new `Run DrumNotation package tests` step, before considering HPA-163 complete.

Do not open another implementation PR.

---

## Risks / decisions to preserve during implementation

### Natural staff-space glyphs are intentionally not legacy-size-compatible

Natural Bravura whole heads/rests may be wider/taller than the removed custom shapes. Preserve ticks and fixed note X, not old glyph dimensions. Raster/visual review happens before golden regeneration.

### Natural isolated flags may lengthen stems

Do not shrink flags into 8×8. Extend only unbeamed flagged stems to satisfy the package-computed inward flag extent plus existing chord clearance. HPA-166 still owns final beam/modifier engraving behavior.

### Anchor X may expose a degenerate existing hook renderer

Topology is invariant here. Every topology-requested hook must still produce one rendered non-zero hook. If corrected anchors expose a zero-length endpoint, fix rendering geometry rather than deleting/changing topology or blessing the missing segment in goldens.

---

## Completion Checklist

Before HPA-163 is ready to merge:

- [ ] `swift test --package-path Packages/DrumNotation` passes from a clean package build.
- [ ] `.swiftlint.yml` includes `Packages`; SwiftLint has no new errors.
- [ ] Bravura 1.392 OTF/metadata/license are package-owned from the pinned VexFlow font source.
- [ ] Every primitive uses `staffSpace`, not a legacy `CGSize` fit.
- [ ] Whole/black noteheads and whole/quarter rests have natural staff-relative scale.
- [ ] Notehead anchors use the same full transform as paint and pass edge tests.
- [ ] Isolated 32nd/64th flags remain clear of heads through bounded unbeamed-stem extension.
- [ ] Notehead/rest/flag/open-articulation raster ink is inside the reported package-derived bounds.
- [ ] A representative PNG row has been visually inspected before golden regeneration.
- [ ] Production and `DrumTabRenderProbeTests.notationOverlay` consume identical `FlagPaintCommand`s.
- [ ] `DrumNoteheadGlyph` and handwritten primitive geometry are gone.
- [ ] DTX identity, voice/staff placement, absolute ticks, note X, beam topology membership/level/kind, hook count and playhead routing are unchanged.
- [ ] Full serial macOS tests and generic iOS Simulator build pass locally.
- [ ] Intentional goldens were regenerated with `TEST_RUNNER_VIRGO_UPDATE_GOLDENS=1`, reviewed, then pass without the update variable.
- [ ] PR #65 is marked ready only after local verification and its GitHub Actions checks pass.
- [ ] HPA-164 still owns measured horizontal formatting; HPA-166 still owns complete stem/beam/modifier/static-sheet parity.
