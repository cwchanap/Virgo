# Beat-Group Beaming, Hooks, Flags, and Tails Design

- **Date:** 2026-07-12
- **Status:** Design approved; awaiting written-spec review
- **Scope:** Replace proximity-based drum-tab beaming with deterministic 4/4 beat groups, partial hooks, and isolated-note flags.
- **Linear:** [HPA-142](https://linear.app/cwchanap/issue/HPA-142/implement-beat-group-beaming-partial-beams-hooks-flags-and-tails)
- **Parent:** [HPA-97](https://linear.app/cwchanap/issue/HPA-97/fix-drum-tab-rendering-spacing-beams-flags-rests-and-stop-note)

## 1. Context

HPA-139, HPA-140, and HPA-141 are complete. Imported notes preserve normalized timing and source identity, notation and the playhead share one fixed `TabGrid`, same-time noteheads remain on one canonical x column, and stems are grouped by canonical time, row, and notation voice.

The remaining beam pipeline is still proximity-based. `NotationLayoutEngine.beamRuns(from:)` joins flagged noteheads when their floating `timePosition` difference is at most `BeamGroupingConstants.maxConsecutiveInterval` (`0.3`). That can connect notes across quarter-note beat boundaries and does not express partial secondary beams.

The current mixed-duration fallback also renders curved flags for uncovered beam levels. For example, a sixteenth joined to an eighth receives a primary beam plus a second-level flag. HPA-142 requires that level to be represented by a partial beam hook while reserving flags for genuinely isolated stems.

## 2. Goals

- Group 4/4 beams inside quarter-note beats using canonical integer ticks.
- Build beam membership from semantic stems rather than individual chord noteheads.
- Preserve all measure, row, voice, and stem-direction boundaries.
- Support primary through fourth-level beams for eighth through 64th notes.
- Render forward and backward hooks for singleton secondary levels.
- Keep isolated flagged notes visibly tailed with the correct flag count.
- Keep upper- and lower-voice geometry anchored to the HPA-141 stem contract.
- Produce deterministic topology, geometry, ordering, and identifiers.
- Fall back conservatively when timing cannot be represented exactly.
- Add pure topology tests plus layout/rendering integration coverage.

## 3. Non-Goals

- No compound-meter grouping for 6/8 or 12/8.
- No tuplets, dotted rhythms, swing or shuffle display, or variable measure lengths.
- No rest-aware beaming; HPA-143 owns explicit rest primitives and HPA-145 owns advanced meter/rhythm semantics.
- No sloped, feathered, cross-staff, or tremolo beams.
- No parser, SwiftData, scoring, input, playback, playhead, wrapping, or row-scrolling changes.
- No notehead, glyph, notation catalog, voice, or default stem-direction changes.
- No broad screenshot/golden fixture suite; HPA-144 owns that final regression layer.
- No strict classical engraving redesign. Flat beams remain the gameplay notation style.

## 4. Approved Approach

Insert a pure, stem-level topology stage between rendered noteheads and rendered geometry:

```text
RenderedNoteHead
  -> BeamStemEvent
  -> beat-scoped BeamTopology
  -> RenderedBeam / RenderedFlag
  -> existing SwiftUI primitive views
```

This replaces notehead proximity grouping without reopening HPA-141's stem and glyph work. The topology layer decides membership, beam levels, and hook direction. `NotationLayoutEngine+Beams.swift` remains responsible for converting that topology into points using existing stem anchors and style values.

## 5. Components and Ownership

### 5.1 Pure topology types

Add `Virgo/layout/NotationBeamTopology.swift` for internal, geometry-free beam decisions.

The input event represents one semantic stem:

```swift
struct BeamStemEvent: Hashable {
    let timeColumn: NotationTimeColumn
    let row: Int
    let voice: NotationVoice
    let stemDirection: StemDirection
    let noteHeadIDs: [UInt64]
    let requiredBeamLevels: Int
    let durationTicks: Int?
}
```

`noteHeadIDs` contains every source head sharing the HPA-141 stem key. `requiredBeamLevels` is the maximum `NoteInterval.flagCount` among those heads. This preserves every required tail if same-time, same-voice source notes disagree about duration.

The topology output expresses drawable membership without points:

```swift
enum BeamSegmentKind: String, Hashable {
    case full
    case forwardHook
    case backwardHook
}

struct BeamTopologySegment: Hashable {
    let level: Int
    let kind: BeamSegmentKind
    let stemEventIndices: [Int]
    let hookNeighborIndex: Int?
}
```

Full segments contain at least two stem events. Hooks contain one owning stem event and the adjacent primary-group event toward which the hook points.

### 5.2 Topology builder

`NotationBeamTopologyBuilder` is a pure value type. It accepts ordered `BeamStemEvent` values, `ticksPerMeasure`, and the time signature. It returns topology segments plus the set of beam levels covered for each stem event.

The builder does not depend on SwiftUI, Core Graphics, SwiftData, logging, or view state. Unsupported or invalid input produces fewer beams and more isolated flags, never guessed cross-note topology.

### 5.3 Layout integration

`NotationLayoutEngine+Beams.swift` will:

1. Collapse rendered noteheads by the existing semantic stem key.
2. Convert exact `NoteInterval` values into canonical duration ticks.
3. Ask the topology builder for beam and hook membership using the layout's `TabGrid` resolution and time signature.
4. Resolve one shared flat base y-coordinate from the full primary group, then offset each beam level from that baseline.
5. Materialize `RenderedBeam` segments from existing HPA-141 stem anchors.
6. Build stems against the outermost full beam or hook that covers each stem, including single-notehead hook owners.
7. Add flags only for levels that topology did not cover.

`RenderedBeam` gains a `kind: BeamSegmentKind` field. Its existing `level`, `direction`, endpoints, thickness, and `noteHeadIDs` remain the rendering contract.

The current `buildBeams(noteHeads:style:)` entry point does not receive meter or grid data. Change it to:

```swift
buildBeams(
    noteHeads: noteHeads,
    tabGrid: tabGrid,
    timeSignature: input.timeSignature,
    style: input.style
)
```

`NotationLayoutEngine.layout(input:)` owns both required values and is the only current caller, so it threads them into beam construction directly.

`beamEndY` currently rejects every beam containing only one notehead. Preserve that defensive rule for `.full` segments, but allow hooks to reach their owner stem:

```swift
guard beam.kind != .full || beam.noteHeadIDs.count > 1 else { return nil }
```

The existing horizontal-span and zero-span guards still apply. A valid hook begins at its owner's stem x-coordinate, so the range check succeeds and the stem reaches the hook y-coordinate instead of falling back to its unbeamed length.

### 5.4 SwiftUI rendering

`NotationBeamView` continues to draw a line from `start` to `end`. Full beams and hooks differ in topology and endpoint length, not in view behavior. `NotationFlagView` remains the renderer for isolated curved tails.

Views must not infer beat groups, hook direction, beam coverage, or flag suppression.

## 6. Stem Event Formation

Build one `BeamStemEvent` for every unique combination of:

- `NotationTimeColumn`
- rendered row
- `NotationVoice`

HPA-141 already guarantees a single catalog-authored direction per voice. The event still stores `stemDirection`, and direction remains part of the later group key, so inconsistent future input cannot be joined accidentally.

Within a stem event:

- Sort `noteHeadIDs` for deterministic output.
- Use the maximum flag count as `requiredBeamLevels`.
- Convert the corresponding shortest interval into canonical duration ticks.
- Keep non-beamable quarter, half, and full events in the ordered timeline as run boundaries, even though they never become beam members.

The builder distinguishes the two reasons `durationTicks` can be `nil`:

- `requiredBeamLevels == 0` means an intentional non-beamable quarter, half, or full boundary.
- `requiredBeamLevels > 0` means a flagged interval could not be represented exactly; that event is isolated and receives its normal flags.

Neither case permits neighboring events to beam across it.

## 7. Four-Four Beat Groups

Rhythm-aware grouping is enabled only when:

- the time signature is 4/4;
- `ticksPerMeasure` is positive; and
- `ticksPerMeasure` is divisible by four.

The quarter-beat size and beat index are:

```swift
beatTicks = ticksPerMeasure / 4
beatGroupIndex = tickWithinMeasure / beatTicks
```

The grouping key contains:

- measure index
- row
- voice
- stem direction
- beat-group index

No beam may cross any of those boundaries.

Within a key, events are sorted by `absoluteLayoutTick`, then deterministic stem identity. Repeated source heads at the same stem event do not create duplicate topology members.

## 8. Rhythmic Continuity

Beat membership alone is insufficient: beams must not span an unknown rest or timing gap.

Two successive flagged stem events are rhythmically contiguous only when:

```swift
next.absoluteLayoutTick == current.absoluteLayoutTick + current.durationTicks
```

Duration conversion for 4/4 uses the interval's measure denominator:

| Interval | Measure denominator | Beam levels |
|---|---:|---:|
| Eighth | 8 | 1 |
| Sixteenth | 16 | 2 |
| 32nd | 32 | 3 |
| 64th | 64 | 4 |

Conversion succeeds only when `ticksPerMeasure` is evenly divisible by the denominator. Quarter, half, and full notes are non-beamable boundaries. A missing or non-integral duration ends the current run and leaves the affected stem isolated.

A primary run requires at least two contiguous flagged stem events. A single flagged event has no primary beam and receives flags for all required levels.

## 9. Beam Levels and Hooks

### 9.1 Primary level

Level 0 joins every stem event in a valid primary run. It produces one full segment from the first stem anchor to the last stem anchor and covers level 0 for every member.

### 9.2 Secondary levels

For each level from 1 through the run's maximum required level minus one:

1. Select stem events whose `requiredBeamLevels` exceeds the level.
2. Partition selected events into consecutive subsequences within the primary run.
3. Emit a full segment for every subsequence containing two or more events.
4. Emit one hook for every singleton subsequence.

This prevents secondary beams from passing through an eighth note or any other stem that does not require that level.

### 9.3 Hook direction

Hook direction is deterministic:

- A singleton at the primary group's first event uses a forward hook.
- A singleton at the primary group's last event uses a backward hook.
- An interior singleton points toward the primary neighbor with the smaller canonical tick distance.
- If the two distances are equal, a stem before the quarter-beat midpoint points forward; a stem at or after the midpoint points backward.

The chosen adjacent primary member is stored as `hookNeighborIndex`.

### 9.4 Hook geometry

`NotationLayoutStyle` gains `beamHookLength`, with a gameplay default of 12 points. Both `NotationLayoutStyle.gameplayDefault` and the hand-copying `with(rowWidth:)` builder must initialize or preserve this field. The live gameplay path rebuilds the style through `with(rowWidth:)`, so omitting the copy would lose hook geometry or fail compilation.

A hook begins at its owner's stem anchor and extends horizontally toward the selected neighbor. Its length is:

```swift
min(style.beamHookLength, abs(neighborStemX - ownerStemX) / 2)
```

The endpoint never reaches or crosses the neighboring stem. Forward hooks increase x; backward hooks decrease x.

## 10. Vertical Geometry and Stem Integration

Virgo retains flat beams. Each primary group resolves one base y-coordinate using all of its chord representatives and the existing HPA-141 glyph/stem anchors:

- Up-stem groups use the highest required endpoint.
- Down-stem groups use the lowest required endpoint.

Every level offsets from that common baseline by `NotationLayoutStyle.beamLevelSpacing`. Full segments and hooks at the same level therefore align vertically even when they cover different subsets.

This changes the current `sharedBeamY` semantics. Today it receives the per-level filtered notehead subset, which can move secondary levels when their members differ from the primary group. The revised helper derives the base y from the complete primary group once; segment levels apply only the signed `beamLevelSpacing` offset.

Full beams list all notehead IDs belonging to their covered stem events. Hooks list all notehead IDs belonging to their owning stem event. `buildStems` treats either kind as beam coverage and extends the stem to its outermost covered level.

## 11. Flag Behavior

Beam coverage is tracked per stem event and beam level.

- A full beam covers its level for every member stem.
- A hook covers its level for its owner.
- A stem outside a primary group has no covered levels.
- `buildFlags` emits one flag for every required level not covered by topology.

Consequences:

- Two adjacent eighths receive one primary beam and no flags.
- A sixteenth followed by an eighth receives a primary beam plus a forward secondary hook and no flags.
- An eighth followed by a sixteenth receives a primary beam plus a backward secondary hook and no flags.
- An isolated sixteenth receives two flags.
- An isolated 64th receives four flags.

This intentionally replaces the current behavior that mixes a primary beam with curved flags for singleton secondary levels.

## 12. Determinism

Topology events, groups, levels, segments, and source IDs are sorted before rendered primitives are created.

Rendered beam IDs include:

- measure
- row
- beat group
- voice
- direction
- level
- segment kind
- first and last absolute ticks

Hook IDs use the owner's tick plus the selected neighbor tick. IDs never depend on dictionary iteration order, floating x values, or source-array order.

Final rendered beams retain the existing stable sort by y, x, level, and then ID as the tie-breaker.

## 13. Conservative Fallbacks

The renderer must prefer incomplete but honest notation over a confident wrong beam.

- Unsupported meters render individual flags for all flagged stems.
- A non-positive or non-quarter-divisible grid renders individual flags.
- A duration that cannot convert exactly into ticks renders individually.
- A rhythmic gap breaks the primary run.
- A quarter, half, or full event breaks the primary run.
- Measure, row, voice, direction, or beat changes always break the group.
- Conflicting intervals inside one semantic chord use the maximum required level so no tail disappears.

The complete `BeamGroupingConstants` type is removed. Both `maxConsecutiveInterval` and `comparisonTolerance` are used only by the proximity-era run/segment implementation that this topology replaces. Remove the constants test from `DrumTypeExtensionsAndConstantsTests.swift` as well. There is no floating-time, visual-distance, tolerance, or proximity fallback.

HPA-145 may later supply meter-aware beat groups and richer duration semantics through the same topology boundary without changing `RenderedBeam` or the SwiftUI views.

## 14. Error Handling

The pure topology builder returns an empty segment list for unsupported or invalid grouping input. This is an expected fallback, not a runtime error.

Layout integration must continue producing stems and flags when topology is empty. Existing defensive guards remain in place when a stem anchor or representative cannot be resolved. Such a malformed event is excluded from beams and retains normal unbeamed stem behavior where possible.

No new fatal errors, assertions, persistence migrations, or user-visible error UI are introduced.

## 15. Testing

### 15.1 Pure topology tests

Add `VirgoTests/NotationBeamTopologyTests.swift` using Swift Testing. Cover:

- a full 4/4 sixteenth run split into four quarter-beat groups;
- primary eighth beams;
- sixteenth/eighth forward hooks;
- eighth/sixteenth backward hooks;
- interior hook direction and midpoint tie-breaking;
- 32nd and 64th multi-level full segments and hooks;
- a gap within a beat producing isolated events;
- exact quarter-beat boundary separation;
- measure, row, voice, and direction separation;
- same-time chord collapse without duplicate topology members;
- conflicting chord intervals using the maximum level;
- unsupported meter fallback;
- invalid, non-positive, and non-integral tick fallback;
- deterministic segment ordering.

### 15.2 Layout integration tests

Update focused coverage in `NotationLayoutEngineChordAndBeamTests.swift` and `NotationLayoutEngineTests.swift` to verify:

- full segments and hooks use the existing authored stem anchors;
- up- and down-stem hooks extend in the correct x direction;
- hooks use the configured 12-point maximum and never exceed half the neighbor distance;
- stems reach the outermost full beam or hook level;
- hook-covered levels do not also produce flags;
- isolated eighth through 64th notes retain one through four flags;
- four beats of sixteenth notes do not become one measure-wide beam;
- beams do not cross row, measure, voice, direction, or beat boundaries;
- rendered beam IDs and final ordering are stable.

Replace the existing mixed-duration expectations that require secondary curved flags with hook expectations. This is not always a mechanical assertion change: existing fixtures whose offsets are not contiguous under `current.durationTicks` must either use corrected contiguous offsets or explicitly assert the newly split primary runs and isolated flags. In particular, the existing sixteenth/32nd/sixteenth fixture at offsets `0`, `0.0625`, and `0.125` contains a 32nd-note gap before its final event and must be reviewed intentionally.

Extend `NotationLayoutDefensiveGuardTests.swift` to verify that:

- a single-notehead hook owner resolves `beamEndY` to the hook y-coordinate;
- a malformed single-notehead `.full` segment is still rejected;
- the existing out-of-horizontal-span and zero-span guards remain effective.

Remove the obsolete `BeamGroupingConstants` threshold test from `DrumTypeExtensionsAndConstantsTests.swift`. Retain existing HPA-141 chord-anchor, voice-first stem, defensive beam-end, and SwiftUI primitive coverage.

### 15.3 Verification ladder

Run sequentially with parallel testing disabled:

1. `NotationBeamTopologyTests`
2. `NotationLayoutEngineChordAndBeamTests`
3. `NotationLayoutEngineTests`
4. Full `VirgoTests`
5. SwiftLint
6. macOS build
7. iPad simulator-compatible build using an available iPad destination

The focused tests provide the primary semantic proof. HPA-144 remains responsible for dense-row and multi-row golden or deterministic render fixtures after all renderer semantics land.

## 16. Likely Files

- `Virgo/layout/NotationBeamTopology.swift` (new)
- `Virgo/layout/NotationLayout.swift`
- `Virgo/layout/NotationLayoutEngine.swift`
- `Virgo/layout/NotationLayoutEngine+Beams.swift`
- `Virgo/views/NotationPrimitiveViews.swift` (only if the new metadata requires conformance updates)
- `Virgo/constants/Drum.swift`
- `VirgoTests/NotationBeamTopologyTests.swift` (new)
- `VirgoTests/NotationLayoutEngineChordAndBeamTests.swift`
- `VirgoTests/NotationLayoutEngineTests.swift`
- `VirgoTests/NotationLayoutDefensiveGuardTests.swift`
- `VirgoTests/DrumTypeExtensionsAndConstantsTests.swift`

## 17. Acceptance Criteria Mapping

- A full 4/4 sixteenth run produces four beat-scoped groups, never one measure-wide run.
- Mixed eighth/sixteenth beats produce a primary beam plus the correct secondary full segments or hooks.
- Secondary beams never pass through a stem that does not require that level.
- Isolated eighth, sixteenth, 32nd, and 64th notes render visible tails.
- Beams never cross measure, row, voice, direction, or quarter-beat boundaries.
- Same-time chords contribute one semantic stem event while preserving all notehead identities.
- Down- and up-stem geometry remains connected to the HPA-141 authored anchors.
- Unsupported or unrepresentable timing renders conservatively with flags.
- No proximity threshold remains in grouping behavior.
- Pure and integration tests deterministically cover topology, hooks, geometry, flags, and fallbacks.
