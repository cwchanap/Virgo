# HPA-581 Task 3 Report — static-isolation Release evidence gate

## Outcome

`GATE: BLOCKED`.

The Release Time Profiler attach and symbolication path was proven, but the
representative Soukyuu chart could not be selected or interacted with on this
host. The macOS GUI session is covered by a `Window Server — Display 1 Shield`
and the Release app's window is not exposed through Accessibility. The focused
Release UI test also fails before the test runner launches because the test
target cannot resolve the `Virgo` Swift module. No Task 3 performance numbers
are reported or inferred.

This is not a `NARROW`, `CLOSE`, or `PROCEED` decision. The HPA-581 gate must be
re-run on a usable GUI session with the real chart before Phase C/D is started.

## Scope and representative chart

- Worktree: `/Users/chanwaichan/workspace/Virgo/.worktrees/hpa-581-off-main-notation`
- HEAD: `b96addd4fbf5337f6bf834fdb706e90cb94798c3`
- Target: macOS Release, same host/configuration as HPA-579 when practical
- Chart contract: shipped `soukyuu_e_no_shouka` MASTER / Expert,
  `Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx`, 2,870 notes, 156 measures,
  900 pt baseline row width
- HPA-579 reference values (not re-measured here): 267.857 ms median
  selection-to-prepared and 4,890.729 ms initial production mount

## Environment evidence

Commands:

```text
git rev-parse HEAD
sw_vers
system_profiler SPHardwareDataType | egrep 'Model Name|Model Identifier|Chip|Memory'
xcodebuild -version
xcrun xctrace version
```

Observed:

```text
b96addd4fbf5337f6bf834fdb706e90cb94798c3
ProductName: macOS
ProductVersion: 26.5.2
BuildVersion: 25F84
Model Name: MacBook Pro
Model Identifier: MacBookPro18,3
Chip: Apple M1 Pro
Memory: 32 GB
Xcode 26.6
Build version 17F113
xctrace version 16.0 (17F113)
```

## Release build/profile setup

The compile check was run outside the worktree's DerivedData so no build
artifacts enter git:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/hpa581-task3-derived build
```

The first sandboxed attempt could not resolve Apollo (`Could not resolve
package dependencies`, `Could not resolve host: github.com`). The same command
with the approved network permission resolved Apollo 1.25.6 and ended with:

```text
** BUILD SUCCEEDED **
```

This is only a compile check. It is not runtime profiling evidence.

## Instruments / symbolication evidence

### Rejected launch attempt

The first automatic launch capture was:

```bash
xcrun xctrace record --template 'Time Profiler' --time-limit 45s \
  --no-prompt --output /private/tmp/hpa581-task3-launch.trace \
  --launch -- /private/tmp/hpa581-task3-derived/Build/Products/Release/Virgo.app/Contents/MacOS/Virgo \
  -ApplePersistenceIgnoreState YES -UITesting -ResetState
```

The trace completed, but its table of contents identified the profiled process
as the pre-existing Debug app at
`/Users/chanwaichan/Library/Developer/Xcode/DerivedData/Virgo-accemltpktxznudndledbprhevra/Build/Products/Debug/Virgo.app`.
It was rejected and contributes no Task 3 evidence.

### Valid Release attach-only capture

To avoid the existing `cwchanap.Virgo` bundle-ID collision, I copied the same
Release app to `/private/tmp/VirgoHPA581.app`, changed only the temporary copy's
bundle identifier/name, and ad-hoc signed that copy. No repository source or
project file was changed. The copy launched with a real CoreGraphics window
(window ID `121045`) and was attached directly:

```bash
xcrun xctrace record --template 'Time Profiler' --time-limit 15s \
  --no-prompt --output /private/tmp/hpa581-task3-release-attach.trace \
  --attach 2558
xcrun xctrace export --input /private/tmp/hpa581-task3-release-attach.trace --toc
xcrun xctrace export --input /private/tmp/hpa581-task3-release-attach.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  --output /private/tmp/hpa581-task3-release-attach-time-profile.xml
```

The trace table of contents reports:

```text
template-name: Time Profiler
duration: 15.936860
process: Virgo, pid 2558, path /private/tmp/VirgoHPA581.app/Contents/MacOS/Virgo
```

The exported sample table contains a symbolicated Virgo source frame:

```text
static VirgoApp.$main()
binary: Virgo
path: /private/tmp/VirgoHPA581.app/Contents/MacOS/Virgo
```

This proves the Release Time Profiler attach/symbolication setup. It is an
idle/startup capture only; it contains no selected chart, `GameplayView`,
`cacheNotationLayout`, `cacheBeatPositions`, or playback interaction and is
therefore not a Task 3 measurement.

## Runtime and interaction observations

The temporary Release copy's window was assigned to Space 1. After a read-only
active-Space check (`active=13600`), switching to that known Space made the
window CoreGraphics-onscreen (`onscreen: 1`), but Accessibility still returned:

```text
2558, false, true, 0,
```

(`unix id`, `frontmost`, `visible`, `window count`). The app's Window menu was
enumerable and contained `VirgoHPA581`, but its AX window count remained zero.
The current onscreen window stack also contained:

```text
Window Server — Display 1 Shield (layer 2147483646)
```

The screen capture was black and no chart-selection surface was available.
Consequently, the following required observations were not achievable:

- chart selection → `isGameplayPrepared == true`;
- main-thread samples in timeline notation layout / beat-position preparation;
- initial production `GameplayView` mount versus 4,890.729 ms;
- playback/static-sheet body activity after static isolation;
- production auto-scroll correctness.

No timing, sample count, mount, playback, or scroll metric is fabricated from
the idle attach trace.

## Focused Release UI-test attempt

The existing UI test was attempted as a real chart-driving fallback:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -configuration Release \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -derivedDataPath /private/tmp/hpa581-ui-derived \
  -only-testing:VirgoUITests/GameplayViewUITests/testGameplayOpensImportedSoukyuuFixture test
```

Build/test setup reached the Release app and generated a dSYM, but the test
target failed before launching the UI runner:

```text
Unable to resolve Swift module dependency to a compatible module: 'Virgo'
@testable import Virgo
Testing cancelled because the build failed.
** TEST FAILED **
```

This is a test-runner/build blocker, not evidence about runtime notation cost.

## Gate decision

`GATE: BLOCKED` — authoritative Release profiling infrastructure is partially
validated (Release compile, Time Profiler attach, and symbolicated Virgo frame),
but the real representative chart interaction and required post-static-isolation
observations cannot be performed while the GUI session is shielded and AX is
unavailable. The HPA-579 267.857 ms baseline remains historical context only;
this report does not claim that Phase A changed or preserved that cost.

Do not start HPA-581 Phase C/D or HPA-584 from this report. Re-run Task 3 on an
unlocked/usable macOS GUI session, confirm the trace is the current Release
binary, then collect chart-selection, preparation stacks, mount, playback, and
auto-scroll evidence before deciding `PROCEED`, `NARROW`, or `CLOSE`.

## Cleanup and repository state

- No production, test, project, or instrumentation source files were changed.
- Temporary profiling apps, traces, XML exports, screenshots, and DerivedData
  were kept under `/private/tmp` and are not part of the worktree.
- The temporary app process was terminated after the attach capture.
- The original `cwchanap.Virgo` store was not deliberately reset or deleted by
  Task 3; the temporary uniquely bundled copy used its own bundle identifier.

Final cleanup verification (2026-08-13):

- Removed the exact Task 3 temporary paths under `/private/tmp`: both rejected
  and valid trace directories, Release/UI DerivedData directories, the uniquely
  bundled app, XML/log exports, PID/stdout files, screenshots, and build log.
- A privileged process check found no remaining `hpa581`, `VirgoHPA581`, or
  `xctrace record` process (the check command itself was excluded).
- `git diff --check` passed. `git status --short --branch` showed no source,
  test, project, trace, DerivedData, or marker changes; only this report was
  pending before the documentation commit.

## Retry after GUI restoration attempt

### Environment and Release setup

The retry ran on 2026-08-13 from the same isolated worktree:

```text
worktree: /Users/chanwaichan/workspace/Virgo/.worktrees/hpa-581-off-main-notation
HEAD: a381df1c1fedc24e04b3891c59650c1e961b4459
macOS: 26.5.2 (25F84)
hardware: MacBook Pro18,3, Apple M1 Pro, 32 GB
Xcode: 26.6 (17F113)
xctrace: 16.0 (17F113)
```

The disposable Release build was run outside the worktree:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/hpa581-task3-retry-derived-2 build
```

It completed with exit code 0 and produced the current Release binary and
dSYM. A uniquely bundled, ad-hoc-signed copy was launched so the normal
`cwchanap.Virgo` store was not touched:

```text
/private/tmp/VirgoHPA581Retry.app
bundle identifier: com.cwchanap.Virgo.HPA581Retry
launch arguments: -ApplePersistenceIgnoreState YES -UITesting
```

`-ResetState` was not used. The app process was PID 52020. CoreGraphics
reported its Virgo window as window 121730 with 900 x 450 bounds, but the
window was assigned to another Space and was not exposed on the active Space
for interaction.

### Release attach and symbolication

A bounded attach-only Time Profiler capture was completed:

```bash
xcrun xctrace record --template 'Time Profiler' --time-limit 15s \
  --no-prompt --output /private/tmp/hpa581-task3-retry-idle.trace \
  --attach 52020
xcrun xctrace export --input /private/tmp/hpa581-task3-retry-idle.trace --toc
xcrun xctrace export --input /private/tmp/hpa581-task3-retry-idle.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  --output /private/tmp/hpa581-task3-retry-idle-time-profile.xml
```

The trace TOC identified the attached process as:

```text
process: Virgo, pid 52020
path: /private/tmp/VirgoHPA581Retry.app/Contents/MacOS/Virgo
template: Time Profiler
duration: 15.919036 seconds
trace interval: 2026-08-13T23:54:31.605-07:00 to 2026-08-13T23:54:47.524-07:00
```

The exported samples were symbolicated, including:

```text
static VirgoApp.$main()
source: Virgo/VirgoApp.swift
```

The idle trace also contained SwiftUI/AttributeGraph and AppKit frames, but
no `GameplayView`, `cacheNotationLayout`, or `cacheBeatPositions` frames. It
therefore proves only that the current Release attach/symbolication path
works; it is not representative chart-interaction evidence.

### Interaction blocker and required observations

The desktop initially rendered normally, but the bounded recovery attempt
ended with this exact login-session state:

```text
CGSessionScreenIsLocked = 1
```

CoreGraphics then reported the active onscreen stack contained:

```text
Window Server — Display 1 Shield (layer 2147483646)
```

Accessibility could not enumerate a Virgo window while that shield was
present. No authentication or broad Space-management workaround was
attempted. Consequently, the representative `soukyuu_e_no_shouka` MASTER /
Expert chart was not selected, and the following required observations remain
unavailable for this retry:

- selection -> `isGameplayPrepared == true`;
- main-thread samples in timeline notation layout or beat-position preparation;
- initial production `GameplayView` mount versus 4,890.729 ms;
- playback/static-sheet body behavior after static isolation;
- production auto-scroll correctness.

No timing, sample count, mount, playback, or scroll metric is inferred from
the idle attach trace. HPA-579's historical 267.857 ms preparation and
4,890.729 ms mount values remain context only.

### Gate and cleanup

`GATE: BLOCKED` — the Release build, attach, and symbolication path succeeded,
but the locked GUI/Display 1 Shield/AX failure prevented the real chart
interaction and every required post-static-isolation observation. This retry,
like the earlier setup trace, does not authorize HPA-581 Phase C/D or HPA-584.
No `PROCEED`, `NARROW`, or `CLOSE` decision is made from unavailable evidence.

The isolated app was quit after the bounded capture. The exact temporary
Release app, traces, XML export, screenshots, and both retry DerivedData
directories under `/private/tmp` were removed. A final process check found no
`VirgoHPA581`, `hpa581-task3`, or `xctrace record` process. No production,
test, project, or instrumentation files were changed.

## Headless retry after compositor root-cause analysis

This retry was an evidence-gate recovery only. It did not begin HPA-581 Phase
C/D or HPA-584 work. The source checkout was at base `6a56a075061afbf9815186b828fce955ffe2f75e`
in the isolated worktree:

```text
/Users/chanwaichan/workspace/Virgo/.worktrees/hpa-581-off-main-notation
```

### Isolated Release run and commands

The machine/configuration was macOS 26.5.2 (25F84), MacBookPro18,3 with an
Apple M1 Pro and 32 GB RAM, Xcode 26.6 (17F113), and xctrace 16.0 (17F113).
The optimized Release binary was built outside the worktree:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/hpa581-task3-headless-derived build
```

The resulting app was copied to a disposable bundle and given a unique
identity before launch:

```bash
ditto /private/tmp/hpa581-task3-headless-derived/Build/Products/Release/Virgo.app \
  /private/tmp/VirgoHPA581HeadlessRetry.app
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.cwchanap.Virgo.HPA581HeadlessRetry' \
  -c 'Set :CFBundleName VirgoHPA581HeadlessRetry' \
  /private/tmp/VirgoHPA581HeadlessRetry.app/Contents/Info.plist
codesign --force --deep --sign - --timestamp=none \
  /private/tmp/VirgoHPA581HeadlessRetry.app
/private/tmp/VirgoHPA581HeadlessRetry.app/Contents/MacOS/Virgo \
  -ApplePersistenceIgnoreState YES -HPA581HeadlessProfile
```

The temporary launch-argument-only hook waited eight seconds before doing
profile work, then used the normal `ContentView` fixture seeding/import path,
the real bundled `soukyuu_e_no_shouka` MASTER/Expert chart, a fresh in-memory
score persistence service, `rowWidth = 900`, `loadChartData()`, and
`setupGameplay()`. The unique bundle identifier and
`ApplePersistenceIgnoreState` kept the default Virgo store out of scope.

Time Profiler was attached to the exact running Release PID before the delayed
work began:

```bash
xcrun xctrace record --template 'Time Profiler' --time-limit 60s \
  --no-prompt --output /private/tmp/hpa581-task3-headless.trace \
  --attach 61764
xcrun xctrace export --input /private/tmp/hpa581-task3-headless.trace \
  --toc --output /private/tmp/hpa581-task3-headless-toc.xml
xcrun xctrace export --input /private/tmp/hpa581-task3-headless.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  --output /private/tmp/hpa581-task3-headless-time-profile.xml
```

The TOC identifies the attached process and binary unambiguously:

```text
process: Virgo, pid 61764, termination-reason exit(0)
binary: /private/tmp/VirgoHPA581HeadlessRetry.app/Contents/MacOS/Virgo
template: Time Profiler
start: 2026-08-14T08:47:49.385-07:00
end:   2026-08-14T08:48:50.318-07:00
duration: 60.932883 s
```

### Production chart and timing markers

The run emitted these production-path markers before the trace was cleaned:

```text
HPA581_HEADLESS chart_ready title=蒼穹への翔歌 difficulty=Expert notes=2870 measures=156
HPA581_HEADLESS_PREP label=warmup elapsed_ms=341.586947 notes=2870 layout_measures=156 beats=1793 prepared=true
HPA581_HEADLESS_PREP label=measure1 elapsed_ms=256.924987 notes=2870 layout_measures=156 beats=1793 prepared=true
HPA581_HEADLESS_PREP label=measure2 elapsed_ms=257.725000 notes=2870 layout_measures=156 beats=1793 prepared=true
HPA581_HEADLESS_PREP label=measure3 elapsed_ms=255.030990 notes=2870 layout_measures=156 beats=1793 prepared=true
HPA581_HEADLESS_GAMEPLAY_SELECTION timestamp=808415275.257359 row_width=900
HPA581_HEADLESS_GAMEPLAY_PREP_START timestamp=808415275.331224
HPA581_HEADLESS_GAMEPLAY_PREP_READY timestamp=808415275.591222 notes=2870 layout_measures=156 rows=156 beats=1793 prepared=true
HPA581_HEADLESS_PLAYBACK_STARTED timestamp=808415275.629507 playing=true
```

The three measured preparation entries were 256.924987 ms, 257.725000 ms,
and 255.030990 ms: median **256.924987 ms**, range **255.030990–257.725000
ms**. The actual `GameplayView` selection-to-prepared marker delta was
**333.863 ms**; the prep-start-to-prepared portion was **259.998 ms**. These
are headless lifecycle/prod-preparation measurements, not a claim of visible
compositor mount latency.

The source hook also emitted two static-body markers immediately after
preparation (`808415275.692129` and `808415276.239355`) and auto-scroll
callbacks for rows **1 through 48**. The first and last callback timestamps
were `808415277.135993` and `808415345.286026`.

### Targeted Time Profiler evidence

The exported time-profile table identifies the main thread as thread ID
`101`. The bounded XPath query used for the evidence was of this form (with
one symbol at a time):

```bash
xmllint --xpath \
  "count(//row[(thread/@id='101' or thread/@ref='101') and \
  .//frame[contains(@name, 'SYMBOL')]])" \
  /private/tmp/hpa581-task3-headless-time-profile.xml
```

Explicit named-frame matches on the main thread were: `NotationLayoutEngine.layout`
2 rows, `GameplayViewModel.computeCachedLayoutData` 2, `setupGameplay` 3,
`updateTimelineContinuousVisuals` 6, `updatePurpleBarPosition` 1,
`GameplayView.body.getter` 23, and `GameplayView.sheetMusicView` 12. These
are named-frame row matches, not CPU percentages; repeated frame references
are not counted as additional definitions.

Representative symbolicated stacks from the attached Release binary were:

```text
00:04.982.729  Main Thread
  specialized NotationLayoutEngine.buildNoteHeads(...)
  NotationLayoutEngine.layout(input:)                                  [NotationLayoutEngine.swift:25]
  GameplayViewModel.computeCachedLayoutData()                          [GameplayViewModel.swift:250]
  GameplayViewModel.setupGameplay(loadPersistedSpeed:)                 [GameplayViewModel.swift:448]
  ContentView.runHPA581HeadlessProfile()                               [ContentView.swift:316]

00:04.976.728  Main Thread
  GameplayViewModel.computeDrumBeats()                                  [GameplayViewModel+Computations.swift:156]
  GameplayViewModel.setupGameplay(loadPersistedSpeed:)                 [GameplayViewModel.swift:448]
  ContentView.runHPA581HeadlessProfile()                               [ContentView.swift:318]

00:07.826.729  Main Thread
  ObservationRegistrar.withMutation(...)
  GameplayViewModel.updateTimelineContinuousVisuals(elapsedTime:track:) [GameplayViewModel+VisualUpdates.swift:73]
  GameplayViewModel.startVisualTickTimer()                              [GameplayViewModel+VisualUpdates.swift:22-23]

00:18.365.728  Main Thread
  GameplayViewModel.calculateTimelinePurpleBarPosition(elapsedTime:)    [GameplayViewModel+VisualUpdates.swift:254]
  GameplayViewModel.calculatePurpleBarPosition(elapsedTime:)            [GameplayViewModel+VisualUpdates.swift:207]
  GameplayViewModel.updatePurpleBarPosition(elapsedTime:)               [GameplayViewModel+VisualUpdates.swift:160]

00:05.875.729  Main Thread
  GameplayView.body.getter
  SwiftUI AttributeGraph layout/update frames

00:07.750.729  Main Thread
  ScrollViewProxy.scrollTo(...)
  GameplayView.sheetMusicView(geometry:)                                [GameplayView.swift:89-90]
```

The notation-layout stack is the real timeline preparation path after Phase A;
the playback stacks show active visual ticks rather than an idle attach. The
trace also sampled the production SwiftUI body and scroll callback path while
playback was running.

### Limitations and gate

The compositor remained unavailable during this headless retry: the prior
root-cause state was `CGSessionScreenIsLocked` with the Display 1 Shield, so
there was no inspectable rendered chart surface. The following distinctions
are intentional:

- The `GameplayView` lifecycle hook proves the real selection/import/preparation
  path ran, but the **initial visible production mount versus 4,890.729 ms is
  unavailable**. The 333.863 ms marker is not a replacement for that
  compositor-inclusive comparison.
- The two static-body markers and absence of further markers during the
  captured playback interval are source-hook evidence only. They do not prove
  pixels were painted or that every SwiftUI static-body evaluation was
  observed under the shield.
- Rows 1–48 prove the production auto-scroll callback path advanced. The
  actual on-screen `ScrollView` position and visual auto-scroll correctness
  remain unavailable.
- Playback is proven by `playing=true`, advancing row callbacks, and the
  symbolicated visual-update/SwiftUI stacks. No claim is made about audible
  output or compositor presentation.

`GATE: PROCEED` — after static isolation, the current optimized Release trace
still samples the real timeline notation layout and beat preparation on the
main actor, and the measured preparation remains materially expensive at about
**257 ms median** (with the actual headless gameplay preparation taking 333.863
ms from selection). Freeing roughly the historical **268 ms** of main-actor
CPU would improve loading/window/dismiss responsiveness; it does **not** promise
a shorter selection-to-ready wall-clock time because readiness still requires
the layout work. No Phase C/D implementation or HPA-584 work was started here.

### Reversion, cleanup, and repository verification

The saved temporary patch was first checked and applied in reverse:

```bash
git apply --reverse --check /private/tmp/hpa581-task3-headless-source.patch
git apply --reverse /private/tmp/hpa581-task3-headless-source.patch
```

The four temporary source files were restored exactly. A marker search found no
`HPA581_HEADLESS` or `HPA581HeadlessProfile` references. The isolated app,
trace, XML exports, app log, DerivedData, GUI-check screenshot, source patch,
and the generated `default.profraw` were removed from their explicit paths
under `/private/tmp`/the worktree. A privileged process check returned no
`VirgoHPA581HeadlessRetry`, `hpa581-task3-headless`, or `xctrace record`
process. `git diff --check` passed; no post-revert build was run because this
bounded handoff explicitly prohibited a new build and the source reversion plus
marker/status checks proved instrumentation did not persist.
