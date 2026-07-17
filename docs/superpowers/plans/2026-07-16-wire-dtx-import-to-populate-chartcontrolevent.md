# Wire DTX Import to Populate ChartControlEvent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Populate `ChartControlEvent` rows from DTX control-lane chips during import so stop/choke/damp marks render for real DTX charts.

**Architecture:** Add a `#VIRGO_CONTROL: 1` header that activates lanes 21/22/23 as stop/choke/damp. Each control chip's native grid tuple (gridPosition/gridSize) is stored as normalized timing — the importer never drops or pre-projects; the layout engine's `exactRescaledTick` decides rendering per the HPA-143 contract. Both local and server import paths are wired. A difficulty-keyed backfill refreshes existing local imports.

**Tech Stack:** Swift 5.9+, SwiftData, Swift Testing (`import Testing`), Xcode 16+/`xcodebuild`, SwiftLint.

## Global Constraints

- Preserve HPA-140 fixed-grid placement, HPA-141 catalog-owned notehead/voice/stem semantics, and HPA-142 beam topology exactly.
- Control-lane interpretation is gated behind `#VIRGO_CONTROL: 1`. Without the header, lanes 21/22/23 are ignored (including standard guitar chips).
- Store every valid control chip's native grid tuple — never drop for incommensurate grids. The layout engine decides rendering (HPA-143 contract: "preserve the event, omit its visual mark").
- Controls never enter `buildTabGrid` or `buildRests` — the layout engine already guarantees this.
- Do not change parser semantics for playable notes — control chips are parsed by the existing `parseNoteLine` into `DTXNote` values; the new code only filters them by `controlLaneKinds` lookup.
- Use Swift Testing (`import Testing`), not XCTest.
- Run every `xcodebuild test` with `-parallel-testing-enabled NO`; run Xcode verification sequentially against `./DerivedData`.
- Any iOS-family build must use an available iPad simulator. Never target an iPhone and never change `TARGETED_DEVICE_FAMILY = 2`.
- Prefix every shell command with `rtk`.
- The project uses file-system-synchronized root groups; do not edit `Virgo.xcodeproj/project.pbxproj` for new Swift files.
- Keep each task limited to the files named in that task, run its focused suites, review its diff, and commit it before starting the next task.

---

## File Structure

- Modify: `Virgo/utilities/DTXFileParser.swift` — `DTXMetadata.virgoControlEnabled`, `#VIRGO_CONTROL:` header parsing, `DTXChartData.controlLaneKinds`, `DTXChartData.toControlEvents(for:)`.
- Modify: `Virgo/utilities/LocalDTXFixtureImporter.swift` — fresh-import control wiring + `refreshControlEventsIfMissing`.
- Modify: `Virgo/utilities/ServerSongDownloader.swift` — `processChart` control wiring.
- Modify: `VirgoTests/DTXFileParserTests.swift` — header opt-in, collision, parsing, preservation, and initializer tests.
- Modify: `VirgoTests/LocalDTXFixtureImporterTests.swift` — fresh import + backfill + multi-difficulty tests.
- Modify: `VirgoTests/ServerSongDownloaderNormalizationTests.swift` — control-event download test.
- Create: `VirgoTests/DTXControlImportIntegrationTests.swift` — parser-to-render end-to-end test.

---

### Task 1: Parser — Header Parsing, controlLaneKinds, and toControlEvents

**Files:**
- Modify: `Virgo/utilities/DTXFileParser.swift`
- Test: `VirgoTests/DTXFileParserTests.swift`

**Interfaces:**
- Produces: `DTXChartData.controlLaneKinds: [String: NotationControlEventKind]` (defaulted to `[:]` in init), `DTXChartData.toControlEvents(for: Chart) -> [ChartControlEvent]`.
- Consumes: `ChartControlEvent` (from `Virgo/models/ChartControlEvent.swift`), `NotationControlEventKind` (same file), `DTXNote.measureIndex`/`gridPosition`/`gridSize` (existing).

- [ ] **Step 1: Write the failing parser tests**

Add these tests to the end of `struct DTXFileParserTests` in `VirgoTests/DTXFileParserTests.swift`:

```swift
    // MARK: - Control Event Parsing

    @Test("header absent produces no control events even with lane-22 chips")
    func controlEventsEmptyWithoutHeader() throws {
        let dtx = """
        #TITLE: No Control
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #00022: 16000000
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)
        #expect(data.controlLaneKinds.isEmpty)
        #expect(data.toControlEvents(for: chart).isEmpty)
    }

    @Test("guitar-channel chips on lane 22 are ignored without VIRGO_CONTROL header")
    func guitarChannelsIgnoredWithoutHeader() throws {
        let dtx = """
        #TITLE: Guitar Song
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #00022: 0A0B0C0D
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)
        #expect(data.toControlEvents(for: chart).isEmpty)
    }

    @Test("header present parses stop chip targeting crash lane 16")
    func controlEventsParseStopChip() throws {
        let dtx = """
        #TITLE: Stop Test
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00021: 16000000
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)
        let controls = data.toControlEvents(for: chart)

        #expect(controls.count == 1)
        let control = try #require(controls.first)
        #expect(control.kind == .stop)
        #expect(control.targetLaneID == "16")
        #expect(control.measureNumber == 1)
        #expect(control.originKind == .dtx)
        #expect(control.sourceLaneID == "21")
        #expect(control.sourceNoteID == "16")
        #expect(control.sourceGridPosition == 0)
        #expect(control.sourceGridSize == 4)
        #expect(control.normalizedMeasureIndex == 0)
        #expect(control.normalizedTickWithinMeasure == 0)
        #expect(control.normalizedTicksPerMeasure == 4)
        #expect(control.normalizedAbsoluteTick == 0)
        #expect(control.chart === chart)
    }

    @Test("choke and damp chips produce correct kinds")
    func controlEventsParseChokeAndDamp() throws {
        let dtx = """
        #TITLE: Choke Damp
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00022: 16000000
        #00023: 12000000
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)
        let controls = data.toControlEvents(for: chart)

        #expect(controls.count == 2)
        #expect(controls.contains { $0.kind == .choke && $0.targetLaneID == "16" })
        #expect(controls.contains { $0.kind == .damp && $0.targetLaneID == "12" })
    }

    @Test("control chips are excluded from toNotes and playable chips from toControlEvents")
    func bidirectionalExclusion() throws {
        let dtx = """
        #TITLE: Mixed
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00012: 01000000
        #00022: 16000000
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)

        let notes = data.toNotes(for: chart)
        let controls = data.toControlEvents(for: chart)

        #expect(notes.count == 1)
        #expect(notes.first?.noteType == .snare)
        #expect(controls.count == 1)
        #expect(controls.first?.kind == .choke)
    }

    @Test("incommensurate control chip is preserved with native grid tuple")
    func incommensurateControlPreserved() throws {
        let dtx = """
        #TITLE: Seven Grid
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00021: 01000000000000
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)
        let controls = data.toControlEvents(for: chart)

        #expect(controls.count == 1)
        let control = try #require(controls.first)
        #expect(control.normalizedTicksPerMeasure == 7)
        #expect(control.normalizedTickWithinMeasure == 1)
        #expect(control.normalizedAbsoluteTick == 1)
    }

    @Test("malformed chip with zero grid size is skipped without crash")
    func malformedChipSkipped() {
        let chart = Chart(difficulty: .medium)
        let data = DTXChartData(
            title: "T", artist: "A", bpm: 120, difficultyLevel: 50,
            notes: [DTXNote(measureNumber: 0, laneID: "22", noteID: "16", notePosition: 0, totalPositions: 0)],
            controlLaneKinds: ["22": .choke]
        )
        #expect(data.toControlEvents(for: chart).isEmpty)
    }

    @Test("DTXChartData initializer without controlLaneKinds defaults to empty")
    func initializerDefaultsControlLaneKinds() {
        let data = DTXChartData(
            title: "T",
            artist: "A",
            bpm: 120,
            difficultyLevel: 50
        )
        #expect(data.controlLaneKinds.isEmpty)
    }
```

- [ ] **Step 2: Run the parser tests and verify RED**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/DTXFileParserTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: compilation fails because `controlLaneKinds` and `toControlEvents(for:)` do not exist on `DTXChartData`.

- [ ] **Step 3: Add `virgoControlEnabled` to `DTXMetadata`**

In `Virgo/utilities/DTXFileParser.swift`, add the field at line 18 (after `stageFile`):

```swift
struct DTXMetadata {
    var title: String?
    var artist: String?
    var bpm: Double?
    var difficultyLevel: Int?
    var preview: String?
    var previewImage: String?
    var stageFile: String?
    var virgoControlEnabled: Bool = false
}
```

- [ ] **Step 4: Add `#VIRGO_CONTROL:` parsing to `processLine`**

In `processLine` (around line 244, after the `#STAGEFILE:` branch), add:

```swift
        } else if line.hasPrefix("#VIRGO_CONTROL:") {
            metadata.virgoControlEnabled = extractValue(from: line, prefix: "#VIRGO_CONTROL:") == "1"
        }
```

- [ ] **Step 5: Add `controlLaneKinds` to `DTXChartData`**

In the `DTXChartData` struct (line 46), add the property after `bgmStartTimePosition`:

```swift
    let controlLaneKinds: [String: NotationControlEventKind]
```

Add the defaulted initializer parameter after `bgmStartTimePosition: Double? = nil`:

```swift
        controlLaneKinds: [String: NotationControlEventKind] = [:]
```

Add the assignment in the init body:

```swift
        self.controlLaneKinds = controlLaneKinds
```

- [ ] **Step 6: Populate `controlLaneKinds` in `parseChartMetadata`**

In `parseChartMetadata` (around line 209), add the mapping before the `return DTXChartData(...)`:

```swift
        let controlLaneKinds: [String: NotationControlEventKind] = metadata.virgoControlEnabled
            ? ["21": .stop, "22": .choke, "23": .damp]
            : [:]
```

Add `controlLaneKinds: controlLaneKinds` to the `DTXChartData(...)` constructor call (after `bgmStartTimePosition:`).

- [ ] **Step 7: Add `toControlEvents(for:)` to `DTXChartData`**

At the end of `extension DTXChartData` (after `toNotes(for:)`, around line 461), add:

```swift
    func toControlEvents(for chart: Chart) -> [ChartControlEvent] {
        guard !controlLaneKinds.isEmpty else { return [] }
        return notes.compactMap { chip -> ChartControlEvent? in
            guard let kind = controlLaneKinds[chip.laneID.uppercased()] else { return nil }
            guard chip.gridSize > 0,
                  chip.gridPosition >= 0,
                  chip.gridPosition < chip.gridSize else {
                Logger.warning(
                    "DTX control chip skipped — malformed grid: lane \(chip.laneID), "
                    + "measure \(chip.measureNumber), position \(chip.gridPosition)/\(chip.gridSize)"
                )
                return nil
            }
            return ChartControlEvent(
                kind: kind,
                measureNumber: chip.measureIndex + 1,
                measureOffset: Double(chip.gridPosition) / Double(chip.gridSize),
                chart: chart,
                originKind: .dtx,
                sourceLaneID: chip.laneID.uppercased(),
                sourceNoteID: chip.noteID.uppercased(),
                sourceGridPosition: chip.gridPosition,
                sourceGridSize: chip.gridSize,
                normalizedMeasureIndex: chip.measureIndex,
                normalizedAbsoluteTick: chip.measureIndex * chip.gridSize + chip.gridPosition,
                normalizedTickWithinMeasure: chip.gridPosition,
                normalizedTicksPerMeasure: chip.gridSize,
                targetLaneID: chip.noteID.uppercased()
            )
        }
    }
```

- [ ] **Step 8: Run the parser tests and verify GREEN**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/DTXFileParserTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: all tests in `DTXFileParserTests` pass, including the seven new control-event tests.

- [ ] **Step 9: Run existing parser regression suites**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/DTXFileParserTests -only-testing:VirgoTests/DTXNormalizationTests -only-testing:VirgoTests/DTXNoteLineParsingTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: all existing tests pass unchanged — the note path is byte-for-byte unaffected.

- [ ] **Step 10: Review and commit**

```bash
rtk git diff --check
rtk git status --short
rtk git add Virgo/utilities/DTXFileParser.swift VirgoTests/DTXFileParserTests.swift
rtk git commit -m "feat: parse DTX control lanes into ChartControlEvent"
```

Expected review: no scoring, input, playback, or layout file changed; `DTXChartData` init is backward-compatible; control chips never enter `normalizedRhythmicEvents`.

---

### Task 2: Local Fixture Importer — Fresh Import and Backfill

**Files:**
- Modify: `Virgo/utilities/LocalDTXFixtureImporter.swift`
- Test: `VirgoTests/LocalDTXFixtureImporterTests.swift`

**Interfaces:**
- Consumes: `DTXChartData.toControlEvents(for:)` and `DTXChartData.controlLaneKinds` from Task 1.
- Produces: `LocalDTXFixtureImporter.refreshControlEventsIfMissing(for:from:in:)` (private static).

- [ ] **Step 1: Write the failing importer tests**

Add these tests to the end of `struct LocalDTXFixtureImporterTests` in `VirgoTests/LocalDTXFixtureImporterTests.swift`, before the private helper methods:

```swift
    // MARK: - Control Event Import

    @Test("fresh import populates controlEvents when DTX has VIRGO_CONTROL header")
    func freshImportPopulatesControlEvents() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()

        let setDef = """
        #TITLE: Control Song
        #L1LABEL: BASIC
        #L1FILE: chart.dtx
        """
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf16)
        let chartContent = """
        #TITLE: Control Song
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00012: 01000000
        #00022: 16000000
        """
        try chartContent.write(to: tempDir.appendingPathComponent("chart.dtx"), atomically: true, encoding: .utf8)

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        let chart = try #require(song.charts.first)
        #expect(chart.notes.count == 1)
        #expect(chart.controlEvents.count == 1)
        let control = try #require(chart.controlEvents.first)
        #expect(control.kind == .choke)
        #expect(control.targetLaneID == "16")
    }

    @Test("refreshControlEventsIfMissing backfills controls on existing import")
    func refreshBackfillsControls() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()

        let setDef = """
        #TITLE: Backfill Song
        #L1LABEL: BASIC
        #L1FILE: chart.dtx
        """
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf16)
        let chartWithControls = """
        #TITLE: Backfill Song
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00022: 16000000
        """
        try chartWithControls.write(to: tempDir.appendingPathComponent("chart.dtx"), atomically: true, encoding: .utf8)

        // First import WITH header but the chart has no controls yet — simulate
        // a pre-feature import by manually creating the song/chart without controls.
        let song = Song(
            title: "Backfill Song", artist: "Tester", bpm: 120, duration: "1:00",
            genre: "DTX Import", timeSignature: .fourFour,
            isServerImported: true, serverSongId: tempDir.lastPathComponent
        )
        let chart = Chart(difficulty: .easy, level: 50, song: song)
        chart.notes = [Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0, chart: chart)]
        song.charts = [chart]
        context.insert(song)
        context.insert(chart)
        try context.save()

        #expect(chart.controlEvents.isEmpty)

        // Re-import triggers refreshControlEventsIfMissing
        _ = try LocalDTXFixtureImporter.importSong(
            from: tempDir, songId: tempDir.lastPathComponent, into: context
        )

        #expect(chart.controlEvents.count == 1)
        #expect(chart.controlEvents.first?.kind == .choke)

        // Idempotent: second re-import does not duplicate
        _ = try LocalDTXFixtureImporter.importSong(
            from: tempDir, songId: tempDir.lastPathComponent, into: context
        )
        #expect(chart.controlEvents.count == 1)
    }

    @Test("multi-difficulty backfill routes controls to the correct chart")
    func multiDifficultyBackfillRoutesCorrectly() throws {
        let context = TestContainer.isolatedContainer().context
        let tempDir = try makeTempDirectory()

        let setDef = """
        #TITLE: Multi Diff
        #L1LABEL: BASIC
        #L1FILE: easy.dtx
        #L2LABEL: ADVANCED
        #L2FILE: adv.dtx
        """
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf16)
        let easyChart = """
        #TITLE: Multi Diff
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 30
        #VIRGO_CONTROL: 1
        #00021: 16000000
        """
        try easyChart.write(to: tempDir.appendingPathComponent("easy.dtx"), atomically: true, encoding: .utf8)
        let advChart = """
        #TITLE: Multi Diff
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 60
        #VIRGO_CONTROL: 1
        #00022: 12000000
        """
        try advChart.write(to: tempDir.appendingPathComponent("adv.dtx"), atomically: true, encoding: .utf8)

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

        let easy = song.charts.first { $0.difficulty == .easy }
        let adv = song.charts.first { $0.difficulty == .medium }

        #expect(easy?.controlEvents.count == 1)
        #expect(easy?.controlEvents.first?.kind == .stop)
        #expect(adv?.controlEvents.count == 1)
        #expect(adv?.controlEvents.first?.kind == .choke)
        // Controls from easy do not leak to adv and vice versa
        #expect(easy?.controlEvents.first?.targetLaneID == "16")
        #expect(adv?.controlEvents.first?.targetLaneID == "12")
    }
```

- [ ] **Step 2: Run the importer tests and verify RED**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/LocalDTXFixtureImporterTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: `freshImportPopulatesControlEvents` fails because the importer never sets `chart.controlEvents`; `refreshBackfillsControls` fails because `refreshControlEventsIfMissing` does not exist.

- [ ] **Step 3: Wire fresh-import control events**

In `LocalDTXFixtureImporter.importSong` (the `importedCharts.forEach` block, around line 85), add control events after the notes assignment:

```swift
            chart.notes = importedChart.data.toNotes(for: chart)
            chart.controlEvents = importedChart.data.toControlEvents(for: chart)
            context.insert(chart)
            for note in chart.notes {
                context.insert(note)
            }
            for control in chart.controlEvents {
                context.insert(control)
            }
```

- [ ] **Step 4: Add `refreshControlEventsIfMissing` to the refresh path**

In `importSong` (around line 43, inside the `if let existingSong` block), add the call after `refreshDurationIfStale`:

```swift
            try refreshControlEventsIfMissing(for: existingSong, from: folderURL, in: context)
```

Add the method itself in the `LocalDTXFixtureImporter` enum (after `refreshDurationIfStale`, around line 313):

```swift
    /// Backfills control events on existing charts that were imported before
    /// the control-event feature. Idempotent — skips charts that already have
    /// controls. Matches charts by difficulty so multi-difficulty imports
    /// receive controls from the correct DTX file.
    @MainActor
    private static func refreshControlEventsIfMissing(
        for song: Song,
        from folderURL: URL,
        in context: ModelContext
    ) throws {
        guard let setContent = decodeSETFile(at: folderURL.appendingPathComponent(setFilename)) else { return }
        let setList = SETList(content: setContent)
        let importedCharts = try loadImportedCharts(from: folderURL, setList: setList)

        var didChange = false
        for importedChart in importedCharts {
            guard let existingChart = song.charts.first(where: {
                $0.difficulty == importedChart.difficulty && !$0.isDeleted
            }) else { continue }
            guard existingChart.safeControlEvents.isEmpty else { continue }

            let controls = importedChart.data.toControlEvents(for: existingChart)
            guard !controls.isEmpty else { continue }

            controls.forEach { context.insert($0) }
            existingChart.controlEvents = controls
            didChange = true
        }

        if didChange {
            try context.save()
        }
    }
```

- [ ] **Step 5: Run the importer tests and verify GREEN**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/LocalDTXFixtureImporterTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: all three new tests pass; existing Soukyuu import tests pass unchanged (no `#VIRGO_CONTROL` header → `toControlEvents` returns `[]`).

- [ ] **Step 6: Review and commit**

```bash
rtk git diff --check
rtk git status --short
rtk git add Virgo/utilities/LocalDTXFixtureImporter.swift VirgoTests/LocalDTXFixtureImporterTests.swift
rtk git commit -m "feat: wire local DTX importer to populate and backfill control events"
```

Expected review: no scoring, input, playback, or layout file changed; backfill is idempotent and difficulty-keyed.

---

### Task 3: Server Download Importer Wiring

**Files:**
- Modify: `Virgo/utilities/ServerSongDownloader.swift`
- Test: `VirgoTests/ServerSongDownloaderNormalizationTests.swift`

**Interfaces:**
- Consumes: `DTXChartData.toControlEvents(for:)` from Task 1.

- [ ] **Step 1: Write the failing server import test**

Add this test to the end of `struct ServerSongDownloaderNormalizationTests` in `VirgoTests/ServerSongDownloaderNormalizationTests.swift`:

```swift
    @Test("downloadAndImportSong populates controlEvents when DTX has VIRGO_CONTROL header")
    func testPopulatesControlEventsWithHeader() async throws {
        let mock = MockFileDownloader()
        let dtxContent = """
        #TITLE: Control Download
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00012: 01000000
        #00022: 16000000
        """
        let dtx = dtxContent.data(using: .shiftJIS) ?? Data(dtxContent.utf8)
        mock.responses["\(r2Base)/control/chart.dtx"] = dtx
        let config = makeConfig("ServerSongDownloaderNorm.control.\(UUID().uuidString)")
        let downloader = ServerSongDownloader(
            downloader: mock,
            fileManager: ServerSongFileManager(),
            config: config
        )

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let serverChart = ServerChart(
                difficulty: "easy", difficultyLabel: "Easy", level: 10,
                filename: "chart.dtx", size: 100,
                fileURL: "\(r2Base)/control/chart.dtx", fileEncoding: "SHIFT_JIS"
            )
            let serverSong = ServerSong(
                songId: "control-test", title: "Control Download", artist: "Tester", bpm: 120.0,
                charts: [serverChart], isDownloaded: false
            )

            let (success, _) = await downloader.downloadAndImportSong(serverSong, container: container)
            #expect(success)

            let verificationContext = ModelContext(container)
            let songs = try verificationContext.fetch(FetchDescriptor<Song>())
            let song = try #require(songs.first)
            let chart = try #require(song.charts.first)
            #expect(chart.notes.count == 1)
            #expect(chart.controlEvents.count == 1)
            let control = try #require(chart.controlEvents.first)
            #expect(control.kind == .choke)
            #expect(control.targetLaneID == "16")
        }
    }
```

- [ ] **Step 2: Run the server test and verify RED**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/ServerSongDownloaderNormalizationTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: `chart.controlEvents.count == 1` fails because the server path never populates controls.

- [ ] **Step 3: Wire control events in `processChart`**

In `ServerSongDownloader.processChart` (around line 191), add control events after the notes:

```swift
        let parsedNotes = chartData.toNotes(for: chart)
        parsedNotes.forEach { chart.notes.append($0) }
        let parsedControls = chartData.toControlEvents(for: chart)
        parsedControls.forEach { context.insert($0); chart.controlEvents.append($0) }
        context.insert(chart)
```

- [ ] **Step 4: Run the server test and verify GREEN**

Run the command from Step 2.

Expected: the control-event test passes; existing normalization/overflow tests pass unchanged.

- [ ] **Step 5: Review and commit**

```bash
rtk git diff --check
rtk git status --short
rtk git add Virgo/utilities/ServerSongDownloader.swift VirgoTests/ServerSongDownloaderNormalizationTests.swift
rtk git commit -m "feat: wire server DTX importer to populate control events"
```

Expected review: only two lines added to `processChart`; no other server-importer path changed.

---

### Task 4: Parser-to-Render Integration Test

**Files:**
- Create: `VirgoTests/DTXControlImportIntegrationTests.swift`
- Test: same file

**Interfaces:**
- Consumes: `DTXFileParser.parseChartMetadata(from:)`, `DTXChartData.toControlEvents(for:)`, `NotationLayoutEngine().layout(input:)`, `NotationLayoutTestSupport`.

- [ ] **Step 1: Write the integration test**

Create `VirgoTests/DTXControlImportIntegrationTests.swift`:

```swift
//
//  DTXControlImportIntegrationTests.swift
//  VirgoTests
//

import Testing
import Foundation
@testable import Virgo

/// End-to-end test: DTX string → parse → ChartControlEvent → layout engine →
/// rendered stop mark. Covers acceptance criterion 2 ("render") through the real
/// parser and layout engine, not just the data pipeline.
@Suite("DTX Control Import Integration")
struct DTXControlImportIntegrationTests {
    private let support = NotationLayoutTestSupport()

    @Test("parsed choke control renders as a stop mark through the layout engine")
    func parsedControlRendersAsStopMark() throws {
        let dtx = """
        #TITLE: Integration
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00012: 01000000
        #00022: 16000000
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)
        let controls = data.toControlEvents(for: chart)

        #expect(controls.count == 1)

        // Convert to NotationControlEvent (the immutable snapshot the layout engine consumes)
        let notationControls = controls.map { NotationControlEvent($0) }

        // Include a playable note so the tab grid has content to project onto
        let result = support.layout(
            notes: [support.fallbackGridNote()],
            controls: notationControls
        )

        #expect(result.stopNotes.count == 1)
        let stopNote = try #require(result.stopNotes.first)
        #expect(stopNote.kind == .choke)
        #expect(stopNote.targetLaneID == "16")
        #expect(stopNote.targetDisplayName == "Crash")
    }

    @Test("parsed incommensurate control preserves measure but omits mark")
    func parsedIncommensurateControlPreservesMeasure() throws {
        let dtx = """
        #TITLE: Incommensurate
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00012: 01000000
        #00221: 01000000000000
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)
        let controls = data.toControlEvents(for: chart)
        let notationControls = controls.map { NotationControlEvent($0) }

        let result = support.layout(
            notes: [support.fallbackGridNote()],
            controls: notationControls
        )

        // The control is at measure index 2 → total measures >= 3
        #expect(result.measures.count >= 3)
        // 1/7 does not project onto a 960-tick grid → no rendered mark
        #expect(result.stopNotes.isEmpty)
    }
}
```

- [ ] **Step 2: Run the integration test and verify GREEN**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/DTXControlImportIntegrationTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: both tests pass — the parser produces correctly-timed control events and the layout engine renders (or omits) them per the HPA-143 contract.

- [ ] **Step 3: Run full regression suites**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/DTXFileParserTests -only-testing:VirgoTests/DTXNormalizationTests -only-testing:VirgoTests/DTXNoteLineParsingTests -only-testing:VirgoTests/LocalDTXFixtureImporterTests -only-testing:VirgoTests/ServerSongDownloaderNormalizationTests -only-testing:VirgoTests/NotationLayoutControlTests -only-testing:VirgoTests/NotationLayoutRestTests -only-testing:VirgoTests/ChartControlEventTests -only-testing:VirgoTests/DTXControlImportIntegrationTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: every selected suite passes — parser, normalization, importer, layout, control-event, and integration tests all green.

- [ ] **Step 4: Review and commit**

```bash
rtk git diff --check
rtk git status --short
rtk git add VirgoTests/DTXControlImportIntegrationTests.swift
rtk git commit -m "test: add DTX parse-to-render control event integration test"
```

Expected review: the new test file exercises the full pipeline without modifying any production code; all regression suites pass.
