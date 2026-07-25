# Drum Tab Regression Fixtures and Golden Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an 11-fixture, DTX-driven regression suite that locks drum-tab layout geometry with textual golden digests, so the HPA-97 rendering fixes cannot silently regress.

**Architecture:** Each fixture is a small DTX string run through the real production import path (`parseChartMetadata` → `persistenceProjection` → `Chart` in a `TestContainer` → `RhythmTimelineResolver` → `RhythmLayoutSnapshotBuilder` → `NotationLayoutEngine`). The resulting layout is serialized to a deterministic text digest and diffed against a committed golden file. One production change — extracting `RhythmLayoutSnapshotBuilder` out of `GameplayViewModel` — guarantees the harness and production share a single code path.

**Tech Stack:** Swift 5.9+, SwiftUI, SwiftData, Swift Testing (`import Testing`), AppKit `ImageRenderer` for the view probe, macOS destination.

**Spec:** `docs/superpowers/specs/2026-07-24-drum-tab-rendering-regression-fixtures-design.md`

## Global Constraints

- **Test framework:** Swift Testing only (`import Testing`, `@Test`, `@Suite`, `#expect`, `#require`). Never XCTest. This repo has no XCTest unit tests.
- **No Xcode project edits.** The project uses `PBXFileSystemSynchronizedRootGroup` (objectVersion 77). New files under `Virgo/` and `VirgoTests/` are picked up automatically. **Never edit `Virgo.xcodeproj/project.pbxproj`.**
- **SwiftLint limits:** line 120 warn / 150 error; function body 50/100 lines; type body 300/600; file 600/1000. Every new file must stay under 600 lines.
- **Test command** (always; never run two of these concurrently against the same `-derivedDataPath`):
  ```bash
  xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
    -destination 'platform=macOS' -configuration Debug \
    -only-testing:VirgoTests -parallel-testing-enabled NO \
    ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    -destination-timeout 300 -derivedDataPath ./DerivedData
  ```
- **Known pre-existing failure:** a full `VirgoTests` run is red on `main` too (`\Chart.difficulty` detached crash). Do not treat it as a regression from this work. Prefer suite-scoped runs, e.g. `-only-testing:VirgoTests/DrumTabGoldenTests`.
- **Swift Testing selectors:** method-level `-only-testing` selectors often report "Executed 0 tests" because the generated selector name does not match. Use **suite-level** selectors.
- **Locked layout style** (used by every fixture): `NotationLayoutStyle.gameplayDefault.with(rowWidth: GameplayLayout.maxRowWidth)` and `notePositionOverrides = Dictionary(uniqueKeysWithValues: DrumType.allCases.map { ($0, $0.notePosition) })`. Never `DrumNotationSettingsManager.loadPositions()` — user settings must not reach a golden.
- **Number formatting in digests:** always `String(format:locale:)` with `Locale(identifier: "en_US_POSIX")`, 2 decimals.
- **Golden regeneration:** `VIRGO_UPDATE_GOLDENS=1` writes the file **and still fails the test**. CI never sets it.
- **DTX chip syntax:** `#<measure:3 digits><lane:2 chars>: <chips>`; chips are 2-character note IDs; `00` means empty; grid size = number of 2-char groups. Example `#00113: 01010101` = measure 1, lane 13, 4 positions, chips at 0,1,2,3. Lane IDs are case-insensitive.
- **Lane IDs:** `11` hi-hat closed, `12` snare, `13` bass drum, `14` high tom, `16` crash, `18` hi-hat open, `19` ride, `1A` left crash, `1B` left pedal, `1C` left bass. Control lanes `21` stop / `22` choke / `23` damp, active only with `#VIRGO_CONTROL: 1`; a control chip's note ID is the **target lane ID**.

## File Structure

| File | Responsibility |
| --- | --- |
| `Virgo/layout/RhythmLayoutSnapshotBuilder.swift` | **Production.** Snapshot assembly extracted from `GameplayViewModel`; the single code path shared with tests. |
| `Virgo/viewmodels/GameplayViewModel+Computations.swift` | **Modify.** Delegate to the builder. |
| `VirgoTests/Fixtures/DrumTabFixture.swift` | Fixture value type + DTX line helper. |
| `VirgoTests/Fixtures/DrumTabFixtureCatalog.swift` | Fixtures 1, 2, 3, 6, 7, 8, 11 (mapping, beaming, flags). |
| `VirgoTests/Fixtures/DrumTabFixtureCatalog+Rhythm.swift` | Fixtures 4, 5, 9, 10 (grid resolution, rests, wrapping). |
| `VirgoTests/Fixtures/DrumTabFixtureHarness.swift` | DTX → `FixtureRenderResult` through the production path. |
| `VirgoTests/NotationLayoutDigest.swift` | `FixtureRenderResult` → deterministic text. |
| `VirgoTests/GoldenFile.swift` | Load/compare/regenerate + diff reporting. |
| `VirgoTests/DrumTabGoldenTests.swift` | 11 digest comparisons. |
| `VirgoTests/DrumTabRegressionInvariantTests.swift` | Spacing + beam geometry + cross-cutting invariants. |
| `VirgoTests/DrumTabRenderProbeTests.swift` | Differential ink probe. |
| `VirgoTests/DrumTabPlayheadAlignmentTests.swift` | Playhead x vs note columns. |
| `VirgoTests/Goldens/*.txt` | 11 committed golden digests. |

---

### Task 1: Extract `RhythmLayoutSnapshotBuilder`

Behavior-neutral move. Everything else depends on it, so it goes first.

**Files:**
- Create: `Virgo/layout/RhythmLayoutSnapshotBuilder.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift` (remove `makeRhythmLayoutSnapshot` and `rhythmMeasuresApplyingWarnings`; call the builder)
- Test: `VirgoTests/RhythmLayoutSnapshotBuilderTests.swift`

**Interfaces:**
- Consumes: `ResolvedChartRhythm`, `RhythmTimeline`, `RhythmicFeel`, `NotationRhythmAnalyzer`, `RhythmLayoutSnapshot`.
- Produces: `@MainActor struct RhythmLayoutSnapshotBuilder { func build(resolvedRhythm: ResolvedChartRhythm, timeline: RhythmTimeline, feel: RhythmicFeel) throws -> RhythmLayoutSnapshot }`

- [ ] **Step 1: Read the code being moved**

Read `Virgo/viewmodels/GameplayViewModel+Computations.swift`, the `makeRhythmLayoutSnapshot(resolvedRhythm:timeline:)` method and the `rhythmMeasuresApplyingWarnings(_:warnings:)` helper below it. Both are `private`. Note that `makeRhythmLayoutSnapshot` reads `resolvedRhythmFeel()` indirectly via its `feel` local — that call becomes the new `feel:` parameter.

- [ ] **Step 2: Write the failing test**

Create `VirgoTests/RhythmLayoutSnapshotBuilderTests.swift`:

```swift
import Testing
import Foundation
@testable import Virgo

@Suite("Rhythm layout snapshot builder", .serialized)
@MainActor
struct RhythmLayoutSnapshotBuilderTests {
    @Test("builder produces a snapshot from a resolved chart rhythm")
    func buildsSnapshotFromResolvedRhythm() throws {
        let dtx = """
        #TITLE: Builder
        #ARTIST: Virgo Fixtures
        #BPM: 120
        #DLEVEL: 50
        #00113: 01010101
        """
        let chartData = try DTXFileParser.parseChartMetadata(from: dtx)
        let projection = try chartData.persistenceProjection()
        let container = TestContainer.isolatedContainer()
        let context = container.context
        let song = Song(
            title: chartData.title,
            artist: chartData.artist,
            bpm: chartData.bpm,
            duration: "0:04",
            genre: "DTX"
        )
        let chart = Chart(
            difficulty: .medium,
            timeSignature: projection.timeSignature,
            song: song
        )
        try chart.setRhythmMetadata(projection.chartMetadata)
        chart.notes = projection.notes.map { $0.makeNote(for: chart) }
        chart.controlEvents = projection.controls.map { $0.makeControl(for: chart) }
        song.charts = [chart]
        context.insert(song)
        try context.save()

        let resolved = RhythmTimelineResolver().resolve(chart: chart)
        #expect(resolved.availability == .valid)
        let timeline = try #require(resolved.timeline)

        let snapshot = try RhythmLayoutSnapshotBuilder().build(
            resolvedRhythm: resolved,
            timeline: timeline,
            feel: .straight
        )

        #expect(snapshot.ticksPerWholeNote == timeline.ticksPerWholeNote)
        #expect(snapshot.notes.count == 4)
        #expect(snapshot.feel == .straight)
        #expect(snapshot.measures.count == timeline.measures.count)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -configuration Debug -only-testing:VirgoTests/RhythmLayoutSnapshotBuilderTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected: build failure — `cannot find 'RhythmLayoutSnapshotBuilder' in scope`.

- [ ] **Step 4: Create the builder by moving the code verbatim**

Create `Virgo/layout/RhythmLayoutSnapshotBuilder.swift`. Move the bodies of `makeRhythmLayoutSnapshot` and `rhythmMeasuresApplyingWarnings` **unchanged**, with two edits only: `feel` comes from the parameter instead of `resolvedRhythmFeel()`, and `rhythmMeasuresApplyingWarnings` becomes a `private func` on the builder.

```swift
import Foundation

/// Assembles the `RhythmLayoutSnapshot` that timeline-native layout consumes.
///
/// Extracted from `GameplayViewModel+Computations` so the gameplay view model and
/// the drum-tab fixture harness share one code path. A parallel copy in tests
/// would let goldens pass while production rendering broke.
@MainActor
struct RhythmLayoutSnapshotBuilder {
    func build(
        resolvedRhythm: ResolvedChartRhythm,
        timeline: RhythmTimeline,
        feel: RhythmicFeel
    ) throws -> RhythmLayoutSnapshot {
        // ... moved verbatim from makeRhythmLayoutSnapshot, using `feel` from the
        // parameter rather than resolvedRhythmFeel(). Keep the trailing
        // snapshot.logDiagnostics() call.
    }

    private func rhythmMeasuresApplyingWarnings(
        _ measures: [RhythmMeasure],
        warnings: [RhythmMeasureWarning]
    ) -> [RhythmMeasure] {
        // ... moved verbatim
    }
}
```

Two constraints, both load-bearing:
- **Keep `snapshot.logDiagnostics()`** before returning. Dropping it changes diagnostic behavior.
- **Keep `@MainActor`.** `ResolvedChartRhythm` is `@MainActor` and the builder reads SwiftData `Note` objects through `noteByEventID`. This is not a pure function.

- [ ] **Step 5: Update `GameplayViewModel+Computations` to delegate**

Delete both private methods. Replace the call site (inside the `do` block that builds `GameplayRhythmRuntime`) with:

```swift
let layoutSnapshot = try RhythmLayoutSnapshotBuilder().build(
    resolvedRhythm: resolvedRhythm,
    timeline: timeline,
    feel: resolvedRhythmFeel()
)
```

Keep `resolvedRhythmFeel()` on the view model — it reads `chart.rhythmMetadataState` and stays there.

- [ ] **Step 6: Run the new test to verify it passes**

Same command as Step 3. Expected: PASS.

- [ ] **Step 7: Verify no regression in the view model suites**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/RhythmTimelineIntegrationTests \
  -only-testing:VirgoTests/GameplayViewModelComputationsTests \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected: same pass/fail set as before the change. These suites are the regression check for a behavior-neutral move — if any newly fails, the move was not verbatim.

- [ ] **Step 8: Lint and commit**

```bash
swiftlint lint --quiet
git add Virgo/layout/RhythmLayoutSnapshotBuilder.swift \
        Virgo/viewmodels/GameplayViewModel+Computations.swift \
        VirgoTests/RhythmLayoutSnapshotBuilderTests.swift
git commit -m "refactor: extract RhythmLayoutSnapshotBuilder from GameplayViewModel

Snapshot assembly was private on the view model, so a fixture harness
would have had to reimplement it — and a divergent copy would let
goldens pass while production rendering broke. Now one code path.

Behavior-neutral: feel is parameterized, logDiagnostics() retained."
```

---

### Task 2: Fixture type, harness, and fixture 1 end-to-end

Prove the whole pipeline with one fixture before adding ten more.

**Files:**
- Create: `VirgoTests/Fixtures/DrumTabFixture.swift`
- Create: `VirgoTests/Fixtures/DrumTabFixtureCatalog.swift`
- Create: `VirgoTests/Fixtures/DrumTabFixtureHarness.swift`
- Test: `VirgoTests/DrumTabFixtureHarnessTests.swift`

**Interfaces:**
- Consumes: `RhythmLayoutSnapshotBuilder` (Task 1).
- Produces:
  - `struct DrumTabFixture { let name: String; let dtx: String; let minimumMeasureCount: Int; let controlBlock: String? }`
  - `static func DrumTabFixture.line(measure: Int, lane: String, positions: [Int: String], total: Int) -> String`
  - `struct FixtureRenderResult { let chart: Chart; let layout: NotationLayout; let snapshot: RhythmLayoutSnapshot; let timeline: RhythmTimeline; let style: NotationLayoutStyle }`
  - `enum DrumTabFixtureHarness { static func render(_ fixture: DrumTabFixture, includeControls: Bool = true) throws -> FixtureRenderResult; static let lockedStyle: NotationLayoutStyle; static let lockedOverrides: [DrumType: GameplayLayout.NotePosition] }`
  - `enum DrumTabFixtureCatalog { static let sameTimeTrio: DrumTabFixture }`

- [ ] **Step 1: Create the fixture value type**

`VirgoTests/Fixtures/DrumTabFixture.swift`:

```swift
import Foundation
@testable import Virgo

/// One drum-tab regression fixture: a small DTX chart plus the metadata the
/// harness needs to render it deterministically.
struct DrumTabFixture {
    let name: String
    let dtx: String
    let minimumMeasureCount: Int
    /// Control-lane chip lines, kept separate so fixture 8 can be rendered with
    /// and without them to prove control events do not feed rest inference.
    let controlBlock: String?

    init(
        name: String,
        dtx: String,
        minimumMeasureCount: Int = 1,
        controlBlock: String? = nil
    ) {
        self.name = name
        self.dtx = dtx
        self.minimumMeasureCount = minimumMeasureCount
        self.controlBlock = controlBlock
    }

    /// Full DTX text, optionally including the control block.
    func source(includeControls: Bool) -> String {
        guard includeControls, let controlBlock else { return dtx }
        return dtx + "\n" + controlBlock
    }

    /// Builds a DTX chip line. Positions not listed are empty (`00`).
    ///
    /// Generated rather than hand-typed because high-resolution fixtures need
    /// 64-position (128-character) lines where a miscount is invisible.
    static func line(
        measure: Int,
        lane: String,
        positions: [Int: String],
        total: Int
    ) -> String {
        let chips = (0..<total)
            .map { positions[$0] ?? "00" }
            .joined()
        let measureField = String(format: "%03d", measure)
        return "#\(measureField)\(lane): \(chips)"
    }

    /// Convenience for lines where every filled position uses the same note ID.
    static func line(
        measure: Int,
        lane: String,
        at positions: [Int],
        total: Int,
        noteID: String = "01"
    ) -> String {
        line(
            measure: measure,
            lane: lane,
            positions: Dictionary(uniqueKeysWithValues: positions.map { ($0, noteID) }),
            total: total
        )
    }
}
```

- [ ] **Step 2: Create the harness**

`VirgoTests/Fixtures/DrumTabFixtureHarness.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import Virgo

/// The rendered output of one fixture, plus the inputs later assertions need.
///
/// Carries `chart` because the playhead tests drive a real `GameplayViewModel`,
/// and `snapshot` because beat groups and engraving support live on
/// `RhythmMeasure` rather than on `RenderedMeasure`.
@MainActor
struct FixtureRenderResult {
    let chart: Chart
    let layout: NotationLayout
    let snapshot: RhythmLayoutSnapshot
    let timeline: RhythmTimeline
    let style: NotationLayoutStyle
    /// Retained so the chart's backing store outlives `render(...)`.
    let container: TestContainer
}

enum DrumTabFixtureHarnessError: Error {
    case rhythmUnavailable(RhythmTimelineAvailability)
    case missingTimeline
}

/// Runs a fixture through the production import and layout path.
///
/// Deliberately mirrors `LocalDTXFixtureImporter` / `ServerSongDownloader`:
/// `persistenceProjection()` + `setRhythmMetadata` rather than
/// `toNotes`/`toControlEvents`, because the latter leaves
/// `rhythmMetadataState == .missing` (routing `resolve` through
/// `resolveMissing`) and stamps control ticks at each chip's native grid size
/// instead of the shared LCM timeline.
@MainActor
enum DrumTabFixtureHarness {
    /// Pinned so goldens cannot depend on window size or user settings.
    static let lockedStyle = NotationLayoutStyle.gameplayDefault
        .with(rowWidth: GameplayLayout.maxRowWidth)

    static let lockedOverrides: [DrumType: GameplayLayout.NotePosition] =
        Dictionary(uniqueKeysWithValues: DrumType.allCases.map { ($0, $0.notePosition) })

    static func render(
        _ fixture: DrumTabFixture,
        includeControls: Bool = true
    ) throws -> FixtureRenderResult {
        let chartData = try DTXFileParser.parseChartMetadata(
            from: fixture.source(includeControls: includeControls)
        )
        let projection = try chartData.persistenceProjection()

        let container = TestContainer.isolatedContainer()
        let context = container.context
        let song = Song(
            title: chartData.title,
            artist: chartData.artist,
            bpm: chartData.bpm,
            duration: "0:10",
            genre: "DTX"
        )
        let chart = Chart(
            difficulty: .medium,
            level: chartData.difficultyLevel,
            timeSignature: projection.timeSignature,
            song: song
        )
        try chart.setRhythmMetadata(projection.chartMetadata)
        chart.notes = projection.notes.map { $0.makeNote(for: chart) }
        chart.controlEvents = projection.controls.map { $0.makeControl(for: chart) }
        song.charts = [chart]
        context.insert(song)
        try context.save()

        let resolved = RhythmTimelineResolver().resolve(chart: chart)
        guard resolved.availability == .valid else {
            throw DrumTabFixtureHarnessError.rhythmUnavailable(resolved.availability)
        }
        guard let timeline = resolved.timeline else {
            throw DrumTabFixtureHarnessError.missingTimeline
        }

        let feel: RhythmicFeel = {
            if case let .valid(metadata) = chart.rhythmMetadataState {
                return metadata.feel ?? .straight
            }
            return .straight
        }()

        let snapshot = try RhythmLayoutSnapshotBuilder().build(
            resolvedRhythm: resolved,
            timeline: timeline,
            feel: feel
        )

        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                timing: .timeline(snapshot),
                minimumMeasureCount: fixture.minimumMeasureCount,
                style: lockedStyle,
                notePositionOverrides: lockedOverrides
            )
        )

        return FixtureRenderResult(
            chart: chart,
            layout: layout,
            snapshot: snapshot,
            timeline: timeline,
            style: lockedStyle,
            container: container
        )
    }
}
```

- [ ] **Step 3: Add fixture 1 to the catalog**

`VirgoTests/Fixtures/DrumTabFixtureCatalog.swift`:

```swift
import Foundation
@testable import Virgo

/// Fixtures covering drum mapping, beaming, and flags.
/// Grid-resolution, rest, and wrapping fixtures live in
/// `DrumTabFixtureCatalog+Rhythm.swift` to stay under SwiftLint's file limit.
enum DrumTabFixtureCatalog {
    private static let header = """
    #TITLE: Virgo Drum Tab Fixture
    #ARTIST: Virgo Fixtures
    #BPM: 120
    #DLEVEL: 50
    """

    static func chart(_ lines: [String]) -> String {
        ([header] + lines).joined(separator: "\n")
    }

    /// Fixture 1: kick + snare + closed hi-hat struck together on beats 1 and 3.
    /// All three heads must land on one x column (HPA-141).
    static let sameTimeTrio = DrumTabFixture(
        name: "same-time-trio",
        dtx: chart([
            DrumTabFixture.line(measure: 1, lane: "13", at: [0, 2], total: 4),
            DrumTabFixture.line(measure: 1, lane: "12", at: [0, 2], total: 4),
            DrumTabFixture.line(measure: 1, lane: "11", at: [0, 2], total: 4)
        ])
    )
}
```

- [ ] **Step 4: Write the failing harness test**

`VirgoTests/DrumTabFixtureHarnessTests.swift`:

```swift
import Testing
import Foundation
@testable import Virgo

@Suite("Drum tab fixture harness", .serialized)
@MainActor
struct DrumTabFixtureHarnessTests {
    @Test("harness renders a fixture through the timeline path")
    func rendersThroughTimelinePath() throws {
        let result = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.sameTimeTrio)

        // Six heads: three drums on each of two beats.
        #expect(result.layout.noteHeads.count == 6)

        // Style must be the pinned one, so goldens cannot drift with window size.
        #expect(result.style == NotationLayoutStyle.gameplayDefault
            .with(rowWidth: GameplayLayout.maxRowWidth))

        // Two distinct time columns, three heads each, one x per column.
        let byColumn = Dictionary(grouping: result.layout.noteHeads) {
            $0.timeColumn.absoluteLayoutTick
        }
        #expect(byColumn.count == 2)
        for (_, heads) in byColumn {
            #expect(heads.count == 3)
            #expect(Set(heads.map { $0.position.x }).count == 1)
        }
    }
}
```

- [ ] **Step 5: Run to verify it fails, then passes**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -configuration Debug -only-testing:VirgoTests/DrumTabFixtureHarnessTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```

First run before Steps 1–3 exist: build failure. After: PASS.

If `rhythmUnavailable` is thrown, the DTX did not parse as a valid-timing chart — print `chartData.rhythmMetadata.diagnostics` and fix the fixture text before continuing. Do not weaken the assertion.

- [ ] **Step 6: Lint and commit**

```bash
swiftlint lint --quiet
git add VirgoTests/Fixtures VirgoTests/DrumTabFixtureHarnessTests.swift
git commit -m "test: drum tab fixture harness on the production import path

DTX text -> persistenceProjection -> Chart in a TestContainer ->
RhythmTimelineResolver -> RhythmLayoutSnapshotBuilder -> layout, with
rowWidth and notePositionOverrides pinned so goldens cannot depend on
window size or user drum-position settings."
```

---

### Task 3: Digest and golden-file machinery

**Files:**
- Create: `VirgoTests/NotationLayoutDigest.swift`
- Create: `VirgoTests/GoldenFile.swift`
- Create: `VirgoTests/DrumTabGoldenTests.swift`
- Create: `VirgoTests/Goldens/same-time-trio.txt` (generated in Step 5)

**Interfaces:**
- Consumes: `FixtureRenderResult` (Task 2).
- Produces:
  - `enum NotationLayoutDigest { static func make(_ result: FixtureRenderResult) -> String }`
  - `enum GoldenFile { static func assertMatches(_ actual: String, fixture: String, sourceLocation: SourceLocation) throws }`

- [ ] **Step 1: Create the digest serializer**

`VirgoTests/NotationLayoutDigest.swift`. Sections are labelled by source: `tl-*` lines come from the snapshot/timeline, the rest from the layout. Every collection is sorted by an explicit total order before serialization — `noteHeadIDsByLayoutTick` is a `[Int: Set<UInt64>]` and SwiftData relationship order is not guaranteed, so unsorted output would be nondeterministic.

```swift
import CoreGraphics
import Foundation
@testable import Virgo

/// Serializes a rendered fixture to deterministic text for golden comparison.
///
/// Locks layout geometry, the grid, the resolved style, and the layout's own
/// dimensions. Does NOT lock anything downstream of layout — view modifiers,
/// colour, z-order, font rasterization. That boundary is deliberate.
@MainActor
enum NotationLayoutDigest {
    private static let posix = Locale(identifier: "en_US_POSIX")

    private static func f(_ value: CGFloat) -> String {
        String(format: "%.2f", locale: posix, Double(value))
    }

    private static func pt(_ point: CGPoint) -> String {
        "(\(f(point.x)),\(f(point.y)))"
    }

    static func make(_ result: FixtureRenderResult) -> String {
        var lines: [String] = []
        lines.append(contentsOf: timelineSection(result))
        lines.append("")
        lines.append(contentsOf: layoutSection(result))
        return lines.joined(separator: "\n") + "\n"
    }

    private static func timelineSection(_ result: FixtureRenderResult) -> [String] {
        let snapshot = result.snapshot
        var lines = ["tl-grid ticksPerWholeNote=\(snapshot.ticksPerWholeNote) feel=\(snapshot.feel)"]
        for measure in snapshot.measures.sorted(by: { $0.measureIndex < $1.measureIndex }) {
            let groups = measure.beatGroups
                .sorted { $0.groupIndex < $1.groupIndex }
                .map(\.startTick)
                .map(String.init)
                .joined(separator: ",")
            let engraving: String
            switch measure.engravingSupport {
            case .supported:
                engraving = "supported"
            case let .unsupported(codes):
                engraving = "unsupported[" + codes.map(\.rawValue).sorted().joined(separator: ",") + "]"
            }
            lines.append(
                "tl-meas m\(measure.measureIndex) startTick=\(measure.startTick) "
                + "durationTicks=\(measure.durationTicks) sig=\(measure.timeSignature.rawValue) "
                + "groups=[\(groups)] engraving=\(engraving)"
            )
        }
        return lines
    }

    private static func layoutSection(_ result: FixtureRenderResult) -> [String] {
        let layout = result.layout
        let grid = layout.tabGrid
        let style = result.style
        var lines: [String] = []

        lines.append(
            "grid  ticksPerWholeNote=\(grid.ticksPerWholeNote) "
            + "tickWidth=\(f(grid.tickWidth)) leftPadding=\(f(grid.leftPadding))"
        )
        lines.append(
            "style rowWidth=\(f(style.rowWidth)) overrides=default "
            + "minNoteColumnGap=\(f(style.minimumNoteColumnGap)) "
            + "minQuarterBeatGap=\(f(style.minimumQuarterBeatGap)) "
            + "staffLineSpacing=\(f(style.staffLineSpacing)) "
            + "noteHeadWidth=\(f(style.noteHeadWidth)) "
            + "noteHeadHeight=\(f(style.noteHeadHeight)) "
            + "stemLength=\(f(style.stemLength))"
        )
        lines.append(
            "dims  noteHeadSize=\(f(layout.noteHeadSize.width))x\(f(layout.noteHeadSize.height)) "
            + "totalHeight=\(f(layout.totalHeight)) "
            + "paintedBounds=\(rect(layout.paintedBounds))"
        )

        for row in Set(layout.measures.map(\.row)).sorted() {
            let measures = layout.measures
                .filter { $0.row == row }
                .sorted { $0.measureIndex < $1.measureIndex }
                .map { "m\($0.measureIndex)" }
                .joined(separator: ",")
            lines.append("row   \(row) measures=[\(measures)] contentWidth=\(f(layout.contentWidth))")
        }

        for measure in layout.measures.sorted(by: measureOrder) {
            lines.append(
                "meas  m\(measure.measureIndex) row=\(measure.row) "
                + "xOffset=\(f(measure.xOffset)) width=\(f(measure.width)) "
                + "startTick=\(measure.startTick) durationTicks=\(measure.durationTicks) "
                + "contentStartX=\(f(measure.contentStartX))"
            )
        }

        lines.append(contentsOf: primitiveLines(layout))
        return lines
    }

    private static func rect(_ rect: CGRect) -> String {
        rect.isNull
            ? "null"
            : "(\(f(rect.minX)),\(f(rect.minY)),\(f(rect.width)),\(f(rect.height)))"
    }

    private static func measureOrder(_ lhs: RenderedMeasure, _ rhs: RenderedMeasure) -> Bool {
        if lhs.row != rhs.row { return lhs.row < rhs.row }
        return lhs.measureIndex < rhs.measureIndex
    }
}
```

- [ ] **Step 2: Add the primitive lines**

Append to `NotationLayoutDigest` (same file; split into a second `extension` if the type body nears 300 lines). Tick-bearing primitives sort by `(measureIndex, tickWithinMeasure, y, id)`; tickless ones by `(x, y, discriminator, id)`.

```swift
@MainActor
extension NotationLayoutDigest {
    // swiftlint:disable:next function_body_length
    fileprivate static func primitiveLines(_ layout: NotationLayout) -> [String] {
        var lines: [String] = []

        let heads = layout.noteHeads.sorted {
            ($0.timeColumn.measureIndex, $0.timeColumn.tickWithinMeasure, Double($0.position.y), $0.id)
                < ($1.timeColumn.measureIndex, $1.timeColumn.tickWithinMeasure, Double($1.position.y), $1.id)
        }
        for head in heads {
            lines.append(
                "head  m\(head.timeColumn.measureIndex) "
                + "t\(String(format: "%04d", head.timeColumn.tickWithinMeasure)) "
                + "abs\(String(format: "%04d", head.timeColumn.absoluteLayoutTick)) "
                + "pos=\(pt(head.position)) \(head.drumType.description) "
                + "glyph=\(head.glyph) variant=\(head.variant) voice=\(head.voice.rawValue) "
                + "stem=\(head.stemDirection.rawValue) row=\(head.row) "
                + "lane=\(head.sourceLaneID ?? "-")"
            )
        }

        for stem in layout.stems.sorted(by: byStart(\.start, \.id)) {
            lines.append(
                "stem  ids=\(stem.noteHeadIDs.sorted()) dir=\(stem.direction.rawValue) "
                + "start=\(pt(stem.start)) end=\(pt(stem.end))"
            )
        }

        for beam in layout.beams.sorted(by: byStart(\.start, \.id)) {
            lines.append(
                "beam  ids=\(beam.noteHeadIDs.sorted()) dir=\(beam.direction.rawValue) "
                + "level=\(beam.level) kind=\(beam.kind.rawValue) "
                + "start=\(pt(beam.start)) end=\(pt(beam.end)) thickness=\(f(beam.thickness))"
            )
        }

        for flag in layout.flags.sorted(by: byStart(\.origin, \.id)) {
            lines.append(
                "flag  head=\(flag.noteHeadID) dir=\(flag.stemDirection.rawValue) "
                + "index=\(flag.flagIndex) origin=\(pt(flag.origin))"
            )
        }

        let rests = layout.rests.sorted {
            ($0.measureIndex, $0.timeColumn.tickWithinMeasure, Double($0.position.y), $0.id)
                < ($1.measureIndex, $1.timeColumn.tickWithinMeasure, Double($1.position.y), $1.id)
        }
        for rest in rests {
            lines.append(
                "rest  m\(rest.measureIndex) "
                + "t\(String(format: "%04d", rest.timeColumn.tickWithinMeasure)) "
                + "voice=\(rest.voice.rawValue) dur=\(rest.duration) ticks=\(rest.durationTicks) "
                + "vis=\(rest.visibility) pos=\(pt(rest.position)) "
                + "tuplet=\(rest.tupletID.map { "\($0)" } ?? "-")"
            )
        }

        let stops = layout.stopNotes.sorted {
            ($0.timeColumn.measureIndex, $0.timeColumn.tickWithinMeasure, $0.id)
                < ($1.timeColumn.measureIndex, $1.timeColumn.tickWithinMeasure, $1.id)
        }
        for stop in stops {
            lines.append(
                "stop  m\(stop.timeColumn.measureIndex) "
                + "t\(String(format: "%04d", stop.timeColumn.tickWithinMeasure)) "
                + "kind=\(stop.kind.rawValue) target=\(stop.targetLaneID) "
                + "pos=\(pt(stop.position)) lane=\(stop.sourceLaneID ?? "-")"
            )
        }

        for artic in layout.articulations.sorted(by: byStart(\.position, \.id)) {
            lines.append(
                "artic kind=\(artic.kind) head=\(artic.sourceNoteHeadID) "
                + "row=\(artic.row) pos=\(pt(artic.position))"
            )
        }

        for dot in layout.rhythmDots.sorted(by: byStart(\.position, \.id)) {
            lines.append("dot   source=\(dot.source) pos=\(pt(dot.position)) row=\(dot.rowIndex)")
        }

        for tuplet in layout.tuplets.sorted(by: { "\($0.id)" < "\($1.id)" }) {
            let bracket = tuplet.bracketPoints.map(pt).joined(separator: " ")
            lines.append(
                "tuplet id=\(tuplet.id) voice=\(tuplet.voice.rawValue) ratio=\(tuplet.ratio) "
                + "members=\(tuplet.memberEventIDs.map(\.rawValue).sorted()) "
                + "bracketVisible=\(tuplet.isBracketVisible) label=\(pt(tuplet.labelPosition)) "
                + "row=\(tuplet.rowIndex) bracket=[\(bracket)]"
            )
        }

        for ledger in layout.ledgerLines.sorted(by: byStart(\.start, \.id)) {
            lines.append("ledger row=\(ledger.row) start=\(pt(ledger.start)) end=\(pt(ledger.end))")
        }

        for bar in layout.measureBars.sorted(by: { ($0.row, Double($0.x), $0.id) < ($1.row, Double($1.x), $1.id) }) {
            lines.append("bar   row=\(bar.row) x=\(f(bar.x)) isFinal=\(bar.isFinal)")
        }

        for mark in layout.feelMarks.sorted(by: byStart(\.position, \.id)) {
            lines.append("feel  \(mark.feel) pos=\(pt(mark.position)) row=\(mark.rowIndex)")
        }

        for warning in layout.rhythmWarnings.sorted(by: byStart(\.position, \.id)) {
            let codes = warning.codes.map(\.rawValue).sorted().joined(separator: ",")
            lines.append(
                "warn  scope=\(warning.scope) codes=[\(codes)] "
                + "row=\(warning.rowIndex.map(String.init) ?? "-") "
                + "measure=\(warning.displayMeasureNumber.map(String.init) ?? "-")"
            )
        }

        return lines
    }

    /// Total order for primitives that carry a point but no time column.
    private static func byStart<T, ID: Comparable>(
        _ point: KeyPath<T, CGPoint>,
        _ id: KeyPath<T, ID>
    ) -> (T, T) -> Bool {
        { lhs, rhs in
            let left = lhs[keyPath: point], right = rhs[keyPath: point]
            if left.x != right.x { return left.x < right.x }
            if left.y != right.y { return left.y < right.y }
            return lhs[keyPath: id] < rhs[keyPath: id]
        }
    }
}
```

- [ ] **Step 3: Create the golden-file helper**

`VirgoTests/GoldenFile.swift`. Regeneration writes the file **and still fails**, so CI can never self-approve.

```swift
import Foundation
import Testing

/// Loads, compares, and optionally regenerates golden digest files.
enum GoldenFile {
    /// Goldens live next to the test sources, located relative to this file so
    /// no Xcode resource bundling is needed.
    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Goldens", isDirectory: true)
    }

    static func url(for fixture: String) -> URL {
        directory.appendingPathComponent("\(fixture).txt")
    }

    static var isUpdating: Bool {
        ProcessInfo.processInfo.environment["VIRGO_UPDATE_GOLDENS"] == "1"
    }

    static func assertMatches(
        _ actual: String,
        fixture: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let target = url(for: fixture)

        if isUpdating {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try actual.write(to: target, atomically: true, encoding: .utf8)
            Issue.record(
                """
                Golden rewritten (VIRGO_UPDATE_GOLDENS=1): \(target.path)
                Review the diff with `git diff` before committing. This test \
                fails by design so a regeneration run can never be mistaken \
                for a passing run.
                """,
                sourceLocation: sourceLocation
            )
            return
        }

        guard FileManager.default.fileExists(atPath: target.path) else {
            Issue.record(
                """
                Missing golden for "\(fixture)" at \(target.path).
                Create it by running this suite with VIRGO_UPDATE_GOLDENS=1.
                """,
                sourceLocation: sourceLocation
            )
            return
        }

        let expected = try String(contentsOf: target, encoding: .utf8)
        guard actual != expected else { return }
        Issue.record(
            Comment(rawValue: report(actual: actual, expected: expected, fixture: fixture, path: target.path)),
            sourceLocation: sourceLocation
        )
    }

    /// Reports differing-line count, first/last divergence, and a capped
    /// unified-style diff. A boolean mismatch on a several-hundred-line string
    /// is undiagnosable, and these digests are long by design.
    private static func report(
        actual: String,
        expected: String,
        fixture: String,
        path: String
    ) -> String {
        let actualLines = actual.components(separatedBy: "\n")
        let expectedLines = expected.components(separatedBy: "\n")
        let maxCount = max(actualLines.count, expectedLines.count)

        var differing: [Int] = []
        for index in 0..<maxCount
        where actualLines[safeIndex: index] != expectedLines[safeIndex: index] {
            differing.append(index)
        }

        var out = ["Golden mismatch for \"\(fixture)\" (\(path))"]
        if actualLines.count != expectedLines.count {
            out.append(
                "Line count differs: expected \(expectedLines.count), actual \(actualLines.count) "
                + "(a missing line and a moved line are different bugs)"
            )
        }
        out.append(
            "\(differing.count) differing line(s); first at \(differing.first.map { $0 + 1 } ?? 0), "
            + "last at \(differing.last.map { $0 + 1 } ?? 0)"
        )

        let cap = 40
        var emitted = 0
        for index in differing {
            if emitted >= cap {
                out.append("… and \(differing.count - cap) more differing line(s)")
                break
            }
            for context in max(0, index - 2)..<index
            where expectedLines[safeIndex: context] != nil {
                out.append("  \(context + 1)   \(expectedLines[safeIndex: context] ?? "")")
            }
            out.append("  \(index + 1) - \(expectedLines[safeIndex: index] ?? "<absent>")")
            out.append("  \(index + 1) + \(actualLines[safeIndex: index] ?? "<absent>")")
            emitted += 1
        }
        out.append("Regenerate with VIRGO_UPDATE_GOLDENS=1, then inspect `git diff`.")
        return out.joined(separator: "\n")
    }
}

private extension Array where Element == String {
    subscript(safeIndex index: Int) -> String? {
        indices.contains(index) ? self[index] : nil
    }
}
```

- [ ] **Step 4: Write the golden test for fixture 1**

`VirgoTests/DrumTabGoldenTests.swift`:

```swift
import Testing
import Foundation
@testable import Virgo

@Suite("Drum tab golden digests", .serialized)
@MainActor
struct DrumTabGoldenTests {
    @Test("same-time-trio matches its golden digest")
    func sameTimeTrio() throws {
        let result = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.sameTimeTrio)
        #expect(result.layout.noteHeads.count == 6)
        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: DrumTabFixtureCatalog.sameTimeTrio.name
        )
    }
}
```

- [ ] **Step 5: Generate the first golden and inspect it**

```bash
VIRGO_UPDATE_GOLDENS=1 xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/DrumTabGoldenTests -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected: FAILS with "Golden rewritten" — by design. Then read the file:

```bash
cat VirgoTests/Goldens/same-time-trio.txt
```

**Verify by eye before committing.** All six heads must show the same `pos=` x within each `t` column, and every head x must equal `contentStartX + tickWithinMeasure * tickWidth`. If the two beats do not share x per column, that is a real HPA-141 regression — stop and report it rather than committing the golden.

- [ ] **Step 6: Confirm the golden now passes without the flag**

Same command as Step 5, without `VIRGO_UPDATE_GOLDENS=1`. Expected: PASS.

- [ ] **Step 7: Confirm determinism across runs**

Run Step 6 twice more. Expected: PASS both times. A failure here means an unsorted collection leaked into the digest — fix the sort, do not re-record the golden.

- [ ] **Step 8: Lint and commit**

```bash
swiftlint lint --quiet
git add VirgoTests/NotationLayoutDigest.swift VirgoTests/GoldenFile.swift \
        VirgoTests/DrumTabGoldenTests.swift VirgoTests/Goldens/same-time-trio.txt
git commit -m "test: layout digest and golden-file machinery

Digest covers every NotationLayout primitive collection plus grid, style
and dimensions, with explicit total orders so SwiftData relationship
order cannot perturb output. Regeneration writes the file and still
fails, so CI cannot self-approve a regression."
```

---

### Task 4: Beaming and flag fixtures (2, 3, 11)

These three carry the HPA-142 coverage: beat-scoped beams, partial beams/hooks, and flags.

**Files:**
- Modify: `VirgoTests/Fixtures/DrumTabFixtureCatalog.swift`
- Modify: `VirgoTests/DrumTabGoldenTests.swift`
- Create: `VirgoTests/Goldens/sixteenth-run-4-4.txt`, `mixed-eighth-sixteenth.txt`, `isolated-flagged-notes.txt`

**Interfaces:**
- Consumes: `DrumTabFixture.line`, `DrumTabFixtureCatalog.chart`, `DrumTabFixtureHarness.render`, `GoldenFile.assertMatches`, `NotationLayoutDigest.make`.
- Produces: `DrumTabFixtureCatalog.sixteenthRun`, `.mixedEighthSixteenth`, `.isolatedFlaggedNotes`.

- [ ] **Step 1: Add the three fixtures**

Append inside `enum DrumTabFixtureCatalog`:

```swift
    /// Fixture 2: a full 4/4 sixteenth run on closed hi-hat.
    /// Must beam as four beat-scoped groups, not one full-measure beam.
    static let sixteenthRun = DrumTabFixture(
        name: "sixteenth-run-4-4",
        dtx: chart([
            DrumTabFixture.line(measure: 1, lane: "11", at: Array(0..<16), total: 16)
        ])
    )

    /// Fixture 3: each beat is an eighth plus two sixteenths (positions 0, 2, 3
    /// of the beat), forcing a primary beam plus a partial secondary beam/hook.
    static let mixedEighthSixteenth = DrumTabFixture(
        name: "mixed-eighth-sixteenth",
        dtx: chart([
            DrumTabFixture.line(
                measure: 1,
                lane: "11",
                at: (0..<4).flatMap { beat in [0, 2, 3].map { beat * 4 + $0 } },
                total: 16
            )
        ])
    )

    /// Fixture 11: one lone sixteenth and one lone eighth, each the only
    /// beamable note in its beat group, so each must render a flag rather than
    /// a zero-length beam. Added because fixtures 1–10 could all be satisfied
    /// by a renderer emitting zero flags: fixture 1 is quarters, fixture 2's
    /// sixteenths are fully beamed, fixture 3 beams within the beat.
    ///
    /// Measure 1: notes at 3, 4, 8, 12 — position 3 is alone in beat 1 and one
    /// sixteenth from the next note, so it is a lone flagged sixteenth.
    /// Measure 2: notes at 0, 4, 10, 12 — position 10 is alone in beat 3 and
    /// one eighth from the next note, so it is a lone flagged eighth.
    static let isolatedFlaggedNotes = DrumTabFixture(
        name: "isolated-flagged-notes",
        dtx: chart([
            DrumTabFixture.line(measure: 1, lane: "11", at: [3, 4, 8, 12], total: 16),
            DrumTabFixture.line(measure: 2, lane: "11", at: [0, 4, 10, 12], total: 16)
        ]),
        minimumMeasureCount: 2
    )
```

- [ ] **Step 2: Add the three golden tests with their gates**

Append inside `struct DrumTabGoldenTests`:

```swift
    @Test("sixteenth run beams per beat group, not per measure")
    func sixteenthRun() throws {
        let fixture = DrumTabFixtureCatalog.sixteenthRun
        let result = try DrumTabFixtureHarness.render(fixture)

        #expect(result.layout.noteHeads.count == 16)
        #expect(result.layout.measures.count == 1)
        // Four beat groups, so at least four distinct primary beam runs.
        let primaryBeamRuns = Set(
            result.layout.beams.filter { $0.level == 1 }.map { $0.noteHeadIDs.sorted() }
        )
        #expect(primaryBeamRuns.count >= 4)

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("mixed eighth/sixteenth beat renders a partial secondary beam or hook")
    func mixedEighthSixteenth() throws {
        let fixture = DrumTabFixtureCatalog.mixedEighthSixteenth
        let result = try DrumTabFixtureHarness.render(fixture)

        #expect(result.layout.noteHeads.count == 12)
        let hooks = result.layout.beams.filter {
            $0.kind == .forwardHook || $0.kind == .backwardHook
        }
        #expect(!hooks.isEmpty, "mixed beat must produce a hook or partial secondary beam")

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("isolated beamable notes render flags and no beams")
    func isolatedFlaggedNotes() throws {
        let fixture = DrumTabFixtureCatalog.isolatedFlaggedNotes
        let result = try DrumTabFixtureHarness.render(fixture)

        // The gate that matters: flags must actually exist, or the digest's
        // flag line kind is dead weight and HPA-144's flags/tails requirement
        // is unmet.
        #expect(result.layout.flags.count == 2)
        #expect(result.layout.beams.isEmpty, "a lone beamable note must flag, not beam")

        // One flag per lone note, on distinct heads.
        #expect(Set(result.layout.flags.map(\.noteHeadID)).count == 2)

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: fixture.name
        )
    }
```

- [ ] **Step 3: Run the gates before recording any golden**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -configuration Debug -only-testing:VirgoTests/DrumTabGoldenTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected: the three new tests fail on the **missing golden** message, having already passed their gates.

**If `isolatedFlaggedNotes` fails its gate rather than the golden check**, the analyzer inferred different durations than the position arithmetic above predicts. The contract is the gate (exactly 2 flags, no beams), not the specific positions. Adjust the note positions so each flagged note is the only beamable note in its beat group — print `result.layout.noteHeads.map { ($0.timeColumn.tickWithinMeasure, $0.rhythm) }` to see what the analyzer produced — then re-run. Do not weaken the gate to match the output.

- [ ] **Step 4: Record the three goldens**

```bash
VIRGO_UPDATE_GOLDENS=1 xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/DrumTabGoldenTests -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Then inspect. In `sixteenth-run-4-4.txt`, confirm no single `beam` line spans the whole measure — each `level=1` beam's `start`/`end` x must stay within one quarter of the measure's tick span. If one beam spans the measure, that is the HPA-97 "overlong connection bar" bug: stop and report it.

- [ ] **Step 5: Confirm all four goldens pass**

Same command without the env var, run twice. Expected: PASS both times.

- [ ] **Step 6: Lint and commit**

```bash
swiftlint lint --quiet
git add VirgoTests/Fixtures/DrumTabFixtureCatalog.swift \
        VirgoTests/DrumTabGoldenTests.swift VirgoTests/Goldens
git commit -m "test: beaming and flag fixtures (sixteenth run, mixed beat, isolated flags)

isolated-flagged-notes exists because no other fixture forces a
RenderedFlag — fixture 1 is quarters, the sixteenth run is fully beamed,
and the mixed beat beams within the beat group, so a renderer emitting
zero flags could have established every other golden."
```

---

### Task 5: Drum mapping fixtures (6, 7)

**Files:**
- Modify: `VirgoTests/Fixtures/DrumTabFixtureCatalog.swift`
- Modify: `VirgoTests/DrumTabGoldenTests.swift`
- Create: `VirgoTests/Goldens/hihat-open-closed-pedal.txt`, `left-bass-1c.txt`

**Interfaces:**
- Produces: `DrumTabFixtureCatalog.hiHatOpenClosedPedal`, `.leftBass1C`.

- [ ] **Step 1: Add the fixtures**

```swift
    /// Fixture 6: open (18), closed (11), and pedal (1B) hi-hat must stay three
    /// distinct mappings rather than collapsing to one glyph.
    static let hiHatOpenClosedPedal = DrumTabFixture(
        name: "hihat-open-closed-pedal",
        dtx: chart([
            DrumTabFixture.line(measure: 1, lane: "18", at: [0], total: 4),
            DrumTabFixture.line(measure: 1, lane: "11", at: [1], total: 4),
            DrumTabFixture.line(measure: 1, lane: "1B", at: [2], total: 4)
        ])
    )

    /// Fixture 7: lane 1C (left bass) must import as a playable kick rather
    /// than being dropped by compactMap, alongside a normal 13 kick.
    static let leftBass1C = DrumTabFixture(
        name: "left-bass-1c",
        dtx: chart([
            DrumTabFixture.line(measure: 1, lane: "13", at: [0], total: 4),
            DrumTabFixture.line(measure: 1, lane: "1C", at: [2], total: 4)
        ])
    )
```

- [ ] **Step 2: Add the golden tests**

```swift
    @Test("open, closed, and pedal hi-hat stay three distinct mappings")
    func hiHatOpenClosedPedal() throws {
        let fixture = DrumTabFixtureCatalog.hiHatOpenClosedPedal
        let result = try DrumTabFixtureHarness.render(fixture)

        #expect(result.layout.noteHeads.count == 3)
        let pairs = Set(result.layout.noteHeads.map { "\($0.drumType.description)|\($0.glyph)" })
        #expect(pairs.count == 3, "expected three distinct (drumType, glyph) pairs, got \(pairs)")

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("lane 1C imports as a playable kick instead of being dropped")
    func leftBass1C() throws {
        let fixture = DrumTabFixtureCatalog.leftBass1C
        let result = try DrumTabFixtureHarness.render(fixture)

        #expect(result.layout.noteHeads.count == 2)
        // Count alone is not enough: another lane surviving would satisfy it
        // while 1C was silently dropped.
        let leftBass = result.layout.noteHeads.filter {
            $0.sourceLaneID == "1C" && $0.drumType == .kick
        }
        #expect(leftBass.count == 1, "lane 1C must map to a kick head")

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: fixture.name
        )
    }
```

- [ ] **Step 3: Run gates, then record, then verify**

Run the suite (gates fail on missing goldens), then record with `VIRGO_UPDATE_GOLDENS=1`, then run twice clean. Commands as in Task 4 Steps 3–5.

If `leftBass1C` finds zero `1C` heads, lane `1C` is being dropped — that is the HPA-139 regression. Report it rather than adjusting the assertion.

- [ ] **Step 4: Lint and commit**

```bash
swiftlint lint --quiet
git add VirgoTests/Fixtures/DrumTabFixtureCatalog.swift \
        VirgoTests/DrumTabGoldenTests.swift VirgoTests/Goldens
git commit -m "test: hi-hat variant and lane 1C mapping fixtures

left-bass-1c asserts a head with both sourceLaneID 1C and drumType kick,
not just a surviving note count — a dropped 1C with another lane intact
would pass a count check."
```

---

### Task 6: Stop/choke/damp fixture with differential rest separation

**Files:**
- Modify: `VirgoTests/Fixtures/DrumTabFixtureCatalog.swift`
- Modify: `VirgoTests/DrumTabGoldenTests.swift`
- Create: `VirgoTests/Goldens/stop-choke-damp.txt`

**Interfaces:**
- Consumes: `DrumTabFixtureHarness.render(_:includeControls:)`, `DrumTabFixture.controlBlock`.
- Produces: `DrumTabFixtureCatalog.stopChokeDamp`.

- [ ] **Step 1: Add the fixture with a separable control block**

The `#VIRGO_CONTROL: 1` directive stays in the base chart so the "without controls" render differs *only* by the chip lines. A control chip's note ID is its target lane.

```swift
    /// Fixture 8: stop (21), choke (22), and damp (23) control chips over a
    /// crash/hi-hat pattern. `controlBlock` is separable so the harness can
    /// render with and without it — proving control events do not feed rest
    /// inference (HPA-143), which a single render cannot demonstrate.
    static let stopChokeDamp = DrumTabFixture(
        name: "stop-choke-damp",
        dtx: chart([
            "#VIRGO_CONTROL: 1",
            DrumTabFixture.line(measure: 1, lane: "16", at: [0, 2], total: 4),
            DrumTabFixture.line(measure: 1, lane: "11", at: [1, 3], total: 4)
        ]),
        controlBlock: [
            DrumTabFixture.line(measure: 1, lane: "21", positions: [0: "16"], total: 4),
            DrumTabFixture.line(measure: 1, lane: "22", positions: [2: "16"], total: 4),
            DrumTabFixture.line(measure: 1, lane: "23", positions: [3: "11"], total: 4)
        ].joined(separator: "\n")
    )
```

- [ ] **Step 2: Add the golden test with the differential gate**

```swift
    @Test("stop, choke, and damp render as stop marks without disturbing rests")
    func stopChokeDamp() throws {
        let fixture = DrumTabFixtureCatalog.stopChokeDamp
        let withControls = try DrumTabFixtureHarness.render(fixture, includeControls: true)
        let withoutControls = try DrumTabFixtureHarness.render(fixture, includeControls: false)

        #expect(withControls.layout.stopNotes.count == 3)
        #expect(withoutControls.layout.stopNotes.isEmpty)
        #expect(
            Set(withControls.layout.stopNotes.map(\.kind)) == [.stop, .choke, .damp]
        )

        // Differential proof of separation: identical playable lanes must yield
        // identical rests whether or not control chips are present. "rests
        // unaffected" is only checkable against a baseline.
        #expect(restLines(withControls) == restLines(withoutControls))

        // Playable content must also be untouched by the control chips.
        #expect(
            withControls.layout.noteHeads.count == withoutControls.layout.noteHeads.count
        )

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(withControls),
            fixture: fixture.name
        )
    }

    /// The `rest` subsection of a digest, for differential comparison.
    private func restLines(_ result: FixtureRenderResult) -> [String] {
        NotationLayoutDigest.make(result)
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("rest ") }
    }
```

- [ ] **Step 3: Run the gate, record the golden, verify**

Run the suite. Expected: the gate passes and only the missing-golden check fails. Then record with `VIRGO_UPDATE_GOLDENS=1` (run 1, with controls, is what gets committed — run 2 is computed in-test and never stored), then run twice clean.

If `restLines` differ between the two renders, control chips are feeding rest inference — an HPA-143 regression. Report it.

- [ ] **Step 4: Lint and commit**

```bash
swiftlint lint --quiet
git add VirgoTests/Fixtures/DrumTabFixtureCatalog.swift \
        VirgoTests/DrumTabGoldenTests.swift VirgoTests/Goldens
git commit -m "test: stop/choke/damp fixture with differential rest separation

Renders the fixture twice, with and without its control chips, and
requires identical rest lines while stop marks go 3 -> 0. 'Rests
unaffected' is not checkable without a baseline."
```

---

### Task 7: Grid-resolution, rest, and wrapping fixtures (4, 9, 10)

Fixture 5 is deliberately excluded — its gate is conditional and gets its own task.

**Files:**
- Create: `VirgoTests/Fixtures/DrumTabFixtureCatalog+Rhythm.swift`
- Modify: `VirgoTests/DrumTabGoldenTests.swift`
- Create: `VirgoTests/Goldens/sparse-hi-res-lane.txt`, `voice-rests.txt`, `multi-row-stable-widths.txt`

**Interfaces:**
- Produces: `DrumTabFixtureCatalog.sparseHiResLane`, `.voiceRests`, `.multiRowStableWidths`.

- [ ] **Step 1: Create the rhythm catalog file**

```swift
import Foundation
@testable import Virgo

/// Grid-resolution, rest, and row-wrapping fixtures. Split from
/// `DrumTabFixtureCatalog.swift` to stay under SwiftLint's 600-line file limit.
extension DrumTabFixtureCatalog {
    /// Fixture 4: a 64-position grid carrying only two chips. Grid resolution is
    /// timing data, not note duration — these must not become 64th notes.
    static let sparseHiResLane = DrumTabFixture(
        name: "sparse-hi-res-lane",
        dtx: chart([
            DrumTabFixture.line(measure: 1, lane: "11", at: [0, 33], total: 64)
        ])
    )

    /// Fixture 9: hi-hat (upper voice) sounds on beats 1–2 while kick (lower
    /// voice) sounds on beats 3–4, so each voice needs its own rests.
    static let voiceRests = DrumTabFixture(
        name: "voice-rests",
        dtx: chart([
            DrumTabFixture.line(measure: 1, lane: "11", at: [0, 1], total: 4),
            DrumTabFixture.line(measure: 1, lane: "13", at: [2, 3], total: 4)
        ])
    )

    /// Fixture 10: eight measures alternating dense (sixteenths) and sparse
    /// (one chip), which wraps to at least two rows at the locked 900pt row
    /// width. Serves as the subject of the spacing invariants: the same tick
    /// delta must produce the same x delta in a sparse and a dense measure.
    static let multiRowStableWidths = DrumTabFixture(
        name: "multi-row-stable-widths",
        dtx: chart((1...8).map { measure in
            measure.isMultiple(of: 2)
                ? DrumTabFixture.line(measure: measure, lane: "11", at: [0], total: 16)
                : DrumTabFixture.line(measure: measure, lane: "11", at: Array(0..<16), total: 16)
        }),
        minimumMeasureCount: 8
    )
}
```

- [ ] **Step 2: Add the golden tests**

```swift
    @Test("sparse high-resolution grid preserves timing without 64th notes")
    func sparseHiResLane() throws {
        let fixture = DrumTabFixtureCatalog.sparseHiResLane
        let result = try DrumTabFixtureHarness.render(fixture)

        #expect(result.layout.noteHeads.count == 2)
        // Grid resolution must not become visual duration.
        #expect(result.layout.noteHeads.allSatisfy { $0.interval != .sixtyfourth })
        // Timing must survive: the second chip sits at 33/64 of the measure.
        let measure = try #require(result.layout.measures.first)
        let ticks = result.layout.noteHeads
            .map(\.timeColumn.tickWithinMeasure)
            .sorted()
        #expect(ticks.first == 0)
        #expect(ticks.last == measure.durationTicks * 33 / 64)

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("upper and lower voices get independent rests")
    func voiceRests() throws {
        let fixture = DrumTabFixtureCatalog.voiceRests
        let result = try DrumTabFixtureHarness.render(fixture)

        let printed = result.layout.rests.filter(\.isPrinted)
        #expect(printed.contains { $0.voice == .upper })
        #expect(printed.contains { $0.voice == .lower })

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("multi-row chart keeps one tick scale across sparse and dense measures")
    func multiRowStableWidths() throws {
        let fixture = DrumTabFixtureCatalog.multiRowStableWidths
        let result = try DrumTabFixtureHarness.render(fixture)

        #expect(result.layout.measures.count == 8)
        #expect(Set(result.layout.measures.map(\.row)).count >= 2, "fixture must wrap rows")

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: fixture.name
        )
    }
```

- [ ] **Step 3: Run gates, record, verify twice**

Commands as in Task 4 Steps 3–5.

If `multiRowStableWidths` does not wrap to two rows, the eight measures fit in 900pt. Increase the measure count until `Set(measures.map(\.row)).count >= 2`, keeping the dense/sparse alternation. If `sparseHiResLane`'s last tick is not `durationTicks * 33 / 64`, the 64-grid did not project exactly — report it as an HPA-139/145 issue.

- [ ] **Step 4: Lint and commit**

```bash
swiftlint lint --quiet
git add VirgoTests/Fixtures/DrumTabFixtureCatalog+Rhythm.swift \
        VirgoTests/DrumTabGoldenTests.swift VirgoTests/Goldens
git commit -m "test: sparse high-res, voice-rest, and multi-row fixtures

multi-row-stable-widths alternates dense and sparse measures so it can
serve as the spacing-invariant subject without a further fixture."
```

---

### Task 8: Triplet fixture with a conditional engraving gate

Fixture 5's gate is conditional on engraving support so a regression cannot degrade real tuplets into the documented fallback and still pass.

**Files:**
- Modify: `VirgoTests/Fixtures/DrumTabFixtureCatalog+Rhythm.swift`
- Modify: `VirgoTests/DrumTabGoldenTests.swift`
- Create: `VirgoTests/Goldens/triplet-grid.txt`

**Interfaces:**
- Produces: `DrumTabFixtureCatalog.tripletGrid`.

- [ ] **Step 1: Add the fixture**

```swift
    /// Fixture 5: a 12-position (non-power-of-two) grid — four groups of
    /// eighth-note triplets. Must not silently degrade to quarter notes.
    static let tripletGrid = DrumTabFixture(
        name: "triplet-grid",
        dtx: chart([
            DrumTabFixture.line(measure: 1, lane: "11", at: Array(0..<12), total: 12)
        ])
    )
```

- [ ] **Step 2: Add the conditional gate**

```swift
    @Test("triplet grid engraves tuplets, or falls back with a specific diagnostic")
    func tripletGrid() throws {
        let fixture = DrumTabFixtureCatalog.tripletGrid
        let result = try DrumTabFixtureHarness.render(fixture)

        #expect(result.layout.noteHeads.count == 12)

        let measure = try #require(
            result.snapshot.measures.first { $0.measureIndex == 0 }
        )

        // Conditional, not a free choice: if the engine can engrave this
        // measure, the tuplet form is required. Accepting either branch would
        // let a regression that degrades real triplets into the fallback pass.
        switch measure.engravingSupport {
        case .supported:
            #expect(
                !result.layout.tuplets.isEmpty,
                "engraving is supported, so the triplet must render as a tuplet"
            )
        case let .unsupported(codes):
            #expect(
                !codes.isEmpty,
                "an unsupported measure must name the diagnostic codes that made it unsupported"
            )
            // Record which codes are live so the golden's SUSPECT trailer is accurate.
            Comment(rawValue: "triplet-grid falls back with codes: \(codes.map(\.rawValue).sorted())")
        }

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: fixture.name
        )
    }
```

- [ ] **Step 3: Run the gate and record which branch is live**

Run the suite. Read the `tl-meas m0 … engraving=` field in the recorded golden.

- If `engraving=supported`, the golden must contain at least one `tuplet` line. Confirm it does.
- If `engraving=unsupported[...]`, append a trailer to `VirgoTests/Goldens/triplet-grid.txt`:
  ```
  # SUSPECT: HPA-145 12-grid measure falls back to unsupported engraving; this golden pins the fallback, not engraved triplets.
  ```
  and re-record so the trailer is inside the compared text (the digest ends with a newline, so append the trailer as the final line and regenerate once more — or simpler, keep the trailer and record the golden first, then add the trailer and re-run to confirm the comparison still passes with the trailer present).

  **Note:** because the trailer becomes part of the compared string, add it by editing the golden after recording, then run the suite once to confirm it now fails, then update `GoldenFile` usage for this one fixture to strip lines beginning with `#` before comparing. Implement the strip in `GoldenFile.assertMatches` for all fixtures — it costs one line and makes trailers usable everywhere:

  ```swift
  private static func stripComments(_ text: String) -> String {
      text.components(separatedBy: "\n")
          .filter { !$0.hasPrefix("#") }
          .joined(separator: "\n")
  }
  ```

  Apply it to both `actual` and `expected` before the equality check, and to the lines used in `report(...)`.

- [ ] **Step 4: Verify twice, lint, commit**

```bash
swiftlint lint --quiet
git add VirgoTests/Fixtures/DrumTabFixtureCatalog+Rhythm.swift \
        VirgoTests/GoldenFile.swift VirgoTests/DrumTabGoldenTests.swift \
        VirgoTests/Goldens
git commit -m "test: triplet grid fixture with engraving-conditional gate

The gate branches on measure.engravingSupport rather than accepting
either a tuplet or a diagnostic, so a regression degrading real triplets
into the documented fallback cannot pass. Golden comments (# ...) are
stripped before comparison so a SUSPECT trailer can mark a pinned
fallback."
```

---

### Task 9: Regression invariant tests

The two HPA-97 screenshot failure modes, plus cross-cutting invariants over all eleven fixtures.

**Files:**
- Create: `VirgoTests/DrumTabRegressionInvariantTests.swift`
- Modify: `VirgoTests/Fixtures/DrumTabFixtureCatalog.swift` (add an `all` list)

**Interfaces:**
- Consumes: every fixture, `FixtureRenderResult`, `TabGrid.xPosition(in:localTick:)`.
- Produces: `DrumTabFixtureCatalog.all: [DrumTabFixture]`.

- [ ] **Step 1: Add the fixture list**

Append inside `enum DrumTabFixtureCatalog`:

```swift
    /// Every fixture, for parameterized invariant tests.
    static let all: [DrumTabFixture] = [
        sameTimeTrio, sixteenthRun, mixedEighthSixteenth, sparseHiResLane,
        tripletGrid, hiHatOpenClosedPedal, leftBass1C, stopChokeDamp,
        voiceRests, multiRowStableWidths, isolatedFlaggedNotes
    ]
```

- [ ] **Step 2: Write the invariant tests**

```swift
import Testing
import Foundation
import CoreGraphics
@testable import Virgo

@Suite("Drum tab regression invariants", .serialized)
@MainActor
struct DrumTabRegressionInvariantTests {
    private let tolerance: CGFloat = 0.01

    // MARK: - Screenshot failure mode 1: inconsistent spacing

    @Test("one tick scale spans every measure and row")
    func singleTickScaleChartWide() throws {
        let result = try DrumTabFixtureHarness.render(
            DrumTabFixtureCatalog.multiRowStableWidths
        )
        // TabGrid is one value for the whole layout, so the observable claim is
        // that each measure's content span matches its tick span at that scale.
        let tickWidth = result.layout.tabGrid.tickWidth
        for measure in result.layout.measures {
            let expected = CGFloat(measure.durationTicks) * tickWidth
            let actual = result.layout.tabGrid
                .xPosition(in: measure, localTick: measure.durationTicks)
                - measure.contentStartX
            #expect(
                abs(actual - expected) < tolerance,
                "measure \(measure.measureIndex) content span \(actual) != tick span \(expected)"
            )
        }
    }

    @Test("equal tick deltas produce equal x deltas in sparse and dense measures")
    func equalTickDeltasGiveEqualXDeltas() throws {
        let result = try DrumTabFixtureHarness.render(
            DrumTabFixtureCatalog.multiRowStableWidths
        )
        let headsByMeasure = Dictionary(grouping: result.layout.noteHeads) {
            $0.timeColumn.measureIndex
        }
        let dense = try #require(headsByMeasure.first { $0.value.count >= 16 }?.key)
        let sparse = try #require(headsByMeasure.first { $0.value.count == 1 }?.key)

        let denseMeasure = try #require(result.layout.measures.first { $0.measureIndex == dense })
        let sparseMeasure = try #require(result.layout.measures.first { $0.measureIndex == sparse })

        // Probe the same tick delta in both measures.
        let delta = min(denseMeasure.durationTicks, sparseMeasure.durationTicks) / 4
        let grid = result.layout.tabGrid
        let denseSpan = grid.xPosition(in: denseMeasure, localTick: delta)
            - grid.xPosition(in: denseMeasure, localTick: 0)
        let sparseSpan = grid.xPosition(in: sparseMeasure, localTick: delta)
            - grid.xPosition(in: sparseMeasure, localTick: 0)

        #expect(
            abs(denseSpan - sparseSpan) < tolerance,
            "dense \(denseSpan) vs sparse \(sparseSpan): density is changing spacing"
        )
    }

    // MARK: - Screenshot failure mode 2: overlong connection bars

    @Test("no beam extends past its own member stems", arguments: [
        DrumTabFixtureCatalog.sixteenthRun,
        DrumTabFixtureCatalog.mixedEighthSixteenth,
        DrumTabFixtureCatalog.multiRowStableWidths
    ])
    func beamsStayWithinTheirMembers(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let stemXByHead = stemXByHeadID(result)
        let hookSlack = result.style.beamHookLength + tolerance

        for beam in result.layout.beams {
            let memberXs = beam.noteHeadIDs.compactMap { stemXByHead[$0] }
            guard let low = memberXs.min(), let high = memberXs.max() else { continue }
            let beamLow = min(beam.start.x, beam.end.x)
            let beamHigh = max(beam.start.x, beam.end.x)

            #expect(
                beamLow >= low - hookSlack,
                "beam \(beam.id) starts \(beamLow) left of its members (\(low))"
            )
            #expect(
                beamHigh <= high + hookSlack,
                "beam \(beam.id) ends \(beamHigh) right of its members (\(high))"
            )
        }
    }

    @Test("no beam spans wider than its beat group")
    func beamsStayWithinTheirBeatGroup() throws {
        let result = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.sixteenthRun)
        let grid = result.layout.tabGrid
        let headByID = Dictionary(
            uniqueKeysWithValues: result.layout.noteHeads.map { ($0.id, $0) }
        )

        for beam in result.layout.beams {
            let heads = beam.noteHeadIDs.compactMap { headByID[$0] }
            guard let first = heads.first else { continue }
            let measureIndex = first.timeColumn.measureIndex
            let renderedMeasure = try #require(
                result.layout.measures.first { $0.measureIndex == measureIndex }
            )
            let rhythmMeasure = try #require(
                result.snapshot.measures.first { $0.measureIndex == measureIndex }
            )
            let group = try #require(
                rhythmMeasure.beatGroups.first {
                    first.timeColumn.tickWithinMeasure >= $0.startTick
                        && first.timeColumn.tickWithinMeasure < $0.endTick
                }
            )
            let groupWidth = grid.xPosition(
                in: renderedMeasure,
                localTick: group.startTick + group.durationTicks
            ) - grid.xPosition(in: renderedMeasure, localTick: group.startTick)

            let beamWidth = abs(beam.end.x - beam.start.x)
            #expect(
                beamWidth <= groupWidth + result.style.beamHookLength + tolerance,
                "beam \(beam.id) spans \(beamWidth) > beat group \(groupWidth)"
            )
        }
    }

    /// Structural guard, not a behavioral invariant: `NotationBeamTopology`'s
    /// `GroupKey` partitions by measure, row, voice, and stem direction, so this
    /// cannot fail under the current implementation. It exists to catch a future
    /// change that removes a field from that key.
    @Test("beam members agree on measure, row, voice, and direction (partition guard)")
    func beamMembersShareTheirPartition() throws {
        for fixture in DrumTabFixtureCatalog.all {
            let result = try DrumTabFixtureHarness.render(fixture)
            let headByID = Dictionary(
                uniqueKeysWithValues: result.layout.noteHeads.map { ($0.id, $0) }
            )
            for beam in result.layout.beams {
                let heads = beam.noteHeadIDs.compactMap { headByID[$0] }
                #expect(Set(heads.map(\.timeColumn.measureIndex)).count <= 1)
                #expect(Set(heads.map(\.row)).count <= 1)
                #expect(Set(heads.map(\.voice)).count <= 1)
                #expect(Set(heads.map(\.stemDirection)).count <= 1)
            }
        }
    }

    // MARK: - Cross-cutting

    @Test("every note head sits on its own tick's grid x", arguments: DrumTabFixtureCatalog.all)
    func headsSitOnGridPositions(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let grid = result.layout.tabGrid
        let measuresByIndex = Dictionary(
            uniqueKeysWithValues: result.layout.measures.map { ($0.measureIndex, $0) }
        )

        for head in result.layout.noteHeads {
            let measure = try #require(measuresByIndex[head.timeColumn.measureIndex])
            let expected = grid.xPosition(
                in: measure,
                localTick: head.timeColumn.tickWithinMeasure
            )
            #expect(
                abs(head.position.x - expected) < tolerance,
                "head \(head.id) at x \(head.position.x), grid says \(expected)"
            )
        }
    }

    @Test("simultaneous heads share one x column", arguments: DrumTabFixtureCatalog.all)
    func simultaneousHeadsShareColumn(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let byTick = Dictionary(grouping: result.layout.noteHeads) {
            $0.timeColumn.absoluteLayoutTick
        }
        for (tick, heads) in byTick {
            let xs = Set(heads.map { ($0.position.x * 100).rounded() })
            #expect(xs.count == 1, "tick \(tick) heads span \(xs.count) x positions")
        }
    }

    @Test("painted bounds contain every primitive", arguments: DrumTabFixtureCatalog.all)
    func paintedBoundsContainEveryPrimitive(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let layout = result.layout
        let style = result.style
        let bounds = layout.noteHeads.map { $0.paintedBounds(style: style) }
            + layout.rests.filter(\.isPrinted).map { $0.paintedBounds(style: style) }
            + layout.stopNotes.map { $0.paintedBounds(style: style) }
            + layout.articulations.map { $0.paintedBounds(style: style) }
            + layout.stems.map { $0.paintedBounds(style: style) }
            + layout.beams.map { $0.paintedBounds(style: style) }
            + layout.flags.map { $0.paintedBounds(style: style) }
            + layout.ledgerLines.map { $0.paintedBounds(style: style) }
            + layout.measureBars.map { $0.paintedBounds(style: style) }

        for rect in bounds where !rect.isNull {
            #expect(layout.paintedBounds.contains(rect))
        }
    }

    /// Stem x is the stem anchor, not the head centre — beam geometry operates
    /// on `stemAnchor(for:).x`. Mapping heads to stem x through the stems keeps
    /// the beam-extent checks honest.
    private func stemXByHeadID(_ result: FixtureRenderResult) -> [UInt64: CGFloat] {
        var map: [UInt64: CGFloat] = [:]
        for stem in result.layout.stems {
            for headID in stem.noteHeadIDs {
                map[headID] = stem.start.x
            }
        }
        return map
    }
}
```

- [ ] **Step 3: Run and confirm all pass**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -configuration Debug -only-testing:VirgoTests/DrumTabRegressionInvariantTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected: PASS. A failure in `beamsStayWithinTheirMembers` or `beamsStayWithinTheirBeatGroup` is the HPA-97 overlong-beam bug — report it with the failing fixture and measured widths rather than widening the tolerance.

- [ ] **Step 4: Lint and commit**

```bash
swiftlint lint --quiet
git add VirgoTests/DrumTabRegressionInvariantTests.swift \
        VirgoTests/Fixtures/DrumTabFixtureCatalog.swift
git commit -m "test: drum tab regression invariants for both screenshot failure modes

Beam checks are geometric (span within member stem anchors and within the
beat group) because those are falsifiable; the membership partition check
is labelled a structural guard since GroupKey already partitions by
measure, row, voice and direction."
```

---

### Task 10: Differential ink render probe

**Files:**
- Create: `VirgoTests/DrumTabRenderProbeTests.swift`

**Interfaces:**
- Consumes: `FixtureRenderResult`, `NotationLayout` (mutable `noteHeads`), `RenderedNoteHead.paintedBounds(style:)`.

- [ ] **Step 1: Find the view under test**

Read `Virgo/views/subviews/GameplaySheetMusicView.swift`, the `drumNotationView(viewModel:)` method. Note two things: it renders `ledgerLines`, rests, `beams`, `flags`, `stems`, **then** `noteHeads` into one `ZStack`, and it resolves `NotationLayoutStyle.gameplayDefault` internally.

Because that method takes a `GameplayViewModel`, the probe cannot call it directly without a view model. Build an equivalent local `ZStack` in the test that mounts the same primitive views in the same order from a `NotationLayout` — `NotationLedgerLineView`, `NotationRestView`, `NotationBeamView`, `NotationFlagView`, `NotationStemView`, `NotationNoteHeadView`. Keep the ordering identical so the differential comparison isolates the head layer.

- [ ] **Step 2: Write the probe**

```swift
import Testing
import SwiftUI
import Foundation
#if os(macOS)
import AppKit
#endif
@testable import Virgo

#if os(macOS)
@Suite("Drum tab render probe", .serialized)
@MainActor
struct DrumTabRenderProbeTests {
    private enum ProbeError: Error {
        case missingCGImage
        case missingPixelBuffer
        case missingBitmapContext
    }

    /// Mounts the notation primitives in the same z-order as
    /// `GameplaySheetMusicView.drumNotationView`, on a transparent background so
    /// staff and sheet chrome cannot mask a missing head.
    private func notationOverlay(
        _ layout: NotationLayout,
        style: NotationLayoutStyle
    ) -> some View {
        ZStack {
            ForEach(layout.ledgerLines) { NotationLedgerLineView(ledgerLine: $0) }
            ForEach(layout.rests.filter(\.isPrinted)) { NotationRestView(rest: $0, style: style) }
            ForEach(layout.beams) { NotationBeamView(beam: $0) }
            ForEach(layout.flags) { NotationFlagView(flag: $0) }
            ForEach(layout.stems) { NotationStemView(stem: $0) }
            ForEach(layout.noteHeads) {
                NotationNoteHeadView(noteHead: $0, size: layout.noteHeadSize)
            }
        }
    }

    /// Per-pixel alpha map. Ink is alpha > 20, so the probe is colour-agnostic
    /// and survives theme changes.
    private func inkMap<V: View>(of view: V, size: CGSize) throws -> (
        pixels: [Bool], width: Int, height: Int
    ) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { throw ProbeError.missingCGImage }

        let width = cgImage.width, height = cgImage.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        try bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { throw ProbeError.missingPixelBuffer }
            guard let context = CGContext(
                data: base, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw ProbeError.missingBitmapContext }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var pixels = [Bool](repeating: false, count: width * height)
        for index in 0..<(width * height) {
            pixels[index] = bytes[index * 4 + 3] > 20
        }
        return (pixels, width, height)
    }

    private func inkCount(
        in map: (pixels: [Bool], width: Int, height: Int),
        rect: CGRect,
        yOffset: CGFloat
    ) -> Int {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(map.width - 1, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int((rect.minY + yOffset).rounded(.down)))
        let maxY = min(map.height - 1, Int((rect.maxY + yOffset).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return 0 }

        var count = 0
        for y in minY...maxY {
            for x in minX...maxX where map.pixels[y * map.width + x] {
                count += 1
            }
        }
        return count
    }

    @Test("note heads are actually painted", arguments: [
        DrumTabFixtureCatalog.sixteenthRun,
        DrumTabFixtureCatalog.multiRowStableWidths
    ])
    func noteHeadsArePainted(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let layout = result.layout

        // The view resolves gameplayDefault internally; if the harness's locked
        // style ever diverges, the sample rects would be misplaced. Fail loudly
        // instead of silently sampling the wrong pixels.
        let viewStyle = NotationLayoutStyle.gameplayDefault
        #expect(
            viewStyle.noteHeadWidth == result.style.noteHeadWidth
                && viewStyle.noteHeadHeight == result.style.noteHeadHeight,
            "view style and harness style disagree on note head size"
        )

        let size = CGSize(width: result.style.rowWidth, height: max(layout.totalHeight, 1))
        let yOffset = layout.topContentInset(style: viewStyle)

        var stripped = layout
        stripped.noteHeads = []

        let withHeads = try inkMap(of: notationOverlay(layout, style: viewStyle), size: size)
        let withoutHeads = try inkMap(of: notationOverlay(stripped, style: viewStyle), size: size)

        let totalWith = withHeads.pixels.filter { $0 }.count
        let totalWithout = withoutHeads.pixels.filter { $0 }.count

        // Checked first so an entirely unmounted head layer fails once, clearly,
        // rather than as N confusing per-head failures.
        #expect(
            totalWith > totalWithout,
            "mounting note heads added no ink (\(totalWith) vs \(totalWithout))"
        )

        // Per-head delta inside the head's own 2-D bounds. A full-height column
        // band would also catch stems and beams, which share the x band — that
        // is why this is differential and rect-scoped.
        for head in layout.noteHeads {
            let rect = head.paintedBounds(style: viewStyle)
            guard !rect.isNull else { continue }
            let delta = inkCount(in: withHeads, rect: rect, yOffset: yOffset)
                - inkCount(in: withoutHeads, rect: rect, yOffset: yOffset)
            #expect(delta > 0, "head \(head.id) contributed no ink in \(rect)")
        }
    }
}
#endif
```

- [ ] **Step 3: Run the probe**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -configuration Debug -only-testing:VirgoTests/DrumTabRenderProbeTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected: PASS.

If per-head deltas are 0 while the total delta is positive, the `yOffset` is wrong: primitive coordinates are staff-relative and the sheet applies `topContentInset`. Print one head's `paintedBounds` and the image height, and adjust the offset until the sampled rect lands on the drawn glyph. Do not relax `delta > 0`.

- [ ] **Step 4: Lint and commit**

```bash
swiftlint lint --quiet
git add VirgoTests/DrumTabRenderProbeTests.swift
git commit -m "test: differential ink probe for note head mounting

Renders each fixture twice, with and without noteHeads, and requires a
positive ink delta inside each head's 2-D painted bounds. A single-render
column-band probe would stay green after deleting every
NotationNoteHeadView, since drumNotationView draws stems and beams in the
same x bands."
```

---

### Task 11: Playhead alignment against rendered note columns

**Files:**
- Create: `VirgoTests/DrumTabPlayheadAlignmentTests.swift`

`RhythmTimelineIntegrationTests.swift` is already 602 lines — over SwiftLint's 600-line warning — so these go in a new file rather than being appended there.

**Interfaces:**
- Consumes: `FixtureRenderResult.chart`, `GameplayViewModelTestHarness.createTestMetronome()`, `GameplayViewModel`.

- [ ] **Step 1: Read the existing playhead assertion**

Read `VirgoTests/RhythmTimelineIntegrationTests.swift` around the assertion `viewModel.purpleBarPosition?.x == Double(laterHead.position.x)` (near line 154) and the view-model construction above it. Mirror that setup — including `loadChartData()` and `setupGameplay(loadPersistedSpeed: false)` — rather than inventing a new one.

- [ ] **Step 2: Write the tests**

```swift
import Testing
import Foundation
@testable import Virgo

@Suite("Drum tab playhead alignment", .serialized)
@MainActor
struct DrumTabPlayheadAlignmentTests {
    @Test("playhead x lands on a rendered note column", arguments: [
        DrumTabFixtureCatalog.sixteenthRun,
        DrumTabFixtureCatalog.multiRowStableWidths
    ])
    func playheadMatchesNoteColumn(_ fixture: DrumTabFixture) async throws {
        // The chart comes from the fixture harness — attached, persisted, and
        // built through persistenceProjection. Never createTestChart: that
        // leaves rhythmMetadataState == .missing, routes resolve() through
        // resolveMissing, and lands on the legacy layout path.
        let rendered = try DrumTabFixtureHarness.render(fixture)

        let viewModel = GameplayViewModel(
            chart: rendered.chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        // These tests bypass the harness's gate step, so re-assert validity.
        // Without this, a fixture degrading to resolveMissing yields nil on
        // both sides and the comparison passes vacuously.
        let runtime = try #require(viewModel.cachedRhythmRuntime)
        #expect(runtime.availability == .valid)
        #expect(runtime.timeline != nil)
        #expect(!viewModel.cachedNotationLayout.noteHeads.isEmpty)

        let position = try #require(
            viewModel.purpleBarPosition,
            "playhead must have a position once gameplay is set up"
        )

        // The playhead must sit on a column that actually has a head.
        let columnXs = Set(
            viewModel.cachedNotationLayout.noteHeads.map { ($0.position.x * 100).rounded() }
        )
        #expect(
            columnXs.contains((CGFloat(position.x) * 100).rounded()),
            "playhead x \(position.x) matches no rendered note column"
        )
    }
}
```

- [ ] **Step 3: Run and adjust for the runtime accessor name**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -configuration Debug -only-testing:VirgoTests/DrumTabPlayheadAlignmentTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```

If `cachedRhythmRuntime` is not the accessor's name or is not visible to tests, grep `GameplayViewModel.swift` for the stored property holding `GameplayRhythmRuntime` and use that. Keep all three validity assertions — only the property name may change.

If `purpleBarPosition` is `nil` after `setupGameplay`, check how `RhythmTimelineIntegrationTests` advances the beat before asserting (it may need a metronome tick or an explicit visual update) and mirror that.

Expected once wired: PASS.

- [ ] **Step 4: Lint and commit**

```bash
swiftlint lint --quiet
git add VirgoTests/DrumTabPlayheadAlignmentTests.swift
git commit -m "test: playhead x alignment against rendered note columns

Drives the same fixtures the goldens use, taking the attached chart from
DrumTabFixtureHarness so the playhead is verified for charts that are
actually covered elsewhere, and re-asserting rhythm validity because
these tests bypass the harness gate step."
```

---

### Task 12: Full-suite verification and documentation

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Run every new suite together**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  -only-testing:VirgoTests/DrumTabRegressionInvariantTests \
  -only-testing:VirgoTests/DrumTabRenderProbeTests \
  -only-testing:VirgoTests/DrumTabPlayheadAlignmentTests \
  -only-testing:VirgoTests/DrumTabFixtureHarnessTests \
  -only-testing:VirgoTests/RhythmLayoutSnapshotBuilderTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected: all PASS. Run it a second time to confirm determinism.

- [ ] **Step 2: Confirm 11 goldens exist and none is empty**

```bash
ls -l VirgoTests/Goldens/
test "$(ls VirgoTests/Goldens/*.txt | wc -l | tr -d ' ')" = "11" && echo "11 goldens OK"
```

- [ ] **Step 3: Verify the regeneration guard actually fails**

```bash
VIRGO_UPDATE_GOLDENS=1 xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/DrumTabGoldenTests -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
git diff --stat VirgoTests/Goldens/
```

Expected: the run FAILS (by design) and `git diff` shows no content change — proving regeneration is byte-stable and cannot silently self-approve. Restore anything that did change with `git checkout VirgoTests/Goldens/`.

- [ ] **Step 4: Run the broader layout suites for regressions**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -only-testing:VirgoTests/NotationBeamTopologyTests \
  -only-testing:VirgoTests/NotationRestTopologyTests \
  -only-testing:VirgoTests/RhythmTimelineIntegrationTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected: unchanged from before Task 1.

- [ ] **Step 5: Document the suite in `CLAUDE.md`**

Add to the "Rhythm & Notation Pipeline" section:

```markdown
### Drum Tab Golden Coverage
`VirgoTests/Fixtures/DrumTabFixtureCatalog*.swift` holds 11 DTX fixtures driven through the real
import path by `DrumTabFixtureHarness` (`persistenceProjection()` + `setRhythmMetadata`, **not**
`toNotes`/`toControlEvents` — the latter leaves `rhythmMetadataState == .missing` and stamps control
ticks at each chip's native grid size). `NotationLayoutDigest` serializes the result to text, compared
against `VirgoTests/Goldens/<fixture>.txt`.

Regenerate with `VIRGO_UPDATE_GOLDENS=1`; the run always **fails** afterwards so CI cannot
self-approve a regression. Review `git diff` before committing. Golden lines starting with `#` are
stripped before comparison, so `# SUSPECT: HPA-<id> …` marks a golden that pins known-suspect output.

`RhythmLayoutSnapshotBuilder` (`Virgo/layout/`) is shared by `GameplayViewModel` and the harness on
purpose — a parallel copy in tests would let goldens pass while production rendering broke.
```

- [ ] **Step 6: Lint and commit**

```bash
swiftlint lint --quiet
git add CLAUDE.md
git commit -m "docs: document drum tab golden coverage in CLAUDE.md"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
| --- | --- |
| §4.1 pipeline via `persistenceProjection` | 2 |
| §4.2 components incl. `FixtureRenderResult` | 2, 3 |
| §4.3 `RhythmLayoutSnapshotBuilder` extraction, `logDiagnostics` + `@MainActor` | 1 |
| §4.4 locked `rowWidth` / `notePositionOverrides` | 2 |
| §5 fixtures 1–11 | 2, 4, 5, 6, 7, 8 |
| §5.1 per-fixture validity gates | 2, 4, 5, 6, 7, 8 |
| §5.2 fixture 5 conditional engraving gate | 8 |
| §5.3 fixture 8 differential rest separation | 6 |
| §6.1 normative line kinds (all 14 collections, `flag`, `beam.kind`, `dims`, `style`) | 3 |
| §6.3 determinism: POSIX locale, explicit total orders | 3 |
| §6.4 golden files + `VIRGO_UPDATE_GOLDENS` | 3, 12 |
| §6.5 diff-on-mismatch reporting | 3 |
| §7.1 spacing + beam geometry + partition guard + cross-cutting | 9 |
| §7.2 golden tests | 3–8 |
| §7.3 differential ink probe | 10 |
| §8 playhead, attached chart, re-asserted gates, sibling file | 11 |
| §9 Swift Testing, `TestContainer`, `.serialized`, no parallel | all |
| §11 `# SUSPECT:` trailer convention | 8, 12 |

**Placeholder scan:** Task 1 Step 4 intentionally says "moved verbatim" rather than reproducing ~70 lines of production code, because reproducing it risks introducing a transcription difference in what must be a behavior-neutral move; Step 1 has the engineer read the exact source first and Step 7 verifies via the existing suites. Every other code step contains complete code.

**Type consistency:** `FixtureRenderResult` gains `container` in Task 2 (beyond the spec's five fields) so the `ModelContainer` outlives `render(...)`, as §4.2 requires. `DrumTabFixtureCatalog.chart(_:)` is `static func` and used by the `+Rhythm` extension. `DrumTabFixture.line` has two overloads — the `positions:` dictionary form (used for control lanes, where the note ID encodes the target) and the `at:` array form. `GoldenFile.stripComments` is introduced in Task 8 and applied to all fixtures from then on; goldens recorded in Tasks 3–7 contain no `#` lines, so they remain valid.

**Known adjustment points flagged for the implementer:** fixture 11's note positions (Task 4 Step 3), fixture 10's measure count for row wrapping (Task 7 Step 3), the triplet engraving branch (Task 8 Step 3), the probe's `yOffset` (Task 10 Step 3), and the runtime accessor name plus playhead advancement (Task 11 Step 3). Each names the contract to preserve and forbids weakening the assertion.
