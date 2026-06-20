# Code Review Follow-Ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the four deferred code-review follow-ups (I1, I6, C1, C2) — two small correctness/clarity fixes and two large mechanical file splits — with no behavior change.

**Architecture:** Four independent phases executed sequentially (`I1 → I6 → C1 → C2`), each ending in a green build + test + single commit. I1 swaps a main-actor `Task.sleep` timeout for a `DispatchSourceTimer` on a background queue. I6 extracts one shared BGM-offset helper used by both DTX import paths. C1 splits `GameplayViewModel.swift` into a state-holding core plus five method-only extensions. C2 splits `GameplayViewModelTests.swift` into eight themed `@Suite` structs plus a shared harness.

**Tech Stack:** Swift 5.9+, SwiftUI, SwiftData, Swift Testing (`import Testing`, `#expect`, `@Suite`), xcodebuild, SwiftLint.

## Global Constraints

- **Platforms:** Build target is `platform=macOS` for development. App is iPad-only for iOS-family builds — never introduce iPhone assumptions.
- **SwiftLint limits:** line 120/150, function body 50/100, type body 300/600, **file 600 (warn) / 1000 (error)**. Every file touched must end under 1000; aim under 600.
- **Test framework:** Swift Testing only (`import Testing`, `#expect`, `#require`, `@Suite`). No XCTest.
- **Swift Testing selectors:** verify with suite/class selectors, not guessed method selectors (method selectors can report "Executed 0 tests").
- **Known unrelated flakiness:** `InputManagerGatedSnapshotTests` is flaky under the full `VirgoTests` bundle (passes in isolation). Do not treat it as a regression.
- **Build/test commands** (reuse the existing `./DerivedData`):
  - Build: `xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData`
  - Test a suite: append `test -only-testing:VirgoTests/<SuiteStructName>` and replace `build` with `test`.
- **One commit per phase** (per the approved spec §10). Phase-internal tasks verify via build/test but do not commit until the phase's final task.

---

## Phase 1 — I1: MIDI-Learn Timeout Off the Main Actor

**Files:**
- Modify: `Virgo/utilities/MIDILearnSession.swift` (whole file, 110 lines)
- Modify: `VirgoTests/MIDILearnSessionTests.swift:62-88` (tighten deadline) and add a supersession test

**Interfaces:**
- Produces: unchanged public API of `MIDILearnSession` (`beginCapture(for:timeoutSeconds:)`, `cancelCapture()`, `consume(_:selectedSourceID:)`, `isCapturing`, `targetDrumType`, `lastConflictMessage`). Only the internal timing mechanism changes.

### Task 1.1: Replace Task-sleep timeout with DispatchSourceTimer

- [ ] **Step 1: Read the current file to confirm state**

Run: `read Virgo/utilities/MIDILearnSession.swift`
Confirm: `MIDILearnSession` is `@MainActor final class`; timeout is `Task { try await Task.sleep(...) }` at lines 49–58; `timeoutTask: Task<Void, Never>?` at line 12; `deinit { timeoutTask?.cancel() }` at 30–32.

- [ ] **Step 2: Replace the timeout storage and teardown**

In `Virgo/utilities/MIDILearnSession.swift`:

Replace the stored property (line 12):
```swift
    private var timeoutTask: Task<Void, Never>?
```
with:
```swift
    private let timeoutQueue = DispatchQueue(label: "com.virgo.midi.learn-timeout")
    // nonisolated so `deinit` (which is nonisolated) can cancel without a main-actor hop.
    // All access is serialized through `timeoutQueue`.
    private nonisolated(unsafe) var timeoutTimer: DispatchSourceTimer?
```

Replace `deinit` (lines 30–32):
```swift
    deinit {
        timeoutTask?.cancel()
    }
```
with:
```swift
    deinit {
        cancelTimeout()
    }
```

- [ ] **Step 3: Replace the timeout scheduling inside `beginCapture`**

Replace the block (lines 49–58):
```swift
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(timeoutSeconds))
            } catch {
                return
            }

            guard let self else { return }
            self.timeoutCaptureIfNeeded(captureID: captureID)
        }
```
with:
```swift
        let timer = DispatchSource.makeTimerSource(queue: timeoutQueue)
        timer.schedule(deadline: .now() + timeoutSeconds)
        timer.setEventHandler { [weak self] in
            // Hop to the main actor to mutate @MainActor state.
            Task { @MainActor in
                self?.timeoutCaptureIfNeeded(captureID: captureID)
            }
        }
        timer.resume()
        timeoutQueue.sync { timeoutTimer = timer }
```
(Keep the existing `let captureID = UUID(); activeCaptureID = captureID; ...` lines immediately above this block unchanged.)

- [ ] **Step 4: Replace `cancelCapture`'s task cancellation and add `cancelTimeout`**

In `cancelCapture()` replace `timeoutTask?.cancel(); timeoutTask = nil` with a call to `cancelTimeout()`, then add the helper. The resulting two methods:
```swift
    func cancelCapture() {
        cancelTimeout()
        targetDrumType = nil
        isCapturing = false
    }

    /// Cancels any in-flight timeout timer. Safe from the main actor and from `deinit`
    /// because it only touches the nonisolated timer via the serial `timeoutQueue`.
    private func cancelTimeout() {
        timeoutQueue.sync {
            timeoutTimer?.cancel()
            timeoutTimer = nil
        }
    }
```
Also add `cancelTimeout()` as the first line inside `beginCapture` (replacing the old `timeoutTask?.cancel()` at line 35) so a new capture supersedes any in-flight timer.

- [ ] **Step 5: Build to confirm compilation**

Run the build command from Global Constraints.
Expected: BUILD SUCCEEDED. If the compiler warns about `nonisolated(unsafe)`, that is expected and acceptable (it documents the manual contract).

- [ ] **Step 6: Run the existing MIDI tests (unchanged) to confirm no regression**

Run: `xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/MIDILearnSessionTests ONLY_ACTIVE_ARCH=YES CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData`
Expected: all existing tests PASS (the timeout test still passes with its current 30s budget — it now completes in ~0.5s).

### Task 1.2: Tighten the timeout deadline and add a supersession test

- [ ] **Step 1: Tighten the deadline in the existing timeout test**

In `VirgoTests/MIDILearnSessionTests.swift`, replace the comment + deadline block inside `learnSessionTimesOutAndClearsCaptureState` (lines 72–84):
```swift
        // The timeout Task in beginCapture runs on the main actor (MIDILearnSession
        // is @MainActor). Poll directly on the main actor with Task.sleep yields,
        // which lets the timeout Task's continuation resume between polls.
        // Under heavy CI load with parallel test suites, the 0.5s Task.sleep can
        // take much longer to resume due to main-actor contention, so use a
        // generous 30s deadline. The test completes in ~0.5s when uncontended.
        learnSession.beginCapture(for: .kick, timeoutSeconds: 0.5)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        while clock.now < deadline && learnSession.isCapturing {
            try await Task.sleep(for: .milliseconds(50))
        }
```
with:
```swift
        // The timeout now runs on a dedicated background DispatchSourceTimer, so it
        // fires ~on time regardless of main-actor load. A 3s deadline gives ample
        // headroom over the 0.5s timeout while still failing fast if the timer broke.
        learnSession.beginCapture(for: .kick, timeoutSeconds: 0.5)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline && learnSession.isCapturing {
            try await Task.sleep(for: .milliseconds(20))
        }
```

- [ ] **Step 2: Add a supersession regression test**

Append this test inside `struct MIDILearnSessionTests` (after `learnSessionTimesOutAndClearsCaptureState`):
```swift
    @Test("starting a new capture cancels the previous in-flight timeout")
    func startingNewCaptureCancelsPreviousTimeout() async throws {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDILearnSessionTests.startingNewCaptureCancelsPreviousTimeout"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let learnSession = MIDILearnSession(settingsManager: settings)
        settings.setSelectedMIDISource(id: "source-2", displayName: "TD-17")

        // Begin a capture with a short timeout, then immediately supersede it.
        learnSession.beginCapture(for: .kick, timeoutSeconds: 0.3)
        let firstCaptureTarget = learnSession.targetDrumType
        learnSession.beginCapture(for: .snare, timeoutSeconds: 0.3)

        #expect(firstCaptureTarget == .kick)
        #expect(learnSession.targetDrumType == .snare, "New capture should win immediately")
        #expect(learnSession.isCapturing)

        // Wait well past the FIRST capture's 0.3s timeout. The stale timer must not
        // fire — if it did, isCapturing would be false and targetDrumType would be nil.
        try await Task.sleep(for: .milliseconds(600))

        #expect(learnSession.isCapturing, "Superseded timeout must not have fired")
        #expect(learnSession.targetDrumType == .snare)

        // Now the second capture's timeout should fire and clear state.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline && learnSession.isCapturing {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(learnSession.isCapturing == false)
        #expect(learnSession.targetDrumType == nil)
    }
```

- [ ] **Step 3: Run the MIDI suite to confirm both tests pass**

Run: `xcodebuild test ... -only-testing:VirgoTests/MIDILearnSessionTests` (full command from Global Constraints).
Expected: all tests PASS, including the tightened (3s deadline) timeout test and the new supersession test.

- [ ] **Step 4: Commit Phase 1**

```bash
git add Virgo/utilities/MIDILearnSession.swift VirgoTests/MIDILearnSessionTests.swift
git commit -m "refactor(midi): move learn-session timeout off the main actor (I1)

Replace the main-actor Task.sleep timeout with a DispatchSourceTimer on a
dedicated background queue, hopping to @MainActor only to mutate state. The
nonisolated timer storage keeps deinit safe without an actor hop. Tightens
the test's defensive 30s poll to 3s and adds a supersession regression test."
```

---

## Phase 2 — I6: Shared BGM Start-Offset Helper

**Files:**
- Modify: `Virgo/models/DrumTrack.swift` (add helper to existing `extension Song` at line 314)
- Modify: `Virgo/utilities/ServerSongDownloader.swift:168-171`
- Modify: `Virgo/utilities/LocalDTXFixtureImporter.swift:68-82`
- Modify: `VirgoTests/LocalDTXFixtureImporterTests.swift` or `VirgoTests/NoteModelTests.swift` (add helper unit test)

**Interfaces:**
- Produces: `Song.setBGMStartOffsetIfUnset(_ parsed: Double)` — sets `bgmStartOffsetSeconds` to `parsed` only when `parsed > 0` and no positive offset is already set.

### Task 2.1: Add the helper and route both importers through it

- [ ] **Step 1: Write the failing test for the helper**

In `VirgoTests/NoteModelTests.swift`, add inside the existing `struct` (or a new `@Suite`):
```swift
    @Test("setBGMStartOffsetIfUnset applies first-positive-wins rule")
    func setBGMStartOffsetIfUnsetAppliesFirstPositiveWins() {
        let song = Song(title: "T", artist: "A", bpm: 120, duration: "1:00", genre: "Rock")
        #expect(song.bgmStartOffsetSeconds == nil)

        song.setBGMStartOffsetIfUnset(0)        // zero is ignored
        #expect(song.bgmStartOffsetSeconds == nil)

        song.setBGMStartOffsetIfUnset(1.5)      // first positive wins
        #expect(song.bgmStartOffsetSeconds == 1.5)

        song.setBGMStartOffsetIfUnset(2.0)      // later positive cannot override
        #expect(song.bgmStartOffsetSeconds == 1.5)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test ... -only-testing:VirgoTests/NoteModelTests`
Expected: FAIL — `setBGMStartOffsetIfUnset` does not exist.

- [ ] **Step 3: Add the helper to `Song`**

In `Virgo/models/DrumTrack.swift`, inside the existing `extension Song { ... }` (starts at line 314), add:
```swift
    /// Sets the BGM start offset from the first chart that defines a positive offset.
    /// Subsequent charts cannot override it (shared-BGM charts share one BGM track).
    /// Used by both LocalDTXFixtureImporter and ServerSongDownloader so the
    /// "first-positive-wins" rule has a single definition.
    func setBGMStartOffsetIfUnset(_ parsed: Double) {
        guard parsed > 0, (bgmStartOffsetSeconds ?? 0) <= 0 else { return }
        bgmStartOffsetSeconds = parsed
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test ... -only-testing:VirgoTests/NoteModelTests`
Expected: PASS.

- [ ] **Step 5: Route ServerSongDownloader through the helper**

In `Virgo/utilities/ServerSongDownloader.swift`, replace lines 168–171:
```swift
        let parsedBGMStartOffset = chartData.bgmStartOffsetSeconds
        if parsedBGMStartOffset > 0, (song.bgmStartOffsetSeconds ?? 0) <= 0 {
            song.bgmStartOffsetSeconds = parsedBGMStartOffset
        }
```
with:
```swift
        song.setBGMStartOffsetIfUnset(chartData.bgmStartOffsetSeconds)
```

- [ ] **Step 6: Route LocalDTXFixtureImporter through the helper**

In `Virgo/utilities/LocalDTXFixtureImporter.swift`, the `Song(...)` initializer (lines 68–82) currently passes:
```swift
            bgmStartOffsetSeconds: importedCharts
                .map(\.data.bgmStartOffsetSeconds)
                .first { $0 > 0 }
```
Change the initializer to pass `bgmStartOffsetSeconds: nil`, then immediately after `let song = Song(...)` (before `context.insert(song)`), iterate the charts through the shared helper:
```swift
        let song = Song(
            title: setList.title ?? firstChart.data.title,
            artist: firstChart.data.artist,
            bpm: firstChart.data.bpm,
            duration: formatDuration(Int(calculateDuration(from: importedCharts))),
            genre: "DTX Import",
            timeSignature: .fourFour,
            isServerImported: true,
            serverSongId: songId,
            bgmFilePath: existingAudioPath(named: "bgm.m4a", in: folderURL),
            previewFilePath: existingAudioPath(named: "preview.mp3", in: folderURL),
            bgmStartOffsetSeconds: nil
        )
        for imported in importedCharts {
            song.setBGMStartOffsetIfUnset(imported.data.bgmStartOffsetSeconds)
        }
```
(Keep all other initializer arguments identical to the current code.)

- [ ] **Step 7: Build and run both importer test suites**

Run build (Global Constraints), then:
`xcodebuild test ... -only-testing:VirgoTests/ServerSongDownloaderTests` and
`xcodebuild test ... -only-testing:VirgoTests/LocalDTXFixtureImporterTests`
Expected: BUILD SUCCEEDED; both suites PASS (semantics unchanged — first positive still wins).

- [ ] **Step 8: Commit Phase 2**

```bash
git add Virgo/models/DrumTrack.swift Virgo/utilities/ServerSongDownloader.swift Virgo/utilities/LocalDTXFixtureImporter.swift VirgoTests/NoteModelTests.swift
git commit -m "refactor(dtx): unify BGM start-offset first-positive-wins helper (I6)

Add Song.setBGMStartOffsetIfUnset(_:) and route both LocalDTXFixtureImporter
and ServerSongDownloader through it, giving the shared-BGM first-positive-wins
rule a single definition."
```

---

## Phase 3 — C1: Split GameplayViewModel.swift

**Files:**
- Modify (shrink): `Virgo/viewmodels/GameplayViewModel.swift` (2084 → core ~430)
- Create: `Virgo/viewmodels/GameplayViewModel+SpeedControl.swift`
- Create: `Virgo/viewmodels/GameplayViewModel+Playback.swift`
- Create: `Virgo/viewmodels/GameplayViewModel+BGM.swift`
- Create: `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`
- Create: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Modify: `Virgo.xcodeproj` (add the 5 new files to the Virgo target)

**Critical access rule (build is the oracle):**
Swift `private` is **file-scoped**. Once a method moves to an extension in a separate file, any `private` member it reads/calls — whether a stored **property** or a helper **method** still in core (or in another extension) — becomes a compile error. Fix each by dropping `private` (making it `internal`). Add a trailing comment `// internal for cross-file extension access` on the first such occurrence per member. Do NOT change any logic.

**`@Observable` constraint:** all stored `var` properties stay in the core file (the macro only sees the primary declaration). Only methods move.

### Task 3.1: Capture the baseline

- [ ] **Step 1: Record current line count**

Run: `wc -l Virgo/viewmodels/GameplayViewModel.swift`
Expected: `2084 ...`.

- [ ] **Step 2: Record the baseline test result**

Run: `xcodebuild test ... -only-testing:VirgoTests/GameplayViewModelTests` (Global Constraints command).
Record the Swift Testing summary line, e.g. `Test run with 125 tests in 1 suite passed`. Save the exact test count and pass/fail status — Phase 3's final task must reproduce this exactly.

### Task 3.2: Move Speed Control into `+SpeedControl.swift`

- [ ] **Step 1: Create the extension file**

Create `Virgo/viewmodels/GameplayViewModel+SpeedControl.swift`:
```swift
//
//  GameplayViewModel+SpeedControl.swift
//  Virgo
//

import Foundation

extension GameplayViewModel {
    // MARK: - Speed Control

    // <move all methods under the "Speed Control" MARK section here, verbatim>
}
```

- [ ] **Step 2: Move the Speed Control methods**

From `Virgo/viewmodels/GameplayViewModel.swift`, cut the entire `// MARK: - Speed Control` section (lines 269–544 — from the MARK comment through the last method before `// MARK: - Unique ID Generation` at line 545) and paste it verbatim inside the extension above. Delete it from the core file.

- [ ] **Step 3: Add the new file to the Xcode project**

Add `GameplayViewModel+SpeedControl.swift` to the Virgo target in `Virgo.xcodeproj` (match the existing file membership pattern of `GameplayViewModel.swift`).

- [ ] **Step 4: Build and fix visibility errors**

Run the build (Global Constraints). For each error of the form `'X' is inaccessible due to 'private' protection level`, change the declaration of `X` (in whichever file it lives) from `private` to `internal` (drop the `private` keyword) and add `// internal for cross-file extension access`.
Expected: BUILD SUCCEEDED after fixing visibility errors.

### Task 3.3: Move Playback Control + Cleanup into `+Playback.swift`

- [ ] **Step 1: Create the extension file**

Create `Virgo/viewmodels/GameplayViewModel+Playback.swift`:
```swift
//
//  GameplayViewModel+Playback.swift
//  Virgo
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

extension GameplayViewModel {
    // MARK: - Playback Control

    // <move Playback Control methods here>

    // MARK: - Cleanup

    // <move Cleanup methods here>
}
```
(Include `#if canImport(UIKit) import UIKit #endif` only if any moved method uses UIKit — check for haptic/UI references; the core file already imports what it needs, so add imports as the build dictates.)

- [ ] **Step 2: Move the methods**

Cut `// MARK: - Playback Control` (lines 657–923) and `// MARK: - Cleanup` (lines 924–961) from the core file and paste verbatim into the extension.

- [ ] **Step 3: Add to Xcode project, build, fix visibility**

Add to target; build; fix `private`→`internal` errors per the access rule.
Expected: BUILD SUCCEEDED.

### Task 3.4: Move BGM helpers into `+BGM.swift`

- [ ] **Step 1: Create the extension file**

Create `Virgo/viewmodels/GameplayViewModel+BGM.swift`:
```swift
//
//  GameplayViewModel+BGM.swift
//  Virgo
//

import Foundation
import AVFoundation

extension GameplayViewModel {
    // MARK: - Private Helpers

    // <move Private Helpers methods here — these are BGM playback helpers>

    // MARK: - BGM Setup

    // <move BGM Setup methods here>
}
```

- [ ] **Step 2: Move the methods**

Cut `// MARK: - Private Helpers` (lines 962–1135) and `// MARK: - BGM Setup` (lines 2058–2084, the final section) from the core file and paste verbatim into the extension.

- [ ] **Step 3: Add to Xcode project, build, fix visibility**

Add to target; build; fix `private`→`internal` errors.
Expected: BUILD SUCCEEDED.

### Task 3.5: Move Visual Updates into `+VisualUpdates.swift`

- [ ] **Step 1: Create the extension file**

Create `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`:
```swift
//
//  GameplayViewModel+VisualUpdates.swift
//  Virgo
//

import Foundation

extension GameplayViewModel {
    // MARK: - Visual Updates

    // <move Visual Updates methods here>
}
```

- [ ] **Step 2: Move the methods**

Cut the entire `// MARK: - Visual Updates` section (lines 1136–1584) from the core file and paste verbatim into the extension.

- [ ] **Step 3: Add to Xcode project, build, fix visibility**

Add to target; build; fix `private`→`internal` errors.
Expected: BUILD SUCCEEDED.

### Task 3.6: Move Computations + Scoring into `+Computations.swift`

- [ ] **Step 1: Create the extension file**

Create `Virgo/viewmodels/GameplayViewModel+Computations.swift`:
```swift
//
//  GameplayViewModel+Computations.swift
//  Virgo
//

import Foundation

extension GameplayViewModel {
    // MARK: - Unique ID Generation

    // <move Unique ID Generation methods here>

    // MARK: - Computation Methods

    // <move Computation Methods here>

    // MARK: - Scoring Methods

    // <move Scoring Methods here>
}
```

- [ ] **Step 2: Move the methods**

Cut these three sections from the core file and paste verbatim into the extension, in this order: `// MARK: - Unique ID Generation` (lines 545–554), `// MARK: - Computation Methods` (lines 1585–1906), `// MARK: - Scoring Methods` (lines 1907–2057).

- [ ] **Step 3: Add to Xcode project, build, fix visibility**

Add to target; build; fix `private`→`internal` errors.
Expected: BUILD SUCCEEDED. The core file now contains only: imports, stored state (`// MARK: - Dependencies` through `// MARK: - Subscriptions`), Initialization, Data Loading, and Setup.

### Task 3.7: Verify and commit Phase 3

- [ ] **Step 1: Confirm line counts are within limits**

Run: `wc -l Virgo/viewmodels/GameplayViewModel.swift Virgo/viewmodels/GameplayViewModel+*.swift`
Expected: every file under 1000 lines; core under ~600 (target ~430); each extension under ~600.

- [ ] **Step 2: Run the full GameplayViewModel test suite and compare to baseline**

Run: `xcodebuild test ... -only-testing:VirgoTests/GameplayViewModelTests`
Expected: identical to the Task 3.1 baseline — same test count, same pass/fail. Any difference is a move bug; locate the misplaced method and fix.

- [ ] **Step 3: Run SwiftLint on the new files**

Run: `swiftlint lint Virgo/viewmodels/`
Expected: no new `file_length` errors. (Pre-existing warnings elsewhere are out of scope.)

- [ ] **Step 4: Commit Phase 3**

```bash
git add Virgo/viewmodels/GameplayViewModel.swift Virgo/viewmodels/GameplayViewModel+SpeedControl.swift Virgo/viewmodels/GameplayViewModel+Playback.swift Virgo/viewmodels/GameplayViewModel+BGM.swift Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift Virgo/viewmodels/GameplayViewModel+Computations.swift Virgo.xcodeproj
git commit -m "refactor(gameplay): split GameplayViewModel into focused extensions (C1)

Move methods into five extension files (SpeedControl, Playback, BGM,
VisualUpdates, Computations). Stored state stays in the core file per the
@Observable macro constraint; cross-file private references widened to
internal. No behavior change — GameplayViewModelTests results unchanged."
```

---

## Phase 4 — C2: Split GameplayViewModelTests.swift

**Files:**
- Modify (replace): `VirgoTests/GameplayViewModelTests.swift` (delete the monolith at the end)
- Create: `VirgoTests/GameplayViewModelTestHarness.swift` (shared builders)
- Create: 8 themed suite files (see table below)

**Themed suites (mirror Phase 3 boundaries):**

| File | Suite struct | Topic |
|---|---|---|
| `GameplayViewModelInitializationTests.swift` | `GameplayViewModelInitializationTests` | init, initial state |
| `GameplayViewModelDataLoadingTests.swift` | `GameplayViewModelDataLoadingTests` | loadChartData, setupGameplay, notation layout caching, active lookup |
| `GameplayViewModelPlaybackTests.swift` | `GameplayViewModelPlaybackTests` | toggle/start/pause/restart/skip, completion scheduling |
| `GameplayViewModelBGMTimelineTests.swift` | `GameplayViewModelBGMTimelineTests` | BGM offset, elapsed time, speed rescale, BGM clock |
| `GameplayViewModelVisualUpdatesTests.swift` | `GameplayViewModelVisualUpdatesTests` | purple bar, visual tick throttling, quantization |
| `GameplayViewModelScoringTests.swift` | `GameplayViewModelScoringTests` | scanForMissedNotes, combo, completion grace window, high-score/session records |
| `GameplayViewModelLayoutComputationsTests.swift` | `GameplayViewModelLayoutComputationsTests` | computeDrumBeats, beat positions, findClosestBeatIndex, track duration |
| `GameplayViewModelCleanupTests.swift` | `GameplayViewModelCleanupTests` | cleanup, reset, state-reset edge cases |

### Task 4.1: Capture the baseline

- [ ] **Step 1: Record exact test count**

Run: `grep -cE "@Test" VirgoTests/GameplayViewModelTests.swift`
Expected: `125`.

- [ ] **Step 2: Record pass/fail baseline**

Run: `xcodebuild test ... -only-testing:VirgoTests/GameplayViewModelTests`
Record the summary line (`Test run with 125 tests in 1 suite passed`). Phase 4 must reproduce 125 tests with identical pass/fail, distributed across the 8 new suites.

- [ ] **Step 3: Inventory shared helpers**

Run: `grep -nE "private func|static func|func make|let .* = " VirgoTests/GameplayViewModelTests.swift | head -50`
Identify the shared setup/builders (container, track, chart, notes factories) used across tests. These move to the harness in Task 4.2.

### Task 4.2: Extract the shared harness

- [ ] **Step 1: Create the harness file**

Create `VirgoTests/GameplayViewModelTestHarness.swift`. Move every shared helper identified in Task 4.1 Step 3 into either:
- a `enum GameplayViewModelTestHarness` with `static func` builders, or
- a `@MainActor struct GameplayViewModelTestHarness` that the suites instantiate.
Keep the helper bodies verbatim. Example scaffold:
```swift
//
//  GameplayViewModelTestHarness.swift
//  VirgoTests
//

import Testing
import Foundation
import SwiftData
@testable import Virgo

@MainActor
enum GameplayViewModelTestHarness {
    // <move shared container/track/chart/notes builders here as static funcs>
}
```

- [ ] **Step 2: Build to confirm the harness compiles standalone**

It won't yet have callers; that's fine. Run the build and fix any compile errors in the moved helpers (e.g., add `import SwiftData` if needed).
Expected: BUILD SUCCEEDED (unused-warnings are acceptable).

### Task 4.3–4.10: Create each themed suite (repeat per file)

For **each** of the 8 suite files listed in the table above, perform these steps. The instruction is identical per file; only the topic/test-set differs.

> **Grouping guidance:** Categorize each `@Test` by reading its name and body (e.g., `testInitialization` → Initialization; `testLoadChartData*`/`testSetupGameplay*`/`testNotationActiveLookup*` → DataLoading; `testCalculateBGMOffset*`/`test*BGM*`/`testCalculateElapsedTime*` → BGMTimeline; `test*PurpleBar*`/`testVisualTick*` → VisualUpdates; `scanForMissedNotes`/combo/completion/high-score → Scoring; `testComputeDrumBeats`/`testFindClosestBeatIndex*`/`testCalculateTrackDuration*`/`testCacheBeatPositions` → LayoutComputations; `testCleanup*`/`testPlaybackStateReset` → Cleanup; everything playback-toggle/start/pause/restart/skip → Playback). Exact suite assignment is best-effort by topic — the **hard correctness criterion is Task 4.11**: all 125 tests present and identical pass/fail. When a test could fit two suites, pick one; do not duplicate.

- [ ] **Step 1: Create the suite file**

Create `VirgoTests/<FileName>.swift`:
```swift
//
//  <FileName>.swift
//  VirgoTests
//

import Testing
import Foundation
@testable import Virgo

@Suite("<Human Readable Topic>", .serialized)
@MainActor
struct <SuiteStructName> {
    // <move the relevant @Test functions here, verbatim>
}
```

- [ ] **Step 2: Move the relevant `@Test` functions**

From `VirgoTests/GameplayViewModelTests.swift`, cut the `@Test` functions belonging to that suite's topic (per the table) and paste them verbatim into the new struct. Update any helper calls to route through `GameplayViewModelTestHarness` where the helper was extracted in Task 4.2.

- [ ] **Step 3: Add the file to the Xcode project (VirgoTests target)**

Match the membership of the existing `GameplayViewModelTests.swift`.

- [ ] **Step 4: Build and fix compile errors**

Run the build. Fix missing imports or helper-name mismatches. Do not commit yet.
Expected: BUILD SUCCEEDED.

(Suites to create, in order: Initialization, DataLoading, Playback, BGMTimeline, VisualUpdates, Scoring, LayoutComputations, Cleanup.)

### Task 4.11: Delete the monolith and verify

- [ ] **Step 1: Delete the original monolithic struct**

Once all 125 tests are relocated (verify with `grep -rcE "@Test" VirgoTests/GameplayViewModel*.swift` summing to 125 across the new files), delete `VirgoTests/GameplayViewModelTests.swift` (remove from disk and from the VirgoTests target).

- [ ] **Step 2: Confirm total test count is preserved**

Run: `grep -rcE "@Test" VirgoTests/GameplayViewModel*.swift`
Expected: total `125` across the 8 suite files (no test lost or duplicated).

- [ ] **Step 3: Run all 8 new suites and compare to baseline**

Run: `xcodebuild test ... -only-testing:VirgoTests/GameplayViewModelInitializationTests -only-testing:VirgoTests/GameplayViewModelDataLoadingTests -only-testing:VirgoTests/GameplayViewModelPlaybackTests -only-testing:VirgoTests/GameplayViewModelBGMTimelineTests -only-testing:VirgoTests/GameplayViewModelVisualUpdatesTests -only-testing:VirgoTests/GameplayViewModelScoringTests -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests -only-testing:VirgoTests/GameplayViewModelCleanupTests`
Expected: 125 tests, pass/fail identical to the Task 4.1 baseline.

- [ ] **Step 4: Confirm line counts within limits**

Run: `wc -l VirgoTests/GameplayViewModel*.swift`
Expected: every file under 1000; ideally under 600.

- [ ] **Step 5: Commit Phase 4**

```bash
git add VirgoTests/GameplayViewModelTestHarness.swift VirgoTests/GameplayViewModel*Tests.swift Virgo.xcodeproj
git rm VirgoTests/GameplayViewModelTests.swift
git commit -m "test(gameplay): split GameplayViewModelTests into themed suites (C2)

Split the 3616-line monolith into 8 themed @Suite structs mirroring the C1
extension boundaries, plus a shared GameplayViewModelTestHarness. All 125
tests preserved with identical pass/fail."
```

---

## Final Verification (all phases)

- [ ] **Step 1: Full macOS build**

Run the build command from Global Constraints.
Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Full VirgoTests run**

Run: `xcodebuild test ... -only-testing:VirgoTests` (Global Constraints).
Expected: Swift Testing summary reports all tests passing. The only acceptable non-pass is the known-unrelated `InputManagerGatedSnapshotTests` full-bundle isolation flakiness (passes in isolation; not touched by this plan).

- [ ] **Step 3: Confirm file-length limits**

Run: `swiftlint lint Virgo/viewmodels/ VirgoTests/`
Expected: no `file_length` **errors** on any file touched by this plan. (Pre-existing warnings on unrelated files are out of scope.)
