# HPA-581 Task 8B report: final Release profile/evidence handoff

Date: 2026-08-14
Gate: **BLOCKED for the final interactive/resize evidence; worker-path CPU evidence captured**

## Scope and outcome

This was a Release evidence-only run. The candidate source measured by the
Release build and by the disposable headless profile was
`00cc98747db8ba4cf23ff066f2b9ec313304c76a`. No production source, tests, or
project files were changed persistently. The shared report worktree advanced to
`401d827` during the concurrent Task 8A handoff; that pre-existing commit is
report-only and did not change the candidate source measured here.

The required real GUI attempt was blocked by the active macOS session. A
disposable current-code representative run did complete the allowed headless
worker-path check: the Release Time Profiler trace had zero main-thread samples
containing `NotationLayoutEngine.layout`, while both layout samples were on
background thread `492`. This confirms that the shipped timeline notation
layout/beat-position preparation was not sampled on the main-thread preparation
slice. It does not prove visible mount, static-body painting, playback
presentation, auto-scroll correctness, or natural resize behavior.

## Release build identity

The normal candidate Release app was built with a profile-only path, separate
from Task 8A's `./DerivedData`:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/hpa581-task8b-profile-dd-20260814 \
  -clonedSourcePackagesDirPath /private/tmp/hpa581-task8b-profile-spm-20260814 \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build
```

Result: `** BUILD SUCCEEDED **`.

```text
source candidate: 00cc98747db8ba4cf23ff066f2b9ec313304c76a
app: /private/tmp/hpa581-task8b-profile-dd-20260814/Build/Products/Release/Virgo.app
binary SHA-256: 394e96f2991fe2e1a1312dd0617a776d2c6844d8df4ca69c5f32a1b394c5e7b8
binary: universal Mach-O arm64 + x86_64
bundle identifier: cwchanap.Virgo
version: 1.0 (1)
Xcode: 26.6 (17F113)
xctrace: 16.0 (17F113)
macOS: 26.5.2 (25F84)
```

The built app was copied to a disposable uniquely identified bundle for the
GUI launch (`com.cwchanap.Virgo.HPA581Task8B`), so it did not reuse the
currently running Task 8A app identity.

## Real GUI attempt

The normal Release launch was attempted first. The exact observations were:

```text
CGSSessionScreenIsLocked=Yes
CGSSessionScreenLockedTime=<non-null>
System Events accessibility query: osascript is not allowed assistive access. (-25211)
GUI process: PID 16863, disposable Release app copy
capture: macOS lock/password screen, not a Virgo window
```

The process was stopped after the blocked attempt. There was no usable Virgo
window or accessibility tree. Therefore the following evidence was **not
obtained** and is intentionally not claimed:

- chart selection through the real library UI;
- visible gameplay mount or initial-mount comparison with HPA-579's
  `4,890.729 ms` reference;
- static-body paint behavior;
- audible or compositor-presented playback;
- visible auto-scroll correctness;
- natural host-window access or ordinary resize/row repacking;
- any width decision.

## Allowed headless worker-path check

Because the GUI was locked, a disposable detached worktree at exactly
`00cc98747db8ba4cf23ff066f2b9ec313304c76a` used the established Task 3
launch-argument-only representative setup identity. The temporary hook used
the bundled `soukyuu_e_no_shouka` fixture, the real import/model graph, the
Expert chart, `GameplayViewModel.loadChartData()`, `rowWidth = 900`, and
`await setupGameplay()`. A second temporary AppKit-init trigger was needed to
start the same hook while the shield prevented reliable view mounting; it did
not change normal startup behavior and was deleted with the detached worktree.

The representative chart marker was:

```text
HPA581_HEADLESS_APPKIT chart_ready title=蒼穹への翔歌 difficulty=Expert notes=2870 measures=156
```

The four disposable setup passes also reported coherent production state:

```text
HPA581_HEADLESS_APPKIT_PREP label=warmup  elapsed_ms=597.615957 notes=2870 layout_measures=156 beats=1793 prepared=true
HPA581_HEADLESS_APPKIT_PREP label=measure1 elapsed_ms=264.837027 notes=2870 layout_measures=156 beats=1793 prepared=true
HPA581_HEADLESS_APPKIT_PREP label=measure2 elapsed_ms=781.142116 notes=2870 layout_measures=156 beats=1793 prepared=true
HPA581_HEADLESS_APPKIT_PREP label=measure3 elapsed_ms=261.922956 notes=2870 layout_measures=156 beats=1793 prepared=true
```

The AppKit trigger and the established ContentView hook overlapped after the
locked-session launch, so these elapsed values are recorded as setup markers
only. They are not used as a before/after readiness or wall-clock claim. In
particular, this run does not claim that moving preparation off-main shortened
selection-to-ready time.

## Time Profiler evidence

The current-code hooked Release app was built in a second unique profile-only
DerivedData path and launched from:

```text
/private/tmp/VirgoHPA581Task8BHeadlessAppKit-20260814.app/Contents/MacOS/Virgo
```

The trace was attached before the delayed setup began:

```bash
xcrun xctrace record --template 'Time Profiler' --time-limit 60s \
  --no-prompt \
  --output /private/tmp/hpa581-task8b-headless-appkit-20260814.trace \
  --attach 26384
```

Trace identity from the exported TOC:

```text
process: Virgo, PID 26384, termination reason exit(0)
binary: /private/tmp/VirgoHPA581Task8BHeadlessAppKit-20260814.app/Contents/MacOS/Virgo
trace template: Time Profiler
start: 2026-08-14T10:50:48.023-07:00
end:   2026-08-14T10:51:48.946-07:00
duration: 60.923451 s
end reason: Time limit reached
```

The temporary copied executable was ad-hoc signed after changing only its
bundle identity. Its pre-copy source-hook Release executable hash was
`75900ddd6d46edd17fe547a4928efb4453041e3a524fa7d244a2e06dc4b2752a`; the
copied/signed executable hash was
`da95510d4722f4d79e1d4487b81bd4f4de5ac87b3118c1ff30122323a78cdc0a`.

The exported table identified the main thread as profile thread id `2`
(`tid=94925758`). Bounded XPath queries over the exported time-profile table
gave these named-frame counts:

```text
symbol                                      main thread   all threads
NotationLayoutEngine.layout                       0             2
GameplayViewModel.computeCachedLayoutData         0             0
GameplayViewModel.setupGameplay                   4             4
GameplayViewModel.computeDrumBeats                1             1
GameplayViewModel.prepareTimelineNotation         1             1
GameplayViewModel.updateTimelineContinuousVisuals 5             5
GameplayViewModel.updatePurpleBarPosition         1             1
GameplayView.body.getter                         18            18
GameplayView.sheetMusicView                      14            14
```

Both `NotationLayoutEngine.layout` matches were symbolicated on background
thread `492`, through `GameplayNotationPreparer.prepare`. A representative
stack was:

```text
Hasher._combine
specialized Dictionary.subscript.getter
specialized NotationLayoutEngine.buildNoteHeads(...)
NotationLayoutEngine.layout(input:)                         [NotationLayoutEngine.swift:25]
static GameplayNotationPreparer.prepare(_:)                  [GameplayNotationPreparation.swift]
```

The main-thread setup sample showed the remaining intentionally synchronous
work:

```text
GameplayViewModel.computeDrumBeats()                          [GameplayViewModel+Computations.swift:156]
GameplayViewModel.setupGameplay(loadPersistedSpeed:)          [GameplayViewModel.swift:475]
specialized VirgoApp.runHPA581HeadlessProfile(in:)
```

The source at the measured candidate confirms that `setupGameplay()` computes
drum beats and the non-notation caches on the main actor, then awaits
`prepareTimelineNotation()`. That method invokes
`Task.detached { GameplayNotationPreparer.prepare(request) }`; the prepared
state contains both the notation layout and `beatPositionsByID`. The trace's
zero main-thread layout count and two background layout samples therefore
confirm the shipped worker-path handoff. The trace does not establish a
compositor-inclusive mount time.

The same trace sampled active production visual-update and SwiftUI paths on the
main thread (`updateTimelineContinuousVisuals`, `updatePurpleBarPosition`,
`GameplayView.body.getter`, and `GameplayView.sheetMusicView`). Because the
display was shielded, those samples are CPU call-path evidence only; they are
not proof that pixels were presented or that scrolling looked correct.

## Gate and limitations

`GATE: BLOCKED` for the final interactive evidence. The current Release worker
path is evidenced as having removed timeline layout/beat-position preparation
from the main-thread preparation slice, but the locked/shielded GUI prevents
the required mount, static-body, playback, auto-scroll, and real-width gates.
No synthetic/headless width result is used to authorize width work. Repeat this
handoff in a genuinely unlocked, non-shielded macOS GUI session before making
any width or HPA-584 mount decision.

## Cleanup and verification

All temporary source hooks were confined to the detached worktree and removed
with it. The following were removed after recording their identities:

- uniquely bundled GUI/headless app copies;
- both profile-only DerivedData trees and SPM clones;
- GUI capture, Time Profiler bundle, TOC, XML export, and app log;
- detached headless worktree;
- generated `default.profraw`.

An exact-process check after cleanup found no `VirgoHPA581Task8B*`,
`hpa581-task8b-headless`, or `xctrace record` process. The report worktree has
no source/test/instrumentation changes; `git diff --check` passes.
