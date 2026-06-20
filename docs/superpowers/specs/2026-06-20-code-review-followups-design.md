# Code Review Follow-Ups Design

**Date:** 2026-06-20  
**Status:** Approved for implementation planning  
**Scope:** Address the four follow-up items deferred from the `feature/gameplay-timing-navigation-and-coverage` review (I1, I6, C1, C2).

## 1. Context

The patch review on `feature/gameplay-timing-navigation-and-coverage` landed three pre-merge fixes (I2, I3, I5) and identified four follow-up items to track as tech debt. Two are small correctness/clarity fixes (I1, I6); two are large mechanical refactors that reduce two files already far past the SwiftLint `file_length` error limit (1000 lines) on `origin/main` (C1, C2):

| Item | File | Current size | Limit (warn / error) |
|---|---|---|---|
| C1 | `Virgo/viewmodels/GameplayViewModel.swift` | 2084 lines | 600 / 1000 |
| C2 | `VirgoTests/GameplayViewModelTests.swift` | 3616 lines, 125 tests | 600 / 1000 |

This spec defines all four, their dependencies, sequencing, and verification so they can be executed item-by-item under one plan.

## 2. Goals

- **I1:** Remove the main-actor scheduling dependency from the MIDI-learn timeout so the timeout fires reliably under CI load, then shrink the test's defensive 30s poll.
- **I6:** Make the "first-positive-wins" BGM start-offset semantics a single source of truth shared by both DTX import paths.
- **C1:** Split `GameplayViewModel.swift` into a focused core plus method-only extensions so every file is under the SwiftLint error limit and navigation improves.
- **C2:** Split `GameplayViewModelTests.swift` into themed `@Suite` structs mirroring C1's boundaries, preserving all 125 tests and their outcomes.
- Preserve behavior: I1/I6/C1/C2 introduce no user-visible behavior change.

## 3. Non-Goals

- Rewriting `GameplayViewModel` responsibilities or its `@Observable` design.
- Changing scoring, audio sync, notation layout, or input timing behavior.
- Adding new gameplay features.
- Splitting any file other than the two named above.
- Touching `MetronomeAudioEngine` (already addressed by I2 in the prior patch).

## 4. Decomposition & Sequencing

The four items are independent except that **C2 should follow C1** so the test suites map 1:1 onto the new production extension files.

```text
I1 (MIDI timeout)       independent  ─┐
I6 (bgm offset clarity) independent  ─┘

C1 (split viewmodel) ──► C2 (split tests, mirrors C1 boundaries)
```

**Execution order: I1 → I6 → C1 → C2**

Rationale: ship the two small, independent correctness/clarity fixes first (fast value, low risk, clear CI benefit), then the large production refactor, then the test refactor that mirrors it. Each item is implemented, built, tested, and committed before the next begins.

| Step | Item | Effort | Key risk |
|---|---|---|---|
| 1 | I1 | Moderate | Timer lifecycle / capture-ID supersession |
| 2 | I6 | Small | None material |
| 3 | C1 | Large | `private` members invisible across extension files |
| 4 | C2 | Large | Shared test harness extraction; preserving 125-test count |

## 5. I1 — MIDI-Learn Timeout Off the Main Actor

### Problem

`MIDILearnSession` is `@MainActor`. Its timeout is a `Task { try await Task.sleep(for: .seconds(timeoutSeconds)) }` (`MIDILearnSession.swift:49-58`). Because the task inherits main-actor isolation, `Task.sleep` resumes on the main actor. Under CI load with parallel test suites, main-actor contention makes a nominal 0.5s sleep take far longer to resume, which is why `MIDILearnSessionTests` polls for up to 30s (`MIDILearnSessionTests.swift:78-87`). This is a real reliability smell, not just a test artifact.

### Approach

Replace the `Task`-sleep with a `DispatchSourceTimer` scheduled on a private serial background queue. On fire, hop back to the `@MainActor` to call the existing `timeoutCaptureIfNeeded(captureID:)`.

**Threading decision (chosen):** the timer reference is `nonisolated(unsafe)` and all access to it is serialized through the dedicated `timeoutQueue`. This is required because `deinit` is nonisolated and cannot synchronously touch `@MainActor`-isolated storage; `DispatchSourceTimer.cancel()` is itself thread-safe, so guarding it with the serial queue keeps both `beginCapture`/`cancelCapture` (main actor) and `deinit` (nonisolated) safe without an actor hop during teardown.

```swift
@MainActor
final class MIDILearnSession: ObservableObject {
    // ...
    private let timeoutQueue = DispatchQueue(label: "com.virgo.midi.learn-timeout")
    private nonisolated(unsafe) var timeoutTimer: DispatchSourceTimer?

    func beginCapture(for drumType: DrumType, timeoutSeconds: Double = 10) {
        cancelTimeout()                          // supersedes any in-flight timer
        // ... existing guards + state set-up ...

        let timer = DispatchSource.makeTimerSource(queue: timeoutQueue)
        timer.schedule(deadline: .now() + timeoutSeconds)
        let captureID = self.activeCaptureID     // captured before scheduling
        timer.setEventHandler { [weak self] in
            Task { @MainActor in                 // hop to main actor to mutate state
                self?.timeoutCaptureIfNeeded(captureID: captureID)
            }
        }
        timer.resume()
        timeoutQueue.sync { timeoutTimer = timer }
    }

    func cancelTimeout() {
        timeoutQueue.sync {
            timeoutTimer?.cancel()
            timeoutTimer = nil
        }
    }
}
```

`cancelCapture()` calls `cancelTimeout()`. `deinit` calls `cancelTimeout()` directly — safe because it only touches the nonisolated timer via the serial queue. The `Task { @MainActor in ... }` inside the handler is the single main-actor hop; the sleep no longer competes for main-actor time.

### Test changes

- Tighten `MIDILearnSessionTests` timeout deadline from 30s → ~2–3s (the timeout now fires off the main actor, so it is no longer subject to main-actor contention).
- Add a test asserting that starting a new capture cancels the previous timeout (supersession does not fire the stale handler).
- All existing `MIDILearnSessionTests` must still pass.

### Verification

`xcodebuild test -only-testing:VirgoTests/MIDILearnSessionTests` on macOS; confirm the tightened deadline holds and no test relies on the old 30s budget.

## 6. I6 — BGM Start-Offset "First-Positive-Wins" as Single Source of Truth

### Problem (clarified)

The review flagged `ServerSongDownloader` "first writer wins." Investigation shows both import paths already implement the **same** semantics — use the first chart whose parsed `bgmStartOffsetSeconds` is positive — but with different code shapes:

- `LocalDTXFixtureImporter.swift:79-81` — `.map(\.data.bgmStartOffsetSeconds).first { $0 > 0 }` over all charts parsed up front.
- `ServerSongDownloader.swift:168-171` — `if parsedBGMStartOffset > 0, (song.bgmStartOffsetSeconds ?? 0) <= 0` per chart as each downloads.

So this is a clarity/consistency fix, not a behavioral bug.

### Approach

Add one shared helper on `Song` and route **both** import paths through it so the invariant has a single definition:

```swift
extension Song {
    /// Sets the BGM start offset from the first chart that defines a positive offset.
    /// Subsequent charts cannot override it (shared-BGM charts share one BGM track).
    func setBGMStartOffsetIfUnset(_ parsed: Double) {
        guard parsed > 0, (bgmStartOffsetSeconds ?? 0) <= 0 else { return }
        bgmStartOffsetSeconds = parsed
    }
}
```

- **`ServerSongDownloader`** calls `song.setBGMStartOffsetIfUnset(chartData.bgmStartOffsetSeconds)` per chart (replacing the inline guard at lines 168–171).
- **`LocalDTXFixtureImporter`** constructs the `Song` with `bgmStartOffsetSeconds: nil`, then iterates the imported charts calling the same setter (replacing the inline `.map(\.data.bgmStartOffsetSeconds).first { $0 > 0 }` at lines 79–81). Iterating the setter over the chart offsets yields the identical "first positive wins" result, now expressed through the one canonical method.

Both paths now share a single definition of the rule; the only difference is batch (local, all charts in hand) vs. incremental (server, one chart per download), which the setter handles uniformly.

### Test changes

- Add a focused test asserting both paths produce identical `bgmStartOffsetSeconds` for the same chart set (e.g., charts with offsets `[0, 1.5, 2.0]` → `1.5`).
- Existing `ServerSongDownloaderTests` and `LocalDTXFixtureImporterTests` must still pass.

### Verification

`xcodebuild test -only-testing:VirgoTests/ServerSongDownloaderTests -only-testing:VirgoTests/LocalDTXFixtureImporterTests`.

## 7. C1 — Split `GameplayViewModel.swift`

### Constraint (critical)

`GameplayViewModel` uses the `@Observable` macro. The macro only processes **stored properties in the primary type declaration**. Therefore **all `var` state stays in the core file**; only **methods** move to extensions. Extensions inherit `@MainActor` isolation automatically.

### Access-control hazard

Extensions declared in **separate files** cannot see `private` members of the core declaration. Two options:

- **(Chosen)** Move cross-extension helper methods to `internal` (default) access. The methods are already effectively internal via the type's API; this just makes the visibility explicit and consistent. Keep truly type-internal storage `private` only when no extension needs it.
- (Rejected) Put all extensions in the same file — defeats the split.

### Target file layout (methods only)

| New file | MARK sections moved (current lines) | Approx lines |
|---|---|---|
| `GameplayViewModel+SpeedControl.swift` | Speed Control (269–544) | ~275 |
| `GameplayViewModel+Playback.swift` | Playback Control + Cleanup (657–961) | ~305 |
| `GameplayViewModel+BGM.swift` | Private Helpers + BGM Setup (962–1135, 2058–2084) | ~290 |
| `GameplayViewModel+VisualUpdates.swift` | Visual Updates (1136–1584) | ~450 |
| `GameplayViewModel+Computations.swift` | Computation Methods + Scoring Methods + Unique ID Generation (545–554, 1585–2057) | ~525 |
| **Core** (kept) | State (21–232), Initialization (234–268), Data Loading (555–579), Setup (580–656) | ~430 |

The largest extension (`+Computations`, ~525) is comfortably under the 600 warn / 1000 error limits. The core (~430) holds all stored state plus init/data-loading/setup and is under the warn limit.

### Method

1. Create the five extension files with the appropriate `extension GameplayViewModel { }` and `// MARK:` headers.
2. Move method bodies verbatim (no logic changes), group by the MARK sections above.
3. Adjust access: any `private` method referenced from another extension becomes `internal` (drop the `private` keyword). Add a one-line comment where a method is `internal` specifically to allow cross-file extension use.
4. Add the new files to `Virgo.xcodeproj` target membership.
5. Build; fix the only expected failures (access visibility + missed `private` references).

### Verification

- `xcodebuild build` succeeds for macOS.
- Full `VirgoTests` run: identical pass/fail to the pre-split baseline (behavior unchanged). Capture the baseline test count before starting.
- Line counts: every resulting file under 1000 (error), ideally under 600 (warn).

## 8. C2 — Split `GameplayViewModelTests.swift`

### Approach

The file is a single `struct GameplayViewModelTests { ... }` with 125 `@Test` functions. Split into ~8 themed `@Suite` structs mirroring C1's boundaries:

| New test suite | Covers |
|---|---|
| `GameplayViewModelInitializationTests` | init, initial state |
| `GameplayViewModelDataLoadingTests` | `loadChartData`, `setupGameplay`, notation layout caching, active lookup |
| `GameplayViewModelPlaybackTests` | toggle/start/pause/restart/skip, completion scheduling |
| `GameplayViewModelBGMTimelineTests` | BGM offset, elapsed time, speed rescale, BGM clock alignment |
| `GameplayViewModelVisualUpdatesTests` | purple bar, visual tick throttling, quantization |
| `GameplayViewModelScoringTests` | `scanForMissedNotes`, combo, completion grace window, high-score/session records |
| `GameplayViewModelLayoutComputationsTests` | `computeDrumBeats`, beat positions, `findClosestBeatIndex`, track duration |
| `GameplayViewModelCleanupTests` | `cleanup`, reset, state-reset edge cases |

### Shared harness

The current file has setup helpers (container/track/chart builders). Extract these into a shared `GameplayViewModelTestHarness` (or a `GameplayViewModelTestFixtures` enum with static builders) in its own file so every suite can use them without duplication.

### Method

1. Capture the baseline: exact test count (125) and pass/fail list before starting.
2. Create the harness file; move shared builders.
3. Create the eight suite files; move `@Test` functions verbatim, grouping by the table above.
4. Each suite is `@MainActor struct ... { }` with `@Suite("...", .serialized)` where ordering matters.
5. Remove the original monolithic struct once all tests are relocated.

### Verification

- Test count after split equals 125 (no test lost or duplicated).
- Pass/fail set identical to baseline.
- Every resulting file under the SwiftLint limits.

## 9. Verification Strategy (all items)

- **Per item:** `xcodebuild build` (macOS) then the item-specific `xcodebuild test` slice, then commit.
- **C1/C2 specifically:** capture a pre-split baseline (test count + pass/fail) and assert identity post-split. This is the only reliable signal that a mechanical move preserved behavior.
- **Swift Testing selector note:** per `CLAUDE.md`, prefer suite/class selectors over guessed method selectors when verifying, since method-level selectors can report "Executed 0 tests."
- **Known unrelated flakiness:** the full `VirgoTests` bundle shows pre-existing `InputManagerGatedSnapshotTests` isolation flakiness under the full bundle (passes in isolation, unrelated to these files). Do not treat that as a regression.

## 10. Rollout / Commit Plan

One commit per item, in order, each green before the next:

1. `refactor(midi): move learn-session timeout off the main actor (I1)`
2. `refactor(dtx): unify BGM start-offset first-positive-wins helper (I6)`
3. `refactor(gameplay): split GameplayViewModel into focused extensions (C1)`
4. `test(gameplay): split GameplayViewModelTests into themed suites (C2)`

No PR is created automatically; the user decides merge timing.
