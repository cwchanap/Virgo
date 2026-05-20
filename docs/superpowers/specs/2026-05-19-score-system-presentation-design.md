# Score System Presentation Design

**Date:** 2026-05-19  
**Status:** Approved for implementation planning  
**Scope:** Harden the existing live scoring loop and improve gameplay/results presentation.

## 1. Context

Virgo already has an active gameplay scoring pipeline:

```text
InputManager
  -> InputTimingMatcher
      -> NoteMatchResult
          -> GameplayViewModel.recordHit(result:)
              -> ScoreEngine
```

`ScoreEngine` owns score, combo, hit counts, miss counts, and timing deviation state. `GameplayViewModel` coordinates session timing, duplicate-hit rejection, auto-miss scanning, completion, and high-score persistence through `HighScoreService`. `GameplayHeaderView` already displays score and combo, and `SessionResultsView` already shows a post-run summary.

This feature should not replace that architecture. It should finish the scoring presentation around the existing system, make the live HUD more useful during tablet play, and harden edge cases that could make scoring feel unfair.

## 2. Goals

- Keep `ScoreEngine` as the scoring authority.
- Add a clear live presentation contract for score, combo, hit accuracy, weighted timing quality, counts, and timing stats.
- Keep live gameplay feedback glanceable and readable on a tablet.
- Do not show live judgment text such as `PERFECT`, `GREAT`, `GOOD`, or `MISS`.
- Improve the results sheet so it explains the session after play ends.
- Preserve current duplicate-hit handling, auto-miss late-window behavior, and per-chart high-score persistence.
- Add focused tests around scoring math, session edge cases, and UI-facing snapshots.

## 3. Non-Goals

- Replacing the scoring engine with a new rhythm-game ruleset.
- Adding a life gauge, fail state, rank letters, rewards, progression, or calibration tools.
- Changing MIDI routing, keyboard mapping, DTX parsing, notation layout, or audio sync behavior.
- Showing per-hit judgment labels during gameplay.
- Adding hardware-dependent MIDI tests.

## 4. Scoring Contract

The existing score rules remain the baseline:

- Perfect hit: 100 base points.
- Great hit: 80 base points.
- Good hit: 50 base points.
- Miss: 0 points and combo reset.
- Combo multiplier tiers stay at 10, 25, 50, and 100 combo.
- Non-miss hits increment combo before scoring.
- Auto-missed notes increment miss count and reset combo without adding score.
- Per-chart high scores are saved only when the final score is strictly greater than the existing record.

The presentation layer should expose these derived values:

| Value | Meaning |
|---|---|
| `score` | Current score from `ScoreEngine` |
| `currentCombo` | Current combo, also used as the live streak stat |
| `maxCombo` | Best combo reached in the session |
| `hitAccuracy` | Non-miss judged notes divided by total judged notes, returning 0 when no notes are judged |
| `timingQuality` | `(perfect * 1.0 + great * 0.8 + good * 0.5) / judgedNotes * 100`, with Miss weighted as 0 and empty sessions returning 0 |
| `perfectCount` / `greatCount` / `goodCount` / `missCount` | Session count breakdown |
| `averageTimingDeviation` | Mean timing error for non-miss hits with timing data |
| `timingTendency` | Early, late, or balanced session tendency |

`hitAccuracy` and `timingQuality` are intentionally separate. Hit accuracy answers "how many notes did I avoid missing?" Timing quality answers "how clean were my judged notes?"

## 5. Presentation Model

Add a small immutable presentation model named `LiveScoreSnapshot`, derived from `ScoreEngine`.

The snapshot should:

- centralize live/result formulas so SwiftUI views do not duplicate scoring math;
- be cheap to create on the main actor after each scoring change;
- expose formatted or raw numeric values as needed by the UI;
- be testable without SwiftUI or audio dependencies;
- support both live HUD and results surfaces.

`ScoreEngine` may expose any pure computed properties needed to build the snapshot, but UI components should prefer consuming the snapshot instead of reaching into all `ScoreEngine` internals directly.

## 6. Gameplay HUD Design

The live HUD should stay compact and stable. It should show:

- score;
- current combo;
- hit accuracy;
- timing quality.

It should not show judgment text. On a tablet, the player is focused on the chart and drum input; detailed text feedback would be hard to read and could distract from the notation.

The HUD should use stable dimensions for score/stat cells so changing numbers do not shift the sheet music. The existing header is the right surface, but it should be reorganized so stats are readable without crowding the title or controls.

## 7. Results Design

The results sheet should carry the detailed feedback that is intentionally absent during live play. It should show:

- final score;
- best score;
- new-best badge only when `HighScoreService.saveIfHighScore` confirms the write;
- hit accuracy;
- timing quality;
- max combo;
- Perfect / Great / Good / Miss breakdown;
- average timing deviation and timing tendency;
- `Play Again` and `Done` actions.

The results surface should explain the run in a way the player can read after finishing. It should not require reconstructing meaning from raw counts alone.

## 8. Edge Cases

The implementation should preserve or add explicit coverage for these behaviors:

- Hits before playback starts or after playback stops are ignored.
- Duplicate hits against the same note do not change score or combo.
- Wrong-lane hits inside the search window count as misses only when no matching note exists for that lane.
- Auto-missed notes are marked only after the Good late window has passed.
- Pause, MIDI disconnect, and resume do not create unavoidable misses.
- Playback completion waits through the final late-hit grace window before saving.
- Skip-to-end marks all unscored notes as misses before saving.
- Zero scores do not create high-score records.
- Failed high-score writes do not show the new-best badge.

## 9. Data Flow

1. `InputManager` receives keyboard or MIDI input during active playback.
2. `InputTimingMatcher` converts input into a `NoteMatchResult`.
3. `GameplayInputHandler` forwards the result to `GameplayViewModel.recordHit(result:)`.
4. `GameplayViewModel` scans prior missed notes, rejects duplicate hits, and updates `ScoreEngine`.
5. `GameplayViewModel` exposes a live score snapshot for HUD rendering.
6. On completion, `GameplayViewModel` saves the final score through `HighScoreService`.
7. `GameplayViewModel` captures a final score snapshot before resetting live state.
8. `SessionResultsView` renders the final snapshot and verified high-score state.

## 10. Testing Strategy

Use Swift Testing with deterministic unit coverage.

Pure scoring tests:

- `hitAccuracy` with empty, all-hit, all-miss, and mixed sessions.
- `timingQuality` with Perfect, Great, Good, Miss, and mixed sessions.
- count math, reset behavior, combo multiplier boundaries, and max combo.
- snapshot construction from representative `ScoreEngine` states.

Gameplay view-model tests:

- hit recording updates score snapshot;
- duplicate-hit rejection does not mutate score;
- auto-miss late-window behavior preserves valid late hits;
- pause/resume and MIDI disconnect paths do not advance miss scanning while paused;
- skip-to-end marks remaining notes as misses before saving;
- completion captures final score and snapshot before reset;
- failed or non-record high-score saves do not show new-best state.

UI/component tests:

- gameplay HUD receives and renders score, combo, hit accuracy, and timing quality;
- results summary receives and renders final score, high score, max combo, quality stats, and timing tendency;
- live HUD layout gives score and stat cells fixed or minimum widths so changing values do not resize the header.

Verification after implementation should run focused scoring/view-model tests first, then the full macOS `VirgoTests` command from the repository instructions.

## 11. Implementation Notes

- Keep scoring formulas pure and isolated.
- Avoid introducing `@Published` hot-path dependencies into `GameplayView`.
- Keep `GameplayViewModel` as the coordinator for live session state.
- Keep persistence outside the input/scoring hot path.
- Stage only score-system files during implementation; `.superpowers/` visual companion artifacts should remain uncommitted.
