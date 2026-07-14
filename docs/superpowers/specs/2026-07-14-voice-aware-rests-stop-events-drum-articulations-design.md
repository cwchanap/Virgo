# Voice-Aware Rests, Stop Events, and Drum Articulations Design

- **Date:** 2026-07-14
- **Status:** Design approved; awaiting written-spec review
- **Scope:** Add deterministic per-voice rest topology, first-class non-scoreable stop-family events, and visible
  hi-hat articulation marks without changing Virgo's fixed notation grid.
- **Linear:** [HPA-143](https://linear.app/cwchanap/issue/HPA-143/render-voice-aware-rests-stopchoke-events-and-drum-articulations)
- **Parent:** [HPA-97](https://linear.app/cwchanap/issue/HPA-97/fix-drum-tab-rendering-spacing-beams-flags-rests-and-stop-note)

## 1. Context

HPA-139 through HPA-142 established the notation contracts that HPA-143 must preserve:

- imported playable notes retain normalized source identity and integer timing;
- notation and the playhead share one fixed `TabGrid`;
- same-time drum voices share one immutable x-coordinate;
- `DrumNotationCatalog` preserves lane-specific variants, notation voice, glyph, staff position, and stem direction;
- beams, hooks, flags, and stems are derived from semantic note events with deterministic boundaries.

The current layout stops at playable note geometry. `NotationLayout` has no rest, control-event, or articulation-overlay
collections. Empty time in upper and lower voices is therefore invisible, stop or choke events have no model separate
from scoreable notes, and open and closed hi-hats both draw the same cross notehead even though
`RenderedNoteHead.variant` distinguishes them.

The parser also does not have an authoritative mapping for DTX mute chips. It parses raw chips before filtering playable
lanes, but chart-local sample IDs and filenames such as `*_mute.ogg` are not a reliable semantic contract. HPA-143 must
create the downstream control-event architecture without guessing that mapping.

## 2. Goals

- Represent silence independently for upper and lower notation voices.
- Render full-measure rests for silent voices and beat-level rests inside active voices.
- Keep hidden spacing and duplicate-suppression rests explicit in semantic topology.
- Model stop, choke, and damp events separately from playable `Note` objects.
- Preserve normalized timing, source identity, control kind, and optional target lane for every control event.
- Render control events at deterministic fixed-grid positions without creating noteheads, stems, beams, flags, or score
  targets.
- Make closed, open, and pedal hi-hat notation visibly distinct using the HPA-141 catalog variant.
- Keep rest, control, and articulation geometry vector-based and independent of font metrics.
- Preserve all HPA-140 through HPA-142 spacing, playhead, notehead, stem, and beam invariants.
- Provide pure topology tests, persistence coverage, layout integration tests, and SwiftUI primitive coverage.

## 3. Non-Goals

- No guessed DTX mute classification from sample filenames, chart-local sample IDs, or undocumented lane assumptions.
- No per-chip sample playback or audio-engine choking; the current gameplay path synchronizes BGM rather than playing
  individual chart samples.
- No scoring, hit matching, combo, MIDI, keyboard, or input-window changes.
- No rest-aware rewrite of HPA-142 beam topology. Rests are derived after beams and do not regroup playable notes.
- No tuplets, dotted rhythms, swing, shuffle, compound-meter rest grouping, or variable measure lengths. HPA-145 owns
  those semantics.
- No synthesized tie, sustain, or release semantics when source data does not represent them explicitly.
- No broad screenshot or golden-fixture matrix. HPA-144 owns that regression layer.
- No music-font or SMuFL dependency and no general engraving redesign.
- No iPhone destination, targeting, or UI assumption.

## 4. Approved Decisions

1. **Parallel semantic tracks:** playable notes, rests, and control events remain separate domain concepts. A rest or
   stop event is never encoded as a special `Note`.
2. **Post-grid derivation:** the engine builds `TabGrid`, measures, noteheads, stems, beams, and flags first. Rest and
   control geometry is translated afterward so it cannot influence spacing or beam membership.
3. **Pure rest topology:** a geometry-free `NotationRestTopologyBuilder` computes per-voice occupied and silent spans
   using canonical integer ticks.
4. **Balanced full-measure visibility:** when only one voice is active, the silent voice prints a full-measure rest.
   When both voices are silent, the upper full-measure rest prints and the lower duplicate remains explicit but hidden.
5. **Contract-first controls:** build the persistent, snapshot, layout, and rendering contracts for `.stop`, `.choke`,
   and `.damp`, plus a focused explicit choke fixture. Production DTX classification remains empty until an
   authoritative mapping or real fixture is available.
6. **Catalog-owned hi-hat identity:** `RenderedNoteHead.variant`, not collapsed `DrumType`, decides whether an open
   hi-hat overlay is present. Closed and pedal behavior stay catalog-driven.
7. **Conservative fallback:** unsupported or inexact timing produces hidden spacing topology or an omitted control mark
   with a diagnostic. The renderer never rounds into a different musical meaning.
8. **Renderable is not playable:** rest/control-only layouts use the notation coordinate system, but only layouts with
   playable noteheads drive the playhead, beat caches, and row scrolling.

## 5. Architecture

The feature adds three independent semantic paths that meet only in `NotationLayout`:

```text
Playable Note
  -> RenderedNoteHead
  -> existing stems / beams / flags
  -> RestTimelineNote
  -> NotationRestTopologyBuilder
  -> RenderedRest

ChartControlEvent
  -> immutable NotationControlEvent snapshot
  -> fixed-grid target resolution
  -> RenderedStopNote

RenderedNoteHead.variant
  -> articulation descriptor
  -> RenderedArticulation
```

`NotationLayoutEngine.layout(input:)` remains the coordinator. Pure builders decide semantics; layout extensions
translate those decisions into `CGPoint` values; SwiftUI primitive views draw only the supplied geometry.

## 6. Control-Event Domain Contract

### 6.1 Persisted model

Add `Virgo/models/ChartControlEvent.swift` with a kind that is independent of scoring:

```swift
enum NotationControlEventKind: String, Codable, CaseIterable {
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

    var originKind: NoteOriginKind = .manual
    var sourceLaneID: String?
    var sourceNoteID: String?
    var sourceGridPosition: Int?
    var sourceGridSize: Int?
    var normalizedMeasureIndex: Int?
    var normalizedAbsoluteTick: Int?
    var normalizedTickWithinMeasure: Int?
    var normalizedTicksPerMeasure: Int?
    var targetLaneID: String?
}
```

The timing and source fields deliberately mirror `Note` where they have the same meaning. The model deliberately has
no `NoteType`, `NoteInterval`, gameplay instrument, notation voice, score value, or hit-window behavior.

`Chart` gains a cascade relationship named `controlEvents`, a `safeControlEvents` accessor, and an initializer default
of `[]`. Copy/import helpers must copy control events independently from notes. Every active app and test `Schema`
registration must include `ChartControlEvent`.

The complete registration list is:

- `Virgo/VirgoApp.swift`;
- `Virgo/services/ScorePersistenceService.swift`;
- `VirgoTests/TestHelpers.swift`;
- `VirgoTests/PatchCoverageAdditionsTests.swift`;
- `VirgoTests/NavigationTests.swift`;
- `VirgoTests/ChartModelDefaultPropertyTests.swift`;
- `VirgoTests/DrumTrackTests.swift`.

This is an additive model registration. HPA-143 updates every current app, service, preview, and test schema and verifies
fresh-container persistence and relationship behavior. It does not introduce a parallel `VersionedSchema` framework or
broaden HPA-146, which separately owns versioned migration testing for the existing HPA-139 fields.

### 6.2 Immutable layout snapshot

SwiftData relationships must not be traversed during SwiftUI rendering. `GameplayViewModel` asynchronously caches the
chart relationship and converts each live model into an immutable value:

```swift
struct NotationControlEvent: Hashable {
    let kind: NotationControlEventKind
    let measureNumber: Int
    let measureOffset: Double
    let sourceLaneID: String?
    let sourceNoteID: String?
    let sourceGridPosition: Int?
    let sourceGridSize: Int?
    let normalizedMeasureIndex: Int?
    let normalizedAbsoluteTick: Int?
    let normalizedTickWithinMeasure: Int?
    let normalizedTicksPerMeasure: Int?
    let targetLaneID: String?
}
```

`NotationLayoutInput` gains `controlEvents: [NotationControlEvent]` with an empty default so existing call sites remain
source-compatible. The snapshot contains no SwiftData reference or rendering geometry.

`ChartRelationshipData` and `ChartRelationshipLoader` remain unchanged. Their contract is specifically
`notesCount`/`notes`/`measureCount`, they have no production consumer, and gameplay already bypasses them. Adding an
unused `controlEvents` field there would duplicate the dedicated `GameplayViewModel` cache without serving a caller.

### 6.3 Classification boundary

The production DTX parser does not infer control events in HPA-143. In particular:

- a sample filename containing `mute`, `stop`, or `choke` is not classification evidence;
- a chart-local sample ID is not a stable semantic identifier;
- an unknown non-playable lane is not silently treated as a choke;
- a control target is not guessed from the nearest playable cymbal.

The new model and value snapshot are the stable destination for a future authoritative parser mapping. HPA-143's choke
fixture constructs an explicit `ChartControlEvent` with a catalog-resolvable target lane, exercising the complete
persistence-to-rendering path without claiming unsupported DTX semantics.

## 7. Rest Topology Contract

### 7.1 Pure types

Add `Virgo/layout/NotationRestTopology.swift`. Its types contain integer musical time and no Core Graphics, SwiftUI,
SwiftData, logging, or view state:

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

enum NotationRestVisibility: Hashable {
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
}
```

`NotationRestVisibility` makes the distinction between visible silence, an unsupported spacing placeholder, and a
suppressed duplicate testable. Both `RestTopologyEvent` and `RenderedRest` expose an `isPrinted` computed property equal
to `visibility == .printed`; topology policy and layout activation therefore share one definition.

`NotationRestTopologyBuilder` accepts timeline notes, total measure count, ticks per measure, and the time signature. It
returns deterministically ordered `RestTopologyEvent` values. It does not know staff positions or pixels.

### 7.2 Timeline-note formation

Layout forms one `RestTimelineNote` per rendered notehead using:

- the HPA-140 `NotationTimeColumn`;
- the HPA-141 `NotationVoice` resolved by `DrumNotationCatalog`;
- the rendered `NoteInterval` converted into exact ticks on the already-built `TabGrid`.

For supported X/4 meters, require `ticksPerMeasure` to divide exactly into `beatsPerMeasure` quarter-note spans. Convert
full, half, quarter, eighth, sixteenth, thirty-second, and sixty-fourth note occupancy as rational multiples of that
quarter duration, returning `nil` unless the final tick count is a positive integer. A full-note occupancy can extend
past a short bar and is clipped at the measure boundary. For a `/8` meter, internal duration conversion is unsupported
in HPA-143; only the full-measure visibility policy remains active until HPA-145 supplies compound-meter grouping.

The control-event collection is never supplied to the rest builder. A stop, choke, or damp event does not occupy a
voice, split a rest, or hide silence.

The supported internal rest vocabulary is the closed undotted power-of-two set on `NotationRestDuration`: half,
quarter, eighth, sixteenth, thirty-second, and sixty-fourth. The enum intentionally has no ordinary `full` case, so an
invalid `.interval(.full)` state cannot be constructed. `.fullMeasure` is separate because it represents the whole
active bar in 2/4, 3/4, 4/4, or 5/4 rather than a four-quarter duration.

## 8. Rest-Synthesis Algorithm

The builder processes each measure and voice independently.

### 8.1 Occupied spans

1. Group timeline notes by `(measureIndex, voice, startTick)`.
2. Resolve a same-time chord to one occupied span. If every member has an exact duration, use the longest member so the
   voice does not appear silent while one chord tone is still sustained.
3. Clip the occupied span to the next onset in the same measure and voice, then to the measure end. Notes in the other
   voice do not shorten it.
4. Merge overlapping exact occupied spans before finding gaps.
5. If any same-time member has an unrepresentable duration, treat the region from that onset to the next same-voice
   onset or measure end as uncertain. Do not print a rest through that region.

This is notation occupancy only. It does not change audio duration or gameplay timing.

### 8.2 Gap decomposition

Walk `[0, ticksPerMeasure)` as exact occupied, exact silent, and uncertain spans. Decompose only exact silent gaps:

1. Start at the gap's first tick.
2. Choose the longest supported interval whose tick duration is exact, fits in the remaining gap, and satisfies
   `startTick % durationTicks == 0` on the measure grid.
3. Emit that printed rest and advance by its duration.
4. Repeat until the gap is exhausted.
5. If no supported interval can represent the remaining ticks exactly, emit one `.hiddenSpacing` event for that
   remainder rather than rounding or inventing dotted/tuplet notation.

Uncertain spans also emit `.hiddenSpacing` topology so their reserved timing remains observable to tests without making
a false statement about visible silence.

### 8.3 Full-measure policy

After onset formation, apply the approved per-measure visibility rules:

- If exactly one voice has playable onsets, the other voice receives one printed `.fullMeasure` rest.
- If neither voice has playable onsets, the upper voice receives one printed `.fullMeasure` rest and the lower voice
  receives the same semantic rest with `.hiddenDuplicate` visibility.
- If a voice has any playable onset, synthesize its internal gaps under the meter support rules in section 7.2; it does
  not also receive a full-measure rest.

This policy applies even when the measure contains only control events, because controls are not playable onsets.

### 8.4 Determinism and identity

Sort topology by measure index, upper before lower voice, start tick, duration, and visibility. Rendered identifiers use
the semantic tuple `(measure, voice, startTick, durationTicks, duration, visibility)` rather than collection order or a
randomized hash.

For malformed duplicate topology, a deterministic duplicate ordinal is appended after sorting. Shuffling input notes
must not change events, identifiers, or order.

## 9. Layout Integration

`NotationLayoutEngine.layout(input:)` uses this order:

1. Sort playable notes.
2. Determine total measures from `minimumMeasureCount`, playable-note timing, and valid control-event timing.
3. Build `TabGrid` from playable notes exactly as HPA-140 does today.
4. Build rendered measures and playable noteheads.
5. Build existing beams, stems, flags, ledger lines, and measure bars.
6. Form rest timeline notes and ask `NotationRestTopologyBuilder` for topology.
7. Translate rest topology into `RenderedRest` values using existing measures and `TabGrid`.
8. Resolve immutable control events into `RenderedStopNote` values on the same grid.
9. Derive articulation overlays from rendered notehead variants.
10. Return all collections in `NotationLayout`.

Control events are intentionally excluded from `buildTabGrid(notes:input:)`. Adding a control event must not change
`ticksPerMeasure`, `tickWidth`, `measureWidth`, wrapping, playable note x-coordinates, or playhead columns.

Complete normalized metadata is authoritative for a control event. Validate that measure index, tick within measure,
absolute tick, and source ticks per measure are nonnegative, in range, and internally consistent. Rescale the source
fraction onto the existing `TabGrid` only when integer division is exact. A manual event without complete normalized
metadata can fall back to `measureNumber` and `measureOffset`, again only when the resulting grid column is exact.
Invalid or inconsistent events contribute neither a measure nor rendered geometry. If the existing grid cannot
represent a valid event's fraction, preserve the event, omit its visual mark, and log a diagnostic rather than raising
grid resolution or rounding the event.

Extract one pure exact-rescaling helper from the current note branch:

```swift
exactRescaledTick(
    sourceTick: Int,
    sourceTicksPerMeasure: Int,
    targetTicksPerMeasure: Int
) -> Int?
```

The helper validates the source range and applies the existing
`targetTicksPerMeasure.isMultiple(of: sourceTicksPerMeasure)` predicate before multiplying. The normalized note path
calls it first and retains its current rounded `measureOffset` fallback when it returns `nil`. The control path calls the
same helper but omits the mark when it returns `nil`; it must not call the note path's rounding fallback.

`NotationLayout` gains:

```swift
let rests: [RenderedRest]
let stopNotes: [RenderedStopNote]
let articulations: [RenderedArticulation]
```

It also gains two explicit predicates:

```swift
var hasPlayableContent: Bool { !noteHeads.isEmpty }

var hasRenderableContent: Bool {
    hasPlayableContent || rests.contains(where: \.isPrinted) || !stopNotes.isEmpty
}
```

Articulations do not need a separate term because every articulation belongs to a playable notehead. Hidden rests and
unresolved controls satisfy neither predicate by themselves.

The predicates have intentionally different consumers:

- `hasRenderableContent` selects the notation coordinate system in `GameplaySheetMusicView`, notation measures and
  content size, measure-position maps, and the cached notation staff background.
- `hasPlayableContent` gates playable beat-position caches, notation playhead calculation, current-row advancement, and
  playback-driven row scrolling.
- `spacingAboveLine5(for:)` remains a notehead-specific geometry calculation rather than a content-activation gate; its
  existing extra staff-spacing margin must contain the open-hi-hat circle.

A rest/control-only chart therefore renders its notation measures and primitives but does not acquire score targets or
drive the playhead and row scroll. Once `hasRenderableContent` selects notation geometry, a false
`hasPlayableContent` returns no playhead instead of falling back to legacy playhead coordinates. This avoids overlaying
two layout systems while keeping HPA-143 out of playback-duration semantics.

## 10. Rendered Primitives

### 10.1 Rests

`RenderedRest` carries semantic identity and resolved geometry:

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
}
```

Interval rests anchor to their start column. Full-measure rests use the visual midpoint of the rendered measure while
retaining tick zero as their semantic start. Both positions are derived from existing measure and grid geometry; neither
adds a column or padding.

Upper and lower voices use style-owned vertical baselines. A hidden rest remains in `NotationLayout.rests` but is not
passed to a SwiftUI primitive and does not participate in accessibility.

### 10.2 Stop-family marks

`RenderedStopNote` carries resolved control semantics and geometry:

```swift
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
}
```

Its fields preserve:

- deterministic ID;
- exact `.stop`, `.choke`, or `.damp` kind;
- source lane/sample identity and target lane identity;
- the target instrument's catalog-resolved display name for accessibility;
- normalized `NotationTimeColumn`;
- row and resolved target position;
- one conservative stopped-mark rendering style.

Sort resolved controls by measure, tick, kind, target lane, source lane, source sample, source grid position, and source
grid size. Encode the rendered ID from that same semantic tuple and append a deterministic duplicate ordinal only when
every field matches. Collection order and Swift's randomized hashing never participate in the ID.

Target resolution uses `targetLaneID` through `DrumNotationCatalog`. If that target is absent or unknown, the event is
preserved in chart data but produces no rendered mark. The renderer does not fall back to a neighboring note, inferred
cymbal, or arbitrary staff position. A resolved target uses the same active `notePositionOverrides` lookup as its
playable instrument before falling back to the catalog's default position, so the mark follows user-authored lane
placement without changing timing.

All three kinds draw the same plus-shaped stopped mark in HPA-143. The semantic kind remains distinct in the model,
rendered primitive, accessibility label, and test identifier. This avoids inventing unsupported DTX-specific glyph
conventions while keeping future visual refinement source-compatible.

A stop mark may share a tick with a notehead or a rest. It draws at a style-defined articulation offset from the target
lane's catalog position and never becomes part of notehead, stem, beam, or flag geometry.

### 10.3 Hi-hat articulation overlays

Add one focused rendered kind and primitive:

```swift
enum RenderedArticulationKind: Hashable {
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

Layout derives it only when `RenderedNoteHead.variant == .openHiHat`.

The articulation ID is the stable tuple `(kind, sourceNoteHeadID)`. Layout emits at most one articulation of a given
kind for one source head, so no duplicate ordinal is required; `row` and pixel position are derived geometry rather than
identity.

- Closed hi-hat remains the catalog's cross notehead with no overlay.
- Open hi-hat uses the same cross plus a small vector open circle above it.
- Pedal hi-hat remains the catalog-authored lower-voice cross at its below-staff position with no open overlay.

The overlay references its source notehead ID and uses that head's immutable center. Views do not re-resolve
`DrumType`, source lane, or catalog identity.

`NormalizedArticulation` is not expanded with inferred tie, sustain, release, or choke cases in this ticket. If future
source data supplies those semantics, it can add explicit overlay or control-event cases without changing the
rest topology.

## 11. SwiftUI Rendering

Add small vector primitives to `NotationPrimitiveViews.swift` or focused companion files:

- `NotationRestView` for full-measure, half, quarter, and flagged rest silhouettes;
- `NotationStopNoteView` for the stopped plus mark;
- `NotationArticulationView` for the open-hi-hat circle.

Views receive resolved semantic kind, size, and position. They do not calculate voice occupancy, duration
decomposition, target lanes, fixed-grid columns, or visibility policy.

Accessibility ownership follows the semantic primitive. `RenderedRest`, `RenderedStopNote`, and `RenderedNoteHead`
expose computed `accessibilityLabel` values from their stored semantic fields, so primitive views do not re-resolve
catalog identity or store a second identity string:

- each printed rest is one element labeled with voice and duration, such as "Upper voice quarter rest" or
  "Lower voice full-measure rest";
- each stop mark is one element labeled with its exact control kind and `targetDisplayName`;
- `NotationNoteHeadView` owns the instrument/variant label, including distinct "Closed hi-hat", "Open hi-hat", and
  "Pedal hi-hat" values;
- `NotationArticulationView` is accessibility-hidden because its open circle only decorates the already-labeled open
  hi-hat head;
- hidden rests produce neither a view nor an accessibility element.

`GameplaySheetMusicView` draws only printed rests and places articulation and stop marks above the affected heads. The
explicit layer order must preserve visible measure bars and keep the playhead above notation while leaving all layout
geometry unchanged.

Add rest sizes, voice baselines, stopped-mark size/offset, articulation diameter/offset, and stroke widths to
`NotationLayoutStyle`. `with(rowWidth:)` must copy every new metric unchanged so width measurement cannot silently reset
the feature's geometry.

`NotationLayout.contentWidth` and `GameplaySheetMusicView.notationContentWidth(for:)` remain unchanged. Interval rests
use existing grid columns, full-measure rests use a measure midpoint, stop marks apply only a vertical target offset,
and open-hi-hat circles retain their source head's x-coordinate. Their horizontal bounds must remain inside the final
measure bar plus the existing `GameplayLayout.uniformSpacing` allowance, so `measureBars` continues to provide the
authoritative maximum x extent. A future primitive that adds a horizontal offset must first join the `contentWidth`
calculation.

## 12. Error Handling and Conservative Fallbacks

- **Unrepresentable note duration:** reserve the uncertain span with `.hiddenSpacing`; do not print a guessed rest.
- **Residual unsupported gap:** emit one hidden spacing event for the exact remaining ticks.
- **Unsupported `/8` meter:** allow the normal measure shell and balanced full-measure policy. For a voice with playable
  onsets, represent every internal complement as hidden spacing rather than printing compound-meter rests; HPA-145 owns
  that grouping.
- **Invalid measure or tick:** skip the affected rendered primitive and log one deterministic diagnostic.
- **Inexact control-grid conversion:** preserve the persistent event, omit its mark, and do not change `TabGrid`.
- **Missing control target:** preserve the event, omit its mark, and report the unresolved lane.
- **Unknown DTX mute semantics:** emit no production control event.
- **Missing notation variant:** retain the existing catalog fallback behavior; do not guess an open-hi-hat overlay.

Diagnostics aggregate repeated unresolved lanes or timing reasons once per layout pass, following the catalog's
existing fallback-warning pattern rather than logging once per render frame.

## 13. Persistence, Gameplay, and Scoring Boundaries

- `ChartControlEvent` participates in Chart cascade deletion and fixture copying independently from `Note`.
- Relationship caching follows the existing asynchronous SwiftData pattern; views never traverse
  `chart.controlEvents` directly.
- `ChartRelationshipData` remains the existing note/count snapshot; it is not the control-event loading path.
- `InputTimingMatcher`, `ScoreEngine`, high-score persistence, and gameplay hit targets continue to consume only
  playable notes.
- Rest/control-only layouts select notation rendering but do not drive beat caches, a moving playhead, current-row
  advancement, or playback-driven scrolling.
- Control events are exposed in the gameplay snapshot for current rendering and future playback consumers.
- HPA-143 does not call `AVAudioPlayer.stop()`, alter BGM scheduling, or claim sample-level mute behavior that Virgo
  cannot currently perform.

## 14. Testing

### 14.1 Pure rest topology

Add `VirgoTests/NotationRestTopologyTests.swift` with focused cases for:

- both voices silent: printed upper and hidden-duplicate lower full-measure rests;
- upper-only notes: lower printed full-measure rest;
- lower-only notes: upper printed full-measure rest;
- independent internal gaps in both voices;
- same-time chord occupancy using the longest exact duration;
- next-onset and measure-end clipping;
- half, quarter, eighth, sixteenth, thirty-second, and sixty-fourth decomposition;
- the closed rest-duration vocabulary making an ordinary full-note rest unrepresentable;
- exact occupancy conversion in supported 2/4, 3/4, 4/4, and 5/4 meters;
- `/8` measures retaining full-measure rests while keeping active-voice internal complements hidden;
- an unaligned or too-small remainder becoming `.hiddenSpacing`;
- an unrepresentable duration reserving an uncertain hidden span;
- control events having no effect on voice occupancy;
- deterministic order and IDs after shuffled input;
- no overlap and exact coverage of supported occupied, printed-rest, and hidden spans.

### 14.2 Control model and layout

Add model and integration coverage for:

- fresh-container `ChartControlEvent` round-trip and Chart cascade behavior;
- all seven explicit app, service, and test schema registrations constructing containers with `ChartControlEvent`;
- fixture copying preserving controls separately from notes;
- explicit `.stop`, `.choke`, and `.damp` raw-value stability;
- a focused explicit `.choke` chart fixture with a catalog-resolvable cymbal target;
- exact control placement on an existing `TabGrid` column;
- a control-only later measure contributing to total measure count;
- no notehead, stem, beam, flag, scoring target, or rest-occupancy event created by a control;
- unresolved target and inexact-grid behavior preserving data while omitting geometry;
- normalized-timing precedence, exact manual-timing fallback, and inconsistent-metadata rejection;
- notes and controls sharing the exact-rescaling helper while only notes retain the rounded fallback;
- target placement following the active playable-instrument position override;
- identical grid resolution, measure width, wrapping, playable note positions, and beam topology with and without the
  same control event.

### 14.3 Layout and rendering

Cover:

- `NotationLayout.rests`, `stopNotes`, and `articulations` ordering and identities;
- stop IDs remaining stable after shuffled input and distinguishing otherwise identical duplicates by ordinal;
- articulation IDs using only kind and source-notehead identity;
- rest-only and control-only layouts reporting `hasRenderableContent == true` and `hasPlayableContent == false`;
- notation-only layouts selecting notation measures, sizing, bars, and staff backgrounds without falling back to
  legacy geometry;
- notation-only layouts producing no playhead or playback-driven row scrolling;
- playable layouts reporting both predicates as true and retaining existing playhead alignment;
- hidden rests remaining semantic but absent from primitive rendering;
- full-measure rest centering and upper/lower vertical separation;
- open hi-hat producing one open-circle overlay;
- closed hi-hat producing no open overlay;
- pedal hi-hat remaining lower-voice and visually distinct from the two upper-voice variants;
- construction of each vector rest, stop, and articulation primitive in `SwiftUIRenderingCoverageTests`;
- printed-rest and stop labels carrying their semantic voice/duration or kind/target values;
- closed, open, and pedal heads exposing distinct labels while the open-circle overlay remains accessibility-hidden;
- the existing extra top-padding margin containing the open-hi-hat circle at the highest supported head position;
- every new primitive remaining within the final measure-bar bound plus the existing uniform-spacing allowance;
- `contentWidth` and `notationContentWidth(for:)` remaining unchanged when measure count and wrapping are held constant;
- `NotationLayoutStyle.with(rowWidth:)` preserving every new metric.

## 15. Verification Ladder

Run Xcode verification sequentially and disable parallel testing:

1. Focused rest topology, control-event, layout, catalog, and SwiftUI rendering suites.
2. Full `VirgoTests` on macOS using `-parallel-testing-enabled NO` and the repository's writable DerivedData path.
3. `swiftlint lint`.
4. macOS build for scheme `Virgo`.
5. iPad simulator compatibility build using an available iPad destination, never an iPhone destination.

Any focused selector must be a proven Swift Testing suite selector. If a guessed method selector executes zero tests,
rerun the containing suite and treat zero executed tests as a verification failure.

## 16. Likely Files

- `Virgo/models/ChartControlEvent.swift` (new persistent control model and immutable snapshot)
- `Virgo/models/DrumTrack.swift` (Chart relationship and fixture-copy integration)
- `Virgo/VirgoApp.swift`
- `Virgo/services/ScorePersistenceService.swift`
- `Virgo/viewmodels/GameplayViewModel.swift` (cached control snapshots)
- `Virgo/viewmodels/GameplayViewModel+Computations.swift` (renderable/playable cache gates)
- `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift` (playhead and row gates)
- `Virgo/layout/NotationRestTopology.swift` (new pure topology builder)
- `Virgo/layout/NotationLayout.swift` (input and rendered contracts)
- `Virgo/layout/NotationLayoutEngine.swift` (post-grid orchestration)
- `Virgo/layout/NotationLayoutEngine+TabGrid.swift` (shared exact tick rescaling)
- `Virgo/layout/NotationLayoutEngine+Rests.swift` (rest geometry translation)
- `Virgo/layout/NotationLayoutEngine+Controls.swift` (control and articulation translation)
- `Virgo/views/NotationPrimitiveViews.swift` or focused primitive companions
- `Virgo/views/subviews/GameplaySheetMusicView.swift`
- `VirgoTests/TestHelpers.swift`
- `VirgoTests/PatchCoverageAdditionsTests.swift`
- `VirgoTests/NavigationTests.swift`
- `VirgoTests/ChartModelDefaultPropertyTests.swift`
- `VirgoTests/DrumTrackTests.swift`
- `VirgoTests/NotationRestTopologyTests.swift` (new)
- `VirgoTests/ChartControlEventTests.swift` (new)
- `VirgoTests/NotationLayoutRestAndControlTests.swift` (new)
- `VirgoTests/DrumNotationCatalogTests.swift`
- `VirgoTests/SwiftUIRenderingCoverageTests.swift`

The exact file split should respect SwiftLint's file, type, and function size limits. Existing large files should gain
focused extensions rather than unrelated refactoring.

## 17. Acceptance Criteria Mapping

- Independent upper and lower silence is computed by a per-measure, per-voice pure topology builder.
- Full-measure, voice-specific, beat-level, hidden-spacing, and hidden-duplicate rests have explicit semantic cases.
- A silent companion voice receives a printed full-measure rest; a fully silent measure suppresses only the duplicate
  lower glyph.
- Stop, choke, and damp are separate persistent/control-layout kinds and never special playable notes.
- An explicit choke fixture exercises persistence, snapshotting, placement, rendering, and non-scoreability.
- Control marks and rests are derived after the fixed grid and do not change note spacing, wrapping, beam topology, or
  playhead alignment.
- Rest/control-only layouts use notation geometry but do not activate scoreable timing, a moving playhead, or row
  scrolling.
- Closed, open, and pedal hi-hat variants remain distinct; open receives a visible circle overlay and pedal keeps its
  lower-voice position.
- Unsupported duration, target, or grid information falls back deterministically without guessed notation.
- Tie, sustain, and release marks are emitted only when future source data represents them explicitly.
- Focused pure, integration, persistence, and rendering tests cover every HPA-143 requirement while leaving HPA-144
  goldens and HPA-145 advanced rhythm semantics in their sibling tickets.

## 18. Risks and Mitigations

### False rests from duration inference

Different voices or malformed same-time durations could make a voice appear silent too early. Group and clip occupancy
inside one voice only, use the longest exact same-time duration, and hide uncertain spans rather than printing them.

### Fixed-grid regression

Including controls in grid resolution could change every downstream x-coordinate. Keep `buildTabGrid` note-only and
require exact conversion of control timing onto the resulting grid.

### Duplicate-rest clutter

Rendering both voices in an empty measure would add visual noise. Preserve both semantic events but print the approved
upper rest only when both voices are silent.

### Unsupported DTX semantics

Filename and sample-ID heuristics could silently misclassify sound effects. Keep production classification empty and
exercise the contract with an explicitly authored choke fixture.

### SwiftData schema blast radius

A new model type affects app, service, preview, and test schemas. Update the seven registrations enumerated in section
6.1 together and cover a fresh-container round trip before layout integration.

### View-only semantic drift

If SwiftUI views infer variants or rest kinds, tests and rendering can diverge. Materialize every semantic decision in
`NotationLayout` and keep primitive views geometry-only.

This remains one implementation-plan-sized change because the work follows three narrow parallel tracks with one layout
integration point, while parser heuristics, audio behavior, advanced rhythm, and broad golden coverage remain explicitly
deferred.
