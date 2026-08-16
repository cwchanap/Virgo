# HPA-584 Final Report: GUI-Environment Close — Interactive Evidence Unavailable

Date: 2026-08-15
Source: `61b19cbe8da1061d64472499b06b88d991d431d9` (branch `jack65786656/hpa-584-performance-re-profile-notation-and-decide-whether-row-2`, PR #64)
Toolchain: Xcode 26.6 (17F113), Swift 6.3.3, macOS 26.5.2 (25F84), arm64

## Final state

**Close without optimization — interactive evidence unavailable.**

- Mount, scrolling, and memory behavior: **unverified** (no performance claim made).
- No row-laziness follow-up, no resize-only follow-up, no speculative issue filed.
- HPA-583 **unblocked by YAGNI**.
- iPad performance: **unverified** (no physical iPad session; advisory per plan).
- Final decision state is exactly one of the plan's four outcomes: **GUI-environment close**.

This is the plan's two-failure fallback path. No production source diff remains.

## Task 1 evidence (completed)

- Toolchain/source identity recorded above; Release compile-check `** BUILD SUCCEEDED **` (clean tree, before instrumentation).
- HPA-579 spec/plan and HPA-581 committed spec/plan read; tracked HPA-581 task-8 reports read as supporting evidence only.
- Source confirmations at HEAD: `GameplayViewModel.prepareTimelineNotation` detaches `GameplayNotationPreparer.prepare` off-main (`GameplayViewModel+Notation.swift:139`); static notation is `.equatable()` (`GameplaySheetMusicView.swift:71`); `updateRowWidth` resolves `max(900, width)` (`GameplayLayout.maxRowWidth = 900`) with on-main post-ready relayout via debounced `cacheNotationLayout()`.
- Disposable instrumentation built (Release, `/private/tmp/hpa584-release-dd`): `HPA584_PREPARED` elapsed/notes/controls/measures/rows/resolvedRowWidth/contentHeight; `HPA584_SHEET_APPEAR` insertion-only viewport/contentHeight; `HPA584_SHEET_RESIZE`; `-HPA584AutoMaster` auto-navigation; `-HPA584WindowWidth`. All reverted; scoped patch retained at `/tmp/hpa584-instrumentation.patch` (uncommitted, per plan).

## GUI attempt 1 (failure 1 — locked session)

Launched the instrumented Release app (direct exec and `open`) with `log stream` capture. Evidence: `CGSSessionScreenIsLocked = 1`, `IOConsoleLocked = Yes`, Virgo window `onscreen=false` (CGWindowList), `screencapture` denied, zero `com.cwchanap.Virgo` subsystem logs. Same failure class HPA-581 task-8B documented. Display was also asleep (`CGDisplayIsAsleep=1`, displaysleep=30); waking via `caffeinate -u` did not clear the loginwindow shield.

## Retry (failure 2 — unlocked session, windows never composite)

After the session genuinely unlocked (`CGSSessionScreenIsLocked = nil`, `IOConsoleLocked = No`, user active, display active), retried per the plan's one-retry rule:

- Original bundle id and a re-identified ad-hoc copy (`com.cwchanap.Virgo.HPA584`, HPA-581 task-8B precedent) both launched via direct exec **and** LaunchServices `open`.
- AppKit ran (AppKit state-restoration logs, window object present at 900x450) but the window stayed `onscreen=false`, subsystem logging stayed empty — SwiftUI content never mounted.
- **Control experiment:** launching `/System/Applications/Calculator.app` via `open` from this agent context also produced zero onscreen windows, while ~20 other onscreen windows existed on the console (user active). The agent execution context cannot surface GUI windows on this host; this is an environment failure, not a Virgo defect.

Two GUI environment/session failures per the plan gate ⇒ Task 6 fallback. Headless substitutes are explicitly disallowed for mount/scroll/memory evidence, and none were used.

## Task 6 cleanup (completed)

- Scoped instrumentation patch saved and reverse-applied; `git status` clean; `git diff --check` OK; no `HPA584` source remnants (`grep` verified).
- Removed: `/tmp/VirgoHPA584.app`, `/private/tmp/hpa584-release-dd`, `/private/tmp/hpa584-release-spm`, all probe/capture/log files, `default.profraw`. No in-repo `DerivedData` existed.
- No profiler artifacts committed. This report is the only tree change.

## Limitations

- No Time Profiler/SwiftUI/memory/resize evidence was collected; none is claimed.
- If evidence is wanted later: rebuild with the retained patch, launch from the **user's own Terminal** (`open <app> --args -HPA584AutoMaster`), attach `xctrace`; that requires an explicit scope change/reopen of HPA-584.
- Linear: post this outcome to HPA-584 (manual — no Linear tool in this session).
