# Gameplay Note Rendering Design

## Context

Virgo's gameplay notation currently renders notes through a split set of responsibilities:

- `GameplayViewModel` groups SwiftData `Note` values into `DrumBeat` values and caches x/y positions.
- `GameplayLayout` provides fixed horizontal and vertical constants.
- `DrumBeatView` decides notehead, stem, flag, and connector geometry while drawing.
- `BeamView` draws flat beams independently from notehead/stem layout.

This makes the renderer fragile because notation rules are inferred locally by SwiftUI views instead of being resolved once by a layout pass. The current symptoms are:

- Sixteenth notes are visually too dense because a 4/4 measure uses fixed quarter-note spacing, which leaves only 12.5px between sixteenth-note columns.
- Notes above or below the five staff lines do not receive ledger lines.
- Mixed rhythms such as sixteenth snare plus eighth kick can collide because same-time grouping does not model visual voices.
- Stem and beam direction is incorrect for high notes because stems/beams are effectively always drawn upward.

The product priority is gameplay readability over strict sheet-music engraving. The renderer should still be music-aware, but it may expand spacing, separate voices, or simplify engraving if that produces a clearer playable chart.

## Goals

- Render dense drum charts clearly enough for gameplay, especially sixteenth-note passages.
- Centralize notation layout decisions in one pure, testable layout engine.
- Support ledger lines for notes outside the main five-line staff.
- Support stem and beam direction decisions based on visual voice and note height.
- Separate upper drum voices from lower kick/pedal voices when needed to prevent collisions.
- Keep SwiftUI rendering fast by caching resolved geometry before playback.

## Non-Goals

- Full professional engraving fidelity.
- Rest rendering, ties, tuplets, grace notes, or cross-staff notation.
- Changing input timing, scoring, MIDI routing, or DTX parsing semantics.
- Reworking the gameplay playback or metronome synchronization architecture.

## Proposed Architecture

Add a pure `NotationLayoutEngine` under `Virgo/layout/`. It converts raw notes and track metadata into render primitives that SwiftUI can paint without re-deciding notation rules.

Inputs:

- `[Note]`
- `TimeSignature`
- drum-to-staff-position map
- `NotationLayoutStyle`

Outputs:

- `NotationLayout`
- `RenderedMeasure`
- `RenderedNoteHead`
- `RenderedStem`
- `RenderedBeam`
- `RenderedLedgerLine`
- `RenderedMeasureBar`

`GameplayViewModel` should call the layout engine during setup and cache the resulting `NotationLayout`. `GameplaySheetMusicView` should render from this layout instead of directly iterating `cachedDrumBeats`, `cachedBeamGroups`, and `cachedBeatPositions`.

The existing `DrumBeat` and `BeamGroup` types can be kept temporarily during migration, but the target state is for them to become internal implementation details or be replaced by layout primitives.

## Layout Rules

### Horizontal Spacing

Measure width should be adaptive. The engine should inspect the smallest subdivision used in each measure and enforce a minimum readable column gap.

Initial style constants:

- Minimum note-column gap: 28px.
- Minimum quarter-beat gap: keep the existing 50px when density is low.
- Measure padding: preserve room for bar lines and visual breathing space.

For a 4/4 measure with sixteenth notes, the measure should expand enough that adjacent sixteenth-note columns are at least the minimum column gap. This is more important than fitting more measures per row.

### Gameplay Voices

The engine should split notes into visual voices:

- Lower voice: kick and hi-hat pedal.
- Upper voice: snare, toms, cymbals, cowbell, hi-hat, ride.

At the same time position, notes within a voice may share a stem when visually compatible. Notes across voices should be allowed to use separate stems and small x offsets when needed. This prevents kick/snare mixed rhythms from creating ambiguous columns.

### Vertical Positioning

All vertical geometry should use a single staff-step coordinate system, then convert to pixels in one place. This avoids mixing relative y offsets in the layout layer with absolute row positions in views.

The initial implementation should use the current default `DrumType.notePosition` mapping. Integrating `DrumNotationSettingsManager` into gameplay rendering is a separate follow-up because the settings screen currently does not appear to feed gameplay notation.

### Ledger Lines

For every notehead outside the five staff lines, emit short horizontal ledger-line primitives for each crossed staff line.

Rules:

- Ledger width should be wider than the notehead by a small margin.
- Ledger lines should be centered on the notehead x position.
- Multiple simultaneous noteheads sharing a ledger line may merge into one wider ledger primitive if their x ranges overlap.

### Stem Direction

Stem direction should be explicit on every rendered stem.

Default gameplay rules:

- Lower voice stems down.
- Upper voice stems up unless the group's average note height is above the staff midpoint enough that downward stems improve readability.
- High cymbal/crash groups above the staff should stem down with beams below the noteheads.
- Single unbeamed notes should use the same direction rule as their voice/group.

### Beams

Beam geometry should be produced by the layout engine, not by `BeamView`.

Rules:

- Beam groups do not cross measure boundaries.
- Beam groups do not cross row boundaries.
- Beam side follows stem direction.
- Beam levels follow `NoteInterval.flagCount`.
- For gameplay readability, beams can stay flat initially; sloped beams are optional later.

### Rendering

SwiftUI views should become renderers for primitives:

- `NoteHeadView` paints the drum symbol.
- `StemPrimitiveView` paints a stem from `start` to `end`.
- `BeamPrimitiveView` paints a beam segment.
- `LedgerLineView` paints a short horizontal line.
- `MeasureBarView` paints regular and final bar lines.

Views should not calculate beam membership, stem direction, ledger-line count, or collision offsets.

## Data Flow

1. `GameplayViewModel.loadChartData()` caches SwiftData relationships as it does today.
2. `GameplayViewModel.setupGameplay()` builds a `NotationLayoutInput`.
3. `NotationLayoutEngine.layout(input:)` returns a pure `NotationLayout`.
4. `GameplayViewModel` caches the layout and creates fast lookup maps for active-beat highlighting and purple-bar positioning.
5. `GameplaySheetMusicView` renders layout primitives.
6. Playback updates only active state and progress indicator position, not static note geometry.

## Testing

Use Swift Testing with pure layout tests where possible:

- Sixteenth notes in 4/4 produce adjacent x positions at least 28px apart.
- A note above `line5` emits the expected ledger line count.
- A kick plus snare at the same time position produces separate lower/upper voice stems.
- High cymbal groups choose downward stems and below-note beams.
- Beam groups stop at measure boundaries.
- Beam groups stop at row boundaries.
- Low-density quarter-note measures preserve existing readable spacing.

SwiftUI snapshot-style tests can remain secondary because the critical behavior is deterministic geometry.

## Migration Plan

Implement incrementally to reduce risk:

1. Add layout primitive models and `NotationLayoutEngine` with tests.
2. Move horizontal position calculation into the engine while rendering existing note views from engine positions.
3. Add ledger-line primitives and render them.
4. Add explicit stem-direction and beam primitives.
5. Add gameplay voice separation and collision offsets.
6. Remove or deprecate duplicated stem/beam decisions from `DrumBeatView` and `BeamView`.

## Follow-Up Decisions

- Whether `DrumNotationSettingsManager` should become a gameplay rendering dependency.
- Exact minimum spacing constants may need tuning after viewing real dense charts.
- Whether to keep flat beams permanently or add optional sloped beams later.
