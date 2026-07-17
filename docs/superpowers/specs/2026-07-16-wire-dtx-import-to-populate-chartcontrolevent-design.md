# Wire DTX Import to Populate ChartControlEvent — Design

**Linear issue:** [HPA-214](https://linear.app/cwchanap/issue/HPA-214/wire-dtx-import-to-populate-chartcontrolevent)
**Parent:** HPA-143 (PR #45) — added the `ChartControlEvent` model, `safeControlEvents` accessor, rest/stop-note rendering, and authored fixture copy, but left the DTX importer intentionally unwired.
**Date:** 2026-07-16
**Revision:** 2 — addresses P1/P2 code-review findings (guitar-channel collision, server import path, GCD-reduced resolution, backfill strategy).

## Problem

HPA-143 added `ChartControlEvent` (stop/choke/damp marks) and wired it fully into the notation rendering engine, but the DTX importer was left disconnected per plan constraints ("without changing parser semantics"). As a result, `DTXFileParser.swift` has zero references to `ChartControlEvent`/`controlEvents`, and both import paths (`LocalDTXFixtureImporter.importSong` and `ServerSongDownloader.processChart`) never set `chart.controlEvents`. Stop/choke/damp marks are inert in production — they only appear via authored fixtures and tests.

## Goal

Populate `ChartControlEvent` from DTX lane/note identity during import so stop/choke/damp marks render for real DTX charts, not just fixtures.

### Acceptance Criteria

1. `DTXFileParser` constructs `ChartControlEvent` rows from DTX control lanes.
2. Imported charts render stop marks without a fixture-copy step.
3. `DTXFileParserTests` cover at least one stop/choke fixture end-to-end.
4. No regression to playable-note grid, scoring, input, or playback.

## Approach: Parallel Parsing Path with Header-Gated Control Lanes

Add a control-event parsing path that produces the same drop behavior as the existing `toNotes(for:)` pipeline, keeping the note path byte-for-byte unchanged. Control-lane interpretation is gated behind a `#VIRGO_CONTROL: 1` header so standard DTX channels (including guitar lanes 21–26) are never misinterpreted in third-party files. Both import paths (local fixture and server download) are wired.

## Design

### 1. Header-Gated Control Lanes

Standard DTX/DTXCreator has no native drum-stop lane, and lanes 21–26 are standard guitar channels in the DTX format ([OutFox DTX channel reference](https://outfox.wiki/en/dev/mode-support/dtx-gda-support)). To avoid collisions, control-lane parsing is **opt-in** via a Virgo-specific header:

```
#VIRGO_CONTROL: 1
```

When this header is present in a DTX file, the parser activates the default control-lane mapping:

| Kind | Lane ID |
|------|---------|
| `stop` | `21` |
| `choke` | `22` |
| `damp` | `23` |

When the header is **absent**, lanes 21/22/23 are ignored entirely (current behavior — they produce no notes and no control events). This guarantees zero collision risk for non-Virgo DTX files.

The `DTXLane` enum is **unchanged** — no new cases are added. The mapping lives in `DTXChartData` as a runtime dictionary, not a compile-time enum, so the feature is activated per-file rather than globally.

### 2. Target Encoding: Chip Value = Target Lane

The 2-char chip value on a control lane encodes the target drum lane ID. Control lanes carry no WAV audio, so the chip value is free to encode the target rather than referencing a sample.

Example (with header present):
```
#VIRGO_CONTROL: 1
#00122: 16000000
```
- Measure `001`, lane `22` (choke), grid position `0` of `4`
- Chip value `16` → `targetLaneID = "16"` (crash cymbal)
- Produces one `ChartControlEvent(kind: .choke, targetLaneID: "16", ...)`

The parser uppercases the chip value to match `DrumNotationCatalog.resolveTarget`'s normalization. Unresolvable target lanes (e.g. `"ZZ"`) are stored as-is; the layout engine already drops their geometry with a diagnostic — no new validation needed.

### 3. Parsing Flow

All additions are in `Virgo/utilities/DTXFileParser.swift`.

**3a. `DTXMetadata` gains a control flag:**

```swift
var virgoControlEnabled: Bool = false
```

**3b. Header parsing in `processLine`** (alongside existing `#TITLE:` / `#BPM:` branches):

```swift
} else if line.hasPrefix("#VIRGO_CONTROL:") {
    metadata.virgoControlEnabled = extractValue(from: line, prefix: "#VIRGO_CONTROL:") == "1"
}
```

**3c. `DTXChartData` gains a `controlLaneKinds` dictionary** populated from the header:

```swift
let controlLaneKinds: [String: NotationControlEventKind]
```

In `parseChartMetadata`, when constructing the return value:

```swift
let controlLaneKinds: [String: NotationControlEventKind] = metadata.virgoControlEnabled
    ? ["21": .stop, "22": .choke, "23": .damp]
    : [:]
```

This dictionary is the single source of truth for which lanes are control lanes in this chart. When empty (header absent), `toControlEvents(for:)` returns `[]` immediately.

**3d. `DTXChartData.toControlEvents(for:)`** — produces the same drop behavior as `toNotes(for:)`, but without a `NormalizedRhythmicEvent`-style intermediate type. Validation is inline:

1. If `controlLaneKinds` is empty, return `[]`.
2. Compute `sharedTicksPerMeasure` from **playable chips only** — same `private static` method (`Self.sharedTicksPerMeasure(for:)`), same value the notes use. Since Swift 4, `private` is file-scoped; `toControlEvents(for:)` in the same file accesses it with no visibility change. If it returns `nil` (LCM exceeds `maximumTicksPerMeasure`), return `[]` — the same guard `normalizedRhythmicEvents()` uses.
3. Filter chips where `controlLaneKinds[chip.laneID.uppercased()] != nil`.
4. For each control chip, validate tick alignment using **GCD-reduced fraction validation** (matching `exactRescaledTick`'s logic in `NotationLayoutEngine+TabGrid.swift`):
   - Reduce `chip.gridPosition / chip.gridSize` by `gcd(gridPosition, gridSize)`.
   - Check `ticksPerMeasure.isMultiple(of: reducedDenominator)`.
   - If it fails, skip with `Logger.warning`.
   - Compute `tickWithinMeasure = reducedTick * (ticksPerMeasure / reducedDenominator)`.
   
   This ensures a control at position `2/8` against a 4-tick grid is accepted (reduces to `1/4`), matching what the layout engine's `exactRescaledTick` will do at render time.
5. Build `ChartControlEvent` with:
   - `kind`: from `controlLaneKinds[chip.laneID]`
   - `targetLaneID`: `chip.noteID.uppercased()`
   - `originKind`: `.dtx`
   - `measureNumber`: `chip.measureIndex + 1`
   - `measureOffset`: `Double(chip.gridPosition) / Double(chip.gridSize)`
   - `sourceLaneID`: `chip.laneID.uppercased()`
   - `sourceNoteID`: `chip.noteID.uppercased()`
   - `sourceGridPosition` / `sourceGridSize`: from chip
   - `normalizedMeasureIndex`: `chip.measureIndex`
   - `normalizedAbsoluteTick`: `chip.measureIndex * ticksPerMeasure + tickWithinMeasure`
   - `normalizedTickWithinMeasure`: the GCD-reduced tick value
   - `normalizedTicksPerMeasure`: the shared value

Because control chips use the same `sharedTicksPerMeasure` as the notes and the GCD-reduced validation matches `exactRescaledTick`, the layout engine's tick projection always succeeds for accepted controls.

### 4. Importer Wiring

#### 4a. Local Fixture Importer (`LocalDTXFixtureImporter.importSong`)

In the `importedCharts.forEach` block (lines 78–91), add control events alongside notes:

```swift
chart.notes = importedChart.data.toNotes(for: chart)
chart.controlEvents = importedChart.data.toControlEvents(for: chart)
context.insert(chart)
for note in chart.notes { context.insert(note) }
for control in chart.controlEvents { context.insert(control) }
```

#### 4b. Server Download Importer (`ServerSongDownloader.processChart`)

At line 191, the server path calls `chartData.toNotes(for: chart)` but never populates controls. Add equivalent wiring:

```swift
let parsedNotes = chartData.toNotes(for: chart)
parsedNotes.forEach { chart.notes.append($0) }
let parsedControls = chartData.toControlEvents(for: chart)
parsedControls.forEach { context.insert($0); chart.controlEvents.append($0) }
```

#### 4c. Backfill for Existing Local Imports

`LocalDTXFixtureImporter.importSong` returns existing songs without reparsing (line 40). Users with already-imported charts would remain unaffected by the feature. Add `refreshControlEventsIfMissing` to the refresh path:

```swift
if let existingSong = try existingSong(with: songId, in: context) {
    try refreshAudioPaths(for: existingSong, from: folderURL, in: context)
    try refreshBGMStartOffsetIfMissing(for: existingSong, from: folderURL, in: context)
    try refreshDurationIfStale(for: existingSong, from: folderURL, in: context)
    try refreshControlEventsIfMissing(for: existingSong, from: folderURL, in: context)
    return existingSong
}
```

`refreshControlEventsIfMissing` logic:
1. Load imported charts from the folder (same `loadImportedCharts` used by the fresh-import path).
2. For each existing chart, if `chart.controlEvents` is non-empty, skip (idempotent).
3. If empty, populate from `importedChart.data.toControlEvents(for: chart)` and insert into context.
4. Save only if changes were made.

This runs on every launch for the bundled Soukyuu fixture (which has no control lanes → `toControlEvents` returns `[]` → no-op). For charts with controls, it backfills on the first launch after upgrade.

**Server songs:** `ServerSongDownloader` rejects duplicate downloads (dedup by `serverSongId`). Existing server-imported charts cannot be backfilled without delete-and-reimport. This is documented as the expected upgrade path for server songs.

#### 4d. Other Paths (No Changes)

- `Song.fixtureCopy` already copies `controlEvents` via `copiedControlEvents` (HPA-143).
- Bundled Soukyuu fixtures contain no `#VIRGO_CONTROL` header → `controlLaneKinds` is empty → `toControlEvents(for:)` returns `[]` → no rendering change.

### 5. Edge Cases & Diagnostics

| Case | Behavior |
|------|----------|
| `#VIRGO_CONTROL` header absent | `controlLaneKinds` is empty; `toControlEvents(for:)` returns `[]`; lanes 21/22/23 ignored (including standard guitar chips) |
| Control chip grid position reduces exactly (e.g. 2/8 → 1/4 against 4-tick grid) | Accepted; GCD-reduced validation matches `exactRescaledTick` |
| Control chip grid genuinely incommensurate (e.g. 1/7 against 4-tick grid) | Chip dropped, `Logger.warning` with lane/measure/grid info |
| `targetLaneID` doesn't resolve in `DrumNotationCatalog` | Stored as-is; layout engine drops geometry + logs (existing behavior) |
| Chart has controls but no playable chips | `sharedTicksPerMeasure` = 1; most control grids won't reduce to divide 1 → dropped. Acceptable: a control-only chart with no notes is malformed |
| Duplicate control at same time/target | Both stored; layout engine assigns deterministic `-duplicate-N` suffixes (existing behavior) |
| Existing Soukyuu fixtures (no header) | `toControlEvents` returns `[]`, zero rendering change |
| Existing local import without controls | `refreshControlEventsIfMissing` backfills on next launch if DTX file has `#VIRGO_CONTROL` header |
| Existing server import without controls | Not backfilled; requires delete-and-reimport |

No new validation layer. The layout engine's two-phase timing validation (`NotationLayoutEngine+Controls.swift`) already handles all rendering-side decisions. The importer populates data faithfully; the engine renders or drops with diagnostics.

### 6. Testing Strategy

All tests use **Swift Testing** (`import Testing`), in-memory `TestContainer`, `-parallel-testing-enabled NO`.

**Unit tests in `DTXFileParserTests.swift`:**

- `#VIRGO_CONTROL: 1` header absent → `toControlEvents(for:)` returns `[]` even if lanes 21/22/23 contain chips
- `#VIRGO_CONTROL: 1` header absent → guitar-channel chips (lane 22) do NOT produce control events (collision regression test)
- `#VIRGO_CONTROL: 1` header present → `toControlEvents(for:)` parses one stop chip targeting crash (lane 16) — asserts kind, targetLaneID, measureNumber, all normalized timing fields, `originKind == .dtx`
- Choke (lane 22) + damp (lane 23) chips produce correct kinds
- Control chip excluded from `toNotes` output (no `Note` created for lane 22 — already guaranteed by `toNoteType()` returning nil)
- Playable chip excluded from `toControlEvents` output (no `ChartControlEvent` for lane 12)
- GCD-reduced grid: control at position 2/8 against playable 4-tick grid is accepted (not dropped)
- Genuinely incommensurate grid: control at 1/7 against 4-tick grid dropped with no crash

**Local importer test in `LocalDTXFixtureImporterTests.swift`:**

- Import a chart whose DTX data contains `#VIRGO_CONTROL: 1` and a control-lane chip; assert `chart.controlEvents.count == 1` and the event is populated without a fixture-copy step
- `refreshControlEventsIfMissing` backfills an existing chart that has zero controls when the DTX file has the header; idempotent on second call

**Server importer test:**

- Download path populates `chart.controlEvents` from a DTX string containing `#VIRGO_CONTROL: 1` and a control chip; assert `chart.controlEvents.count == 1`

> **Note on acceptance criterion 2 ("render"):** The importer tests verify the data pipeline (parse → populate → persist). Rendering correctness — stop marks appearing on the notation staff — relies on HPA-143's `NotationLayoutRestAndControlTests` / `NotationLayoutControlTests`, which exercise the same `ChartControlEvent` model through the same layout engine. Since this issue changes only how `ChartControlEvent` rows are *produced* (not how they're *rendered*), those engine tests remain the rendering authority.

**Regression guard:**

- Run existing `DTXFileParserTests`, `DTXNormalizationTests`, `DTXNoteLineParsingTests` unchanged — confirms the note path is byte-for-byte unaffected

## Constraints (inherited from HPA-143)

- Do not infer stop/choke/damp events from sample IDs, unknown lanes, or neighboring cymbals — only lanes declared via `#VIRGO_CONTROL: 1` produce control events.
- Do not change parser semantics for playable notes — control chips are parsed by the existing `parseNoteLine` into `DTXNote` values; the new code only filters them by `controlLaneKinds` lookup.
- Controls never enter `buildTabGrid` or `buildRests` — the layout engine already guarantees this.
- Use Swift Testing, not XCTest.
- Run `xcodebuild test` with `-parallel-testing-enabled NO`.
- iPad-only for iOS builds (`TARGETED_DEVICE_FAMILY = 2`); never target iPhone.
- **SwiftLint watch:** `DTXFileParser.swift` is 462 lines (file limit: 600 warn / 1000 error). `toControlEvents(for:)` with its 12-field construction + filter + GCD validate may approach the 50-line function-body warn limit. If it does, extract the per-chip mapping into a private helper to stay under the limit.

## Out of Scope

- Audio choking (muting a sample at a control-event timestamp) — notation marks only.
- New scoring or input targets for control events.
- Compound-meter control timing beyond what the existing layout engine supports.
- Modifying the bundled Soukyuu fixtures to include control chips.
- GUI/editor support for placing control chips in DTXCreator — this is a parser/importer change only.
- Server-song backfill without delete-and-reimport — server dedup rejects duplicates; a future migration/versioning pass could address this.
- Custom lane mappings beyond the default 21/22/23 → stop/choke/damp (the header is boolean, not a mapping table; a future `#VIRGO_CONTROL_LANES:` directive could enable per-file customization).
