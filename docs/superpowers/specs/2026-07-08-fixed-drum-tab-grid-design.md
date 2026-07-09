# Fixed Drum-Tab Grid And Shared Timeline Mapping Design

**Date:** 2026-07-08
**Status:** Design approved; pending written-spec review
**Scope:** Replace per-measure adaptive note spacing with a fixed chart-level drum-tab grid and one shared timeline-to-x mapping for notation and playhead positioning.
**Linear:** [HPA-140](https://linear.app/cwchanap/issue/HPA-140/implement-fixed-drum-tab-grid-and-shared-timeline-to-x-mapping)

## 1. Context

Virgo's current `NotationLayoutEngine.measureWidth(...)` expands each measure based on the smallest local note gap. Dense measures become wide, sparse measures stay narrow, and the same beat can appear at different x spacing from one measure to the next.

HPA-139 is already complete and added normalized timing metadata to imported `Note` records:

- `normalizedMeasureIndex`
- `normalizedAbsoluteTick`
- `normalizedTickWithinMeasure`
- `normalizedTicksPerMeasure`

HPA-140 should consume that metadata for layout. It should not reopen parser normalization, notehead/stem semantics, beaming, rests, articulations, tuplets, or variable measure-length timing; those belong to related follow-up tickets.

## 2. Goals

- Introduce a fixed drum-tab grid for each notation layout pass.
- Use one timeline-to-x mapper for rendered note heads, cached beat positions, and the purple playhead.
- Prefer imported normalized tick metadata when available.
- Keep manual and legacy notes renderable through a deterministic 960-tick fallback.
- Make wrapping deterministic from fixed grid width, not local measure density.
- Keep the current beat-boundary purple playhead behavior while aligning it to the same grid as notes.
- Add focused geometry tests for sparse high-resolution charts, dense sixteenth charts, multi-row wrapping, cached beat positions, and playhead alignment.

## 3. Non-Goals

- No zoom, fit-to-row, or user-controlled scale in this ticket.
- No continuous/sub-beat playhead motion.
- No parser/model normalization changes beyond consuming existing fields.
- No notehead/stem placement rewrite; voice-collision offsets stay as the current visual adjustment.
- No beaming, hook, flag, rest, choke, articulation, tuplets, compound meter, or variable measure-length work.
- No broad UI redesign or golden screenshot suite. HPA-144 owns broader rendering fixtures and golden coverage.

## 4. Architecture

Add a small grid model in `Virgo/layout/NotationLayout.swift`, for example:

```swift
struct TabGrid: Equatable {
    let ticksPerMeasure: Int
    let tickWidth: CGFloat
    let leftPadding: CGFloat
    let measureWidth: CGFloat
}
```

Add a shared mapper API near the grid model or in a focused helper type:

```swift
x = measure.xOffset + grid.leftPadding + CGFloat(tickIndex) * grid.tickWidth
```

`NotationLayoutEngine` builds one `TabGrid` for the whole layout pass and stores it on `NotationLayout`. All rendered measures receive the same width. All note heads first resolve a canonical tick index, then ask the mapper for the canonical x column.

`GameplayViewModel` should not independently recreate notation x math. When notation layout is active, visual updates should ask the rendered layout/grid for:

- beat-boundary purple-bar x positions
- cached beat x/y positions
- rendered measure rows used by row auto-scroll

The existing `GameplayLayout.calculateMeasurePositions(...)` path remains as a fallback for non-notation or empty-layout cases.

## 5. Grid Resolution And Display Scale

The grid has two related but separate concerns:

- **Canonical tick resolution:** the integer timeline space used for exact placement.
- **Display scale:** the number of points per tick used to render the chart.

Canonical resolution rules:

- If imported notes provide valid `normalizedTicksPerMeasure`, resolve a deterministic common grid that can represent all imported note ticks.
- In the normal imported case, HPA-139 should already have produced a chart-level `normalizedTicksPerMeasure`; use it directly.
- If multiple valid resolutions appear, use a least-common-multiple grid when it remains representable by `Int` and the source ticks scale exactly.
- Notes without metadata fall back to `960` ticks per measure and derive `tickWithinMeasure` from normalized `measureOffset`.
- If a chart mixes imported and legacy notes, the legacy `960`-tick resolution is included in the common-grid LCM set alongside the imported resolutions, and every note is converted into the resulting common grid before x mapping. Including `960` guarantees that legacy notes — which only carry a fractional `measureOffset` — land on the same tick boundaries that 960-resolution offset rounding would produce, preserving their placement precision. Converting legacy notes into an arbitrary imported-only LCM grid (e.g. `32`) would coarsen their rounding and shift them off their intended positions. (See `NotationLayoutEngine.resolvedTicksPerMeasure` and `mixedNormalizedAndFallbackNotesUseFallbackGridResolution`.)

Display scale rules:

- Use one `tickWidth` for the entire layout pass.
- Choose `tickWidth` from actual chart density, not merely source grid resolution.
- Find the smallest positive gap between occupied canonical tick columns in the chart.
- If no dense gap exists, use a default sixteenth-note subdivision as the readable baseline.
- Ensure that the selected smallest rendered column gap is at least `NotationLayoutStyle.minimumNoteColumnGap`, plus voice-collision padding when cross-voice adjacent columns require it.
- Sparse high-resolution charts should therefore preserve exact tick placement without becoming huge solely because the source grid was high-resolution.
- Dense sixteenth charts should render sixteenth columns with readable spacing.

Fixed measure width:

```swift
measureWidth = grid.leftPadding + CGFloat(grid.ticksPerMeasure) * grid.tickWidth
```

Note: `grid.leftPadding` already includes `GameplayLayout.barLineWidth` (it equals `barLineWidth + uniformSpacing`), so `measureWidth` must not add `barLineWidth` again. The implementation uses `TabGrid.measureWidth(ticksPerMeasure:tickWidth:leftPadding:)` which computes `leftPadding + ticks * tickWidth`.

The first note column stays at:

```swift
measure.xOffset + grid.leftPadding
```

`grid.leftPadding` should preserve the current start-column intent, equivalent to `GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing`.

## 6. Wrapping And Rows

`NotationLayoutEngine.buildMeasures(...)` should stop asking for a density-dependent width per measure. It should use the grid's fixed `measureWidth` for every measure in the layout pass.

Wrapping remains row-width-based:

- Start at `GameplayLayout.leftMargin`.
- Place each measure at the current x offset.
- Wrap before placing a measure when `currentX + grid.measureWidth > input.style.rowWidth` and this is not the first measure.
- Advance by `grid.measureWidth + GameplayLayout.measureSpacing`.

Because every measure has the same width in a layout pass, sparse and dense measures wrap identically for a given chart and row width. Row-width resize can still rebuild the layout, but local note density should no longer cause jitter after initial layout.

## 7. Note Placement

For each note:

1. Resolve normalized time position with the existing measure-number normalization rules.
2. Resolve `measureIndex`.
3. Resolve `tickWithinMeasure`:
   - use imported `normalizedTickWithinMeasure` scaled into the layout grid when present and valid;
   - otherwise convert normalized `measureOffset` into the layout grid.
4. Resolve x through the shared mapper.
5. Resolve y through the current drum position rules.
6. Apply existing voice-collision offsets after canonical x placement.

The canonical column remains the grid-mapped x. Voice-collision offsets are visual separation only, so the playhead aligns with the column center rather than with an offset upper or lower voice head.

## 8. Playhead And Cached Beat Positions

The purple playhead remains beat-boundary quantized for HPA-140. The behavior that it holds between beats should not change.

The mapping should change:

- Convert `beatWithinMeasure` to a canonical tick in the layout grid.
- Ask the shared mapper for x.
- Use the rendered notation measure row for y.
- Continue clamping past-the-end playback to the final measure end.

`GameplayViewModel.cacheBeatPositions()` should use the notation layout when it is active. It should derive beat x/y from `cachedNotationLayout.measures` and `cachedNotationLayout.tabGrid`, not from legacy `measurePositionMap` plus `GameplayLayout.preciseNoteXPosition(...)`.

After `cacheNotationLayout()`, notation-specific row maps should be rebuilt from `cachedNotationLayout.measures`. Any fallback `measurePositionMap` should remain valid for legacy code paths, but notation playhead and cached beat positions should treat the rendered notation layout as authoritative.

## 9. Compatibility

- Existing manual tests and hand-created notes can keep using only `measureNumber` and `measureOffset`.
- Imported DTX notes with normalized metadata get exact tick placement.
- Existing `Note.interval` and `visualDurationCandidate` behavior is not reworked in this ticket.
- Existing voice collision, chord direction unification, beam run direction unification, ledger lines, stems, beams, flags, and primitive views remain in place.
- Existing row-width debounce behavior can stay; the rebuilt layout is simply deterministic once row width settles.
- The legacy `GameplayLayout` note-position helpers remain for fallback paths and existing tests that do not activate notation layout.

## 10. Error Handling And Guards

- Ignore invalid normalized tick metadata when values are nil, non-positive, negative, or outside the measure grid.
- Fall back to 960-tick conversion from `measureOffset` for invalid or missing metadata.
- Clamp tick indices into `0...ticksPerMeasure` when mapping the playhead so end-of-measure clamping remains stable.
- If common-grid resolution cannot be computed safely, fall back to 960 ticks per measure and log a warning rather than dropping notes.
- Continue logging dropped notes if rendered note-head count differs from cached notes.

## 11. Tests

Focused Swift Testing coverage should include:

- `NotationLayoutEngineTests`: sparse high-resolution imported notes preserve exact timing without inflating width solely from source resolution.
- `NotationLayoutEngineTests`: dense sixteenth notes render with readable fixed spacing.
- `NotationLayoutEngineTests`: sparse and dense measures in the same chart use the same measure width.
- `NotationLayoutEngineTests`: multi-row wrapping is deterministic from fixed grid width.
- `GameplayViewModelVisualUpdatesTests`: purple-bar beat-boundary x equals the shared mapper's x for the rendered notation measure.
- `GameplayViewModelVisualUpdatesTests`: end-of-track purple-bar clamping uses the grid end column.
- `GameplayViewModelComputationsTests` or a focused equivalent: cached beat positions use rendered notation layout rows and x mapping when notation layout is active.

Existing tests that assert local adaptive expansion, such as "sixteenth notes expand measure width", should be rewritten because HPA-140 intentionally removes per-measure adaptive width.

## 12. Verification

Run focused tests first:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -parallel-testing-enabled NO test

xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/GameplayViewModelVisualUpdatesTests \
  -parallel-testing-enabled NO test
```

Before merging implementation, run the repo macOS unit-test command from `CLAUDE.md` with `-parallel-testing-enabled NO`.

## 13. Risks

- A chart-level fixed scale can make genuinely dense charts wider and produce more rows. That is acceptable for HPA-140 because zoom is out of scope.
- Mixing imported normalized notes and legacy notes requires careful tick scaling. Tests should cover this if implementation touches mixed charts.
- Voice collision means some note heads are visually offset from the canonical column. Tests should distinguish canonical x alignment from collision-offset notehead x.
- Existing tests around adaptive width will need intentional updates, not compatibility shims.
