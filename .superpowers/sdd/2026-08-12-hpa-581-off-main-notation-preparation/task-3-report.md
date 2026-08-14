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
