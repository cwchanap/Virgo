# DrumNotation

Local Swift package owning reusable drum-notation engraving and the static notation view:
resolved input validation, measured horizontal formatting, stem/beam/flag topology, immutable
engraved geometry (`EngravedNotation`), and `DrumNotationView` painting it through the vendored
Bravura/SMuFL glyphs. The dependency direction is one-way: Virgo depends on DrumNotation; the
package has no dependency on Virgo source, SwiftData, app design tokens, or app state.

## Public flow

```swift
let input = try ResolvedNotationInput(
    ticksPerWholeNote: 1920,
    measures: [ResolvedMeasure(index: 0, startTick: 0, durationTicks: 1920,
                               meter: NotationMeter(beats: 4, noteValue: 4), beatGroups: [...])],
    notes: [ResolvedNote(...)]
)
let layout = try NotationEngraver.engrave(
    input,
    style: NotationEngravingStyle()
)
let position = layout.position(measureIndex: 0, localTick: 240)
let view = DrumNotationView(layout: layout, accessibilityLabels: [:])
```

`NotationEngraver.engrave` is the single public route to geometry; `DrumNotationView` is the single
public route to pixels. `NotationFormatter.format` remains public for consumers that need the
formatting layer alone, but `engrave` already embeds the `FormattedNotation` it produces
(`EngravedNotation.formatted`), including the `position(measureIndex:localTick:)` lookup the live
playhead consumes.

## Ownership boundary

The package owns:

- `ResolvedNotationInput` and the resolved model: `ResolvedMeasure` (meter + beat groups),
  `ResolvedNote` (stem direction, staff step, notehead style, duration, dots, voice, exact
  `durationTicks`, caller-resolved `tiebreakOrder`, `isRhythmEngravable`, articulation),
  `ResolvedRest`, `ResolvedControl`, and `ResolvedTupletGroup`.
- `NotationFormatter` — the sole horizontal formatting/X authority.
- `StemTopologyBuilder` — one shared stem-group topology that drives stems, beams, flags, and the
  formatter's collision reservations; there is no second opinion.
- `NotationEngraver` — primitive geometry and one package-level Y normalization.
- `EngravedNotation` — immutable final sheet-local geometry.
- `DrumNotationView` — static painting of the engraving via `DrumNotationAppearance` colors and a
  caller-supplied `[NotationSemanticID: String]` VoiceOver map.
- The vendored Bravura font, its SMuFL metadata, and the closed glyph catalog (below).

The caller (Virgo) owns everything upstream and alongside:

- Rhythm inference and validation (`RhythmTimelineResolver`, `NotationRhythmAnalyzer`) — the
  package never sees BPM, seconds, DTX lanes, or unresolved durations.
- The `ResolvedNotationInput` projection (`VirgoNotationProjection`), including voice assignment,
  staff-step ordering, suppression, and tuplet inference.
- Playback, scrolling, and the playhead — the app reads `EngravedNotation.position` and
  `EngravedRow.staffCenterY`; the package never observes a clock.
- Localized accessibility copy — labels arrive view-only through `DrumNotationView`'s
  `accessibilityLabels` map; no localized string enters the model or the geometry.
- App presentation: feel marks, rhythm warnings, palette, fonts other than Bravura.

## Engraving contract (HPA-164/HPA-166)

Input is `ResolvedNotationInput` — `ticksPerWholeNote` plus `ResolvedMeasure`s
(index/startTick/durationTicks/meter/beat groups), `ResolvedNote`s, printed `ResolvedRest`s,
`ResolvedControl`s (timing anchors with zero collision width) and `ResolvedTupletGroup`s.
Construction validates: positive `ticksPerWholeNote`, unique/valid/non-overlapping measures, beat
groups covering each measure contiguously, unique event IDs, positive durations, every event
`localTick` inside its owning measure, every note/rest span inside its measure, and tuplet member
references. Absolute tick is derived (`startTick + localTick`), never accepted as input.

Output is immutable `EngravedNotation`: rows, measures, note heads, rests, stems, beams, flags,
ledger lines, rhythm dots, articulations, controls, tuplets, measure bars, painted bounds, content
extents, and the embedded `FormattedNotation`. All X/Y is **final normalized sheet-local
geometry** — the engraver applies one package-level Y normalization after painted bounds are
collected; the caller applies no post-format transform on either axis.

Beam/flag/stem geometry and spacing come from one `StemTopologyBuilder` pass: the same groups
decide which notes share beams, which members carry forward/backward hooks, which isolated notes
paint duration-specific flags, and how much flag/beam ink each onset column reserves in the
formatter. `isRhythmEngravable == false` suppresses a note's duration ink (stems/beams/flags/dots)
while its head still paints — the mechanism a caller uses to keep note identity in a measure that
does not permit engraving.

Spacing, widths, rows and lookup are deterministic one-pass rules — no global density scan, iterative
relaxation or chart-wide X-per-tick scale, so a dense measure never rescales a sparse neighbor:

- **Per-gap rule.** The tick-0 column sits at `leadingMeasureInset`; each next column advances by
  `max(rhythmicGap, collisionGap)` with `rhythmicGap = minimumQuarterNoteSpacing * deltaTicks * 4 /
  ticksPerWholeNote` (multiply-then-divide, exact up to the final `CGFloat`) and `collisionGap =
  previous.rightExtent + minimumInterColumnClearance + next.leftExtent`.
- **Measure width.** Natural, never compressed: `leadingMeasureInset + (tick-0 → end-anchor span) +
  trailingMeasureInset`. An over-wide measure keeps its natural width.
- **Row packing.** Greedy over whole measures: each row's first measure sits at `rowLeadingInset`,
  `measureSpacing` separates measures on a row, and a measure wraps to the next row before it would
  cross `availableRowWidth`; a measure that cannot fit even alone on a row still gets its own row at
  natural width.
- **Full-measure rests.** The timing anchor stays the column's `logicalColumnX`; the rest's
  `visualX` (finalized once the width is known) is the center of the measure content span
  (`leadingMeasureInset … width − trailingMeasureInset`).
- **Tick lookup.** `position(measureIndex:localTick:)` takes a `Double` local tick (the live
  playhead passes continuous ticks). Exact anchors return their `logicalColumnX`; values between
  anchors interpolate linearly between adjacent columns of the same measure only — never across a
  measure or row boundary. The start/end anchor columns make empty, control-only and trailing
  measures resolvable across their full span. Tiny floating-point drift at the measure edges
  (±1e-6 ticks) clamps to the boundary anchor; anything further outside, an unknown measure index,
  or non-finite input returns nil.

The default style `NotationFormattingStyle.virgoDefault` pins the Virgo mapping:
`availableRowWidth` 900 (the app's row-width floor), `rowLeadingInset` 100, `staffSpace` 20,
`stemWidth` 2, `minimumInterColumnClearance` 8, `minimumQuarterNoteSpacing` 50, `measureSpacing` 12,
`leadingMeasureInset` 52, `trailingMeasureInset` 0, `rhythmDotRadius` 2.5, `rhythmDotSpacing` 4.

`minimumInterColumnClearance` is **edge-to-edge** clearance between adjacent column ink — not a
center-to-center pitch. The 8pt default derives from the old 28pt center pitch minus the X-black
notehead width at staff-space 20 (the vendored Bravura head paints 23.2pt ≈ 1.16 staff spaces, so
the real collision pitch is ≈31.2pt; the historical 28pt figure assumed a 20pt hand-drawn head); it
is a semantic conversion, not a field rename.

## View contract

`DrumNotationView` paints `EngravedNotation` plus row furniture (staff lines, drum clef, meter
numerals, bar lines) at the engraving's final coordinates. It reads nothing from the app: no
Virgo environment values, theme, or global layout, and no gameplay clock. Colors come from
`DrumNotationAppearance`; VoiceOver text comes from the `accessibilityLabels` map keyed by
`NotationSemanticID` (`.note(id)`, `.rest(id)`, `.control(id)`, `.tuplet(id)`). Accessibility copy
is a view-only input — changing the label map never changes engraving equality or geometry.

## Vendored Bravura font

`Resources/Bravura/` contains the Bravura font, its SMuFL `metadata.json`, and its license,
vendored verbatim.

- Semantic reference: [VexFlow](https://github.com/0xfe/vexflow) 5.0.0 — the glyph selection
  (which codepoint a normal/X/diamond head, rest, flag, or articulation maps to) mirrors
  VexFlow's percussion rendering semantics.
- Font reference: [`@vexflow-fonts/bravura`](https://github.com/vexflow/vexflow-fonts) 1.0.2,
  which packages Bravura 1.392.
- Source commit: `vexflow/vexflow-fonts@b2bc3a6070225e4d395966b36de76c36a9429b1c`.
- No Node, jsdom, VexFlow runtime, or HPA-163 generator ships with or is invoked by this
  package — glyphs are looked up through a closed internal catalog at runtime.

## Percussion notehead legend

- **normal** — standard round notehead (regular drum hits: kick, snare, toms).
- **X** — cross notehead (cymbals: hi-hats, crash, ride, china, splash).
- **diamond** — diamond notehead (cowbell).

The old Virgo app's hand-drawn half-circle, bullseye, and open-circle notehead shapes are
intentionally retired in favor of these SMuFL glyphs.

## Closed SMuFL glyph table

The runtime lookup is a closed internal catalog (`Sources/DrumNotation/Glyphs/SMuFLGlyphCatalog.swift`)
pinned to Bravura 1.392 (SMuFL 1.3 codepoints); this table records it exactly.

| Semantic slot | SMuFL glyph | Codepoint |
| --- | --- | --- |
| Normal whole notehead | `noteheadWhole` | U+E0A2 |
| Normal half notehead | `noteheadHalf` | U+E0A3 |
| Normal black notehead | `noteheadBlack` | U+E0A4 |
| X whole notehead | `noteheadXWhole` | U+E0A7 |
| X half notehead | `noteheadXHalf` | U+E0A8 |
| X black notehead | `noteheadXBlack` | U+E0A9 |
| Diamond whole notehead | `noteheadDiamondWhole` | U+E0D8 |
| Diamond half notehead | `noteheadDiamondHalf` | U+E0D9 |
| Diamond black notehead | `noteheadDiamondBlack` | U+E0DB |
| Whole rest | `restWhole` | U+E4E3 |
| Half rest | `restHalf` | U+E4E4 |
| Quarter rest | `restQuarter` | U+E4E5 |
| Eighth rest | `rest8th` | U+E4E6 |
| 16th rest | `rest16th` | U+E4E7 |
| 32nd rest | `rest32nd` | U+E4E8 |
| 64th rest | `rest64th` | U+E4E9 |
| 8th flag, stem up | `flag8thUp` | U+E240 |
| 8th flag, stem down | `flag8thDown` | U+E241 |
| 16th flag, stem up | `flag16thUp` | U+E242 |
| 16th flag, stem down | `flag16thDown` | U+E243 |
| 32nd flag, stem up | `flag32ndUp` | U+E244 |
| 32nd flag, stem down | `flag32ndDown` | U+E245 |
| 64th flag, stem up | `flag64thUp` | U+E246 |
| 64th flag, stem down | `flag64thDown` | U+E247 |
| Open articulation | `pictOpen` | U+E7F8 |
