# DrumNotation

Local Swift package holding shared drum-notation primitives (glyph rendering, duration types).
Consumed by the Virgo app target; has no dependency on Virgo source.

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

## Measured formatter contract (HPA-164)

The package owns measured formatting over an exact integer-tick coordinate space. Input is
`ResolvedNotationInput` — `ticksPerWholeNote` plus `ResolvedMeasure`s (index/startTick/durationTicks),
`ResolvedNote`s (integer ID, measure/local tick position, stem direction, staff step, notehead style,
duration, dots, optional visible-flag duration), printed `ResolvedRest`s (ID, position, duration, dots,
`isFullMeasure`) and `ResolvedControl`s (ID + position). Construction validates: positive
`ticksPerWholeNote`, unique/valid/non-overlapping measures, and every event `localTick` inside its owning
measure. Absolute tick is derived (`startTick + localTick`), never accepted as input. There is no
package voice, tuplet, beat group, BPM/seconds or DTX lane — the caller filters and resolves first.

Output is immutable `FormattedNotation`: measures ordered by index, each with row assignment,
sheet-local `xOffset`/`width`, and tick-ordered `FormattedColumn`s carrying the logical onset X
(`logicalColumnX`, never displaced), per-head visual `headCenterX` (VexFlow staff-second displacement),
the printed rest's visual X, and `leftExtent`/`rightExtent` collision ink reaches measured relative to
`logicalColumnX` (displaced heads + dots + printed rests + visible flag ink attached at its stem
direction's stem axis — the head glyph's `stemUpSE`/`stemDownNW` anchor at the undisplaced column;
controls are timing anchors with zero width). `NotationFormatter.format(_:style:)` currently
builds columns/displacement/extents only — spacing, measure widths, row packing and tick interpolation
land with the measured-spacing task, so columns stay at `logicalColumnX` = 0 relative to their measure
until then.

The default style `NotationFormattingStyle.virgoDefault` pins the Virgo mapping:
`availableRowWidth` 900 (the app's row-width floor), `rowLeadingInset` 100, `staffSpace` 20,
`stemWidth` 2, `minimumInterColumnClearance` 8, `minimumQuarterNoteSpacing` 50, `measureSpacing` 12,
`leadingMeasureInset` 52, `trailingMeasureInset` 0, `rhythmDotRadius` 2.5, `rhythmDotSpacing` 4.

`minimumInterColumnClearance` is **edge-to-edge** clearance between adjacent column ink — not a
center-to-center pitch. The 8pt default derives from the old 28pt center pitch minus the common
20pt X-black notehead width at staff-space 20; it is a semantic conversion, not a field rename.

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
