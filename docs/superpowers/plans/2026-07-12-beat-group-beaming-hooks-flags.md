# Beat-Group Beaming, Hooks, Flags, and Tails Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Virgo's proximity-based beam renderer with deterministic 4/4 beat groups, explicit primary-group topology, partial hooks, and isolated-note flags.

**Architecture:** Add a pure `NotationBeamTopologyBuilder` that consumes canonical timeline events and returns ordered primary groups plus per-event beam-level coverage. `NotationLayoutEngine+Beams.swift` will form events from rendered noteheads, materialize flat full/hook segments from the topology, and use the topology coverage to drive stems and flags without changing notehead, grid, playhead, scoring, or persistence behavior.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Testing, Core Graphics geometry, Xcode 16+/`xcodebuild`, SwiftLint.

## Global Constraints

- Implement rhythm-aware grouping only for 4/4; unsupported meters render individual flags and remain HPA-145 scope.
- Never beam across a quarter-beat, measure, row, voice, stem-direction, non-beamable boundary, invalid duration, or rhythmic gap.
- Keep beams flat; do not add sloped, feathered, cross-staff, tremolo, rest-aware, tuplet, dotted, swing, or variable-measure behavior.
- Use canonical integer `NotationTimeColumn` ticks only; remove every floating-time proximity and tolerance decision.
- Use a style-owned 12-point maximum hook length and cap each hook at half its neighbor distance.
- Keep HPA-141 notehead centers, catalog identity, glyph geometry, stem anchors, and voice-first semantics unchanged.
- Do not change SwiftData, parser, scoring, input, playback, playhead, wrapping, row scrolling, or public persistence contracts.
- Use Swift Testing (`import Testing`), not XCTest, for unit tests.
- Run every `xcodebuild test` with `-parallel-testing-enabled NO`; use macOS for unit tests.
- Any iOS-family build must use an available iPad simulator; never target iPhone and never change `TARGETED_DEVICE_FAMILY = 2`.
- Prefix all shell commands with `rtk`.
- The Xcode project uses file-system-synchronized root groups; do not edit `Virgo.xcodeproj/project.pbxproj` for the new source or test files.

---

## File Structure

- Create `Virgo/layout/NotationBeamTopology.swift`: geometry-free timeline-event, primary-group, segment, coverage, and builder types.
- Create `VirgoTests/NotationBeamTopologyTests.swift`: pure topology behavior and fallback tests.
- Modify `Virgo/layout/NotationLayout.swift`: add `RenderedBeam.kind` and `NotationLayoutStyle.beamHookLength` with row-width copying.
- Modify `Virgo/layout/NotationLayoutEngine.swift`: thread `TabGrid` and meter through beam construction and consume `BeamBuildResult`.
- Modify `Virgo/layout/NotationLayoutEngine+Beams.swift`: canonical event formation, topology integration, segment geometry, coverage-driven flags, hook-aware stem ends, and deterministic sorting.
- Modify `Virgo/constants/Drum.swift`: remove the obsolete `BeamGroupingConstants` type.
- Modify `VirgoTests/NotationLayoutEngineChordAndBeamTests.swift`: beat, hook, boundary, baseline, geometry, and fixture-migration coverage.
- Modify `VirgoTests/NotationLayoutEngineTests.swift`: style propagation, isolated flags, unsupported-meter fallback, and shuffled-input determinism.
- Modify `VirgoTests/NotationLayoutDefensiveGuardTests.swift`: explicit full/hook kinds and hook-aware `beamEndY` guards.
- Modify `VirgoTests/DrumTypeExtensionsAndConstantsTests.swift`: remove the obsolete proximity-threshold test.
- Modify `VirgoTests/SwiftUIRenderingCoverageTests.swift`: make direct beam segment kinds explicit.

---

### Task 1: Build the Pure Beam Topology

**Files:**
- Create: `Virgo/layout/NotationBeamTopology.swift`
- Create: `VirgoTests/NotationBeamTopologyTests.swift`

**Interfaces:**
- Consumes: `NotationTimeColumn`, `NotationVoice`, `StemDirection`, and `TimeSignature` from existing Virgo models.
- Produces: `BeamTimelineEventRole`, `BeamTimelineEvent`, `BeamSegmentKind`, `BeamTopologySegment`, `BeamPrimaryGroupID`, `BeamPrimaryGroup`, `BeamTopologyResult`, and `NotationBeamTopologyBuilder.build(events:ticksPerMeasure:timeSignature:)`.

- [ ] **Step 1: Write failing pure-topology tests**

Create `VirgoTests/NotationBeamTopologyTests.swift` with the canonical helper and first behavior set:

```swift
import Testing
@testable import Virgo

@Suite("Notation Beam Topology Tests")
struct NotationBeamTopologyTests {
    private let builder = NotationBeamTopologyBuilder()

    private func event(
        tick: Int,
        levels: Int,
        durationTicks: Int?,
        row: Int = 0,
        voice: NotationVoice = .upper,
        direction: StemDirection = .up,
        noteHeadID: UInt64
    ) -> BeamTimelineEvent {
        BeamTimelineEvent(
            timeColumn: NotationTimeColumn(
                measureIndex: 0,
                tickWithinMeasure: tick,
                absoluteLayoutTick: tick
            ),
            row: row,
            voice: voice,
            stemDirection: direction,
            noteHeadIDs: [noteHeadID],
            role: .beamable(
                requiredBeamLevels: levels,
                durationTicks: durationTicks
            )
        )
    }

    private func boundary(
        tick: Int,
        noteHeadID: UInt64,
        direction: StemDirection = .up
    ) -> BeamTimelineEvent {
        BeamTimelineEvent(
            timeColumn: NotationTimeColumn(
                measureIndex: 0,
                tickWithinMeasure: tick,
                absoluteLayoutTick: tick
            ),
            row: 0,
            voice: .upper,
            stemDirection: direction,
            noteHeadIDs: [noteHeadID],
            role: .boundary
        )
    }

    @Test("Four contiguous sixteenths create one two-level primary group")
    func fourSixteenthsCreateTwoLevels() throws {
        let events = (0..<4).map {
            event(
                tick: $0 * 60,
                levels: 2,
                durationTicks: 60,
                noteHeadID: UInt64($0)
            )
        }

        let result = builder.build(
            events: events,
            ticksPerMeasure: 960,
            timeSignature: .fourFour
        )

        let group = try #require(result.primaryGroups.first)
        #expect(result.primaryGroups.count == 1)
        #expect(group.eventIndices == [0, 1, 2, 3])
        #expect(group.segments.map(\.level) == [0, 1])
        #expect(group.segments.allSatisfy { $0.kind == .full })
        for index in 0..<4 {
            #expect(result.coveredLevelsByEventIndex[index] == [0, 1])
        }
    }

    @Test("Sixteenth followed by eighth creates a forward secondary hook")
    func mixedDurationsCreateForwardHook() throws {
        let events = [
            event(tick: 0, levels: 2, durationTicks: 60, noteHeadID: 1),
            event(tick: 60, levels: 1, durationTicks: 120, noteHeadID: 2)
        ]

        let result = builder.build(
            events: events,
            ticksPerMeasure: 960,
            timeSignature: .fourFour
        )
        let group = try #require(result.primaryGroups.first)
        let hook = try #require(group.segments.first { $0.level == 1 })

        #expect(hook.kind == .forwardHook)
        #expect(hook.eventIndices == [0])
        #expect(hook.hookNeighborIndex == 1)
        #expect(result.coveredLevelsByEventIndex[0] == [0, 1])
        #expect(result.coveredLevelsByEventIndex[1] == [0])
    }

    @Test("Stemless boundary splits an otherwise contiguous run")
    func boundarySplitsRun() {
        let events = [
            event(tick: 0, levels: 2, durationTicks: 60, noteHeadID: 1),
            boundary(tick: 30, noteHeadID: 2),
            event(tick: 60, levels: 2, durationTicks: 60, noteHeadID: 3)
        ]

        let result = builder.build(
            events: events,
            ticksPerMeasure: 960,
            timeSignature: .fourFour
        )

        #expect(result == BeamTopologyResult.empty)
    }

    @Test("Direction is a primary grouping boundary")
    func directionSeparatesGroups() {
        let events = [
            event(tick: 0, levels: 1, durationTicks: 120, noteHeadID: 1),
            event(
                tick: 120,
                levels: 1,
                durationTicks: 120,
                direction: .down,
                noteHeadID: 2
            )
        ]

        let result = builder.build(
            events: events,
            ticksPerMeasure: 960,
            timeSignature: .fourFour
        )

        #expect(result == BeamTopologyResult.empty)
    }

    @Test("Unsupported meter returns no topology coverage")
    func unsupportedMeterFallsBack() {
        let events = [
            event(tick: 0, levels: 1, durationTicks: 120, noteHeadID: 1),
            event(tick: 120, levels: 1, durationTicks: 120, noteHeadID: 2)
        ]

        let result = builder.build(
            events: events,
            ticksPerMeasure: 960,
            timeSignature: .sixEight
        )

        #expect(result == BeamTopologyResult.empty)
    }
}
```

- [ ] **Step 2: Run the focused suite and verify the RED state**

Run:

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/NotationBeamTopologyTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: build fails because the topology types and builder do not exist.

- [ ] **Step 3: Implement the geometry-free topology types and builder**

Create `Virgo/layout/NotationBeamTopology.swift` with these public-to-module contracts and helpers:

```swift
enum BeamTimelineEventRole: Hashable {
    case beamable(requiredBeamLevels: Int, durationTicks: Int?)
    case boundary

    var requiredBeamLevels: Int {
        if case let .beamable(levels, _) = self { return levels }
        return 0
    }

    var durationTicks: Int? {
        if case let .beamable(_, durationTicks) = self { return durationTicks }
        return nil
    }
}

struct BeamTimelineEvent: Hashable {
    let timeColumn: NotationTimeColumn
    let row: Int
    let voice: NotationVoice
    let stemDirection: StemDirection
    let noteHeadIDs: [UInt64]
    let role: BeamTimelineEventRole
}

enum BeamSegmentKind: String, Hashable {
    case full
    case forwardHook
    case backwardHook
}

struct BeamTopologySegment: Hashable {
    let level: Int
    let kind: BeamSegmentKind
    let eventIndices: [Int]
    let hookNeighborIndex: Int?
}

struct BeamPrimaryGroupID: Hashable {
    let measureIndex: Int
    let row: Int
    let voice: NotationVoice
    let stemDirection: StemDirection
    let beatGroupIndex: Int
    let firstAbsoluteTick: Int
    let lastAbsoluteTick: Int
}

struct BeamPrimaryGroup: Hashable {
    let id: BeamPrimaryGroupID
    let eventIndices: [Int]
    let segments: [BeamTopologySegment]
}

struct BeamTopologyResult: Equatable {
    let primaryGroups: [BeamPrimaryGroup]
    let coveredLevelsByEventIndex: [Int: Set<Int>]

    static let empty = BeamTopologyResult(
        primaryGroups: [],
        coveredLevelsByEventIndex: [:]
    )
}

struct NotationBeamTopologyBuilder {
    private struct GroupKey: Hashable {
        let measureIndex: Int
        let row: Int
        let voice: NotationVoice
        let direction: StemDirection
        let beatGroupIndex: Int
    }

    func build(
        events: [BeamTimelineEvent],
        ticksPerMeasure: Int,
        timeSignature: TimeSignature
    ) -> BeamTopologyResult {
        guard timeSignature == .fourFour,
              ticksPerMeasure > 0,
              ticksPerMeasure.isMultiple(of: 4) else {
            return .empty
        }

        let beatTicks = ticksPerMeasure / 4
        var grouped: [GroupKey: [Int]] = [:]
        for (index, event) in events.enumerated() {
            let tick = event.timeColumn.tickWithinMeasure
            guard tick >= 0, tick < ticksPerMeasure else { continue }
            let key = GroupKey(
                measureIndex: event.timeColumn.measureIndex,
                row: event.row,
                voice: event.voice,
                direction: event.stemDirection,
                beatGroupIndex: tick / beatTicks
            )
            grouped[key, default: []].append(index)
        }

        let orderedKeys = grouped.keys.sorted(by: groupKeyComesBefore)
        var primaryGroups: [BeamPrimaryGroup] = []
        var coverage: [Int: Set<Int>] = [:]

        for key in orderedKeys {
            let indices = (grouped[key] ?? []).sorted {
                eventComesBefore(events[$0], events[$1])
            }
            for run in primaryRuns(indices: indices, events: events) {
                let group = makePrimaryGroup(
                    key: key,
                    run: run,
                    events: events,
                    beatTicks: beatTicks
                )
                primaryGroups.append(group)
                for segment in group.segments {
                    let coveredIndices = segment.kind == .full
                        ? segment.eventIndices
                        : Array(segment.eventIndices.prefix(1))
                    for index in coveredIndices {
                        coverage[index, default: []].insert(segment.level)
                    }
                }
            }
        }

        return BeamTopologyResult(
            primaryGroups: primaryGroups,
            coveredLevelsByEventIndex: coverage
        )
    }

    private func primaryRuns(
        indices: [Int],
        events: [BeamTimelineEvent]
    ) -> [[Int]] {
        var runs: [[Int]] = []
        var current: [Int] = []

        func flush() {
            if current.count >= 2 { runs.append(current) }
            current = []
        }

        for index in indices {
            guard case let .beamable(levels, duration?) = events[index].role,
                  levels > 0,
                  duration > 0 else {
                flush()
                continue
            }
            if let previous = current.last,
               let previousDuration = events[previous].role.durationTicks,
               events[index].timeColumn.absoluteLayoutTick
                == events[previous].timeColumn.absoluteLayoutTick + previousDuration {
                current.append(index)
            } else {
                flush()
                current = [index]
            }
        }
        flush()
        return runs
    }

    private func makePrimaryGroup(
        key: GroupKey,
        run: [Int],
        events: [BeamTimelineEvent],
        beatTicks: Int
    ) -> BeamPrimaryGroup {
        let firstTick = events[run[0]].timeColumn.absoluteLayoutTick
        let lastTick = events[run[run.count - 1]].timeColumn.absoluteLayoutTick
        var segments = [BeamTopologySegment(
            level: 0,
            kind: .full,
            eventIndices: run,
            hookNeighborIndex: nil
        )]
        let maximumLevel = run.map { events[$0].role.requiredBeamLevels }.max() ?? 1

        if maximumLevel > 1 {
            for level in 1..<maximumLevel {
                var eligiblePositions: [Int] = []
                func flushEligible() {
                    guard !eligiblePositions.isEmpty else { return }
                    let eligibleIndices = eligiblePositions.map { run[$0] }
                    if eligibleIndices.count >= 2 {
                        segments.append(BeamTopologySegment(
                            level: level,
                            kind: .full,
                            eventIndices: eligibleIndices,
                            hookNeighborIndex: nil
                        ))
                    } else if let position = eligiblePositions.first {
                        let neighborPosition = hookNeighborPosition(
                            ownerPosition: position,
                            run: run,
                            events: events,
                            key: key,
                            beatTicks: beatTicks
                        )
                        let ownerIndex = run[position]
                        let neighborIndex = run[neighborPosition]
                        let kind: BeamSegmentKind = events[neighborIndex]
                            .timeColumn.absoluteLayoutTick
                            > events[ownerIndex].timeColumn.absoluteLayoutTick
                            ? .forwardHook : .backwardHook
                        segments.append(BeamTopologySegment(
                            level: level,
                            kind: kind,
                            eventIndices: [ownerIndex],
                            hookNeighborIndex: neighborIndex
                        ))
                    }
                    eligiblePositions = []
                }

                for position in run.indices {
                    if events[run[position]].role.requiredBeamLevels > level {
                        eligiblePositions.append(position)
                    } else {
                        flushEligible()
                    }
                }
                flushEligible()
            }
        }

        return BeamPrimaryGroup(
            id: BeamPrimaryGroupID(
                measureIndex: key.measureIndex,
                row: key.row,
                voice: key.voice,
                stemDirection: key.direction,
                beatGroupIndex: key.beatGroupIndex,
                firstAbsoluteTick: firstTick,
                lastAbsoluteTick: lastTick
            ),
            eventIndices: run,
            segments: segments
        )
    }

    private func hookNeighborPosition(
        ownerPosition: Int,
        run: [Int],
        events: [BeamTimelineEvent],
        key: GroupKey,
        beatTicks: Int
    ) -> Int {
        if ownerPosition == run.startIndex { return ownerPosition + 1 }
        if ownerPosition == run.index(before: run.endIndex) { return ownerPosition - 1 }

        let ownerTick = events[run[ownerPosition]].timeColumn.tickWithinMeasure
        let previousTick = events[run[ownerPosition - 1]].timeColumn.tickWithinMeasure
        let nextTick = events[run[ownerPosition + 1]].timeColumn.tickWithinMeasure
        let previousDistance = ownerTick - previousTick
        let nextDistance = nextTick - ownerTick
        if previousDistance != nextDistance {
            return previousDistance < nextDistance ? ownerPosition - 1 : ownerPosition + 1
        }
        let beatMidpoint = key.beatGroupIndex * beatTicks + beatTicks / 2
        return ownerTick < beatMidpoint ? ownerPosition + 1 : ownerPosition - 1
    }

    private func groupKeyComesBefore(_ lhs: GroupKey, _ rhs: GroupKey) -> Bool {
        if lhs.measureIndex != rhs.measureIndex {
            return lhs.measureIndex < rhs.measureIndex
        }
        if lhs.row != rhs.row { return lhs.row < rhs.row }
        if lhs.voice.rawValue != rhs.voice.rawValue {
            return lhs.voice.rawValue < rhs.voice.rawValue
        }
        if lhs.direction.rawValue != rhs.direction.rawValue {
            return lhs.direction.rawValue < rhs.direction.rawValue
        }
        return lhs.beatGroupIndex < rhs.beatGroupIndex
    }

    private func eventComesBefore(
        _ lhs: BeamTimelineEvent,
        _ rhs: BeamTimelineEvent
    ) -> Bool {
        if lhs.timeColumn.absoluteLayoutTick != rhs.timeColumn.absoluteLayoutTick {
            return lhs.timeColumn.absoluteLayoutTick < rhs.timeColumn.absoluteLayoutTick
        }
        return lhs.noteHeadIDs.lexicographicallyPrecedes(rhs.noteHeadIDs)
    }
}
```

- [ ] **Step 4: Run the pure suite and verify GREEN**

Run the command from Step 2.

Expected: `NotationBeamTopologyTests` passes with zero failures.

- [ ] **Step 5: Commit the pure topology**

```bash
rtk git add Virgo/layout/NotationBeamTopology.swift VirgoTests/NotationBeamTopologyTests.swift
rtk git commit -m "feat: add beat-scoped beam topology"
```

---

### Task 2: Add Explicit Render and Style Contracts

**Files:**
- Modify: `Virgo/layout/NotationLayout.swift:71-119,218-226`
- Modify: `Virgo/layout/NotationLayoutEngine+Beams.swift:341-350`
- Modify: `VirgoTests/NotationLayoutEngineTests.swift`
- Modify: `VirgoTests/NotationLayoutDefensiveGuardTests.swift:60-68`
- Modify: `VirgoTests/SwiftUIRenderingCoverageTests.swift:214-222,333-341`

**Interfaces:**
- Consumes: `BeamSegmentKind` from Task 1.
- Produces: `NotationLayoutStyle.beamHookLength`, `RenderedBeam.kind`, and explicit test construction for all segment kinds.

- [ ] **Step 1: Add failing style and render-contract assertions**

Add this Swift Testing case to `NotationLayoutEngineTests.swift`:

```swift
@Test("row-width style copy preserves hook length")
func rowWidthStyleCopyPreservesHookLength() {
    let style = NotationLayoutStyle.gameplayDefault
    let resized = style.with(rowWidth: 2_000)

    #expect(style.beamHookLength == 12)
    #expect(resized.beamHookLength == style.beamHookLength)
    #expect(resized.rowWidth == 2_000)
}
```

Add `kind: .full` to the existing defensive `RenderedBeam` initializer, `kind: .forwardHook` to the one-notehead SwiftUI probe, and `kind: .full` to the two-notehead SwiftUI beam probe.

Add `kind: .full` to the proximity-era production `RenderedBeam` initializer in `NotationLayoutEngine+Beams.swift`; Task 3 will replace that constructor with topology materialization.

- [ ] **Step 2: Run focused tests and verify the RED state**

Run:

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/NotationLayoutEngineTests -only-testing:VirgoTests/NotationLayoutDefensiveGuardTests -only-testing:VirgoTests/SwiftUIRenderingCoverageTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: compile fails because `beamHookLength` and `RenderedBeam.kind` are not defined.

- [ ] **Step 3: Add the style and rendered-segment fields**

Modify `NotationLayoutStyle` in `Virgo/layout/NotationLayout.swift`:

```swift
struct NotationLayoutStyle: Equatable {
    let minimumNoteColumnGap: CGFloat
    let minimumQuarterBeatGap: CGFloat
    let rowWidth: CGFloat
    let staffLineSpacing: CGFloat
    let noteHeadWidth: CGFloat
    let noteHeadHeight: CGFloat
    let stemLength: CGFloat
    let stemWidth: CGFloat
    let minimumStemExtensionPastChord: CGFloat
    let beamThickness: CGFloat
    let beamLevelSpacing: CGFloat
    let beamHookLength: CGFloat
    let ledgerLineOverhang: CGFloat

    var noteHeadSize: CGSize {
        CGSize(width: noteHeadWidth, height: noteHeadHeight)
    }

    static let gameplayDefault = NotationLayoutStyle(
        minimumNoteColumnGap: 28,
        minimumQuarterBeatGap: GameplayLayout.uniformSpacing,
        rowWidth: GameplayLayout.maxRowWidth,
        staffLineSpacing: GameplayLayout.staffLineSpacing,
        noteHeadWidth: GameplayLayout.beatColumnWidth,
        noteHeadHeight: GameplayLayout.drumSymbolFontSize,
        stemLength: GameplayLayout.stemHeight,
        stemWidth: GameplayLayout.stemWidth,
        minimumStemExtensionPastChord: GameplayLayout.staffLineSpacing / 2,
        beamThickness: 4,
        beamLevelSpacing: GameplayLayout.beamLevelSpacing,
        beamHookLength: 12,
        ledgerLineOverhang: 6
    )

    func with(rowWidth newRowWidth: CGFloat) -> NotationLayoutStyle {
        NotationLayoutStyle(
            minimumNoteColumnGap: minimumNoteColumnGap,
            minimumQuarterBeatGap: minimumQuarterBeatGap,
            rowWidth: newRowWidth,
            staffLineSpacing: staffLineSpacing,
            noteHeadWidth: noteHeadWidth,
            noteHeadHeight: noteHeadHeight,
            stemLength: stemLength,
            stemWidth: stemWidth,
            minimumStemExtensionPastChord: minimumStemExtensionPastChord,
            beamThickness: beamThickness,
            beamLevelSpacing: beamLevelSpacing,
            beamHookLength: beamHookLength,
            ledgerLineOverhang: ledgerLineOverhang
        )
    }
}
```

Modify `RenderedBeam` without giving `kind` a default:

```swift
struct RenderedBeam: Identifiable, Hashable {
    let id: String
    let noteHeadIDs: [UInt64]
    let direction: StemDirection
    let level: Int
    let kind: BeamSegmentKind
    let start: CGPoint
    let end: CGPoint
    let thickness: CGFloat
}
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run the command from Step 2.

Expected: all three focused suites pass.

- [ ] **Step 5: Commit the render/style contract**

```bash
rtk git add Virgo/layout/NotationLayout.swift Virgo/layout/NotationLayoutEngine+Beams.swift VirgoTests/NotationLayoutEngineTests.swift VirgoTests/NotationLayoutDefensiveGuardTests.swift VirgoTests/SwiftUIRenderingCoverageTests.swift
rtk git commit -m "feat: add beam hook rendering contracts"
```

---

### Task 3: Integrate Topology With Layout, Stems, Hooks, and Flags

**Files:**
- Modify: `Virgo/layout/NotationLayoutEngine.swift:22-39`
- Modify: `Virgo/layout/NotationLayoutEngine+Beams.swift`
- Modify: `VirgoTests/NotationLayoutEngineChordAndBeamTests.swift`
- Modify: `VirgoTests/NotationLayoutEngineTests.swift`
- Modify: `VirgoTests/NotationLayoutDefensiveGuardTests.swift`

**Interfaces:**
- Consumes: every topology and rendering contract from Tasks 1-2.
- Produces: `BeamBuildResult`, direction-aware `StemGroupKey`, `buildTimelineEvents(noteHeads:ticksPerMeasure:)`, `buildBeams(noteHeads:tabGrid:timeSignature:style:)`, topology-driven `buildFlags`, hook-aware `beamEndY`, shared primary-group baselines, and deterministic rendered segment IDs/order.

- [ ] **Step 1: Add failing layout integration tests**

Add these focused tests to `NotationLayoutEngineChordAndBeamTests.swift`:

```swift
@Test("full 4/4 sixteenth run creates four two-level beat groups")
func fullSixteenthRunIsBeatScoped() {
    let notes = (0..<16).map {
        Note(
            interval: .sixteenth,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: Double($0) / 16.0
        )
    }
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )

    #expect(layout.beams.filter { $0.level == 0 && $0.kind == .full }.count == 4)
    #expect(layout.beams.filter { $0.level == 1 && $0.kind == .full }.count == 4)
    #expect(layout.flags.isEmpty)
}

@Test("mixed sixteenth and eighth use a forward hook without flags")
func mixedDurationsRenderForwardHook() throws {
    let notes = [
        Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
        Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 16.0)
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )

    let hook = try #require(layout.beams.first { $0.level == 1 })
    #expect(hook.kind == .forwardHook)
    #expect(hook.noteHeadIDs.count == 1)
    #expect(hook.end.x > hook.start.x)
    #expect(hook.end.x - hook.start.x <= 12)
    #expect(layout.flags.isEmpty)
}

@Test("stemless boundary prevents adjacent flagged notes from beaming")
func stemlessBoundaryBreaksLayoutRun() {
    let notes = [
        Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
        Note(interval: .half, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 32.0),
        Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 16.0)
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )

    #expect(layout.beams.isEmpty)
    #expect(layout.flags.count == 4)
}
```

Add direct guard tests to `NotationLayoutDefensiveGuardTests.swift`:

```swift
@Test("beamEndY accepts a single-notehead hook owner")
func beamEndYAcceptsSingleOwnerHook() throws {
    let noteHead = makeDefensiveNoteHead(id: 1, x: 20)
    let hook = RenderedBeam(
        id: "hook-defensive-test",
        noteHeadIDs: [1],
        direction: .up,
        level: 1,
        kind: .forwardHook,
        start: CGPoint(x: 20, y: 40),
        end: CGPoint(x: 30, y: 40),
        thickness: 4
    )

    let result = NotationLayoutEngine().beamEndY(
        for: noteHead,
        beam: hook,
        style: .gameplayDefault
    )
    #expect(result == 40)
}

@Test("beamEndY rejects a malformed single-notehead full segment")
func beamEndYRejectsMalformedSingleOwnerFullBeam() {
    let noteHead = makeDefensiveNoteHead(id: 1, x: 20)
    let beam = RenderedBeam(
        id: "full-defensive-test",
        noteHeadIDs: [1],
        direction: .up,
        level: 0,
        kind: .full,
        start: CGPoint(x: 20, y: 40),
        end: CGPoint(x: 30, y: 40),
        thickness: 4
    )

    #expect(
        NotationLayoutEngine().beamEndY(
            for: noteHead,
            beam: beam,
            style: .gameplayDefault
        ) == nil
    )
}
```

Extract the existing hand-built defensive notehead into a private `makeDefensiveNoteHead(id:x:)` helper so the old out-of-span test and both new tests share exactly the same construction.

```swift
private func makeDefensiveNoteHead(
    id: UInt64,
    x: CGFloat
) -> RenderedNoteHead {
    let note = Note(
        interval: .sixteenth,
        noteType: .snare,
        measureNumber: 1,
        measureOffset: 0
    )
    return RenderedNoteHead(
        id: id,
        sourceObjectID: ObjectIdentifier(note),
        sourceLaneID: nil,
        sourceChipID: nil,
        noteType: .snare,
        drumType: .snare,
        glyph: .filledDiamond,
        variant: .standard,
        voice: .upper,
        stemDirection: .up,
        timeColumn: NotationTimeColumn(
            measureIndex: 0,
            tickWithinMeasure: 0,
            absoluteLayoutTick: 0
        ),
        timePosition: 0,
        row: 0,
        position: CGPoint(x: x, y: 100),
        staffStep: -4,
        interval: .sixteenth,
        catalogOrder: 1
    )
}
```

- [ ] **Step 2: Run the integration suites and verify RED**

Run:

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/NotationLayoutEngineChordAndBeamTests -only-testing:VirgoTests/NotationLayoutEngineTests -only-testing:VirgoTests/NotationLayoutDefensiveGuardTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: beat-scoped counts, hook kind, stemless boundary, and hook stem-end assertions fail against the proximity implementation.

- [ ] **Step 3: Thread grid and meter through beam construction**

Add this internal result near the top of `NotationLayoutEngine+Beams.swift`:

```swift
struct BeamBuildResult {
    let events: [BeamTimelineEvent]
    let topology: BeamTopologyResult
    let beams: [RenderedBeam]
}
```

Change `NotationLayoutEngine.layout(input:)` to:

```swift
let beamBuild = buildBeams(
    noteHeads: noteHeads,
    tabGrid: tabGrid,
    timeSignature: input.timeSignature,
    style: input.style
)
let stems = buildStems(
    noteHeads: noteHeads,
    beams: beamBuild.beams,
    style: input.style
)
let flags = buildFlags(
    noteHeads: noteHeads,
    beamBuild: beamBuild,
    stems: stems,
    style: input.style
)
```

Pass `beamBuild.beams` into the final `NotationLayout` initializer.

- [ ] **Step 4: Form canonical direction-aware timeline events**

Add `stemDirection` to `StemGroupKey`, update every construction in `buildStems`, `buildFlags`, and chord lookup, then add these helpers:

```swift
fileprivate struct StemGroupKey: Hashable {
    let timeColumn: NotationTimeColumn
    let row: Int
    let voice: NotationVoice
    let stemDirection: StemDirection
}
```

```swift
func buildTimelineEvents(
    noteHeads: [RenderedNoteHead],
    ticksPerMeasure: Int
) -> [BeamTimelineEvent] {
    Dictionary(grouping: noteHeads) {
        StemGroupKey(
            timeColumn: $0.timeColumn,
            row: $0.row,
            voice: $0.voice,
            stemDirection: $0.stemDirection
        )
    }
    .values
    .map { group in
        let ordered = group.sorted {
            if $0.interval.flagCount != $1.interval.flagCount {
                return $0.interval.flagCount > $1.interval.flagCount
            }
            if $0.catalogOrder != $1.catalogOrder {
                return $0.catalogOrder < $1.catalogOrder
            }
            return $0.id < $1.id
        }
        let representative = ordered[0]
        let maximumLevels = ordered.map(\.interval.flagCount).max() ?? 0
        let role: BeamTimelineEventRole = maximumLevels == 0
            ? .boundary
            : .beamable(
                requiredBeamLevels: maximumLevels,
                durationTicks: durationTicks(
                    for: representative.interval,
                    ticksPerMeasure: ticksPerMeasure
                )
            )
        return BeamTimelineEvent(
            timeColumn: representative.timeColumn,
            row: representative.row,
            voice: representative.voice,
            stemDirection: representative.stemDirection,
            noteHeadIDs: group.map(\.id).sorted(),
            role: role
        )
    }
    .sorted(by: timelineEventComesBefore)
}

func durationTicks(
    for interval: NoteInterval,
    ticksPerMeasure: Int
) -> Int? {
    let denominator: Int
    switch interval {
    case .eighth: denominator = 8
    case .sixteenth: denominator = 16
    case .thirtysecond: denominator = 32
    case .sixtyfourth: denominator = 64
    case .full, .half, .quarter: return nil
    }
    guard ticksPerMeasure.isMultiple(of: denominator) else { return nil }
    return ticksPerMeasure / denominator
}

private func timelineEventComesBefore(
    _ lhs: BeamTimelineEvent,
    _ rhs: BeamTimelineEvent
) -> Bool {
    if lhs.timeColumn.measureIndex != rhs.timeColumn.measureIndex {
        return lhs.timeColumn.measureIndex < rhs.timeColumn.measureIndex
    }
    if lhs.timeColumn.absoluteLayoutTick != rhs.timeColumn.absoluteLayoutTick {
        return lhs.timeColumn.absoluteLayoutTick < rhs.timeColumn.absoluteLayoutTick
    }
    if lhs.row != rhs.row { return lhs.row < rhs.row }
    if lhs.voice.rawValue != rhs.voice.rawValue {
        return lhs.voice.rawValue < rhs.voice.rawValue
    }
    if lhs.stemDirection.rawValue != rhs.stemDirection.rawValue {
        return lhs.stemDirection.rawValue < rhs.stemDirection.rawValue
    }
    return lhs.noteHeadIDs.lexicographicallyPrecedes(rhs.noteHeadIDs)
}
```

Because event formation starts from every rendered notehead, half/full boundary events survive even though `buildStems` continues to filter them out.

- [ ] **Step 5: Materialize full and hook geometry from primary groups**

Replace the old `BeamGroupKey`, `beamRuns`, `beams(for:)`, and `beamSegments` path with `buildBeams(noteHeads:tabGrid:timeSignature:style:)`. The implementation must:

```swift
func buildBeams(
    noteHeads: [RenderedNoteHead],
    tabGrid: TabGrid,
    timeSignature: TimeSignature,
    style: NotationLayoutStyle
) -> BeamBuildResult {
    let events = buildTimelineEvents(
        noteHeads: noteHeads,
        ticksPerMeasure: tabGrid.ticksPerMeasure
    )
    let topology = NotationBeamTopologyBuilder().build(
        events: events,
        ticksPerMeasure: tabGrid.ticksPerMeasure,
        timeSignature: timeSignature
    )
    let headsByID = Dictionary(uniqueKeysWithValues: noteHeads.map { ($0.id, $0) })

    let beams = topology.primaryGroups.flatMap { group -> [RenderedBeam] in
        let representatives = group.eventIndices.compactMap { index in
            stemRepresentative(
                in: events[index].noteHeadIDs.compactMap { headsByID[$0] }
            )
        }
        guard let direction = representatives.first?.stemDirection else { return [] }
        let baseY = sharedBeamBaseY(
            for: representatives,
            direction: direction,
            style: style
        )
        return group.segments.compactMap { segment in
            renderedBeam(
                segment: segment,
                group: group,
                events: events,
                headsByID: headsByID,
                baseY: baseY,
                style: style
            )
        }
    }
    .sorted(by: renderedBeamComesBefore)

    return BeamBuildResult(events: events, topology: topology, beams: beams)
}
```

Implement segment materialization with these helpers:

```swift
private func renderedBeam(
    segment: BeamTopologySegment,
    group: BeamPrimaryGroup,
    events: [BeamTimelineEvent],
    headsByID: [UInt64: RenderedNoteHead],
    baseY: CGFloat,
    style: NotationLayoutStyle
) -> RenderedBeam? {
    guard let ownerIndex = segment.eventIndices.first,
          let owner = representative(
            for: events[ownerIndex],
            headsByID: headsByID
          ) else { return nil }

    let start = stemAnchor(for: owner, style: style)
    let endX: CGFloat
    let terminalIndex: Int
    switch segment.kind {
    case .full:
        guard let lastIndex = segment.eventIndices.last,
              let last = representative(
                for: events[lastIndex],
                headsByID: headsByID
              ) else { return nil }
        endX = stemAnchor(for: last, style: style).x
        terminalIndex = lastIndex
    case .forwardHook, .backwardHook:
        guard let neighborIndex = segment.hookNeighborIndex,
              let neighbor = representative(
                for: events[neighborIndex],
                headsByID: headsByID
              ) else { return nil }
        let neighborX = stemAnchor(for: neighbor, style: style).x
        let length = min(style.beamHookLength, abs(neighborX - start.x) / 2)
        guard length > 0 else { return nil }
        endX = start.x + (neighborX > start.x ? length : -length)
        terminalIndex = neighborIndex
    }
    guard endX != start.x else { return nil }

    let direction = group.id.stemDirection
    let levelOffset = CGFloat(segment.level) * style.beamLevelSpacing
    let y = direction == .up ? baseY - levelOffset : baseY + levelOffset
    let noteHeadIDs: [UInt64]
    if segment.kind == .full {
        noteHeadIDs = Array(Set(segment.eventIndices.flatMap {
            events[$0].noteHeadIDs
        })).sorted()
    } else {
        noteHeadIDs = events[ownerIndex].noteHeadIDs.sorted()
    }

    return RenderedBeam(
        id: renderedBeamID(
            group: group,
            segment: segment,
            firstTick: events[ownerIndex].timeColumn.absoluteLayoutTick,
            lastTick: events[terminalIndex].timeColumn.absoluteLayoutTick
        ),
        noteHeadIDs: noteHeadIDs,
        direction: direction,
        level: segment.level,
        kind: segment.kind,
        start: CGPoint(x: start.x, y: y),
        end: CGPoint(x: endX, y: y),
        thickness: style.beamThickness
    )
}

private func representative(
    for event: BeamTimelineEvent,
    headsByID: [UInt64: RenderedNoteHead]
) -> RenderedNoteHead? {
    stemRepresentative(in: event.noteHeadIDs.compactMap { headsByID[$0] })
}

private func sharedBeamBaseY(
    for representatives: [RenderedNoteHead],
    direction: StemDirection,
    style: NotationLayoutStyle
) -> CGFloat {
    let candidates = representatives.map {
        let anchorY = stemAnchor(for: $0, style: style).y
        return direction == .up
            ? anchorY - style.stemLength
            : anchorY + style.stemLength
    }
    return direction == .up
        ? candidates.min() ?? 0
        : candidates.max() ?? 0
}

private func renderedBeamID(
    group: BeamPrimaryGroup,
    segment: BeamTopologySegment,
    firstTick: Int,
    lastTick: Int
) -> String {
    let id = group.id
    return "beam_m\(id.measureIndex)_r\(id.row)_b\(id.beatGroupIndex)_"
        + "v\(id.voice.rawValue)_d\(id.stemDirection.rawValue)_"
        + "l\(segment.level)_\(segment.kind.rawValue)_\(firstTick)_\(lastTick)"
}
```

Use this total-order comparator:

```swift
private func renderedBeamComesBefore(
    _ lhs: RenderedBeam,
    _ rhs: RenderedBeam
) -> Bool {
    if lhs.start.y != rhs.start.y { return lhs.start.y < rhs.start.y }
    if lhs.start.x != rhs.start.x { return lhs.start.x < rhs.start.x }
    if lhs.level != rhs.level { return lhs.level < rhs.level }
    return lhs.id < rhs.id
}
```

Replace `sharedBeamY(for:level:style:)` with the `sharedBeamBaseY` helper above. It calculates the level-zero extremum from every primary-group stem representative, not every chord head and not the per-level subset.

- [ ] **Step 6: Make stem ends and flags topology-aware**

Change the first `beamEndY` guard to:

```swift
guard beam.kind != .full || beam.noteHeadIDs.count > 1 else { return nil }
```

Keep the horizontal-span and zero-span guards unchanged.

Change `buildFlags` to accept `BeamBuildResult` and use the topology coverage directly:

```swift
func buildFlags(
    noteHeads: [RenderedNoteHead],
    beamBuild: BeamBuildResult,
    stems: [RenderedStem],
    style: NotationLayoutStyle
) -> [RenderedFlag] {
    let headsByID = Dictionary(uniqueKeysWithValues: noteHeads.map { ($0.id, $0) })
    let stemsByNoteHeadID = Dictionary(
        uniqueKeysWithValues: stems.flatMap { stem in
            stem.noteHeadIDs.map { ($0, stem) }
        }
    )

    return beamBuild.events.enumerated().flatMap { index, event in
        guard case let .beamable(requiredLevels, _) = event.role else { return [] }
        let eventHeads = event.noteHeadIDs.compactMap { headsByID[$0] }
        guard let representative = eventHeads.sorted(by: {
            if $0.interval.flagCount != $1.interval.flagCount {
                return $0.interval.flagCount > $1.interval.flagCount
            }
            if $0.catalogOrder != $1.catalogOrder {
                return $0.catalogOrder < $1.catalogOrder
            }
            return $0.id < $1.id
        }).first,
        let stem = stemsByNoteHeadID[representative.id] else { return [] }

        let covered = beamBuild.topology.coveredLevelsByEventIndex[index] ?? []
        let flagOrigin = CGPoint(
            x: stem.start.x + GameplayLayout.flagXOffset,
            y: stem.end.y
        )
        return (0..<requiredLevels).compactMap { level in
            guard !covered.contains(level) else { return nil }
            let yOffset = stem.direction == .up
                ? CGFloat(level) * GameplayLayout.flagVerticalSpacing
                : -CGFloat(level) * GameplayLayout.flagVerticalSpacing
            return RenderedFlag(
                id: "flag_\(representative.id)_\(level)",
                noteHeadID: representative.id,
                stemDirection: stem.direction,
                flagIndex: level,
                origin: CGPoint(x: flagOrigin.x, y: flagOrigin.y + yOffset)
            )
        }
    }
}
```

- [ ] **Step 7: Run focused integration suites and verify GREEN**

Run the command from Step 2.

Expected: all focused integration and defensive tests pass with no floating/disconnected hooks.

- [ ] **Step 8: Commit the engine integration**

```bash
rtk git add Virgo/layout/NotationLayoutEngine.swift Virgo/layout/NotationLayoutEngine+Beams.swift VirgoTests/NotationLayoutEngineChordAndBeamTests.swift VirgoTests/NotationLayoutEngineTests.swift VirgoTests/NotationLayoutDefensiveGuardTests.swift
rtk git commit -m "feat: render beat-scoped beams and hooks"
```

---

### Task 4: Migrate Regressions, Remove Proximity Code, and Verify Platforms

**Files:**
- Modify: `Virgo/constants/Drum.swift:200-204`
- Modify: `VirgoTests/DrumTypeExtensionsAndConstantsTests.swift:151-154`
- Modify: `VirgoTests/NotationBeamTopologyTests.swift`
- Modify: `VirgoTests/NotationLayoutEngineChordAndBeamTests.swift`
- Modify: `VirgoTests/NotationLayoutEngineTests.swift`
- Verify: all files listed under File Structure

**Interfaces:**
- Consumes: completed topology and engine behavior from Tasks 1-3.
- Produces: no legacy proximity API, complete mixed-duration/fallback/determinism regression coverage, and final macOS/iPad verification evidence.

- [ ] **Step 1: Add the remaining topology edge-case tests**

Extend `NotationBeamTopologyTests.swift` with table-driven cases that assert:

```swift
@Test("isolated invalid beamable event has no coverage")
func invalidDurationIsIsolated() {
    let events = [
        event(tick: 0, levels: 2, durationTicks: nil, noteHeadID: 1),
        event(tick: 60, levels: 2, durationTicks: 60, noteHeadID: 2)
    ]
    let result = builder.build(
        events: events,
        ticksPerMeasure: 960,
        timeSignature: .fourFour
    )
    #expect(result == .empty)
}

@Test("thirty-second and sixty-fourth levels are completely covered")
func deepBeamLevelsAreCovered() throws {
    let events = [
        event(tick: 0, levels: 4, durationTicks: 15, noteHeadID: 1),
        event(tick: 15, levels: 1, durationTicks: 120, noteHeadID: 2)
    ]
    let result = builder.build(
        events: events,
        ticksPerMeasure: 960,
        timeSignature: .fourFour
    )
    let segments = try #require(result.primaryGroups.first?.segments)
    #expect(segments.map(\.level) == [0, 1, 2, 3])
    #expect(segments.dropFirst().allSatisfy { $0.kind == .forwardHook })
    #expect(result.coveredLevelsByEventIndex[0] == [0, 1, 2, 3])
}
```

Add the equal-distance midpoint rule as a table-driven pure test:

```swift
@Test(
    "equal-distance interior hooks point toward the beat center",
    arguments: [
        (ownerTick: 60, expected: BeamSegmentKind.forwardHook),
        (ownerTick: 180, expected: BeamSegmentKind.backwardHook)
    ]
)
func equalDistanceHooksUseBeatMidpoint(
    ownerTick: Int,
    expected: BeamSegmentKind
) throws {
    let events = [
        event(
            tick: ownerTick - 30,
            levels: 1,
            durationTicks: 30,
            noteHeadID: 1
        ),
        event(
            tick: ownerTick,
            levels: 2,
            durationTicks: 30,
            noteHeadID: 2
        ),
        event(
            tick: ownerTick + 30,
            levels: 1,
            durationTicks: 30,
            noteHeadID: 3
        )
    ]
    let result = builder.build(
        events: events,
        ticksPerMeasure: 960,
        timeSignature: .fourFour
    )
    let hook = try #require(
        result.primaryGroups.first?.segments.first { $0.level == 1 }
    )
    #expect(hook.kind == expected)
}
```

- [ ] **Step 2: Intentionally migrate old mixed-duration fixtures**

Update the existing `remainingFlagsOriginateAtBeamAdjustedStemEnd` fixture in `NotationLayoutEngineChordAndBeamTests.swift`. Rename it to describe fragmented topology and assert the actual gap:

```swift
@Test("implicit gap splits mixed-duration run and leaves final sixteenth isolated")
func implicitGapSplitsMixedDurationRun() throws {
    let notes = [
        Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
        Note(interval: .thirtysecond, noteType: .snare, measureNumber: 1, measureOffset: 0.0625),
        Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.125)
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )

    let finalHead = try #require(
        layout.noteHeads.first { abs($0.timePosition - 0.125) < 0.000_001 }
    )
    #expect(layout.beams.contains { $0.kind == .backwardHook && $0.level == 2 })
    #expect(layout.flags.filter { $0.noteHeadID == finalHead.id }.count == 2)
}
```

Replace the old two-note mixed-duration expectations with this backward-hook counterpart to Task 3's forward-hook test:

```swift
@Test("eighth followed by sixteenth uses a backward hook without flags")
func mixedDurationsRenderBackwardHook() throws {
    let notes = [
        Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
        Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 8.0)
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )
    let hook = try #require(layout.beams.first { $0.level == 1 })
    #expect(hook.kind == .backwardHook)
    #expect(hook.noteHeadIDs.count == 1)
    #expect(hook.end.x < hook.start.x)
    #expect(layout.flags.isEmpty)
}
```

- [ ] **Step 3: Add unsupported-meter and shuffled-input integration coverage**

Add to `NotationLayoutEngineTests.swift`:

```swift
@Test("unsupported meter renders isolated flags without beams")
func unsupportedMeterUsesConservativeFlags() {
    let notes = [
        Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
        Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125)
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .sixEight)
    )
    #expect(layout.beams.isEmpty)
    #expect(layout.flags.count == 2)
}

@Test("shuffled source notes preserve rendered beam IDs and order")
func shuffledInputIsDeterministic() {
    let notes = (0..<8).map {
        Note(
            interval: .sixteenth,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: Double($0) / 16.0
        )
    }
    let forward = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )
    let reversed = NotationLayoutEngine().layout(
        input: NotationLayoutInput(
            notes: Array(notes.reversed()),
            timeSignature: .fourFour
        )
    )
    #expect(forward.beams.map(\.id) == reversed.beams.map(\.id))
}
```

- [ ] **Step 4: Remove the obsolete proximity API and test**

Delete the complete `BeamGroupingConstants` type from `Virgo/constants/Drum.swift` and delete `testBeamGroupingConstant()` from `DrumTypeExtensionsAndConstantsTests.swift`.

Run:

```bash
rtk rg -n 'BeamGroupingConstants|maxConsecutiveInterval|comparisonTolerance|beamRuns\(|beamSegments\(' Virgo VirgoTests
```

Expected: no matches.

- [ ] **Step 5: Run all focused suites sequentially**

Run:

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/NotationBeamTopologyTests -only-testing:VirgoTests/NotationLayoutEngineChordAndBeamTests -only-testing:VirgoTests/NotationLayoutEngineTests -only-testing:VirgoTests/NotationLayoutDefensiveGuardTests -only-testing:VirgoTests/SwiftUIRenderingCoverageTests -only-testing:VirgoTests/DrumTypeExtensionsAndConstantsTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: all focused suites pass with zero failures.

- [ ] **Step 6: Run the full unit suite**

Run:

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -enableCodeCoverage YES -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected: `VirgoTests` passes with zero failures and no parallel test clones.

- [ ] **Step 7: Run static checks and platform builds**

Run sequentially:

```bash
rtk swiftlint lint
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' build
```

Expected: SwiftLint introduces no new violations; macOS and iPad simulator-compatible builds succeed. If the named iPad simulator is unavailable, use `rtk xcrun simctl list devices available` and substitute an available iPad destination only.

- [ ] **Step 8: Verify the final diff and commit**

Run:

```bash
rtk git diff --check
rtk git status --short
```

Expected: no whitespace errors; only HPA-142 source/tests are modified.

Commit:

```bash
rtk git add Virgo/constants/Drum.swift VirgoTests/DrumTypeExtensionsAndConstantsTests.swift VirgoTests/NotationBeamTopologyTests.swift VirgoTests/NotationLayoutEngineChordAndBeamTests.swift VirgoTests/NotationLayoutEngineTests.swift
rtk git commit -m "test: cover drum beam topology regressions"
```

---

## Final Review Checklist

- Every 4/4 primary run is quarter-beat scoped and canonically contiguous.
- Full segments, forward hooks, and backward hooks have deterministic topology and geometry.
- One primary-group baseline drives every level; secondary subsets cannot move it.
- Hook owners extend their stems to the hook y-coordinate.
- Topology coverage and rendered flags never duplicate a beam level.
- Standalone eighth through 64th notes retain one through four curved flags.
- Stemless half/full and quarter boundary events cannot disappear before topology.
- Same-time conflicting directions form separate events and stems.
- Unsupported meters and invalid durations produce individual flags, not guessed beams.
- `RenderedBeam.kind` is explicit at every initializer.
- Rendered beam sorting has an ID tie-breaker and survives source-note shuffling.
- No `BeamGroupingConstants`, proximity method, or tolerance caller remains.
- Focused tests, full `VirgoTests`, SwiftLint, macOS build, and iPad build all complete successfully.
