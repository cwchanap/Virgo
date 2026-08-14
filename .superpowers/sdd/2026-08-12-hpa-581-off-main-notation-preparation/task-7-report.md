# HPA-581 Task 7 report: post-prepared width relayout gate

Date: 2026-08-14
Gate: **BLOCKED**
Source HEAD: `2a833dcacb7056cc5e35df68450e83d4f6e399e8`

## Scope and decision

Task 7 requires a real Release Virgo app, a representative chart, and a natural
host-window resize that changes notation row packing. The attempt could not
reach a usable host window because the active macOS GUI session was screen
locked and display-shielded. No chart selection, row-width change, packing
observation, or post-debounce Time Profiler sample was obtained. This is a
`BLOCKED` gate; no width-specific production change is authorized.

Headless geometry, test-only geometry, source hooks, and the synthetic 3,000 pt
probe were not used as substitutes.

## Release build identity

- Command: `xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Release -derivedDataPath ./DerivedData-HPA581-Task7 -clonedSourcePackagesDirPath /private/tmp/hpa581-task7-spm.DmVWIz CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build`
- Result: `** BUILD SUCCEEDED **`.
- App: `Virgo.app`, Release configuration, universal `arm64` + `x86_64` binary.
- Binary SHA-256: `e2f32f041f2b3db203908a66c9a10e470acb83af4e125557a78db9ad16804cb1`.
- Bundle identifier/version: `cwchanap.Virgo`, `1.0 (1)`.
- SDK/toolchain observed: Xcode 26.6 (`17F113`), macOS 26.5.2 (`25F84`), macOS SDK 26.5, `xctrace` 16.0.

The build required the elevated network fallback only to fetch the pinned
Apollo 1.25.6 package. The build output contained existing deprecation and
Sendable warnings but no build failure.

## Real host/window attempt

The app was launched from the exact Release product with:

```text
/usr/bin/open -n ./DerivedData-HPA581-Task7/Build/Products/Release/Virgo.app --args -UITesting
```

`-UITesting` was used only for non-destructive seed-if-needed startup behavior;
`-ResetState` and `-SkipSeed` were not used. The representative target would
have been `soukyuu_e_no_shouka` MASTER (`mas.dtx`, 2,870 notes, 156 measures),
but gameplay could not be reached.

Observed GUI state:

- Virgo process was running as PID 5123 from the Release product.
- Accessibility reported Virgo `frontmost=false` and `count of windows=0`.
- A desktop capture was entirely black.
- `ioreg` reported `CGSSessionScreenIsLocked=Yes` and a non-null
  `CGSSessionScreenLockedTime`.
- An activation attempt did not expose a window. The process sample showed the
  normal AppKit event loop (`NSApplication.run` / `nextEventMatchingMask`) and
  did not provide chart or packing evidence.

Therefore there were no real host window sizes to record, no natural resize
gesture or ordinary window-size transition could be performed, and row
packing is **not measurable** in this session. No Time Profiler trace was
started because the required packing-changing resize never occurred.

## Evidence hygiene and verification

- No production source, tests, instrumentation, generations, or resize
  scheduling were changed.
- The temporary Release process was stopped after the blocked attempt.
- Temporary DerivedData, the temporary Swift package clone, and the screenshot
  were removed.
- `git diff --check`: passed.
- The report is the only intended tracked change for Task 7; clean-worktree
  status will be verified after the report commit.

## Follow-up

Repeat this gate in an unlocked, non-shielded macOS GUI session. Only if an
ordinary resize genuinely changes row packing should a post-debounce Time
Profiler sample determine whether a width-specific implementation slice is
warranted.
