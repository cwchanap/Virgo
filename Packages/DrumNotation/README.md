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

- **normal** — standard round notehead (regular drum hits).
- **X** — cross notehead (cymbals, hi-hat).
- **diamond** — diamond notehead (open hi-hat/ride bell style hits).

The old Virgo app's hand-drawn half-circle, bullseye, and open-circle notehead shapes are
intentionally retired in favor of these SMuFL glyphs.
