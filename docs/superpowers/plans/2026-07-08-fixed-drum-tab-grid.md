# Fixed Drum-Tab Grid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace adaptive per-measure notation spacing with a fixed chart-level drum-tab grid and one shared timeline-to-x mapper for notes, cached beats, and the purple playhead.

**Architecture:** Add `TabGrid` and mapping helpers to the existing layout model, then make `NotationLayoutEngine` emit one fixed grid per layout pass. The view model consumes the rendered notation layout as the source of truth for notation rows and x mapping while preserving legacy fallbacks.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData models, Swift Testing, Xcode project `Virgo.xcodeproj`, macOS test destination.

## Global Constraints

- Keep HPA-140 focused on fixed grid, wrapping, shared x mapping, row scroll, and geometry tests.
- Do not add zoom, fit-to-row, or user-controlled scale.
- Do not change parser normalization, notehead/stem semantics, beaming, rests, articulations, tuplets, compound meter, or variable measure-length timing.
- Keep the purple playhead beat-boundary quantized.
- Prefer `Note.normalizedTicksPerMeasure` and `normalizedTickWithinMeasure` when valid; use a deterministic 960-tick fallback otherwise.
- Keep iOS-family builds iPad-only; do not add iPhone destinations or `TARGETED_DEVICE_FAMILY = "1,2"`.
- Run Xcode tests with `-parallel-testing-enabled NO`.

---

## File Structure

- Modify `Virgo/layout/NotationLayout.swift`
  - Add `TabGrid`.
  - Add shared x/tick mapping helpers.
  - Add `tabGrid` to `NotationLayout`.
- Modify `Virgo/layout/NotationLayoutEngine.swift`
  - Build one `TabGrid` per layout pass.
  - Use fixed `tabGrid.measureWidth` for every rendered measure.
  - Resolve note x positions through `TabGrid`.
  - Retain current y placement, voice collision offsets, stems, beams, flags, and ledger lines.
- Modify `Virgo/viewmodels/GameplayViewModel+Computations.swift`
  - Rebuild notation row maps from `cachedNotationLayout.measures`.
  - Make cached beat positions use notation layout/grid when notation layout is active.
- Modify `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`
  - Make notation purple-bar x positions use `TabGrid`.
  - Keep beat-boundary quantization and final-measure clamping.
- Modify `VirgoTests/NotationLayoutEngineTests.swift`
  - Replace adaptive-width expectations with fixed-grid geometry assertions.
  - Add sparse high-resolution, dense sixteenth, shared-width, and wrapping tests.
- Modify `VirgoTests/GameplayViewModelVisualUpdatesTests.swift`
  - Update purple-bar tests to assert grid-mapper alignment.
- Modify `VirgoTests/GameplayViewModelComputationsTests.swift`
  - Add cached beat position coverage for notation layout/grid mapping.

---

### Task 1: Add `TabGrid` And Replace Adaptive Layout

**Files:**
- Modify: `Virgo/layout/NotationLayout.swift`
- Modify: `Virgo/layout/NotationLayoutEngine.swift`
- Test: `VirgoTests/NotationLayoutEngineTests.swift`

**Interfaces:**
- Produces: `TabGrid.fallbackTicksPerMeasure: Int`
- Produces: `TabGrid.xPosition(in:tickIndex:) -> CGFloat`
- Produces: `TabGrid.tickIndex(forBeatWithinMeasure:beatsPerMeasure:) -> Int`
- Produces: `NotationLayout.tabGrid: TabGrid`
- Produces: fixed-width rendered measures where `RenderedMeasure.width == NotationLayout.tabGrid.measureWidth`
- Consumes: existing `RenderedMeasure`, `NotationLayoutInput`, `Note.normalizedTickWithinMeasure`, and `Note.normalizedTicksPerMeasure`

- [ ] **Step 1: Write failing layout/grid tests**

Add these tests near the other layout metadata tests in `VirgoTests/NotationLayoutEngineTests.swift`:

```swift
@Test("layout exposes a tab grid built from normalized note metadata")
func layoutExposesTabGridFromNormalizedMetadata() throws {
    let note = Note(
        interval: .quarter,
        noteType: .snare,
        measureNumber: 1,
        measureOffset: 31.0 / 32.0,
        originKind: .dtx,
        normalizedMeasureIndex: 0,
        normalizedAbsoluteTick: 31,
        normalizedTickWithinMeasure: 31,
        normalizedTicksPerMeasure: 32
    )

    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
    )

    #expect(layout.tabGrid.ticksPerMeasure == 32)
    #expect(layout.tabGrid.leftPadding == GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing)
    #expect(layout.tabGrid.measureWidth > GameplayLayout.measureWidth(for: .fourFour))
    #expect(layout.tabGrid.measureWidth < 700)
}

@Test("tab grid maps beat boundaries to deterministic tick columns")
func tabGridMapsBeatBoundariesToDeterministicTickColumns() throws {
    let note = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
    )
    let measure = try #require(layout.measures.first)

    let startTick = layout.tabGrid.tickIndex(forBeatWithinMeasure: 0.0, beatsPerMeasure: 4)
    let secondBeatTick = layout.tabGrid.tickIndex(forBeatWithinMeasure: 1.0, beatsPerMeasure: 4)
    let startX = layout.tabGrid.xPosition(in: measure, tickIndex: startTick)
    let secondBeatX = layout.tabGrid.xPosition(in: measure, tickIndex: secondBeatTick)

    #expect(startTick == 0)
    #expect(secondBeatTick == layout.tabGrid.ticksPerMeasure / 4)
    #expect(abs(startX - (measure.xOffset + layout.tabGrid.leftPadding)) < 0.001)
    #expect(secondBeatX > startX)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -parallel-testing-enabled NO test
```

Expected: FAIL at compile time because `NotationLayout.tabGrid` and `TabGrid` do not exist.

- [ ] **Step 3: Add `TabGrid` to the layout model**

In `Virgo/layout/NotationLayout.swift`, add this type above `struct NotationLayoutInput`:

```swift
struct TabGrid: Equatable {
    static let fallbackTicksPerMeasure = 960

    let ticksPerMeasure: Int
    let tickWidth: CGFloat
    let leftPadding: CGFloat
    let measureWidth: CGFloat

    static let fallback = TabGrid(
        ticksPerMeasure: fallbackTicksPerMeasure,
        tickWidth: GameplayLayout.uniformSpacing / CGFloat(fallbackTicksPerMeasure / 4),
        leftPadding: GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing,
        measureWidth: GameplayLayout.barLineWidth
            + GameplayLayout.uniformSpacing
            + CGFloat(fallbackTicksPerMeasure) * (
                GameplayLayout.uniformSpacing / CGFloat(fallbackTicksPerMeasure / 4)
            )
    )

    func xPosition(in measure: RenderedMeasure, tickIndex: Int) -> CGFloat {
        let clampedTick = min(max(tickIndex, 0), ticksPerMeasure)
        return measure.xOffset + leftPadding + CGFloat(clampedTick) * tickWidth
    }

    func tickIndex(forBeatWithinMeasure beatWithinMeasure: Double, beatsPerMeasure: Int) -> Int {
        guard beatWithinMeasure.isFinite, beatsPerMeasure > 0 else { return 0 }
        let clampedBeat = min(max(beatWithinMeasure, 0), Double(beatsPerMeasure))
        return Int((clampedBeat / Double(beatsPerMeasure) * Double(ticksPerMeasure)).rounded())
    }
}
```

Then add `var tabGrid: TabGrid` to `NotationLayout`:

```swift
struct NotationLayout {
    var tabGrid: TabGrid
    var measures: [RenderedMeasure]
    var noteHeads: [RenderedNoteHead]
    var stems: [RenderedStem]
    var beams: [RenderedBeam]
    var flags: [RenderedFlag]
    var ledgerLines: [RenderedLedgerLine]
    var measureBars: [RenderedMeasureBar]
    var noteHeadPositionsByID: [UInt64: CGPoint]
    var noteHeadIDsByTimePosition: [Int: Set<UInt64>]
    var totalHeight: CGFloat
```

Update `NotationLayout.empty`:

```swift
static let empty = NotationLayout(
    tabGrid: .fallback,
    measures: [],
    noteHeads: [],
    stems: [],
    beams: [],
    flags: [],
    ledgerLines: [],
    measureBars: [],
    noteHeadPositionsByID: [:],
    noteHeadIDsByTimePosition: [:],
    totalHeight: 0
)
```

- [ ] **Step 4: Build the grid in `NotationLayoutEngine.layout(input:)`**

In `Virgo/layout/NotationLayoutEngine.swift`, add a grid before measures are built and pass it into the layout result:

```swift
func layout(input: NotationLayoutInput) -> NotationLayout {
    let sortedNotes = input.notes.sorted {
        MeasureUtils.timePosition(measureNumber: $0.measureNumber, measureOffset: $0.measureOffset)
        < MeasureUtils.timePosition(measureNumber: $1.measureNumber, measureOffset: $1.measureOffset)
    }
    let maxNormalizedMeasureIndex = sortedNotes.map { note in
        MeasureUtils.measureIndex(from: MeasureUtils.timePosition(
            measureNumber: note.measureNumber, measureOffset: note.measureOffset
        ))
    }.max() ?? 0
    let totalMeasures = max(input.minimumMeasureCount, maxNormalizedMeasureIndex + 1, 1)
    let tabGrid = buildTabGrid(notes: sortedNotes, input: input)
    let measures = buildMeasures(totalMeasures: totalMeasures, tabGrid: tabGrid, input: input)
    let noteHeads = buildNoteHeads(notes: sortedNotes, measures: measures, tabGrid: tabGrid, input: input)
    let beams = buildBeams(noteHeads: noteHeads, style: input.style)
    let stems = buildStems(noteHeads: noteHeads, beams: beams, style: input.style)
    let flags = buildFlags(noteHeads: noteHeads, beams: beams, stems: stems, style: input.style)
    let ledgerLines = buildLedgerLines(noteHeads: noteHeads, style: input.style)
    let measureBars = buildMeasureBars(measures: measures)
    let noteHeadPositionsByID = Dictionary(uniqueKeysWithValues: noteHeads.map { ($0.id, $0.position) })
    let noteHeadIDsByTimePosition = Dictionary(
        grouping: noteHeads,
        by: { NotationLayout.timePositionKey($0.timePosition) }
    ).mapValues { Set($0.map(\.id)) }
    let totalHeight = GameplayLayout.totalHeight(
        for: measures.map {
            GameplayLayout.MeasurePosition(row: $0.row, xOffset: $0.xOffset, measureIndex: $0.measureIndex)
        }
    )

    return NotationLayout(
        tabGrid: tabGrid,
        measures: measures,
        noteHeads: noteHeads,
        stems: stems,
        beams: beams,
        flags: flags,
        ledgerLines: ledgerLines,
        measureBars: measureBars,
        noteHeadPositionsByID: noteHeadPositionsByID,
        noteHeadIDsByTimePosition: noteHeadIDsByTimePosition,
        totalHeight: totalHeight
    )
}
```

Add this helper section before `// MARK: - Measure Building`:

```swift
// MARK: - Tab Grid

private func buildTabGrid(notes: [Note], input: NotationLayoutInput) -> TabGrid {
    let ticksPerMeasure = resolvedTicksPerMeasure(for: notes)
    let requiredGap = requiredGridColumnGap(notes: notes, input: input)
    let baselineGap = max(ticksPerMeasure / 16, 1)
    let occupiedTicks = Set(notes.map { tickWithinMeasure(for: $0, ticksPerMeasure: ticksPerMeasure) })
    let actualSmallestGap = smallestPositiveGap(in: occupiedTicks.sorted())
    let spacingTickGap = min(actualSmallestGap ?? baselineGap, baselineGap)
    let tickWidth = requiredGap / CGFloat(max(spacingTickGap, 1))
    let leftPadding = GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing
    let measureWidth = GameplayLayout.barLineWidth + leftPadding + CGFloat(ticksPerMeasure) * tickWidth

    return TabGrid(
        ticksPerMeasure: ticksPerMeasure,
        tickWidth: tickWidth,
        leftPadding: leftPadding,
        measureWidth: measureWidth
    )
}

private func resolvedTicksPerMeasure(for notes: [Note]) -> Int {
    let values = Set(notes.compactMap { note -> Int? in
        guard let ticks = note.normalizedTicksPerMeasure, ticks > 0 else { return nil }
        return ticks
    })

    guard !values.isEmpty else { return TabGrid.fallbackTicksPerMeasure }

    return values.sorted().reduce(1) { partial, value in
        guard let next = leastCommonMultiple(partial, value), next <= TabGrid.fallbackTicksPerMeasure * 64 else {
            return TabGrid.fallbackTicksPerMeasure
        }
        return next
    }
}

private func leastCommonMultiple(_ lhs: Int, _ rhs: Int) -> Int? {
    guard lhs > 0, rhs > 0 else { return nil }
    let divisor = greatestCommonDivisor(lhs, rhs)
    let divided = lhs / divisor
    guard divided <= Int.max / rhs else { return nil }
    return divided * rhs
}

private func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
    var a = lhs
    var b = rhs
    while b != 0 {
        let next = a % b
        a = b
        b = next
    }
    return abs(a)
}

private func requiredGridColumnGap(notes: [Note], input: NotationLayoutInput) -> CGFloat {
    let hasCollision = notes.contains { note in
        let measure = normalizedMeasureIndex(for: note)
        return containsCrossVoiceCollision(measureIndex: measure, notes: notes)
    }

    return hasCollision
        ? input.style.minimumNoteColumnGap + 2 * input.style.voiceCollisionOffset
        : input.style.minimumNoteColumnGap
}

private func smallestPositiveGap(in ticks: [Int]) -> Int? {
    guard ticks.count > 1 else { return nil }
    return zip(ticks.dropFirst(), ticks)
        .map { $0.0 - $0.1 }
        .filter { $0 > 0 }
        .min()
}
```

- [ ] **Step 5: Add tick conversion helper**

In the helpers section of `NotationLayoutEngine.swift`, add:

```swift
private func tickWithinMeasure(for note: Note, ticksPerMeasure: Int) -> Int {
    if let sourceTick = note.normalizedTickWithinMeasure,
       let sourceTicksPerMeasure = note.normalizedTicksPerMeasure,
       sourceTick >= 0,
       sourceTicksPerMeasure > 0,
       sourceTick <= sourceTicksPerMeasure,
       ticksPerMeasure.isMultiple(of: sourceTicksPerMeasure) {
        return min(sourceTick * (ticksPerMeasure / sourceTicksPerMeasure), ticksPerMeasure)
    }

    let offset = normalizedOffset(for: note)
    return min(max(Int((offset * Double(ticksPerMeasure)).rounded()), 0), ticksPerMeasure)
}
```

- [ ] **Step 6: Continue with fixed-width measure and note placement changes**

The model and engine signatures above are not a reviewable stopping point by themselves. Continue with Part B below in the same task before running the final test cycle or committing.

---

#### Part B: Replace Adaptive Measure Width And Note X Placement With The Grid

**Files:**
- Modify: `Virgo/layout/NotationLayoutEngine.swift`
- Test: `VirgoTests/NotationLayoutEngineTests.swift`

**Interfaces:**
- Consumes: `TabGrid.xPosition(in:tickIndex:) -> CGFloat`
- Consumes: `tickWithinMeasure(for:ticksPerMeasure:) -> Int`
- Produces: fixed-width rendered measures where `RenderedMeasure.width == NotationLayout.tabGrid.measureWidth`

- [ ] **Step 1: Replace adaptive-width tests with fixed-grid tests**

In `VirgoTests/NotationLayoutEngineTests.swift`, replace `sixteenthNotesExpandMeasureWidthForReadableSpacing` with:

```swift
@Test("sixteenth notes use fixed grid spacing for readable columns")
func sixteenthNotesUseFixedGridSpacingForReadableColumns() {
    let notes = (0..<16).map { index in
        Note(
            interval: .sixteenth,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: Double(index) / 16.0
        )
    }
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )
    let sortedX = layout.noteHeads.map(\.position.x).sorted()

    #expect(layout.measures.first?.width == layout.tabGrid.measureWidth)
    for index in 1..<sortedX.count {
        #expect(sortedX[index] - sortedX[index - 1] >= 28)
    }
}
```

Add these tests near the same section:

```swift
@Test("sparse and dense measures share fixed grid width")
func sparseAndDenseMeasuresShareFixedGridWidth() throws {
    let notes = [
        Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0),
        Note(interval: .quarter, noteType: .snare, measureNumber: 2, measureOffset: 0.0),
        Note(interval: .sixteenth, noteType: .bass, measureNumber: 2, measureOffset: 1.0 / 16.0),
        Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 2.0 / 16.0),
        Note(interval: .sixteenth, noteType: .bass, measureNumber: 2, measureOffset: 3.0 / 16.0)
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, minimumMeasureCount: 2)
    )
    let measure0 = try #require(layout.measures.first { $0.measureIndex == 0 })
    let measure1 = try #require(layout.measures.first { $0.measureIndex == 1 })

    #expect(measure0.width == measure1.width)
    #expect(measure0.width == layout.tabGrid.measureWidth)
}

@Test("sparse high resolution imported notes do not inflate from source resolution alone")
func sparseHighResolutionImportedNotesDoNotInflateFromSourceResolutionAlone() throws {
    let notes = [
        Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: 0.0,
            originKind: .dtx,
            normalizedMeasureIndex: 0,
            normalizedAbsoluteTick: 0,
            normalizedTickWithinMeasure: 0,
            normalizedTicksPerMeasure: 64
        ),
        Note(
            interval: .quarter,
            noteType: .bass,
            measureNumber: 1,
            measureOffset: 63.0 / 64.0,
            originKind: .dtx,
            normalizedMeasureIndex: 0,
            normalizedAbsoluteTick: 63,
            normalizedTickWithinMeasure: 63,
            normalizedTicksPerMeasure: 64
        )
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )
    let measure = try #require(layout.measures.first)
    let sortedX = layout.noteHeads.map(\.position.x).sorted()

    #expect(layout.tabGrid.ticksPerMeasure == 64)
    #expect(measure.width < 700)
    #expect(sortedX.last ?? 0 > sortedX.first ?? 0)
}
```

Update `quarterNotesKeepExistingSpacing` so it no longer expects the legacy `uniformSpacing`:

```swift
@Test("quarter notes align to fixed grid quarter columns")
func quarterNotesAlignToFixedGridQuarterColumns() {
    let notes = (0..<4).map { index in
        Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: Double(index) / 4.0
        )
    }
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )
    let sortedX = layout.noteHeads.map(\.position.x).sorted()
    let expectedGap = CGFloat(layout.tabGrid.ticksPerMeasure / 4) * layout.tabGrid.tickWidth

    #expect(sortedX.count == 4)
    #expect(abs((sortedX[1] - sortedX[0]) - expectedGap) < 0.001)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -parallel-testing-enabled NO test
```

Expected: FAIL because `NotationLayoutEngine` still uses adaptive `measureWidth(...)` and local `beatGap`.

- [ ] **Step 3: Make measure building use fixed grid width**

Replace `buildMeasures(totalMeasures:notes:input:)` in `Virgo/layout/NotationLayoutEngine.swift` with:

```swift
private func buildMeasures(
    totalMeasures: Int,
    tabGrid: TabGrid,
    input: NotationLayoutInput
) -> [RenderedMeasure] {
    var result: [RenderedMeasure] = []
    var currentRow = 0
    var currentX = GameplayLayout.leftMargin

    for measureIndex in 0..<totalMeasures {
        if currentX + tabGrid.measureWidth > input.style.rowWidth, measureIndex > 0 {
            currentRow += 1
            currentX = GameplayLayout.leftMargin
        }
        result.append(
            RenderedMeasure(
                id: measureIndex,
                measureIndex: measureIndex,
                row: currentRow,
                xOffset: currentX,
                width: tabGrid.measureWidth
            )
        )
        currentX += tabGrid.measureWidth + GameplayLayout.measureSpacing
    }

    return result
}
```

Leave `measureWidth(measureIndex:notes:input:)` in place only if tests or other callers still need it during the transition. If no caller remains after this task, remove it and remove its now-unused helpers in the same commit.

- [ ] **Step 4: Make note placement use `TabGrid`**

Change the `buildNoteHeads` signature and x calculation:

```swift
private func buildNoteHeads(
    notes: [Note],
    measures: [RenderedMeasure],
    tabGrid: TabGrid,
    input: NotationLayoutInput
) -> [RenderedNoteHead] {
    var nextID: UInt64 = 0
    let measuresByIndex = Dictionary(uniqueKeysWithValues: measures.map { ($0.measureIndex, $0) })
    var drafts: [NoteHeadDraft] = []

    for note in notes {
        guard let drumType = DrumType.from(noteType: note.noteType) else { continue }
        let timePos = MeasureUtils.timePosition(
            measureNumber: note.measureNumber,
            measureOffset: note.measureOffset
        )
        let normalizedMeasureIndex = MeasureUtils.measureIndex(from: timePos)
        let normalizedOffset = timePos - Double(normalizedMeasureIndex)
        guard let measure = measuresByIndex[normalizedMeasureIndex] else { continue }
        let tickIndex = tickWithinMeasure(for: note, ticksPerMeasure: tabGrid.ticksPerMeasure)
        let x = tabGrid.xPosition(in: measure, tickIndex: tickIndex)
        let resolvedPosition = notePosition(for: drumType, overrides: input.notePositionOverrides)
        let y = GameplayLayout.StaffLinePosition.line1.absoluteY(for: measure.row)
            + resolvedPosition.yOffset
        let voice = NotationVoice.voice(for: drumType)
        let direction = stemDirection(for: resolvedPosition, voice: voice)
        nextID += 1
        drafts.append(
            NoteHeadDraft(
                noteHead: RenderedNoteHead(
                    id: nextID - 1,
                    sourceNoteID: ObjectIdentifier(note),
                    drumType: drumType,
                    voice: voice,
                    timePosition: timePos,
                    measureIndex: normalizedMeasureIndex,
                    row: measure.row,
                    position: CGPoint(x: x, y: y),
                    staffStep: staffStep(for: resolvedPosition),
                    stemDirection: direction,
                    interval: note.interval
                ),
                collisionColumn: VoiceCollisionColumn(
                    measureIndex: normalizedMeasureIndex,
                    quantizedColumn: quantizedColumn(for: normalizedOffset)
                )
            )
        )
    }

    return applyVoiceCollisionOffsets(to: drafts, style: input.style)
}
```

- [ ] **Step 5: Remove obsolete adaptive width helpers**

If `measureWidth(measureIndex:notes:input:)`, `minimumColumnGap(...)`, `columnOffsets(...)`, or `beatGap(for:input:)` have no callers after Step 4, remove them. Keep `containsCrossVoiceCollision(...)` because the grid-gap calculation consumes it.

- [ ] **Step 6: Run notation layout tests**

Run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -parallel-testing-enabled NO test
```

Expected: PASS. If tests fail because old tests still assert adaptive width, update those assertions to fixed-grid equivalents in this same task.

- [ ] **Step 7: Commit fixed grid layout**

Run:

```bash
rtk git add Virgo/layout/NotationLayout.swift Virgo/layout/NotationLayoutEngine.swift VirgoTests/NotationLayoutEngineTests.swift
rtk git commit -m "feat: add fixed drum tab grid layout"
```

Expected: commit succeeds.

---

### Task 2: Route Purple Playhead X Through `TabGrid`

**Files:**
- Modify: `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`
- Test: `VirgoTests/GameplayViewModelVisualUpdatesTests.swift`

**Interfaces:**
- Consumes: `NotationLayout.tabGrid`
- Consumes: `TabGrid.tickIndex(forBeatWithinMeasure:beatsPerMeasure:) -> Int`
- Consumes: `TabGrid.xPosition(in:tickIndex:) -> CGFloat`
- Produces: `calculateNotationPurpleBarPosition(measureIndex:beatWithinMeasure:) -> (x: Double, y: Double)?` aligned with `TabGrid`

- [ ] **Step 1: Replace playhead width test with grid mapper assertion**

In `VirgoTests/GameplayViewModelVisualUpdatesTests.swift`, replace `testNotationPurpleBarPositionUsesRenderedMeasureWidth` with:

```swift
@Test func testNotationPurpleBarPositionUsesTabGridMapper() async throws {
    let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
    chart.notes.append(
        Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
    )
    chart.notes.append(
        Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 1.0 / 16.0)
    )
    let metronome = GameplayViewModelTestHarness.createTestMetronome()
    let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

    await viewModel.loadChartData()
    viewModel.setupGameplay(loadPersistedSpeed: false)

    let measure = try #require(viewModel.cachedNotationLayout.measures.first)
    let position = try #require(
        viewModel.calculateNotationPurpleBarPosition(measureIndex: 0, beatWithinMeasure: 1.0)
    )
    let tick = viewModel.cachedNotationLayout.tabGrid.tickIndex(
        forBeatWithinMeasure: 1.0,
        beatsPerMeasure: 4
    )
    let expectedX = viewModel.cachedNotationLayout.tabGrid.xPosition(in: measure, tickIndex: tick)

    #expect(abs(position.x - Double(expectedX)) < 0.001)
}
```

Update `testPurpleBarClampsToEndOfFinalMeasure` expected x:

```swift
let endTick = viewModel.cachedNotationLayout.tabGrid.ticksPerMeasure
let expectedX = viewModel.cachedNotationLayout.tabGrid.xPosition(in: measure, tickIndex: endTick)
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/GameplayViewModelVisualUpdatesTests \
  -parallel-testing-enabled NO test
```

Expected: FAIL because `calculateNotationPurpleBarPosition(...)` still computes x from `measure.width`.

- [ ] **Step 3: Update notation purple-bar mapping**

In `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`, replace `calculateNotationPurpleBarPosition(measureIndex:beatWithinMeasure:)` with:

```swift
func calculateNotationPurpleBarPosition(
    measureIndex: Int,
    beatWithinMeasure: Double
) -> (x: Double, y: Double)? {
    guard let track = track, !cachedNotationLayout.noteHeads.isEmpty else { return nil }
    guard let measure = cachedNotationLayout.measures.first(where: { $0.measureIndex == measureIndex }) else {
        return nil
    }

    let tickIndex = cachedNotationLayout.tabGrid.tickIndex(
        forBeatWithinMeasure: beatWithinMeasure,
        beatsPerMeasure: track.timeSignature.beatsPerMeasure
    )
    let indicatorX = cachedNotationLayout.tabGrid.xPosition(in: measure, tickIndex: tickIndex)
    let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measure.row)

    return (x: Double(indicatorX), y: Double(staffCenterY))
}
```

- [ ] **Step 4: Run visual update tests**

Run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/GameplayViewModelVisualUpdatesTests \
  -parallel-testing-enabled NO test
```

Expected: PASS.

- [ ] **Step 5: Commit playhead mapping**

Run:

```bash
rtk git add Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift VirgoTests/GameplayViewModelVisualUpdatesTests.swift
rtk git commit -m "fix: align notation playhead with tab grid"
```

Expected: commit succeeds.

---

### Task 3: Use Rendered Notation Rows And Grid For Cached Beat Positions

**Files:**
- Modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Test: `VirgoTests/GameplayViewModelComputationsTests.swift`

**Interfaces:**
- Consumes: `NotationLayout.measures`
- Consumes: `NotationLayout.tabGrid`
- Produces: `cachedBeatPositions[beat.id]` using notation grid x/y when `cachedNotationLayout.noteHeads` is active
- Produces: `measurePositionMap` rebuilt from rendered notation measures after `cacheNotationLayout()`

- [ ] **Step 1: Add failing cached beat position test**

Add this test under the `cacheBeatPositions` section in `VirgoTests/GameplayViewModelComputationsTests.swift`:

```swift
@Test("cacheBeatPositions uses notation tab grid when notation layout is active")
func testCacheBeatPositionsUsesNotationTabGridWhenActive() async throws {
    let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
    chart.notes.append(Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0))
    chart.notes.append(Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.25))

    let vm = GameplayViewModelCoverageTestSupport.makeViewModel(chart: chart)
    defer { vm.cleanup() }
    await vm.loadChartData()
    vm.setupGameplay(loadPersistedSpeed: false)

    let beat = try #require(vm.cachedDrumBeats.first { abs($0.timePosition - 0.25) < 0.0001 })
    let cached = try #require(vm.cachedBeatPositions[beat.id])
    let measure = try #require(vm.cachedNotationLayout.measures.first { $0.measureIndex == 0 })
    let tick = vm.cachedNotationLayout.tabGrid.tickIndex(forBeatWithinMeasure: 1.0, beatsPerMeasure: 4)
    let expectedX = vm.cachedNotationLayout.tabGrid.xPosition(in: measure, tickIndex: tick)
    let expectedY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measure.row)

    #expect(abs(cached.x - Double(expectedX)) < 0.001)
    #expect(abs(cached.y - Double(expectedY)) < 0.001)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/GameplayViewModelComputationsTests \
  -parallel-testing-enabled NO test
```

Expected: FAIL because `cacheBeatPositions()` still reads `measurePositionMap` and `GameplayLayout.preciseNoteXPosition(...)`.

- [ ] **Step 3: Rebuild `measurePositionMap` from notation layout**

In `GameplayViewModel+Computations.swift`, after `cachedMeasureRowMap` is assigned in `cacheNotationLayout()`, add:

```swift
measurePositionMap = Dictionary(
    uniqueKeysWithValues: cachedNotationLayout.measures.map { measure in
        (
            measure.measureIndex,
            GameplayLayout.MeasurePosition(
                row: measure.row,
                xOffset: measure.xOffset,
                measureIndex: measure.measureIndex
            )
        )
    }
)
```

Keep the existing fallback map built in `computeCachedLayoutData()` before notation layout exists.

- [ ] **Step 4: Split cached beat position mapping**

Replace `cacheBeatPositions()` in `GameplayViewModel+Computations.swift` with:

```swift
func cacheBeatPositions() {
    guard let track = track else { return }

    cachedBeatPositions = [:]

    if !cachedNotationLayout.noteHeads.isEmpty {
        cacheNotationBeatPositions(track: track)
    } else {
        cacheLegacyBeatPositions(track: track)
    }

    Logger.debug("Cached \(cachedBeatPositions.count) beat positions for performance optimization")
}

private func cacheNotationBeatPositions(track: DrumTrack) {
    let measuresByIndex = Dictionary(uniqueKeysWithValues: cachedNotationLayout.measures.map {
        ($0.measureIndex, $0)
    })

    for beat in cachedDrumBeats {
        let measureIndex = MeasureUtils.measureIndex(from: beat.timePosition)
        guard let measure = measuresByIndex[measureIndex] else { continue }
        let beatOffsetInMeasure = beat.timePosition - Double(measureIndex)
        let beatWithinMeasure = beatOffsetInMeasure * Double(track.timeSignature.beatsPerMeasure)
        let tick = cachedNotationLayout.tabGrid.tickIndex(
            forBeatWithinMeasure: beatWithinMeasure,
            beatsPerMeasure: track.timeSignature.beatsPerMeasure
        )
        let beatX = cachedNotationLayout.tabGrid.xPosition(in: measure, tickIndex: tick)
        let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measure.row)
        cachedBeatPositions[beat.id] = (x: Double(beatX), y: Double(staffCenterY))
    }
}

private func cacheLegacyBeatPositions(track: DrumTrack) {
    for beat in cachedDrumBeats {
        let measureIndex = MeasureUtils.measureIndex(from: beat.timePosition)

        if let measurePos = measurePositionMap[measureIndex] {
            let beatOffsetInMeasure = beat.timePosition - Double(measureIndex)
            let beatPosition = beatOffsetInMeasure * Double(track.timeSignature.beatsPerMeasure)
            let beatX = GameplayLayout.preciseNoteXPosition(
                measurePosition: measurePos,
                beatPosition: beatPosition,
                timeSignature: track.timeSignature
            )
            let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measurePos.row)
            cachedBeatPositions[beat.id] = (x: Double(beatX), y: Double(staffCenterY))
        }
    }
}
```

- [ ] **Step 5: Run computation tests**

Run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/GameplayViewModelComputationsTests \
  -parallel-testing-enabled NO test
```

Expected: PASS.

- [ ] **Step 6: Commit cached beat mapping**

Run:

```bash
rtk git add Virgo/viewmodels/GameplayViewModel+Computations.swift VirgoTests/GameplayViewModelComputationsTests.swift
rtk git commit -m "fix: cache beat positions from notation grid"
```

Expected: commit succeeds.

---

### Task 4: Verify Multi-Row Wrapping And Row Auto-Scroll Semantics

**Files:**
- Modify: `VirgoTests/NotationLayoutEngineTests.swift`
- Modify: `VirgoTests/GameplayViewModelVisualUpdatesTests.swift`
- Modify: implementation files only if these tests reveal a defect

**Interfaces:**
- Consumes: fixed `RenderedMeasure.width`
- Consumes: `GameplayViewModel.rowForMeasure(_:) -> Int`
- Produces: deterministic wrapping and row lookup from rendered notation rows

- [ ] **Step 1: Add deterministic wrapping test**

Add this test to `NotationLayoutEngineTests`:

```swift
@Test("fixed grid wrapping is deterministic across local note density")
func fixedGridWrappingIsDeterministicAcrossLocalNoteDensity() throws {
    let notes = [
        Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0),
        Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 0.0),
        Note(interval: .sixteenth, noteType: .bass, measureNumber: 2, measureOffset: 1.0 / 16.0),
        Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 2.0 / 16.0),
        Note(interval: .quarter, noteType: .bass, measureNumber: 3, measureOffset: 0.0),
        Note(interval: .quarter, noteType: .snare, measureNumber: 4, measureOffset: 0.0)
    ]
    let style = NotationLayoutStyle.gameplayDefault.with(rowWidth: 620)
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(
            notes: notes,
            timeSignature: .fourFour,
            minimumMeasureCount: 4,
            style: style
        )
    )

    let widths = Set(layout.measures.map(\.width))
    #expect(widths.count == 1)
    #expect(layout.measures.map(\.row) == [0, 1, 2, 3])
}
```

- [ ] **Step 2: Add row lookup test**

Add this test to `GameplayViewModelVisualUpdatesTests`:

```swift
@Test func testRowForMeasureUsesRenderedNotationRows() async throws {
    let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
    for measure in 1...4 {
        chart.notes.append(
            Note(interval: .quarter, noteType: .snare, measureNumber: measure, measureOffset: 0.0)
        )
    }
    let metronome = GameplayViewModelTestHarness.createTestMetronome()
    let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

    await viewModel.loadChartData()
    viewModel.cachedLayoutRowWidth = 620
    viewModel.setupGameplay(loadPersistedSpeed: false)

    let measureRows = Dictionary(
        uniqueKeysWithValues: viewModel.cachedNotationLayout.measures.map { ($0.measureIndex, $0.row) }
    )

    #expect(viewModel.rowForMeasure(0) == measureRows[0])
    #expect(viewModel.rowForMeasure(1) == measureRows[1])
    #expect(viewModel.rowForMeasure(3) == measureRows[3])
}
```

- [ ] **Step 3: Run tests to verify behavior**

Run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -only-testing:VirgoTests/GameplayViewModelVisualUpdatesTests \
  -parallel-testing-enabled NO test
```

Expected: PASS if Tasks 2 and 4 correctly made rendered notation rows authoritative. If either test fails, adjust `buildMeasures(...)`, `cacheNotationLayout()`, or `rowForMeasure(_:)` so row lookup uses `cachedNotationLayout.measures`.

- [ ] **Step 4: Run focused layout and visual suites**

Run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -only-testing:VirgoTests/GameplayViewModelVisualUpdatesTests \
  -parallel-testing-enabled NO test
```

Expected: PASS.

- [ ] **Step 5: Commit wrapping and row-scroll coverage**

Run:

```bash
rtk git add VirgoTests/NotationLayoutEngineTests.swift VirgoTests/GameplayViewModelVisualUpdatesTests.swift
rtk git commit -m "test: cover fixed grid wrapping and row lookup"
```

Expected: commit succeeds. If implementation files changed in Step 3, include them in the same commit.

---

### Task 5: Final Verification And Cleanup

**Files:**
- Modify: no files expected unless verification reveals a concrete issue

**Interfaces:**
- Consumes: all previous task outputs
- Produces: a clean working tree with focused and broad macOS verification recorded

- [ ] **Step 1: Run focused HPA-140 suites**

Run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -only-testing:VirgoTests/GameplayViewModelVisualUpdatesTests \
  -only-testing:VirgoTests/GameplayViewModelComputationsTests \
  -parallel-testing-enabled NO test
```

Expected: PASS.

- [ ] **Step 2: Run full macOS unit tests**

Run:

```bash
rtk xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests \
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: PASS. If this fails outside the touched layout/view-model/test area, capture the exact failing suite and decide whether it is related before changing code.

- [ ] **Step 3: Inspect final diff**

Run:

```bash
rtk git diff --stat d83e23b..HEAD
rtk git status --short --branch
```

Expected: the diff is limited to layout, gameplay view-model extensions, and focused tests; working tree is clean.

- [ ] **Step 4: Summarize verification**

Record the commands and outcomes in the implementation handoff or PR body:

```text
Verification:
- rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -only-testing:VirgoTests/NotationLayoutEngineTests -only-testing:VirgoTests/GameplayViewModelVisualUpdatesTests -only-testing:VirgoTests/GameplayViewModelComputationsTests -parallel-testing-enabled NO test
- rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -enableCodeCoverage YES -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected: no extra code changes in this step.
