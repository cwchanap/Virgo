# Coverage Improvement Design

## Problem

`Virgo.app` currently sits at **85.03% coverage (15282/17972 executable lines)** from the baseline unit-test coverage report. The target for this work is an **absolute 5-point increase**, bringing the app target to **at least 90.03%**.

The baseline full-suite run also exposed a **pre-existing flaky failure** in `GameplayViewModelTests.testResumePlaybackMultipleTimesMaintainsTiming`. That test passed when `GameplayViewModelTests` was run in isolation, so this design keeps that failure out of scope unless the coverage work directly touches the same code path.

## Goals

- Raise `Virgo.app` coverage to **>= 90.03%**
- Prefer **deterministic unit/render tests** over timing-sensitive interaction tests
- Reuse the repo's existing Swift Testing, SwiftData, and SwiftUI test helpers
- Limit production changes to **small internal seams** that improve testability without changing behavior

## Non-Goals

- Fixing the pre-existing `GameplayViewModelTests` timing flake
- Broad refactors unrelated to the coverage target
- Behavioral changes to gameplay, startup, or persistence flows

## Coverage Hotspots That Drive the Design

The baseline coverage report shows that the biggest practical gains are concentrated in a handful of SwiftUI-heavy files:

| File | Covered / Executable | Coverage | Uncovered lines |
| --- | ---: | ---: | ---: |
| `Virgo/views/subviews/GameplaySheetMusicView.swift` | 0 / 474 | 0.00% | 474 |
| `Virgo/views/GameplayView.swift` | 10 / 276 | 3.62% | 266 |
| `Virgo/views/BeamView.swift` | 0 / 95 | 0.00% | 95 |
| `Virgo/views/subviews/GameplayPlaybackControls.swift` | 0 / 71 | 0.00% | 71 |
| `Virgo/views/MusicNotationViews.swift` | 0 / 54 | 0.00% | 54 |
| `Virgo/views/ContentView.swift` | 242 / 338 | 71.60% | 96 |
| `Virgo/views/ProfileView.swift` | 419 / 516 | 81.20% | 97 |
| `Virgo/views/DrumBeatView.swift` | 217 / 333 | 65.17% | 116 |

These numbers make an app-shell-only pass insufficient for a +5-point increase. The design therefore targets the **gameplay rendering surface first**, then adds **app-shell/startup branch coverage**, with a final fallback pass if the first two waves do not clear the target.

## Proposed Design

### 1. Gameplay Render Coverage Pass

Add a focused gameplay render coverage suite that exercises `GameplayView` and its owned subviews in deterministic states.

#### Files to cover

- `Virgo/views/GameplayView.swift`
- `Virgo/views/subviews/GameplaySheetMusicView.swift`
- `Virgo/views/BeamView.swift`
- `Virgo/views/subviews/GameplayPlaybackControls.swift`
- `Virgo/views/MusicNotationViews.swift`

#### Test approach

- Reuse `GameplayViewModelCoverageTestSupport` to build a prepared `GameplayViewModel`
- Reuse `SwiftUITestUtilities.assertViewWithEnvironment` to mount views in both:
  - **placeholder/loading states** (`viewModel == nil`)
  - **fully prepared states** with cached notes, beam groups, measure positions, and beat positions
- Cover both the high-level `GameplayView` render path and the low-level subview branches directly so zero-coverage helpers are forced through:
  - `sheetMusicView` loading fallback vs populated sheet-music layout
  - `controlsView` placeholder vs populated controls
  - `StaffLinesBackgroundView` with multi-row measure positions
  - `BeamGroupView` / `BeamView` active and inactive beams, plus non-rendering branches (`< 2` beats, row mismatch)
  - `DrumClefSymbol` and `TimeSignatureSymbol`

#### Why this is the first wave

This cluster contains the highest number of uncovered lines that can be exercised through render-state tests without invasive production changes.

### 2. App Shell and Startup Coverage Pass

Add a second suite focused on app entry and startup orchestration.

#### Files to cover

- `Virgo/views/MainMenuView.swift`
- `Virgo/VirgoApp.swift`
- `Virgo/views/ContentView.swift`

#### Test approach

- Add `MainMenuView` coverage for renderability and stable identifiers (`logoText`, `subtitleText`, `startButton`)
- Cover `VirgoApp` launch-argument behavior by testing a small extracted helper for the UI-testing animation-disable decision
- Cover `ContentView` startup and routing branches, especially:
  - UI-testing + reset-state path
  - UI-testing + seed-if-needed path
  - skip-seed path
  - preview-vs-standard playback routing for `onPlayTap`

### 3. Minimal Production Seams

Production changes are allowed only where they make existing logic testable without altering behavior.

#### Planned seams

1. **`ContentView` startup helper**
   - Extract launch-argument/startup decisions into a small internal helper or static functions
   - Inputs should be simple values (argument list, fixture titles, song metadata)
   - Outputs should drive the same existing behavior already in `onAppear`

2. **`VirgoApp` launch helper**
   - Extract the "should disable animations for UI testing" decision into a small helper so it can be tested without bootstrapping the app lifecycle

#### Explicit constraint

These seams must stay **internal and behavior-preserving**. The surrounding view logic should keep the same runtime flow and call sites.

### 4. Fallback Coverage Sweep If Needed

If the gameplay and app-shell passes do not push coverage to `>= 90.03%`, finish with the lowest-risk follow-up targets already close to coverage payoff:

- `Virgo/views/ProfileView.swift`
- `Virgo/views/DrumBeatView.swift`

This fallback is intentionally limited to avoid turning the work into an open-ended refactor.

## Testing Strategy

- Use **Swift Testing** with `@Suite(..., .serialized)` and `@MainActor` where stateful SwiftUI or SwiftData fixtures are involved
- Use existing helpers:
  - `TestSetup.withTestSetup`
  - `GameplayViewModelCoverageTestSupport`
  - `TestModelFactory`
  - `SwiftUICoverageFixtures`
  - `SwiftUITestUtilities.assertViewWithEnvironment`
- Prefer direct render-state coverage and pure helper tests over interaction-heavy tests
- Avoid sleeps; use existing deterministic helpers and precomputed state

## Risks and Mitigations

### Risk: gameplay render tests become timing-sensitive

**Mitigation:** build view-model state explicitly and target render branches directly instead of driving playback.

### Risk: helper extraction accidentally changes behavior

**Mitigation:** keep extracted seams pure, internal, and narrowly scoped to existing branching logic.

### Risk: full-suite flake obscures final verification

**Mitigation:** keep the known `GameplayViewModelTests` flake out of scope, compare against the baseline failure, and use app-target coverage numbers from `xccov` to measure the coverage improvement directly.

## Success Criteria

- `Virgo.app` coverage reaches **at least 90.03%**
- New tests follow existing repo conventions
- Any production changes are small internal seams only
- No new product behavior is introduced as part of the coverage work
