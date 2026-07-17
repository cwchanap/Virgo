# Wire DTX Import to Populate ChartControlEvent — Design

**Linear issue:** [HPA-214](https://linear.app/cwchanap/issue/HPA-214/wire-dtx-import-to-populate-chartcontrolevent)
**Parent:** HPA-143 (PR #45) — added the `ChartControlEvent` model, `safeControlEvents` accessor, rest/stop-note rendering, and authored fixture copy, but left the DTX importer intentionally unwired.
**Date:** 2026-07-16
**Revision:** 3 — addresses all code-review findings (native-grid preservation per HPA-143 contract, difficulty-keyed backfill, producer contract, parser-to-render integration test, initializer compatibility).

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

Add a control-event parsing path that produces `ChartControlEvent` rows from DTX control chips, keeping the note path byte-for-byte unchanged. Control-lane interpretation is gated behind a `#VIRGO_CONTROL: 1` header so standard DTX channels (including guitar lanes 21–26) are never misinterpreted in third-party files. Both import paths (local fixture and server download) are wired.

**Key principle (HPA-143 contract):** The importer stores every control chip's **native grid tuple** as its normalized timing. It never drops, rounds, or pre-projects controls. The layout engine decides rendering: if `exactRescaledTick` can project the native fraction onto the tab grid, the mark renders; otherwise the event is preserved (it contributes to measure count) but its visual mark is omitted with a diagnostic. This matches HPA-143's design: "preserve the event, omit its visual mark, and log a diagnostic rather than raising grid resolution or rounding the event."

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

**3c. `DTXChartData` gains `controlLaneKinds`** with a defaulted initializer parameter:

```swift
let controlLaneKinds: [String: NotationControlEventKind]
```

The initializer gains `controlLaneKinds: [String: NotationControlEventKind] = [:]` as a trailing defaulted parameter. This preserves compatibility with all existing call sites (including `DTXFileParserTests.swift:115` which constructs `DTXChartData` without it).

In `parseChartMetadata`, when constructing the return value:

```swift
let controlLaneKinds: [String: NotationControlEventKind] = metadata.virgoControlEnabled
    ? ["21": .stop, "22": .choke, "23": .damp]
    : [:]
```

**3d. `DTXChartData.toControlEvents(for:)`** — stores every control chip's native grid tuple. No dropping, no projection, no `sharedTicksPerMeasure`:

1. If `controlLaneKinds` is empty, return `[]`.
2. Filter chips where `controlLaneKinds[chip.laneID.uppercased()] != nil`.
3. For each control chip, apply basic sanity guards (matching `NormalizedRhythmicEvent.init?`):
   - `chip.gridSize > 0`
   - `chip.gridPosition >= 0`
   - `chip.gridPosition < chip.gridSize`
   
   If any guard fails, skip with `Logger.warning` (malformed chip, not an incommensurate grid).
4. Build `ChartControlEvent` storing the chip's **native grid tuple** as normalized timing:
   - `kind`: from `controlLaneKinds[chip.laneID]`
   - `targetLaneID`: `chip.noteID.uppercased()`
   - `originKind`: `.dtx`
   - `measureNumber`: `chip.measureIndex + 1`
   - `measureOffset`: `Double(chip.gridPosition) / Double(chip.gridSize)`
   - `sourceLaneID`: `chip.laneID.uppercased()`
   - `sourceNoteID`: `chip.noteID.uppercased()`
   - `sourceGridPosition` / `sourceGridSize`: from chip
   - `normalizedMeasureIndex`: `chip.measureIndex`
   - `normalizedTickWithinMeasure`: `chip.gridPosition` (native)
   - `normalizedTicksPerMeasure`: `chip.gridSize` (native)
   - `normalizedAbsoluteTick`: `chip.measureIndex * chip.gridSize + chip.gridPosition` (native)

This is the same pattern `NormalizedRhythmicEvent` uses — each chip carries its own resolution. The layout engine's semantic timing validation (`NotationLayoutEngine+Controls.swift:222-251`) accepts this because:
- `measureIndex >= 0` ✓
- `tick >= 0` ✓ (gridPosition >= 0)
- `resolution > 0` ✓ (gridSize > 0)
- `tick <= resolution` ✓ (gridPosition < gridSize)
- `absolute == measureIndex * resolution + tick` ✓ (by construction)

At render time, `exactRescaledTick(sourceTick: gridPosition, sourceTicksPerMeasure: gridSize, targetTicksPerMeasure: tabGrid.ticksPerMeasure)` does GCD reduction and projects. A control at 2/8 reduces to 1/4 and renders on a 960-tick grid at tick 240. A control at 1/7 fails projection (7 does not divide 960) — the mark is omitted but the event is preserved for its measure contribution. This is the HPA-143 contract.

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

`refreshControlEventsIfMissing` matches charts by **difficulty** (the stable identity key), not array order:

1. Decode `SET.def` and call `loadImportedCharts(from:folderURL:setList:)` — this parses each difficulty's DTX file separately, producing one `ImportedChart` per difficulty with its own `DTXChartData`.
2. For each `ImportedChart`, find the existing `Chart` in `existingSong.charts` where `chart.difficulty == importedChart.difficulty`.
3. If no matching chart exists, skip.
4. If the matched chart already has non-empty `safeControlEvents`, skip (idempotent).
5. If empty, populate from `importedChart.data.toControlEvents(for: chart)`, insert each into context, and set `chart.controlEvents`.
6. Save only if at least one chart was updated.

This correctly handles multi-difficulty imports: each difficulty's controls come from its own DTX file, never from another difficulty's file. The bundled Soukyuu fixture has no `#VIRGO_CONTROL` header → all `controlLaneKinds` are empty → `toControlEvents` returns `[]` → no-op.

**Server songs:** `ServerSongDownloader` rejects duplicate downloads (dedup by `serverSongId`). Existing server-imported charts cannot be backfilled without delete-and-reimport. This is documented as the expected upgrade path for server songs.

#### 4d. Other Paths (No Changes)

- `Song.fixtureCopy` already copies `controlEvents` via `copiedControlEvents` (HPA-143).
- Bundled Soukyuu fixtures contain no `#VIRGO_CONTROL` header → `controlLaneKinds` is empty → `toControlEvents(for:)` returns `[]` → no rendering change.

### 5. Producer Contract

Chart authors activate control events by adding one line to their DTX file:

```
#VIRGO_CONTROL: 1
```

Then placing chips on lanes 21 (stop), 22 (choke), or 23 (damp), where the 2-char chip value is the target drum's lane ID. The header can appear anywhere in the file before or after note lines (it is processed by `processLine` alongside other metadata).

**Server path:** The server serves raw DTX file content. The `#VIRGO_CONTROL` header is naturally preserved — `ServerSongDownloader.processChart` downloads the file, decodes it, and passes the raw string to `DTXFileParser.parseChartMetadata(from:)`, which processes the header. No server-side changes are needed. A server chart author simply includes the header in their DTX file before uploading.

**Test fixtures:** Tests use inline DTX strings containing the header (no bundled fixture file is modified). This provides end-to-end coverage of the header → parse → populate path without touching production assets.

### 6. Edge Cases & Diagnostics

| Case | Behavior |
|------|----------|
| `#VIRGO_CONTROL` header absent | `controlLaneKinds` is empty; `toControlEvents(for:)` returns `[]`; lanes 21/22/23 ignored (including standard guitar chips) |
| Control chip on native grid (e.g. 0/4, 2/8, 1/7) | All preserved with native tuple; layout engine projects at render time |
| Native fraction projectable (e.g. 2/8 → 1/4 on 960-tick grid) | Mark renders at projected tick; layout engine handles GCD reduction |
| Native fraction incommensurate (e.g. 1/7 on 960-tick grid) | Event preserved (measure contribution retained); mark omitted; layout engine logs diagnostic |
| Malformed chip (gridSize ≤ 0, gridPosition out of range) | Chip skipped at import with `Logger.warning` |
| `targetLaneID` doesn't resolve in `DrumNotationCatalog` | Stored as-is; layout engine drops geometry + logs (existing behavior) |
| Chart has controls but no playable chips | Controls preserved with native tuples; layout engine may or may not project depending on tab grid (which defaults to sixteenth-note baseline) |
| Duplicate control at same time/target | Both stored; layout engine assigns deterministic `-duplicate-N` suffixes (existing behavior) |
| Existing Soukyuu fixtures (no header) | `toControlEvents` returns `[]`, zero rendering change |
| Existing local import without controls | `refreshControlEventsIfMissing` backfills on next launch if DTX file has `#VIRGO_CONTROL` header |
| Existing server import without controls | Not backfilled; requires delete-and-reimport |

No new validation layer at render time. The layout engine's two-phase timing validation (`NotationLayoutEngine+Controls.swift`) already handles all rendering-side decisions — semantic validation passes by construction, and `exactRescaledTick` decides projection. The importer populates data faithfully; the engine renders or drops with diagnostics.

### 7. Testing Strategy

All tests use **Swift Testing** (`import Testing`), in-memory `TestContainer`, `-parallel-testing-enabled NO`.

**Unit tests in `DTXFileParserTests.swift`:**

- `#VIRGO_CONTROL: 1` header absent → `toControlEvents(for:)` returns `[]` even if lanes 21/22/23 contain chips
- `#VIRGO_CONTROL: 1` header absent → guitar-channel chips (lane 22) do NOT produce control events (collision regression test)
- `#VIRGO_CONTROL: 1` header present → `toControlEvents(for:)` parses one stop chip targeting crash (lane 16) — asserts kind, targetLaneID, measureNumber, `originKind == .dtx`, `normalizedTickWithinMeasure`, `normalizedTicksPerMeasure` equal the chip's native gridPosition/gridSize
- Choke (lane 22) + damp (lane 23) chips produce correct kinds
- Control chip excluded from `toNotes` output (no `Note` created for lane 22 — already guaranteed by `toNoteType()` returning nil)
- Playable chip excluded from `toControlEvents` output (no `ChartControlEvent` for lane 12)
- Incommensurate control (1/7 grid) is preserved, not dropped — assert it appears in the output with `normalizedTicksPerMeasure == 7`
- Malformed chip (gridSize 0) skipped with no crash
- `DTXChartData` initializer without `controlLaneKinds` still compiles and defaults to `[:]`

**Local importer tests in `LocalDTXFixtureImporterTests.swift`:**

- Import a chart whose DTX data contains `#VIRGO_CONTROL: 1` and a control-lane chip; assert `chart.controlEvents.count == 1`
- `refreshControlEventsIfMissing` backfills an existing chart that has zero controls when the DTX file has the header; idempotent on second call
- Multi-difficulty backfill: two difficulties (easy + hard), each with its own DTX file; assert controls from easy's file don't appear on hard's chart (difficulty-keyed matching)

**Server importer test:**

- Download path populates `chart.controlEvents` from a DTX string containing `#VIRGO_CONTROL: 1` and a control chip; assert `chart.controlEvents.count == 1`

**Parser-to-render integration test** (in `NotationLayoutControlTests.swift` or a new integration test file):

- Parse a DTX string with `#VIRGO_CONTROL: 1` and a choke chip targeting crash → build `ChartControlEvent` → construct `NotationLayoutInput` with the control event → call `NotationLayoutEngine().layout(input:)` → assert `layout.stopNotes` contains one `RenderedStopNote` with the correct kind and target. This covers acceptance criterion 2's render path end-to-end through the real parser and layout engine.

**Regression guard:**

- Run existing `DTXFileParserTests`, `DTXNormalizationTests`, `DTXNoteLineParsingTests` unchanged — confirms the note path is byte-for-byte unaffected

## Constraints (inherited from HPA-143)

- Do not infer stop/choke/damp events from sample IDs, unknown lanes, or neighboring cymbals — only lanes declared via `#VIRGO_CONTROL: 1` produce control events.
- Do not change parser semantics for playable notes — control chips are parsed by the existing `parseNoteLine` into `DTXNote` values; the new code only filters them by `controlLaneKinds` lookup.
- Controls never enter `buildTabGrid` or `buildRests` — the layout engine already guarantees this.
- **Preserve every valid control chip** — store native grid tuples; never drop for incommensurate grids. The layout engine decides rendering (HPA-143 contract: "preserve the event, omit its visual mark").
- Use Swift Testing, not XCTest.
- Run `xcodebuild test` with `-parallel-testing-enabled NO`.
- iPad-only for iOS builds (`TARGETED_DEVICE_FAMILY = 2`); never target iPhone.
- **SwiftLint watch:** `DTXFileParser.swift` is 462 lines (file limit: 600 warn / 1000 error). `toControlEvents(for:)` with its 12-field construction + filter + guards may approach the 50-line function-body warn limit. If it does, extract the per-chip mapping into a private helper to stay under the limit.

## Out of Scope

- Audio choking (muting a sample at a control-event timestamp) — notation marks only.
- New scoring or input targets for control events.
- Compound-meter control timing beyond what the existing layout engine supports.
- Modifying the bundled Soukyuu fixtures to include control chips.
- GUI/editor support for placing control chips in DTXCreator — this is a parser/importer change only.
- Server-song backfill without delete-and-reimport — server dedup rejects duplicates; a future migration/versioning pass could address this.
- Custom lane mappings beyond the default 21/22/23 → stop/choke/damp (the header is boolean, not a mapping table; a future `#VIRGO_CONTROL_LANES:` directive could enable per-file customization).
