# Voice-Aware Rests, Stop Events, and Drum Articulations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render deterministic per-voice rests, explicit stop/choke/damp marks, and open-hi-hat articulation circles without changing Virgo's playable-note grid, scoring, playback, or parser semantics.

**Architecture:** Add a persisted `ChartControlEvent` parallel to `Note`, snapshot it before rendering, and feed it into the existing notation engine without allowing controls to influence `TabGrid`. Add a geometry-free `NotationRestTopologyBuilder` over canonical integer ticks, then materialize rests, controls, and articulations only after HPA-140 through HPA-142 have produced measures, noteheads, beams, stems, flags, ledger lines, and bars. Keep render activation (`hasRenderableContent`) separate from gameplay activation (`hasPlayableContent`) so rest/control-only charts use notation geometry but never acquire score targets, a playhead, or row scrolling.

**Tech Stack:** Swift 5.9+, SwiftData, SwiftUI, Core Graphics, Swift Testing, Xcode 16+/`xcodebuild`, SwiftLint.

## Global Constraints

- Preserve HPA-140 fixed-grid placement, HPA-141 catalog-owned notehead/voice/stem semantics, and HPA-142 beam topology exactly.
- Build `TabGrid` from playable notes only. A control event must not alter tick resolution, tick width, measure width, wrapping, notehead x-coordinates, beam topology, or playhead columns.
- Persist controls separately from `Note`; do not give them a `NoteType`, `NoteInterval`, score value, gameplay instrument, hit window, or audio behavior.
- Do not infer stop/choke/damp events from DTX filenames, sample IDs, unknown lanes, or neighboring cymbals. HPA-143 adds the destination model and explicit authored fixtures only.
- Use normalized control timing only when it is complete, internally consistent, and exactly rescalable. Manual controls may use an exact `measureOffset` fallback; controls never use the playable-note rounding fallback.
- Synthesize rest occupancy independently for upper and lower voices. Controls never occupy a voice or split a rest.
- Support internal rest decomposition only for simple X/4 meters (2/4, 3/4, 4/4, 5/4). `/8` meters retain full-measure visibility policy but hide active-voice internal complements until HPA-145.
- Use the closed rest vocabulary `fullMeasure`, `half`, `quarter`, `eighth`, `sixteenth`, `thirtySecond`, and `sixtyFourth`; there is no ordinary `full` case.
- Do not add dotted rests, tuplets, compound-meter grouping, sloped/cross-staff notation, audio choking, or new scoring/input targets.
- Keep `ChartRelationshipData` and `ChartRelationshipLoader` unchanged; their note/count snapshot has no production caller and is not the gameplay control-event cache.
- Update the seven explicit model-container registrations listed in Task 1. Song/Chart-rooted SwiftUI previews continue to discover related models through their root schema and do not become an eighth hand-maintained registration list.
- Use `NotationLayout.hasRenderableContent` for notation coordinate-system selection, measures, sizing, maps, bars, and cached staff background.
- Use `NotationLayout.hasPlayableContent` for beat caches, notation playhead calculation, current-row advancement, and playback-driven scrolling. Once notation geometry is active, a non-playable layout returns no playhead; it never falls back to legacy playhead coordinates.
- Keep new primitives inside the final measure-bar bound plus existing uniform-spacing allowance; do not change `NotationLayout.contentWidth` or `notationContentWidth(for:)`.
- Expose semantic accessibility labels on rendered data. Hide hidden rests and the decorative open-hi-hat circle from accessibility.
- Use Swift Testing (`import Testing`), not XCTest.
- Run every `xcodebuild test` with `-parallel-testing-enabled NO`; run Xcode verification sequentially against `./DerivedData`.
- Any iOS-family build must use an available iPad simulator. Never target an iPhone and never change `TARGETED_DEVICE_FAMILY = 2`.
- Prefix every shell command with `rtk`.
- The project uses file-system-synchronized root groups; do not edit `Virgo.xcodeproj/project.pbxproj` for new Swift files.
- Keep each task limited to the files named in that task, run its focused suites, review its diff, and commit it before starting the next task.

---

## File Structure

- Create `Virgo/models/ChartControlEvent.swift`: persisted control-event kind/model and immutable `NotationControlEvent` snapshot.
- Modify `Virgo/models/DrumTrack.swift`: Chart cascade relationship, safe accessor, initializer compatibility, and fixture copying.
- Modify `Virgo/VirgoApp.swift`: production schema registration.
- Modify `Virgo/services/ScorePersistenceService.swift`: in-memory service schema registration.
- Modify `VirgoTests/TestHelpers.swift`: test schema registration and defensive orphan cleanup.
- Modify `VirgoTests/PatchCoverageAdditionsTests.swift`: local test-store schema registration.
- Modify `VirgoTests/NavigationTests.swift`: local test-container schema registration.
- Modify `VirgoTests/ChartModelDefaultPropertyTests.swift`: local test-container schema registration and safe-control defaults.
- Modify `VirgoTests/DrumTrackTests.swift`: local test-container schema registration.
- Create `VirgoTests/ChartControlEventTests.swift`: model, persistence, cascade, copy, and enum coverage.
- Create `Virgo/layout/NotationRestTopology.swift`: pure rest timeline, duration, visibility, topology event, and builder.
- Create `VirgoTests/NotationRestTopologyTests.swift`: pure occupancy, decomposition, fallback, coverage, and determinism matrix.
- Modify `Virgo/layout/NotationLayout.swift`: immutable input, style metrics, rendered primitives, predicates, and accessibility labels.
- Modify `Virgo/constants/DrumNotation.swift`: catalog-backed display-name and lane-target resolution helpers.
- Modify `Virgo/layout/NotationLayoutEngine+TabGrid.swift`: shared exact tick rescaling while retaining the note-only rounding fallback.
- Modify `VirgoTests/NotationLayoutEngineTests.swift`: style-copy, exact-rescaling, input-compatibility, predicate, and accessibility contracts.
- Modify `VirgoTests/DrumNotationCatalogTests.swift`: target-lane and head-label contracts.
- Create `Virgo/layout/NotationLayoutEngine+Rests.swift`: timeline formation, pure topology invocation, and rest geometry.
- Modify `Virgo/layout/NotationLayoutEngine.swift`: total-measure calculation and post-grid rest/control/articulation pipeline.
- Create `Virgo/layout/NotationLayoutEngine+Controls.swift`: control timing/target resolution, deterministic IDs, diagnostics, and articulation overlays.
- Create `VirgoTests/NotationLayoutRestAndControlTests.swift`: engine-level rests, controls, articulation, invariants, identity, and geometry.
- Modify `Virgo/viewmodels/GameplayViewModel.swift`: async immutable control-event cache.
- Modify `Virgo/viewmodels/GameplayViewModel+Computations.swift`: input threading and renderable/playable cache gates.
- Modify `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`: playable-only row/playhead gates with no legacy fallback.
- Modify `Virgo/views/NotationPrimitiveViews.swift`: vector rest, stopped-mark, articulation, and notehead accessibility rendering.
- Modify `Virgo/views/subviews/GameplaySheetMusicView.swift`: renderable coordinate selection, layer order, printed-rest filtering, and notation-only behavior.
- Modify `VirgoTests/GameplayViewModelDataLoadingTests.swift`: snapshot, staff/map, and notation-only activation coverage.
- Modify `VirgoTests/GameplayViewModelComputationsTests.swift`: rest/control-only beat-cache behavior.
- Modify `VirgoTests/GameplayViewModelVisualUpdatesTests.swift`: no-playhead/no-row-scroll behavior and playable regressions.
- Modify `VirgoTests/SwiftUIRenderingCoverageTests.swift`: primitive construction, accessibility ownership, sheet selection, and sizing coverage.

---

### Task 1: Add the Persisted Control-Event Domain

**Files:**
- Create: `Virgo/models/ChartControlEvent.swift`
- Create: `VirgoTests/ChartControlEventTests.swift`
- Modify: `Virgo/models/DrumTrack.swift`
- Modify: `Virgo/VirgoApp.swift`
- Modify: `Virgo/services/ScorePersistenceService.swift`
- Modify: `VirgoTests/TestHelpers.swift`
- Modify: `VirgoTests/PatchCoverageAdditionsTests.swift`
- Modify: `VirgoTests/NavigationTests.swift`
- Modify: `VirgoTests/ChartModelDefaultPropertyTests.swift`
- Modify: `VirgoTests/DrumTrackTests.swift`

**Interfaces:**
- Produces `NotationControlEventKind`, `ChartControlEvent`, and immutable `NotationControlEvent`.
- Extends `Chart` with `controlEvents`, `safeControlEvents`, and an initializer default that preserves every existing call site.
- Keeps control persistence independent from playable notes and cascades controls when a Chart is deleted.

- [ ] **Step 1: Write the failing model and persistence tests**

Create `VirgoTests/ChartControlEventTests.swift` with a serialized suite. Use a fresh in-memory schema that explicitly contains every model, then cover raw values, model defaults, immutable snapshot copying, persistence, Chart cascade deletion, and `Song.fixtureCopy`:

```swift
import SwiftData
import Testing
@testable import Virgo

@Suite("Chart Control Event Tests", .serialized)
@MainActor
struct ChartControlEventTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Song.self, Chart.self, Note.self, ChartControlEvent.self,
            ServerSong.self, ServerChart.self, ScoreRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("control kinds preserve stable raw values")
    func kindRawValuesAreStable() {
        #expect(NotationControlEventKind.stop.rawValue == "stop")
        #expect(NotationControlEventKind.choke.rawValue == "choke")
        #expect(NotationControlEventKind.damp.rawValue == "damp")
        #expect(NotationControlEventKind.allCases == [.stop, .choke, .damp])
    }

    @Test("control defaults to manual origin and snapshots all semantic fields")
    func defaultsAndSnapshot() {
        let event = ChartControlEvent(
            kind: .choke,
            measureNumber: 2,
            measureOffset: 0.25,
            sourceLaneID: "55",
            sourceNoteID: "0A",
            sourceGridPosition: 1,
            sourceGridSize: 4,
            normalizedMeasureIndex: 1,
            normalizedAbsoluteTick: 5,
            normalizedTickWithinMeasure: 1,
            normalizedTicksPerMeasure: 4,
            targetLaneID: "1A"
        )

        let snapshot = NotationControlEvent(event)

        #expect(event.originKind == .manual)
        #expect(snapshot.kind == .choke)
        #expect(snapshot.measureNumber == 2)
        #expect(snapshot.measureOffset == 0.25)
        #expect(snapshot.sourceLaneID == "55")
        #expect(snapshot.sourceNoteID == "0A")
        #expect(snapshot.normalizedAbsoluteTick == 5)
        #expect(snapshot.targetLaneID == "1A")
    }

    @Test("control persists and Chart deletion cascades")
    func persistenceAndCascade() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let chart = Chart(difficulty: .medium)
        let event = ChartControlEvent(
            kind: .stop,
            measureNumber: 1,
            measureOffset: 0.5,
            chart: chart,
            targetLaneID: "18"
        )
        chart.controlEvents = [event]
        context.insert(chart)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ChartControlEvent>()).count == 1)

        context.delete(chart)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ChartControlEvent>()).isEmpty)
    }

    @Test("fixture copy preserves controls separately from notes")
    func fixtureCopyPreservesControls() throws {
        let template = Song(title: "T", artist: "A", bpm: 120, duration: "1:00", genre: "Test")
        let chart = Chart(difficulty: .hard, song: template)
        chart.notes = [Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0)]
        chart.controlEvents = [
            ChartControlEvent(kind: .choke, measureNumber: 1, measureOffset: 0.25, targetLaneID: "1A")
        ]
        template.charts = [chart]

        let copy = Song.fixtureCopy(from: template)
        let copiedChart = try #require(copy.charts.first)
        let copiedControl = try #require(copiedChart.controlEvents.first)

        #expect(copiedChart.notes.count == 1)
        #expect(copiedChart.controlEvents.count == 1)
        #expect(copiedControl !== chart.controlEvents[0])
        #expect(copiedControl.chart === copiedChart)
        #expect(copiedControl.kind == .choke)
        #expect(copiedControl.targetLaneID == "1A")
    }
}
```

Add focused assertions to `ChartModelDefaultPropertyTests` that `Chart(difficulty:)` has empty `controlEvents` and `safeControlEvents`, and that `safeControlEvents` returns attached non-deleted events.

- [ ] **Step 2: Run the model suites and verify RED**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/ChartControlEventTests -only-testing:VirgoTests/ChartComputedPropertyTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: compilation fails because `ChartControlEvent`, `NotationControlEventKind`, `NotationControlEvent`, and `Chart.controlEvents` do not exist.

- [ ] **Step 3: Add the model and immutable snapshot**

Create `Virgo/models/ChartControlEvent.swift`:

```swift
import Foundation
import SwiftData

enum NotationControlEventKind: String, Codable, CaseIterable, Hashable {
    case stop
    case choke
    case damp
}

@Model
final class ChartControlEvent {
    var kind: NotationControlEventKind
    var measureNumber: Int
    var measureOffset: Double
    var chart: Chart?
    var originKind: NoteOriginKind = NoteOriginKind.manual
    var sourceLaneID: String?
    var sourceNoteID: String?
    var sourceGridPosition: Int?
    var sourceGridSize: Int?
    var normalizedMeasureIndex: Int?
    var normalizedAbsoluteTick: Int?
    var normalizedTickWithinMeasure: Int?
    var normalizedTicksPerMeasure: Int?
    var targetLaneID: String?

    init(
        kind: NotationControlEventKind,
        measureNumber: Int,
        measureOffset: Double,
        chart: Chart? = nil,
        originKind: NoteOriginKind = .manual,
        sourceLaneID: String? = nil,
        sourceNoteID: String? = nil,
        sourceGridPosition: Int? = nil,
        sourceGridSize: Int? = nil,
        normalizedMeasureIndex: Int? = nil,
        normalizedAbsoluteTick: Int? = nil,
        normalizedTickWithinMeasure: Int? = nil,
        normalizedTicksPerMeasure: Int? = nil,
        targetLaneID: String? = nil
    ) {
        self.kind = kind
        self.measureNumber = measureNumber
        self.measureOffset = measureOffset
        self.chart = chart
        self.originKind = originKind
        self.sourceLaneID = sourceLaneID
        self.sourceNoteID = sourceNoteID
        self.sourceGridPosition = sourceGridPosition
        self.sourceGridSize = sourceGridSize
        self.normalizedMeasureIndex = normalizedMeasureIndex
        self.normalizedAbsoluteTick = normalizedAbsoluteTick
        self.normalizedTickWithinMeasure = normalizedTickWithinMeasure
        self.normalizedTicksPerMeasure = normalizedTicksPerMeasure
        self.targetLaneID = targetLaneID
    }
}

struct NotationControlEvent: Hashable {
    let kind: NotationControlEventKind
    let measureNumber: Int
    let measureOffset: Double
    let originKind: NoteOriginKind
    let sourceLaneID: String?
    let sourceNoteID: String?
    let sourceGridPosition: Int?
    let sourceGridSize: Int?
    let normalizedMeasureIndex: Int?
    let normalizedAbsoluteTick: Int?
    let normalizedTickWithinMeasure: Int?
    let normalizedTicksPerMeasure: Int?
    let targetLaneID: String?

    init(_ event: ChartControlEvent) {
        kind = event.kind
        measureNumber = event.measureNumber
        measureOffset = event.measureOffset
        originKind = event.originKind
        sourceLaneID = event.sourceLaneID
        sourceNoteID = event.sourceNoteID
        sourceGridPosition = event.sourceGridPosition
        sourceGridSize = event.sourceGridSize
        normalizedMeasureIndex = event.normalizedMeasureIndex
        normalizedAbsoluteTick = event.normalizedAbsoluteTick
        normalizedTickWithinMeasure = event.normalizedTickWithinMeasure
        normalizedTicksPerMeasure = event.normalizedTicksPerMeasure
        targetLaneID = event.targetLaneID
    }
}
```

In `Chart`, add the inverse cascade relationship and initializer default without changing existing argument order before `song`:

```swift
@Relationship(deleteRule: .cascade, inverse: \ChartControlEvent.chart)
var controlEvents: [ChartControlEvent]

var safeControlEvents: [ChartControlEvent] {
    guard !isDeleted else { return [] }
    return controlEvents.filter { !$0.isDeleted }
}
```

Extend the initializer with `controlEvents: [ChartControlEvent] = []` after `notes`, assign it, and update `Song.fixtureCopy` to clone every control field with `chart: chart`. Do not append controls to `chart.notes` and do not copy a live model reference.

- [ ] **Step 4: Register the model in all seven explicit schemas**

Add `ChartControlEvent.self` immediately after `Note.self` in:

1. `Virgo/VirgoApp.swift`
2. `Virgo/services/ScorePersistenceService.swift`
3. `VirgoTests/TestHelpers.swift`
4. `VirgoTests/PatchCoverageAdditionsTests.swift`
5. `VirgoTests/NavigationTests.swift`
6. `VirgoTests/ChartModelDefaultPropertyTests.swift`
7. `VirgoTests/DrumTrackTests.swift`

In `TestContainer.reset()`, add a defensive fetch/delete pass for orphaned `ChartControlEvent` values after Charts and before Notes:

```swift
let controlEvents = try context.fetch(FetchDescriptor<ChartControlEvent>())
controlEvents.forEach { context.delete($0) }
```

- [ ] **Step 5: Run focused persistence/schema suites and verify GREEN**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/ChartControlEventTests -only-testing:VirgoTests/ChartComputedPropertyTests -only-testing:VirgoTests/DrumTrackTests -only-testing:VirgoTests/NavigationTests -only-testing:VirgoTests/PatchCoverageAdditionsTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: every selected suite executes and passes; the fresh container stores controls and Chart deletion removes them.

- [ ] **Step 6: Review and commit the domain contract**

```bash
rtk git diff --check
rtk git status --short
rtk git add Virgo/models/ChartControlEvent.swift Virgo/models/DrumTrack.swift Virgo/VirgoApp.swift Virgo/services/ScorePersistenceService.swift VirgoTests/ChartControlEventTests.swift VirgoTests/TestHelpers.swift VirgoTests/PatchCoverageAdditionsTests.swift VirgoTests/NavigationTests.swift VirgoTests/ChartModelDefaultPropertyTests.swift VirgoTests/DrumTrackTests.swift
rtk git commit -m "feat: add chart control event domain"
```

Expected review: no parser, scoring, input, or playback file changed; exactly seven explicit schema roots were updated.

---

### Task 2: Build the Pure Voice-Aware Rest Topology

**Files:**
- Create: `Virgo/layout/NotationRestTopology.swift`
- Create: `VirgoTests/NotationRestTopologyTests.swift`

**Interfaces:**
- Consumes only `NotationTimeColumn`, `NotationVoice`, `TimeSignature`, and integer durations.
- Produces deterministic `RestTopologyEvent` values with printed, hidden-spacing, and hidden-duplicate semantics.
- Contains no Core Graphics, SwiftUI, SwiftData, logging, or gameplay state.

- [ ] **Step 1: Write the failing topology policy tests**

Create `VirgoTests/NotationRestTopologyTests.swift` with helpers that use a 960-tick 4/4 measure and build by voice. Start with the full-measure and independent-voice cases:

```swift
import Testing
@testable import Virgo

@Suite("Notation Rest Topology Tests")
struct NotationRestTopologyTests {
    private let builder = NotationRestTopologyBuilder()

    private func note(
        tick: Int,
        voice: NotationVoice,
        durationTicks: Int?,
        measure: Int = 0
    ) -> RestTimelineNote {
        RestTimelineNote(
            timeColumn: NotationTimeColumn(
                measureIndex: measure,
                tickWithinMeasure: tick,
                absoluteLayoutTick: measure * 960 + tick
            ),
            voice: voice,
            durationTicks: durationTicks
        )
    }

    private func build(
        _ notes: [RestTimelineNote],
        measures: Int = 1,
        signature: TimeSignature = .fourFour
    ) -> [RestTopologyEvent] {
        builder.build(
            notes: notes,
            totalMeasureCount: measures,
            ticksPerMeasure: 960,
            timeSignature: signature
        )
    }

    @Test("silent measure prints one upper full-measure rest and hides the lower duplicate")
    func bothVoicesSilent() {
        #expect(build([]) == [
            RestTopologyEvent(
                measureIndex: 0, voice: .upper, startTick: 0, durationTicks: 960,
                duration: .fullMeasure, visibility: .printed
            ),
            RestTopologyEvent(
                measureIndex: 0, voice: .lower, startTick: 0, durationTicks: 960,
                duration: .fullMeasure, visibility: .hiddenDuplicate
            )
        ])
    }

    @Test("upper-only onset prints a lower full-measure rest")
    func upperOnlyPrintsLowerCompanion() {
        let result = build([note(tick: 0, voice: .upper, durationTicks: 240)])
        #expect(result.contains { $0.voice == .lower && $0.duration == .fullMeasure && $0.isPrinted })
        #expect(!result.contains { $0.voice == .upper && $0.duration == .fullMeasure })
    }

    @Test("lower-only onset prints an upper full-measure rest")
    func lowerOnlyPrintsUpperCompanion() {
        let result = build([note(tick: 0, voice: .lower, durationTicks: 240)])
        #expect(result.contains { $0.voice == .upper && $0.duration == .fullMeasure && $0.isPrinted })
        #expect(!result.contains { $0.voice == .lower && $0.duration == .fullMeasure })
    }
}
```

- [ ] **Step 2: Add the decomposition, uncertainty, coverage, and determinism matrix**

In the same suite, add explicit tests for all of these cases; compare complete event arrays rather than counts where possible:

- half, quarter, eighth, sixteenth, thirty-second, and sixty-fourth gaps on aligned columns;
- `Set(NotationRestDuration.allCases)` equals the seven closed cases and cannot contain an ordinary `.full` value;
- exact duration conversion in 2/4, 3/4, 4/4, and 5/4;
- longest exact same-time chord member controls occupancy;
- an onset clips the prior duration, including a next onset near the barline;
- overlapping exact spans merge before gap discovery;
- upper/lower onsets never clip each other;
- an unaligned or too-small remainder becomes one `.hiddenSpacing` event;
- a `nil` duration reserves from onset to next same-voice onset/measure end as `.hiddenSpacing`;
- `/8` keeps silent/full-measure policy but turns active-voice internal complements into hidden spacing;
- an empty multi-measure chart applies the silent policy in every measure;
- shuffled input produces the same sorted events;
- exact covered ticks for each voice are partitioned into occupied plus rest/hidden spans with no overlap or hole.

Use table-driven arguments for simple-meter duration conversion:

```swift
@Test(
    "quarter duration is exact in supported simple meters",
    arguments: [
        (TimeSignature.twoFour, 480),
        (TimeSignature.threeFour, 320),
        (TimeSignature.fourFour, 240),
        (TimeSignature.fiveFour, 192)
    ]
)
func quarterDurationIsExact(signature: TimeSignature, expectedTicks: Int) {
    #expect(
        builder.noteDurationTicks(
            for: NoteInterval.quarter,
            ticksPerMeasure: 960,
            timeSignature: signature
        ) == expectedTicks
    )
}
```

- [ ] **Step 3: Run the topology suite and verify RED**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/NotationRestTopologyTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: compilation fails because the topology types and builder do not exist.

- [ ] **Step 4: Add the pure types and exact duration conversion**

Create `Virgo/layout/NotationRestTopology.swift` beginning with:

```swift
struct RestTimelineNote: Hashable {
    let timeColumn: NotationTimeColumn
    let voice: NotationVoice
    let durationTicks: Int?
}

enum NotationRestDuration: String, CaseIterable, Hashable {
    case fullMeasure
    case half
    case quarter
    case eighth
    case sixteenth
    case thirtySecond
    case sixtyFourth
}

enum NotationRestVisibility: String, Hashable {
    case printed
    case hiddenSpacing
    case hiddenDuplicate
}

struct RestTopologyEvent: Hashable {
    let measureIndex: Int
    let voice: NotationVoice
    let startTick: Int
    let durationTicks: Int
    let duration: NotationRestDuration
    let visibility: NotationRestVisibility

    var isPrinted: Bool { visibility == .printed }
}
```

Implement two type-safe helpers over one private integer-rational function:

- `noteDurationTicks(for interval: NoteInterval, ticksPerMeasure: Int, timeSignature: TimeSignature) -> Int?` supports `.full` through `.sixtyfourth` for playable-note occupancy;
- `restDurationTicks(for duration: NotationRestDuration, ticksPerMeasure: Int, timeSignature: TimeSignature) -> Int?` supports `.half` through `.sixtyFourth` and returns `nil` for `.fullMeasure` because full-measure length comes from the active bar.

Require `/4`, positive grid size, and exact division; return `nil` otherwise. Use numerator/denominator pairs `{full: 4/1, half: 2/1, quarter: 1/1, eighth: 1/2, sixteenth: 1/4, thirtysecond: 1/8, sixtyfourth: 1/16}` for note occupancy and the same table without `full` for internal rest candidates. Reject every multiplication remainder.

- [ ] **Step 5: Implement occupancy and gap decomposition**

Implement `NotationRestTopologyBuilder.build(notes:totalMeasureCount:ticksPerMeasure:timeSignature:)` in this exact order:

1. Reject nonpositive measure/grid inputs with `[]`.
2. Normalize notes to in-range measure/tick values and group by `(measureIndex, voice, startTick)`.
3. Collapse a same-time chord to the longest exact duration; if any member is `nil`, mark the onset uncertain.
4. Clip each exact/uncertain onset at the next same-voice onset and the measure end.
5. Merge overlapping exact spans; preserve uncertain spans as hidden ranges.
6. Apply full-measure visibility policy before internal decomposition.
7. For active voices in X/4, walk gaps left to right and greedily choose the longest aligned exact duration.
8. For active voices in `/8`, emit hidden spacing for complements rather than visible internal rests.
9. Sort measure, upper-before-lower, start tick, duration case order, then visibility case order.

The greedy candidate table must be fixed and closed:

```swift
private let decompositionOrder: [NotationRestDuration] = [
    .half, .quarter, .eighth, .sixteenth, .thirtySecond, .sixtyFourth
]
```

For each gap, choose the first candidate whose exact tick count is positive, does not exceed the remainder, and satisfies `cursor.isMultiple(of: durationTicks)`. If none fits, emit one `.hiddenSpacing` event for the entire remainder and stop that gap. Never round, emit a dotted rest, or synthesize `.fullMeasure` inside an active voice.

- [ ] **Step 6: Run the topology suite and verify GREEN**

Run the command from Step 3.

Expected: every policy, coverage, `/8`, and shuffled-input case passes with no graphics or persistence imports in the new source file.

- [ ] **Step 7: Review and commit the topology**

```bash
rtk git diff --check
rtk git add Virgo/layout/NotationRestTopology.swift VirgoTests/NotationRestTopologyTests.swift
rtk git commit -m "feat: add voice-aware rest topology"
```

Expected review: the builder is geometry-free, controls are absent from its API, and there is no representable ordinary full-note rest case.

---

### Task 3: Add Render Contracts, Style Metrics, Catalog Labels, and Exact Tick Rescaling

**Files:**
- Modify: `Virgo/layout/NotationLayout.swift`
- Modify: `Virgo/layout/NotationLayoutEngine+TabGrid.swift`
- Modify: `Virgo/constants/DrumNotation.swift`
- Modify: `VirgoTests/NotationLayoutEngineTests.swift`
- Modify: `VirgoTests/DrumNotationCatalogTests.swift`

**Interfaces:**
- Extends `NotationLayoutInput` with source-compatible `controlEvents: []`.
- Adds `RenderedRest`, `RenderedStopNote`, `RenderedArticulation`, explicit predicates, and semantic labels.
- Adds style-owned rest/stop/articulation metrics and preserves them through `with(rowWidth:)`.
- Shares exact integer rescaling between notes and controls while retaining note-only rounded fallback.

- [ ] **Step 1: Write failing input, style, predicate, and label tests**

Add tests to `NotationLayoutEngineTests` that assert:

```swift
@Test("layout input defaults to no control events")
func layoutInputDefaultsToNoControls() {
    let input = NotationLayoutInput(notes: [], timeSignature: .fourFour)
    #expect(input.controlEvents.isEmpty)
}

@Test("row-width copy preserves all HPA-143 metrics")
func rowWidthCopyPreservesRestAndControlMetrics() {
    let style = NotationLayoutStyle.gameplayDefault
    let resized = style.with(rowWidth: 2_000)

    #expect(resized.restSymbolWidth == style.restSymbolWidth)
    #expect(resized.restSymbolHeight == style.restSymbolHeight)
    #expect(resized.fullMeasureRestWidth == style.fullMeasureRestWidth)
    #expect(resized.fullMeasureRestHeight == style.fullMeasureRestHeight)
    #expect(resized.upperVoiceRestOffset == style.upperVoiceRestOffset)
    #expect(resized.lowerVoiceRestOffset == style.lowerVoiceRestOffset)
    #expect(resized.stopMarkSize == style.stopMarkSize)
    #expect(resized.stopMarkStrokeWidth == style.stopMarkStrokeWidth)
    #expect(resized.stopMarkVerticalOffset == style.stopMarkVerticalOffset)
    #expect(resized.articulationDiameter == style.articulationDiameter)
    #expect(resized.articulationStrokeWidth == style.articulationStrokeWidth)
    #expect(resized.articulationVerticalOffset == style.articulationVerticalOffset)
}
```

Construct defensive `NotationLayout` values for each predicate:

- empty/hidden-only: neither predicate;
- notehead: both predicates;
- printed rest only: renderable but not playable;
- stop only: renderable but not playable;
- articulation only: neither predicate, because an articulation without its source head is malformed.

Assert labels exactly: `"Upper voice quarter rest"`, `"Lower voice full-measure rest"`, `"Choke Crash"`, `"Closed hi-hat"`, `"Open hi-hat"`, and `"Pedal hi-hat"`.

- [ ] **Step 2: Write failing catalog and exact-rescaling tests**

In `DrumNotationCatalogTests`, assert `resolveTarget(laneID: "1A")` returns the crash definition and display name `"Crash"`, lowercase lane input normalizes, and an unknown lane returns `nil`.

In `NotationLayoutEngineTests`, add direct exact-helper tests:

```swift
@Test("exact rescaling accepts divisible grids and rejects rounding")
func exactRescalingDoesNotRound() {
    let engine = NotationLayoutEngine()
    #expect(engine.exactRescaledTick(sourceTick: 1, sourceTicksPerMeasure: 4, targetTicksPerMeasure: 960) == 240)
    #expect(engine.exactRescaledTick(sourceTick: 1, sourceTicksPerMeasure: 7, targetTicksPerMeasure: 960) == nil)
    #expect(engine.exactRescaledTick(sourceTick: -1, sourceTicksPerMeasure: 4, targetTicksPerMeasure: 960) == nil)
    #expect(engine.exactRescaledTick(sourceTick: 5, sourceTicksPerMeasure: 4, targetTicksPerMeasure: 960) == nil)
}

@Test("notes retain rounded fallback when exact rescaling fails")
func notesRetainRoundedFallback() {
    let note = Note(
        interval: .quarter,
        noteType: .snare,
        measureNumber: 1,
        measureOffset: 1.0 / 7.0,
        normalizedTickWithinMeasure: 1,
        normalizedTicksPerMeasure: 7
    )
    #expect(NotationLayoutEngine().tickWithinMeasure(for: note, ticksPerMeasure: 960) == 137)
}
```

- [ ] **Step 3: Run focused contract suites and verify RED**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/NotationLayoutEngineTests -only-testing:VirgoTests/DrumNotationCatalogTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: compilation fails on the new input, style, rendered, predicate, catalog, and exact-rescaling APIs.

- [ ] **Step 4: Add input, style, and rendered contracts**

Extend `NotationLayoutInput` with `let controlEvents: [NotationControlEvent]` and an initializer argument defaulted to `[]` immediately after `notes`.

Add explicit scalar style fields with these defaults so row-width copies remain Equatable and mechanically complete:

```swift
restSymbolWidth: 18,
restSymbolHeight: 28,
fullMeasureRestWidth: 18,
fullMeasureRestHeight: 5,
upperVoiceRestOffset: -GameplayLayout.staffLineSpacing,
lowerVoiceRestOffset: GameplayLayout.staffLineSpacing,
stopMarkSize: 14,
stopMarkStrokeWidth: 2,
stopMarkVerticalOffset: 18,
articulationDiameter: 10,
articulationStrokeWidth: 1.5,
articulationVerticalOffset: 18
```

Copy all twelve fields unchanged in `with(rowWidth:)`.

Add `rests`, `stopNotes`, and `articulations` to `NotationLayout`, initialize all three to `[]` in `.empty`, and add:

```swift
var hasPlayableContent: Bool { !noteHeads.isEmpty }

var hasRenderableContent: Bool {
    hasPlayableContent || rests.contains(where: \.isPrinted) || !stopNotes.isEmpty
}
```

Define the rendered values with stable String IDs and stored semantic fields:

```swift
struct RenderedRest: Identifiable, Hashable {
    let id: String
    let timeColumn: NotationTimeColumn
    let measureIndex: Int
    let row: Int
    let voice: NotationVoice
    let durationTicks: Int
    let duration: NotationRestDuration
    let visibility: NotationRestVisibility
    let position: CGPoint

    var isPrinted: Bool { visibility == .printed }
    var accessibilityLabel: String {
        "\(voice.accessibilityName) voice \(duration.accessibilityName) rest"
    }
}

struct RenderedStopNote: Identifiable, Hashable {
    let id: String
    let kind: NotationControlEventKind
    let sourceLaneID: String?
    let sourceNoteID: String?
    let targetLaneID: String
    let targetDisplayName: String
    let timeColumn: NotationTimeColumn
    let row: Int
    let position: CGPoint

    var accessibilityLabel: String {
        "\(kind.rawValue.capitalized) \(targetDisplayName)"
    }
}

enum RenderedArticulationKind: String, Hashable {
    case openHiHat
}

struct RenderedArticulation: Identifiable, Hashable {
    let id: String
    let kind: RenderedArticulationKind
    let sourceNoteHeadID: UInt64
    let row: Int
    let position: CGPoint
}
```

Add small semantic-name switches: `NotationVoice.upper/lower` become `"Upper"`/`"Lower"`; rest durations become `"full-measure"`, `"half"`, `"quarter"`, `"eighth"`, `"sixteenth"`, `"thirty-second"`, and `"sixty-fourth"`. Add `RenderedNoteHead.accessibilityLabel` using explicit `closedHiHat`, `openHiHat`, and `pedalHiHat` overrides, falling back to `noteType.rawValue` for every other variant. Do not ask a SwiftUI view to resolve the catalog again.

- [ ] **Step 5: Add catalog target resolution and shared exact tick scaling**

In `DrumNotationCatalog`, add a small value return that preserves the definition and display name:

```swift
struct ResolvedDrumNotationTarget: Hashable {
    let definition: DrumNotationDefinition
    let laneID: String
    let displayName: String
}

static func resolveTarget(laneID: String) -> ResolvedDrumNotationTarget? {
    let normalizedLaneID = laneID.uppercased()
    guard let definition = definitions.first(where: {
        $0.lanes.contains(where: { $0.id == normalizedLaneID })
    }) else { return nil }
    return ResolvedDrumNotationTarget(
        definition: definition,
        laneID: normalizedLaneID,
        displayName: definition.noteType.rawValue
    )
}
```

In `NotationLayoutEngine+TabGrid.swift`, extract:

```swift
func exactRescaledTick(
    sourceTick: Int,
    sourceTicksPerMeasure: Int,
    targetTicksPerMeasure: Int
) -> Int? {
    guard sourceTick >= 0,
          sourceTicksPerMeasure > 0,
          targetTicksPerMeasure > 0,
          sourceTick <= sourceTicksPerMeasure,
          targetTicksPerMeasure.isMultiple(of: sourceTicksPerMeasure) else {
        return nil
    }
    return sourceTick * (targetTicksPerMeasure / sourceTicksPerMeasure)
}
```

Change the normalized note branch to call this helper first. Preserve its current `measureOffset` rounding fallback byte-for-byte when the helper returns `nil`; Task 5's control resolver will call only the exact helper.

- [ ] **Step 6: Run focused contract suites and verify GREEN**

Run the command from Step 3.

Expected: all contract tests pass, existing input call sites compile unchanged, and the rounded-note fallback still returns 137 for the 1/7 fixture.

- [ ] **Step 7: Review and commit the contracts**

```bash
rtk git diff --check
rtk git add Virgo/layout/NotationLayout.swift Virgo/layout/NotationLayoutEngine+TabGrid.swift Virgo/constants/DrumNotation.swift VirgoTests/NotationLayoutEngineTests.swift VirgoTests/DrumNotationCatalogTests.swift
rtk git commit -m "feat: add rest and control rendering contracts"
```

Expected review: `contentWidth` is unchanged, exact rescaling is shared, and only notes retain rounding.

---

### Task 4: Materialize Rest Topology in the Notation Engine

**Files:**
- Create: `Virgo/layout/NotationLayoutEngine+Rests.swift`
- Create: `VirgoTests/NotationLayoutRestAndControlTests.swift`
- Modify: `Virgo/layout/NotationLayoutEngine.swift`

**Interfaces:**
- Converts rendered noteheads to `RestTimelineNote` using exact `TabGrid` durations.
- Calls the pure builder after all existing HPA-140 through HPA-142 artifacts exist.
- Maps topology to stable, positioned `RenderedRest` values without changing measures or grid geometry.

- [ ] **Step 1: Write failing rest-layout integration tests**

Create `VirgoTests/NotationLayoutRestAndControlTests.swift` and add a `layout(notes:controls:minimumMeasureCount:style:)` helper. Cover:

- an empty one-measure input produces printed upper + hidden lower full-measure rests;
- an upper snare-only measure prints a lower full-measure rest;
- a lower kick-only measure prints an upper full-measure rest;
- two active voices receive independent internal rests;
- the full-measure rest x equals the rendered measure midpoint while its semantic tick remains zero;
- interval rests anchor to `TabGrid.xPosition` at `startTick`;
- upper and lower printed rests use distinct style-owned y baselines;
- hidden rests remain in `layout.rests` but do not make `isPrinted` true;
- adding rests leaves notehead, stem, beam, flag, ledger, bar, measure, grid, and content-width values unchanged for the same notes;
- shuffled notes yield identical rendered rest ordering and IDs.

Use a semantic ID assertion rather than accepting an opaque index:

```swift
#expect(rest.id.contains("m0"))
#expect(rest.id.contains("vupper"))
#expect(rest.id.contains("t0"))
#expect(rest.id.contains("dfullMeasure"))
#expect(rest.id.contains("xprinted"))
```

- [ ] **Step 2: Run the layout suite and verify RED**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/NotationLayoutRestAndControlTests -only-testing:VirgoTests/NotationRestTopologyTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: integration assertions fail because `NotationLayoutEngine` still returns no rests.

- [ ] **Step 3: Form exact rest timeline notes**

Create `NotationLayoutEngine+Rests.swift`. Convert `NoteInterval` to exact occupancy ticks through `NotationRestTopologyBuilder.noteDurationTicks`. `.full` is permitted for note occupancy but never maps to `NotationRestDuration`; clip its occupied span in the topology builder.

Build timeline notes from rendered noteheads only:

```swift
func buildRestTimelineNotes(
    noteHeads: [RenderedNoteHead],
    tabGrid: TabGrid,
    timeSignature: TimeSignature
) -> [RestTimelineNote] {
    noteHeads.map { head in
        RestTimelineNote(
            timeColumn: head.timeColumn,
            voice: head.voice,
            durationTicks: NotationRestTopologyBuilder().noteDurationTicks(
                for: head.interval,
                ticksPerMeasure: tabGrid.ticksPerMeasure,
                timeSignature: timeSignature
            )
        )
    }
}
```

Do not accept control events in this helper.

- [ ] **Step 4: Materialize topology into deterministic rest geometry**

Add `buildRests(noteHeads:measures:tabGrid:input:)` that invokes `NotationRestTopologyBuilder`. Resolve y from staff line 3 plus `upperVoiceRestOffset` or `lowerVoiceRestOffset`. Resolve x as:

- `.fullMeasure`: `measure.xOffset + measure.width / 2`;
- every interval or hidden range: `tabGrid.xPosition(in: measure, tickIndex: startTick)`.

Build the semantic base ID from measure, voice, start tick, duration ticks, duration, and visibility. Sort before ID assignment and append `-duplicate-N` only for exact duplicate semantic tuples. The first occurrence has ordinal 0 encoded as `-duplicate-0`; this keeps malformed duplicates fully explicit and stable.

- [ ] **Step 5: Insert rest derivation after existing artifacts**

In `NotationLayoutEngine.layout(input:)`, preserve steps 1–5 exactly, then call `buildRests` after `buildDerivedArtifacts`. Return `rests` while keeping Task 3's `stopNotes` and `articulations` empty until Task 5.

Do not pass rests into beam, stem, flag, ledger, bar, measure, grid, or content-width builders.

- [ ] **Step 6: Run topology and rest-layout suites and verify GREEN**

Run the command from Step 2.

Expected: pure and integrated rest tests pass; existing playable geometry comparisons are equal before/after rest materialization.

- [ ] **Step 7: Run existing notation regressions**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/NotationLayoutEngineTests -only-testing:VirgoTests/NotationLayoutEngineChordAndBeamTests -only-testing:VirgoTests/NotationBeamTopologyTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: HPA-140 through HPA-142 grid, head, stem, beam, hook, and flag suites pass unchanged.

- [ ] **Step 8: Review and commit rest integration**

```bash
rtk git diff --check
rtk git add Virgo/layout/NotationLayoutEngine.swift Virgo/layout/NotationLayoutEngine+Rests.swift VirgoTests/NotationLayoutRestAndControlTests.swift
rtk git commit -m "feat: render voice-aware notation rests"
```

Expected review: rest topology is the only source of visibility decisions and the layout extension only resolves geometry.

---

### Task 5: Resolve Controls and Open-Hi-Hat Articulations After the Grid

**Files:**
- Create: `Virgo/layout/NotationLayoutEngine+Controls.swift`
- Modify: `Virgo/layout/NotationLayoutEngine.swift`
- Modify: `VirgoTests/NotationLayoutRestAndControlTests.swift`

**Interfaces:**
- Validates control timing in two phases: semantic source timing for total measures, then exact projection to the existing `TabGrid` for geometry.
- Resolves targets through `DrumNotationCatalog` and active position overrides.
- Derives open-hi-hat circles only from rendered notehead variants.

- [ ] **Step 1: Write failing control timing and invariant tests**

Extend `NotationLayoutRestAndControlTests` with explicit authored `NotationControlEvent` fixtures and cover:

- `.stop`, `.choke`, and `.damp` remain semantically distinct while using the same plus-mark geometry;
- complete normalized timing takes precedence over `measureNumber`/`measureOffset`;
- normalized fields validate measure index, tick range, absolute tick consistency, and positive source resolution;
- any partially present normalized tuple is invalid rather than silently falling back;
- an all-nil normalized tuple may use manual timing only when `originKind == .manual` and the target grid column is exact;
- DTX-origin controls without complete normalized timing omit geometry;
- an exact 1/4 source tick maps to target tick 240 on a 960 grid;
- 1/7 source timing on a 960 grid contributes a valid measure but no rendered mark;
- invalid/inconsistent timing contributes neither a later measure nor geometry;
- a valid control in measure 3 raises `measures.count` to 3 without adding a notehead, stem, beam, flag, or playable rest onset;
- missing/unknown target lane preserves input data but omits geometry;
- target lane `1A` resolves to Crash and follows a `.crash` note-position override;
- controls never change grid resolution, tick width, measure width, wrapping, notehead positions, beams, flags, or `contentWidth` for an otherwise identical input.

- [ ] **Step 2: Write failing ID, duplicate, articulation, and accessibility tests**

Add tests for:

- sorted controls use measure, tick, kind, target lane, source lane, source ID, source grid position, and source grid size;
- shuffled input produces the same stop order and IDs;
- exact duplicate controls receive deterministic `duplicate-0`/`duplicate-1` suffixes;
- open-hi-hat notehead produces exactly one `.openHiHat` articulation;
- closed and pedal hi-hat variants produce none;
- articulation ID is exactly derived from kind + source notehead ID and excludes row/CGPoint;
- articulation position is the source head center shifted by style offset;
- open/closed/pedal notehead labels are distinct; the stop label includes exact kind and target display name.

- [ ] **Step 3: Run the integration suite and verify RED**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/NotationLayoutRestAndControlTests -only-testing:VirgoTests/DrumNotationCatalogTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: control/articulation cases fail because the engine still returns empty collections and ignores controls in total-measure calculation.

- [ ] **Step 4: Implement two-phase control timing validation**

Create `NotationLayoutEngine+Controls.swift` with a private semantic time value containing measure index, source tick, and source resolution. Apply these rules exactly:

1. If all four normalized fields are present, require nonnegative measure/absolute/tick, positive source resolution, `tick <= sourceResolution`, and `absolute == measure * sourceResolution + tick`.
2. If one to three normalized fields are present, return invalid.
3. If all four are absent, require `.manual`, `measureNumber >= 1`, finite `measureOffset` in `[0, 1]`, normalize an offset of exactly 1 to the next measure at tick 0, and retain the fractional offset for grid projection.
4. DTX-origin controls never use the manual fallback.

Use valid semantic timing to compute total measure count before building measures. A target-resolution failure or inexact target-grid projection does not erase a valid measure contribution.

For geometry, call `exactRescaledTick` for normalized events. For manual events, compute `scaled = offset * Double(tabGrid.ticksPerMeasure)` and accept only when `scaled.isFinite && scaled.rounded() == scaled`; never call the Note rounding helper.

- [ ] **Step 5: Resolve targets, geometry, diagnostics, and IDs**

Resolve `targetLaneID` with `DrumNotationCatalog.resolveTarget`. Derive the target staff position from `input.notePositionOverrides[definition.gameplayInstrument] ?? definition.defaultPosition`, then use the same staff-step conversion helper as noteheads. Place the plus mark above that lane by `stopMarkVerticalOffset`.

Aggregate invalid timing reasons, inexact-grid source resolutions, and unresolved target lane IDs in Sets and log each sorted set once at the end of the layout pass. Do not log inside SwiftUI rendering or once per frame.

Sort resolved controls by the approved semantic tuple and encode the same tuple into the ID. Append a deterministic duplicate ordinal for every exact duplicate.

- [ ] **Step 6: Derive open-hi-hat overlays from rendered heads**

Implement:

```swift
func buildArticulations(
    noteHeads: [RenderedNoteHead],
    style: NotationLayoutStyle
) -> [RenderedArticulation] {
    noteHeads
        .filter { $0.variant == .openHiHat }
        .map { head in
            RenderedArticulation(
                id: "openHiHat-head-\(head.id)",
                kind: .openHiHat,
                sourceNoteHeadID: head.id,
                row: head.row,
                position: CGPoint(
                    x: head.position.x,
                    y: head.position.y - style.articulationVerticalOffset
                )
            )
        }
        .sorted { $0.sourceNoteHeadID < $1.sourceNoteHeadID }
}
```

Do not expand `NormalizedArticulation` and do not re-resolve note type/lane in a view.

- [ ] **Step 7: Complete the engine ordering**

Update `NotationLayoutEngine.layout(input:)` to the approved ten-step order: notes, total measures, grid, measures/heads, existing artifacts, rest topology, rendered rests, rendered controls, articulations, return.

Return all three new collections. Confirm controls never enter `buildTabGrid` or `buildRests`.

- [ ] **Step 8: Run control/rest integration suites and verify GREEN**

Run the command from Step 3.

Expected: all timing, target, ID, duplicate, articulation, and grid-invariant tests pass.

- [ ] **Step 9: Run the existing notation regressions again**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/NotationLayoutEngineTests -only-testing:VirgoTests/NotationLayoutEngineChordAndBeamTests -only-testing:VirgoTests/NotationBeamTopologyTests -only-testing:VirgoTests/NotationRestTopologyTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: all existing and new notation suites pass with identical playable geometry.

- [ ] **Step 10: Review and commit controls/articulations**

```bash
rtk git diff --check
rtk git add Virgo/layout/NotationLayoutEngine.swift Virgo/layout/NotationLayoutEngine+Controls.swift VirgoTests/NotationLayoutRestAndControlTests.swift
rtk git commit -m "feat: render stop marks and drum articulations"
```

Expected review: no parser guess, no audio stop call, no score/input change, and no control-driven grid change.

---

### Task 6: Thread Immutable Controls Through Gameplay and Render Accessible Primitives

**Files:**
- Modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`
- Modify: `Virgo/views/NotationPrimitiveViews.swift`
- Modify: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Modify: `VirgoTests/GameplayViewModelDataLoadingTests.swift`
- Modify: `VirgoTests/GameplayViewModelComputationsTests.swift`
- Modify: `VirgoTests/GameplayViewModelVisualUpdatesTests.swift`
- Modify: `VirgoTests/SwiftUIRenderingCoverageTests.swift`

**Interfaces:**
- Converts `chart.controlEvents` to immutable snapshots in `loadChartData()`.
- Separates renderable notation geometry from playable gameplay motion at every former `!noteHeads.isEmpty` gate.
- Renders only printed rests, all resolved stops, and open-hi-hat overlays with semantic accessibility ownership.

- [ ] **Step 1: Write failing snapshot and activation tests**

In `GameplayViewModelDataLoadingTests`, add a chart with an explicit choke and assert `loadChartData()` fills `cachedControlEvents` with an immutable value. Mutate the source model afterward and assert the snapshot remains unchanged.

Add notation-only setup tests for an empty/rest-only chart and a control-only chart:

- `cachedNotationLayout.hasRenderableContent == true`;
- `cachedNotationLayout.hasPlayableContent == false`;
- notation measures/maps/staff background are populated;
- `cachedDrumBeats` and `cachedBeatPositions` are empty;
- `cachedNotationNoteHeadPositions` is empty.

Retain one playable-note case asserting both predicates and all existing playable caches are populated.

- [ ] **Step 2: Write failing playhead, row, and sheet-selection tests**

In `GameplayViewModelComputationsTests` and `GameplayViewModelVisualUpdatesTests`, cover:

- rest/control-only layouts return `nil` from `calculateNotationPurpleBarPosition` and `calculatePurpleBarPosition` even while `isPlaying` is true;
- they do not enter `cacheLegacyBeatPositions` after notation geometry is selected;
- `rowForMeasure` and playback updates do not advance `currentRow` for non-playable content;
- a playable layout retains current notation playhead alignment and row clamping.

In `SwiftUIRenderingCoverageTests`, update the existing sheet-sizing test so an empty/rest-only ViewModel now uses notation width/height/measures, while still having no playable content. Add a malformed truly empty `NotationLayout.empty` case for the legacy fallback.

- [ ] **Step 3: Write failing primitive and accessibility tests**

Construct and mount:

- one printed full-measure rest;
- one half, quarter, eighth, sixteenth, thirty-second, and sixty-fourth rest;
- one stop/choke/damp mark each;
- one open-hi-hat articulation circle.

Assert hidden rests are filtered before `NotationRestView` construction. Assert rendered semantic labels, distinct head labels, and `NotationArticulationView`'s accessibility-hidden contract. Add a geometry assertion that the highest supported open-hi-hat overlay remains inside `spacingAboveLine5(for:)`'s existing extra one-spacing margin.

- [ ] **Step 4: Run gameplay/rendering suites and verify RED**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/GameplayViewModelDataLoadingTests -only-testing:VirgoTests/GameplayViewModelComputationsTests -only-testing:VirgoTests/GameplayViewModelVisualUpdatesTests -only-testing:VirgoTests/SwiftUIRenderingCoverageTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: snapshot, activation, playhead, primitive, and accessibility tests fail against the notehead-only gameplay/view gates.

- [ ] **Step 5: Cache immutable controls and thread them into layout**

In `GameplayViewModel`, add:

```swift
/// Immutable control snapshots; views/layout never traverse the SwiftData relationship.
var cachedControlEvents: [NotationControlEvent] = []
```

In `loadChartData()`, read `chart.controlEvents` alongside `chart.notes` on the MainActor and immediately map each value through `NotationControlEvent.init`. Pass `cachedControlEvents` to `NotationLayoutInput` in `cacheNotationLayout()`.

Do not add controls to `cachedNotes`, `sortedNotesByTimePosition`, `InputManager.configure`, `ScoreEngine`, `cachedDrumBeats`, or missed-note scanning.

- [ ] **Step 6: Replace all content gates with the correct predicate**

Change render-geometry consumers in `GameplayViewModel+Computations.swift` from notehead emptiness to `hasRenderableContent`:

- cached measure-row map;
- cached measure lookup;
- notation measure-position map;
- cached notation staff background.

Keep playable consumers on `hasPlayableContent`:

- `cacheBeatPositions` chooses notation beat positions only for playable notation;
- if notation is renderable but not playable, leave `cachedBeatPositions` empty instead of calling `cacheLegacyBeatPositions`;
- cached notehead position map remains naturally empty for notation-only content.

In `GameplayViewModel+VisualUpdates.swift`, use `hasPlayableContent` for notation playhead, current-row advancement, and row clamping. `rowForMeasure` returns the existing `currentRow` when notation is renderable but not playable. Add an outer `hasRenderableContent` check before every legacy playhead/row fallback so renderable/non-playable layouts return no playhead and never enter legacy coordinates.

- [ ] **Step 7: Add vector primitives and semantic accessibility**

In `NotationPrimitiveViews.swift`:

- `NotationRestView` accepts `RenderedRest` plus style/size, draws a filled rectangle for full-measure/half, a fixed zig-zag for quarter, and a stem with 1/2/3/4 vector hooks for eighth through sixty-fourth;
- `NotationStopNoteView` draws two perpendicular stroked lines centered on `position` using `stopMarkSize` and `stopMarkStrokeWidth`;
- `NotationArticulationView` draws a stroked circle centered on `position` using articulation diameter/stroke and calls `.accessibilityHidden(true)`;
- `NotationNoteHeadView` adds `.accessibilityLabel(noteHead.accessibilityLabel)`;
- printed rest/stop views add their rendered semantic label;
- hidden rests never reach a view.

Keep these views geometry-only: no occupancy, tick, target-lane, catalog, or visibility decisions.

- [ ] **Step 8: Update sheet selection and layer order**

Change `usesNotationLayout(viewModel:)` to `cachedNotationLayout.hasRenderableContent`. Keep `spacingAboveLine5(for:)` notehead-specific and verify its existing one-spacing margin contains the open circle.

In `drumNotationView`, use this order inside its ZStack:

1. ledger lines;
2. printed rests only;
3. beams;
4. flags;
5. stems;
6. noteheads;
7. articulation circles;
8. stop marks.

Keep bar lines in the existing separate bar layer and the playhead in its existing outer overlay so both remain visible. Do not change `notationContentWidth(for:)`.

- [ ] **Step 9: Run gameplay/rendering suites and verify GREEN**

Run the command from Step 4.

Expected: all four selected suites pass; notation-only content renders using notation geometry and produces no gameplay motion.

- [ ] **Step 10: Run all focused HPA-143 suites**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/ChartControlEventTests -only-testing:VirgoTests/NotationRestTopologyTests -only-testing:VirgoTests/NotationLayoutRestAndControlTests -only-testing:VirgoTests/NotationLayoutEngineTests -only-testing:VirgoTests/DrumNotationCatalogTests -only-testing:VirgoTests/GameplayViewModelDataLoadingTests -only-testing:VirgoTests/GameplayViewModelComputationsTests -only-testing:VirgoTests/GameplayViewModelVisualUpdatesTests -only-testing:VirgoTests/SwiftUIRenderingCoverageTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: every selector executes nonzero tests and passes with zero failures.

- [ ] **Step 11: Run the full macOS unit suite**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -enableCodeCoverage YES -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected: `VirgoTests` passes with zero failures and no parallel test clones. If a focused selector ever reports zero tests, rerun its containing suite and treat zero execution as a failure.

- [ ] **Step 12: Run lint and platform builds sequentially**

```bash
rtk swiftlint lint
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build
rtk xcrun simctl list devices available
```

Choose an available iPad from the final command, then run exactly one iPad compatibility build, for example:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' build
```

Expected: lint introduces no new HPA-143 warnings; macOS and an available iPad simulator build succeed. Never substitute an iPhone destination.

- [ ] **Step 13: Verify scope, review the whole branch, and commit**

```bash
rtk rg -n "ChartControlEvent.self" Virgo VirgoTests --glob '*.swift'
rtk rg -n "hasRenderableContent|hasPlayableContent|noteHeads.isEmpty" Virgo/viewmodels Virgo/views/subviews/GameplaySheetMusicView.swift --glob '*.swift'
rtk rg -n "AVAudioPlayer\.stop|\.stop\(\)" Virgo/layout Virgo/models/ChartControlEvent.swift
rtk git diff --check
rtk git status --short
```

Expected:

- the seven explicit schema roots include `ChartControlEvent.self`;
- every former notehead-only production gate has an intentional renderable/playable classification;
- no HPA-143 layout/model file adds audio stopping;
- only the files in this plan are modified;
- `ChartRelationshipData`, `ChartRelationshipLoader`, DTX parsing, scoring, input matching, and persistence scoring remain unchanged.

Commit:

```bash
rtk git add Virgo/viewmodels/GameplayViewModel.swift Virgo/viewmodels/GameplayViewModel+Computations.swift Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift Virgo/views/NotationPrimitiveViews.swift Virgo/views/subviews/GameplaySheetMusicView.swift VirgoTests/GameplayViewModelDataLoadingTests.swift VirgoTests/GameplayViewModelComputationsTests.swift VirgoTests/GameplayViewModelVisualUpdatesTests.swift VirgoTests/SwiftUIRenderingCoverageTests.swift
rtk git commit -m "feat: render accessible rests and control marks"
```

Expected whole-branch review package:

- review Task 1 through Task 6 commits individually;
- compare the full branch against the approved HPA-143 design spec;
- report any stale or already-satisfied finding instead of editing unrelated code;
- if review finds a real gap, apply the smallest test-first fix, rerun the affected focused suite, then rerun the full macOS unit suite before completion.

---

## Final Acceptance Checklist

- [ ] Persisted controls round-trip, copy independently, cascade with Chart, and appear in all seven explicit schemas.
- [ ] The pure rest topology owns all voice occupancy, visibility, decomposition, uncertainty, and deterministic ordering decisions.
- [ ] Ordinary full-note rests are unrepresentable; full-measure silence is a separate semantic case.
- [ ] Controls do not affect rest occupancy, grid construction, playable layout, scoring, input, playback, or audio.
- [ ] Notes and controls share exact tick rescaling, but only notes retain rounded fallback.
- [ ] Rest/control/articulation geometry is derived after existing measure/note/beam/stem/flag/bar geometry.
- [ ] Stop IDs use the full semantic tuple plus duplicate ordinal; articulation IDs use kind + source notehead only.
- [ ] Open/closed/pedal hi-hats remain semantically and accessibly distinct.
- [ ] Printed rests and stops are accessible; hidden rests and the decorative open circle are hidden.
- [ ] Rest/control-only layouts render notation measures, bars, sizes, and staff backgrounds without playhead, beat cache, current-row advancement, or scrolling.
- [ ] Playable charts retain current playhead alignment and every HPA-140 through HPA-142 invariant.
- [ ] `contentWidth` remains unchanged because every new primitive stays within the final bar allowance.
- [ ] Focused suites, full `VirgoTests`, SwiftLint, macOS build, and an available iPad simulator build all complete sequentially.
