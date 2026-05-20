# Score System Presentation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Harden Virgo's existing scoring loop and present score, combo, hit accuracy, timing quality, and results through a clean snapshot-driven UI contract.

**Architecture:** Keep `ScoreEngine` as the pure scoring authority. Add an immutable `LiveScoreSnapshot` presentation model derived from `ScoreEngine`, expose live and final snapshots from `GameplayViewModel`, then update `GameplayHeaderView` and `SessionResultsView` to consume snapshots instead of duplicating formulas.

**Tech Stack:** Swift 5.9, SwiftUI, Observation, Swift Testing, SwiftData, Xcode file-system synchronized groups.

---

## Reference

- Spec: `docs/superpowers/specs/2026-05-19-score-system-presentation-design.md`
- Existing scoring: `Virgo/utilities/ScoreEngine.swift`
- Existing gameplay coordinator: `Virgo/viewmodels/GameplayViewModel.swift`
- Existing HUD: `Virgo/components/GameplayHeaderView.swift`
- Existing results sheet: `Virgo/views/subviews/SessionResultsView.swift`
- Existing score tests: `VirgoTests/ScoreEngineTests.swift`, `VirgoTests/ScoreEngineEdgeCaseTests.swift`
- Existing gameplay tests: `VirgoTests/GameplayViewModelTests.swift`, `VirgoTests/GameplayViewModelCoveragePlaybackAdditionsTests.swift`
- Existing render tests: `VirgoTests/SwiftUIRenderingCoverageTests.swift`

The project uses `PBXFileSystemSynchronizedRootGroup`, so new Swift files under `Virgo/` and `VirgoTests/` should be picked up without manual `.pbxproj` file references.

Leave `.superpowers/` visual-companion artifacts untracked.

## Task 1: Add `LiveScoreSnapshot`

**Files:**
- Create: `Virgo/utilities/LiveScoreSnapshot.swift`
- Create: `VirgoTests/LiveScoreSnapshotTests.swift`

**Step 1: Write the failing tests**

Create `VirgoTests/LiveScoreSnapshotTests.swift`:

```swift
import Testing
@testable import Virgo

@Suite("LiveScoreSnapshot Tests")
struct LiveScoreSnapshotTests {
    @Test("empty snapshot returns zeroed display stats")
    func emptySnapshotReturnsZeroes() {
        let snapshot = LiveScoreSnapshot(scoreEngine: ScoreEngine())

        #expect(snapshot.score == 0)
        #expect(snapshot.currentCombo == 0)
        #expect(snapshot.maxCombo == 0)
        #expect(snapshot.judgedNoteCount == 0)
        #expect(snapshot.hitAccuracy == 0.0)
        #expect(snapshot.timingQuality == 0.0)
        #expect(snapshot.hitAccuracyPercentText == "0%")
        #expect(snapshot.timingQualityPercentText == "0%")
    }

    @Test("snapshot exposes score combo and counts from ScoreEngine")
    func snapshotExposesScoreComboAndCounts() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: -10.0)
        engine.processHit(accuracy: .great, timingError: 20.0)
        engine.processHit(accuracy: .good, timingError: 50.0)
        engine.processHit(accuracy: .miss)

        let snapshot = LiveScoreSnapshot(scoreEngine: engine)

        #expect(snapshot.score == engine.score)
        #expect(snapshot.currentCombo == engine.combo)
        #expect(snapshot.maxCombo == engine.maxCombo)
        #expect(snapshot.perfectCount == 1)
        #expect(snapshot.greatCount == 1)
        #expect(snapshot.goodCount == 1)
        #expect(snapshot.missCount == 1)
        #expect(snapshot.judgedNoteCount == 4)
    }

    @Test("hit accuracy counts non-miss hits over all judged notes")
    func hitAccuracyUsesNonMissOverJudgedNotes() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .great)
        engine.processHit(accuracy: .good)
        engine.processHit(accuracy: .miss)

        let snapshot = LiveScoreSnapshot(scoreEngine: engine)

        #expect(abs(snapshot.hitAccuracy - 75.0) < 0.001)
        #expect(snapshot.hitAccuracyPercentText == "75%")
    }

    @Test("timing quality uses weighted perfect great good and miss values")
    func timingQualityUsesWeightedCounts() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .great)
        engine.processHit(accuracy: .good)
        engine.processHit(accuracy: .miss)

        let snapshot = LiveScoreSnapshot(scoreEngine: engine)

        // (1.0 + 0.8 + 0.5 + 0.0) / 4 * 100 = 57.5
        #expect(abs(snapshot.timingQuality - 57.5) < 0.001)
        #expect(snapshot.timingQualityPercentText == "58%")
    }

    @Test("snapshot carries timing deviation fields")
    func snapshotCarriesTimingFields() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: -20.0)
        engine.processHit(accuracy: .great, timingError: 10.0)

        let snapshot = LiveScoreSnapshot(scoreEngine: engine)

        #expect(snapshot.averageTimingDeviation != nil)
        #expect(snapshot.earlyPercentage == engine.earlyPercentage)
        #expect(snapshot.latePercentage == engine.latePercentage)
        #expect(snapshot.timingTendency == engine.timingTendency)
    }
}
```

**Step 2: Run the failing tests**

Run:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/LiveScoreSnapshotTests \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: FAIL because `LiveScoreSnapshot` does not exist.

**Step 3: Implement the minimal model**

Create `Virgo/utilities/LiveScoreSnapshot.swift`:

```swift
import Foundation

struct LiveScoreSnapshot: Equatable {
    let score: Int
    let currentCombo: Int
    let maxCombo: Int
    let perfectCount: Int
    let greatCount: Int
    let goodCount: Int
    let missCount: Int
    let hitAccuracy: Double
    let timingQuality: Double
    let averageTimingDeviation: Double?
    let earlyPercentage: Double
    let latePercentage: Double
    let timingTendency: TimingTendency

    static let empty = LiveScoreSnapshot(scoreEngine: ScoreEngine())

    init(scoreEngine: ScoreEngine) {
        self.score = scoreEngine.score
        self.currentCombo = scoreEngine.combo
        self.maxCombo = scoreEngine.maxCombo
        self.perfectCount = scoreEngine.perfectCount
        self.greatCount = scoreEngine.greatCount
        self.goodCount = scoreEngine.goodCount
        self.missCount = scoreEngine.missCount
        self.hitAccuracy = scoreEngine.accuracyPercentage
        self.timingQuality = Self.calculateTimingQuality(
            perfectCount: scoreEngine.perfectCount,
            greatCount: scoreEngine.greatCount,
            goodCount: scoreEngine.goodCount,
            missCount: scoreEngine.missCount
        )
        self.averageTimingDeviation = scoreEngine.averageTimingDeviation
        self.earlyPercentage = scoreEngine.earlyPercentage
        self.latePercentage = scoreEngine.latePercentage
        self.timingTendency = scoreEngine.timingTendency
    }

    var judgedNoteCount: Int {
        perfectCount + greatCount + goodCount + missCount
    }

    var hitAccuracyPercentText: String {
        Self.percentText(hitAccuracy)
    }

    var timingQualityPercentText: String {
        Self.percentText(timingQuality)
    }

    private static func calculateTimingQuality(
        perfectCount: Int,
        greatCount: Int,
        goodCount: Int,
        missCount: Int
    ) -> Double {
        let judgedNotes = perfectCount + greatCount + goodCount + missCount
        guard judgedNotes > 0 else { return 0.0 }

        let weightedHits = Double(perfectCount)
            + Double(greatCount) * TimingAccuracy.great.scoreMultiplier
            + Double(goodCount) * TimingAccuracy.good.scoreMultiplier
        return weightedHits / Double(judgedNotes) * 100.0
    }

    private static func percentText(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}
```

**Step 4: Run the tests**

Run the same `xcodebuild test ... -only-testing:VirgoTests/LiveScoreSnapshotTests` command.

Expected: PASS.

**Step 5: Commit**

```bash
git add Virgo/utilities/LiveScoreSnapshot.swift VirgoTests/LiveScoreSnapshotTests.swift
git commit -m "feat: add live score snapshot"
```

## Task 2: Wire live and final snapshots through `GameplayViewModel`

**Files:**
- Modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Modify: `VirgoTests/GameplayViewModelCoveragePlaybackAdditionsTests.swift`

**Step 1: Write failing view-model snapshot tests**

Append tests to `GameplayViewModelCoveragePlaybackTests` in `VirgoTests/GameplayViewModelCoveragePlaybackAdditionsTests.swift`:

```swift
@Test("liveScoreSnapshot reflects current score engine state")
func testLiveScoreSnapshotReflectsCurrentScore() async throws {
    let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 2)
    await vm.loadChartData()
    vm.setupGameplay()
    defer { vm.cleanup() }

    vm.isPlaying = true
    let note = try #require(vm.cachedNotes.first)
    let result = NoteMatchResult(
        hitInput: InputHit(drumType: .kick, velocity: 1.0, timestamp: Date()),
        matchedNote: note,
        timingAccuracy: .perfect,
        measureNumber: note.measureNumber,
        measureOffset: note.measureOffset,
        timingError: 0.0
    )

    vm.recordHit(result: result)

    #expect(vm.liveScoreSnapshot.score == 100)
    #expect(vm.liveScoreSnapshot.currentCombo == 1)
    #expect(vm.liveScoreSnapshot.hitAccuracy == 100.0)
    #expect(vm.liveScoreSnapshot.timingQuality == 100.0)
}

@Test("handlePlaybackCompletion captures final score snapshot before reset")
func testHandlePlaybackCompletionCapturesFinalScoreSnapshot() async throws {
    let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 2)
    await vm.loadChartData()
    vm.setupGameplay()
    defer { vm.cleanup() }

    vm.startPlayback()
    let note = try #require(vm.cachedNotes.first)
    let result = NoteMatchResult(
        hitInput: InputHit(drumType: .kick, velocity: 1.0, timestamp: Date()),
        matchedNote: note,
        timingAccuracy: .great,
        measureNumber: note.measureNumber,
        measureOffset: note.measureOffset,
        timingError: 20.0
    )
    vm.recordHit(result: result)

    vm.handlePlaybackCompletion()

    #expect(vm.scoreEngine.score == 0)
    #expect(vm.sessionScoreSnapshot.score == 80)
    #expect(vm.sessionScoreSnapshot.currentCombo == 1)
    #expect(vm.sessionScoreSnapshot.timingQuality == 80.0)
    #expect(vm.sessionScoreSnapshot.averageTimingDeviation == 20.0)
}
```

**Step 2: Run the failing tests**

Run:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/GameplayViewModelPlaybackCoverageTests \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: FAIL because `liveScoreSnapshot` and `sessionScoreSnapshot` do not exist.

**Step 3: Add snapshot properties and completion capture**

In `Virgo/viewmodels/GameplayViewModel.swift`, near the scoring state properties, add:

```swift
    var liveScoreSnapshot: LiveScoreSnapshot {
        LiveScoreSnapshot(scoreEngine: scoreEngine)
    }
    /// Snapshot captured at session end before resetScoring clears live state.
    var sessionScoreSnapshot = LiveScoreSnapshot.empty
```

In `handlePlaybackCompletion()`, capture the snapshot before reset:

```swift
        let finalScore = scoreEngine.score
        let finalSnapshot = LiveScoreSnapshot(scoreEngine: scoreEngine)
        let isNewRecord = highScoreService.saveIfHighScore(finalScore, for: chart.persistentModelID)
        sessionScoreEngine = scoreEngine
        resetPlaybackState()
```

After reset, preserve the final snapshot for the results sheet:

```swift
        sessionFinalScore = finalScore
        sessionScoreSnapshot = finalSnapshot
        sessionIsNewRecord = isNewRecord
        isShowingSessionResults = true
```

In `resetScoring()`, clear stale final snapshots when a new run starts:

```swift
        sessionScoreSnapshot = .empty
```

If a test shows this clears the just-captured completion snapshot, keep the assignment after `resetPlaybackState()` as shown above.

**Step 4: Run the tests**

Run the same `GameplayViewModelPlaybackCoverageTests` command.

Expected: PASS.

**Step 5: Commit**

```bash
git add Virgo/viewmodels/GameplayViewModel.swift VirgoTests/GameplayViewModelCoveragePlaybackAdditionsTests.swift
git commit -m "feat: expose gameplay score snapshots"
```

## Task 3: Harden paused finite miss scanning

**Files:**
- Modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Modify: `VirgoTests/GameplayViewModelCoveragePlaybackAdditionsTests.swift`

**Step 1: Write the failing paused-scan test**

Append to `GameplayViewModelPlaybackCoverageTests`:

```swift
@Test("finite missed-note scan is ignored while playback is paused")
func testFiniteMissScanIgnoredWhilePaused() async throws {
    let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 2)
    await vm.loadChartData()
    vm.setupGameplay()
    defer { vm.cleanup() }

    vm.startPlayback()
    vm.pausePlayback()

    #expect(vm.isPlaying == false)
    vm.scanForMissedNotes(upToTimePosition: 10.0)

    #expect(vm.scoreEngine.missCount == 0)
    #expect(vm.liveScoreSnapshot.judgedNoteCount == 0)
}
```

**Step 2: Run the failing test**

Run:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/GameplayViewModelPlaybackCoverageTests/testFiniteMissScanIgnoredWhilePaused \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: FAIL because `scanForMissedNotes(upToTimePosition:)` currently has no paused finite-scan guard.

**Step 3: Add the guard**

At the top of `scanForMissedNotes(upToTimePosition:)`, after the method starts and before calculating the miss boundary:

```swift
        guard isPlaying || playheadPosition.isInfinite else { return }
```

This allows existing skip-to-end and completion scans that pass `.infinity`, while preventing finite visual-tick style scans from mutating score after pause or disconnect.

**Step 4: Run focused scan tests**

Run:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/GameplayViewModelPlaybackCoverageTests/testFiniteMissScanIgnoredWhilePaused \
  -only-testing:VirgoTests/GameplayViewModelTests/testScanCursorResetsOnResetScoring \
  -only-testing:VirgoTests/GameplayViewModelTests/testScanMissTriggersComboBreakFeedback \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Virgo/viewmodels/GameplayViewModel.swift VirgoTests/GameplayViewModelCoveragePlaybackAdditionsTests.swift
git commit -m "fix: ignore paused finite miss scans"
```

## Task 4: Add snapshot-driven gameplay HUD

**Files:**
- Modify: `Virgo/components/GameplayHeaderView.swift`
- Modify: `VirgoTests/SwiftUIRenderingCoverageTests.swift`

**Step 1: Write/update rendering tests**

In `VirgoTests/SwiftUIRenderingCoverageTests.swift`, update the existing header render test or add a new one that prepares a view model with score data:

```swift
@Test("GameplayHeaderView renders score snapshot stats")
func testGameplayHeaderViewRendersScoreSnapshotStats() async throws {
    try await TestSetup.withTestSetup {
        let vm = await GameplayViewModelCoverageTestSupport.makePreparedViewModel()
        vm.isPlaying = true
        let note = try #require(vm.cachedNotes.first)
        let result = NoteMatchResult(
            hitInput: InputHit(drumType: .kick, velocity: 1.0, timestamp: Date()),
            matchedNote: note,
            timingAccuracy: .perfect,
            measureNumber: note.measureNumber,
            measureOffset: note.measureOffset,
            timingError: 0.0
        )
        vm.recordHit(result: result)

        let track = try #require(vm.track)
        let view = GameplayHeaderView(
            track: track,
            isPlaying: .constant(true),
            viewModel: vm,
            onDismiss: {},
            onPlayPause: {},
            onRestart: {}
        )
        .background(Color.black)

        SwiftUITestUtilities.assertViewWithEnvironment(view, size: CGSize(width: 1280, height: 130))
        vm.cleanup()
    }
}
```

**Step 2: Run the rendering test**

Run:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/SwiftUIRenderingCoverageTests/testGameplayHeaderViewRendersScoreSnapshotStats \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: It may PASS before UI changes if the test only checks renderability. That is acceptable as a coverage test, but still perform Step 3 because the spec requires the new stats in the HUD.

**Step 3: Update the HUD implementation**

In `GameplayHeaderView.body`, derive a snapshot:

```swift
                let snapshot = viewModel?.liveScoreSnapshot ?? .empty
                GameplayScoreHUDView(
                    snapshot: snapshot,
                    showMilestone: viewModel?.showMilestoneAnimation ?? false,
                    showBreak: viewModel?.showComboBreakFeedback ?? false
                )
```

Replace the current score/combo-only `VStack` with `GameplayScoreHUDView`.

Add private views in `GameplayHeaderView.swift`:

```swift
private struct GameplayScoreHUDView: View {
    let snapshot: LiveScoreSnapshot
    let showMilestone: Bool
    let showBreak: Bool

    var body: some View {
        HStack(spacing: 8) {
            ScoreStatCell(label: "SCORE", value: "\(snapshot.score)", color: .white, minWidth: 76)
            ScoreStatCell(label: "ACC", value: snapshot.hitAccuracyPercentText, color: .green, minWidth: 54)
            ScoreStatCell(label: "QLTY", value: snapshot.timingQualityPercentText, color: .cyan, minWidth: 54)
            ComboCounterView(
                combo: snapshot.currentCombo,
                showMilestone: showMilestone,
                showBreak: showBreak
            )
            .frame(minWidth: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Score \(snapshot.score), accuracy \(snapshot.hitAccuracyPercentText), " +
            "quality \(snapshot.timingQualityPercentText), combo \(snapshot.currentCombo)"
        )
    }
}

private struct ScoreStatCell: View {
    let label: String
    let value: String
    let color: Color
    let minWidth: CGFloat

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.gray)
        }
        .frame(minWidth: minWidth, alignment: .trailing)
    }
}
```

Adjust spacing and widths to keep title and controls readable at `1280 x 120`. Keep the header dark and compact; do not add live judgment text.

**Step 4: Run header tests**

Run:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/SwiftUIRenderingCoverageTests/testGameplayHeaderViewRendering \
  -only-testing:VirgoTests/SwiftUIRenderingCoverageTests/testGameplayHeaderViewRendersScoreSnapshotStats \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Virgo/components/GameplayHeaderView.swift VirgoTests/SwiftUIRenderingCoverageTests.swift
git commit -m "feat: show live score quality in gameplay HUD"
```

## Task 5: Update results sheet to use final score snapshot

**Files:**
- Modify: `Virgo/views/subviews/SessionResultsView.swift`
- Modify: `Virgo/views/GameplayView.swift`
- Modify: `VirgoTests/SwiftUIRenderingCoverageTests.swift`

**Step 1: Write/update failing results tests**

Update `SessionResultsView` construction in `VirgoTests/SwiftUIRenderingCoverageTests.swift` to pass a snapshot:

```swift
let scoreEngine = makeScoreEngineForResults()
let view = SessionResultsView(
    finalScore: 2450,
    highScore: 2450,
    isNewRecord: true,
    scoreSnapshot: LiveScoreSnapshot(scoreEngine: scoreEngine),
    onPlayAgain: {},
    onDone: {}
)
```

Apply the same pattern to the non-record results test.

**Step 2: Run the failing rendering tests**

Run:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/SwiftUIRenderingCoverageTests/testSessionResultsViewRenderingForNewRecord \
  -only-testing:VirgoTests/SwiftUIRenderingCoverageTests/testSessionResultsViewRenderingWithoutRecordBadge \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: FAIL because `SessionResultsView` still accepts `scoreEngine`.

**Step 3: Update `SessionResultsView`**

Change the property:

```swift
    let scoreSnapshot: LiveScoreSnapshot
```

Replace direct `scoreEngine` reads:

```swift
AccuracyCircleView(percentage: scoreSnapshot.hitAccuracy)
```

```swift
AccuracyBreakdownChart(
    perfectCount: scoreSnapshot.perfectCount,
    greatCount: scoreSnapshot.greatCount,
    goodCount: scoreSnapshot.goodCount,
    missCount: scoreSnapshot.missCount
)
```

```swift
TimingDeviationView(
    averageDeviation: scoreSnapshot.averageTimingDeviation,
    earlyPercentage: scoreSnapshot.earlyPercentage,
    latePercentage: scoreSnapshot.latePercentage,
    tendency: scoreSnapshot.timingTendency
)
```

Update `statsGrid` to include max combo, timing quality, and best score:

```swift
private var statsGrid: some View {
    HStack(spacing: 0) {
        statCell(label: "MAX COMBO", value: "\(scoreSnapshot.maxCombo)x", color: .orange)
        statCell(label: "QUALITY", value: scoreSnapshot.timingQualityPercentText, color: .cyan)
        statCell(label: "BEST SCORE", value: "\(highScore)", color: .purple)
    }
    .padding(.horizontal)
}
```

Update the preview to build a `LiveScoreSnapshot(scoreEngine: engine)`.

**Step 4: Update `GameplayView` call site**

In `Virgo/views/GameplayView.swift`, change:

```swift
                    scoreEngine: vm.sessionScoreEngine,
```

to:

```swift
                    scoreSnapshot: vm.sessionScoreSnapshot,
```

**Step 5: Run the results tests**

Run the same two `SwiftUIRenderingCoverageTests` results tests.

Expected: PASS.

**Step 6: Commit**

```bash
git add Virgo/views/subviews/SessionResultsView.swift Virgo/views/GameplayView.swift VirgoTests/SwiftUIRenderingCoverageTests.swift
git commit -m "feat: render results from score snapshots"
```

## Task 6: Run final focused and full verification

**Files:**
- No code edits unless verification finds a regression.

**Step 1: Run focused score presentation tests**

Run:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/LiveScoreSnapshotTests \
  -only-testing:VirgoTests/GameplayViewModelPlaybackCoverageTests \
  -only-testing:VirgoTests/SwiftUIRenderingCoverageTests \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: PASS.

**Step 2: Run full unit tests**

Run:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: PASS.

**Step 3: Run SwiftLint if available**

Run:

```bash
swiftlint lint
```

Expected: PASS or only pre-existing warnings unrelated to touched files. If `swiftlint` is unavailable, record that clearly in the final implementation report.

**Step 4: Inspect final diff**

Run:

```bash
git status -sb
git diff --stat
git diff --check
```

Expected: only score-system files changed, no whitespace errors, `.superpowers/` still untracked unless separately ignored by the user.

**Step 5: Final commit if verification required fixes**

If verification required fixes, commit them:

```bash
git add Virgo/utilities/LiveScoreSnapshot.swift Virgo/viewmodels/GameplayViewModel.swift Virgo/components/GameplayHeaderView.swift Virgo/views/GameplayView.swift Virgo/views/subviews/SessionResultsView.swift VirgoTests/LiveScoreSnapshotTests.swift VirgoTests/GameplayViewModelCoveragePlaybackAdditionsTests.swift VirgoTests/SwiftUIRenderingCoverageTests.swift
git commit -m "test: verify score presentation flow"
```

If no extra fixes were needed after the task commits, do not create an empty commit.
