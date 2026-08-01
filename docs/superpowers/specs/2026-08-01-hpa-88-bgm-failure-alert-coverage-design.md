# HPA-88: BGM Failure Alert UI Coverage

**Date:** 2026-08-01  
**Status:** Revised design — pending review

## Context

`GameplayViewModel.setupBGMPlayer()` already stores a user-facing message in
`bgmLoadingError` when `AVAudioPlayer` cannot load a configured BGM file. The
current `GameplayView` also presents a `Background Music Unavailable` alert
when that property is non-nil, and explains that gameplay continues with the
metronome only.

The existing tests cover the ViewModel state transition for an invalid BGM
path and the no-BGM-path early return, but do not verify that the actual
SwiftUI alert is presented with the failure and fallback messages. HPA-88's
remaining gap is therefore visible-state coverage, not a production behavior
change.

The launch-argument constants are also covered by `LaunchArgumentsTests` in
`VirgoTests/LoggerTests.swift`; adding a new test-only flag requires extending
that value, uniqueness, dash-prefix, and non-empty coverage.

The unit render harness is not suitable for this acceptance check. It mounts a
bare `NSHostingView` without a visible `NSWindow`, and its text walker only
descends from that mounted hierarchy. A macOS SwiftUI `.alert` is presented
outside that hierarchy, so the render harness cannot prove alert presentation
or button dismissal. The existing no-visible-windows test makes adding hidden
window infrastructure to that harness the wrong direction.

The production setup path is also deterministic for this test: `setupGameplay()`
has one production caller in `GameplayView.prepareGameplay()`, and that caller
does not mark the ViewModel prepared until `setupGameplay()` returns. Therefore
the injected error is set before `gameplayRoot` can mount, with only the alert's
native accessibility presentation remaining asynchronous.

## Goal

Prove that the real app presents the user-facing BGM failure alert, including
the error text, the metronome-only fallback text, and the dismiss action.

## Non-goals

- Do not change `GameplayView`'s existing alert behavior or copy.
- Do not remove `bgmLoadingError` or its logging.
- Do not add a toast/banner or change playback behavior.
- Do not mutate or corrupt a persisted song's BGM path as part of the test.
- Do not add alert-window enumeration to `SwiftUITestUtilities`.

## Design

Use a real macOS XCUITest so the assertion observes the app's accessibility
hierarchy after SwiftUI presents the alert. The test will use a narrowly scoped
launch-argument seam instead of changing persisted fixture data.

### Test-only failure injection

Add `LaunchArguments.uiTestingBGMFailure` with the value
`-UITestingBGMFailure`. `setupBGMPlayer()` will recognize the seam only when
both `-UITesting` and `-UITestingBGMFailure` are present. After the existing
timing-fatal guard, it will call a small pure helper
`GameplayViewModel.shouldInjectBGMFailure(arguments:)`. The call site is
compiled only in Debug builds, while the pure helper remains always compiled
for unconditional unit coverage. When the Debug-only gate fires, it will set
the deterministic message, log the same reason format as the real failure
path, leave `bgmPlayer` nil, and return before the normal song-path guard:

```swift
#if DEBUG
if Self.shouldInjectBGMFailure(arguments: ProcessInfo.processInfo.arguments) {
    let reason = "UI test injected failure"
    bgmLoadingError = "Failed to load BGM: \(reason)"
    Logger.error("Failed to setup BGM player: \(reason)")
    bgmPlayer = nil
    return
}
#endif
```

The helper is internal so a unit test can prove the dual-flag contract without
trying to override `ProcessInfo.processInfo.arguments` in the test process.

This precedence is intentional: the existing UI-test sample songs have no
recorded BGM path, so the seam must simulate a configured-load failure without
turning ordinary metronome-only tracks into errors. Normal launches and normal
`-UITesting` launches remain unchanged.

The UI test will assert the stable sentinel substring `UI test injected failure`
instead of duplicating the complete app message across targets. It will also
assert the independent fallback substring `Playing with the metronome only.`.

Add focused unit coverage in `GameplayViewModelPlaybackBGMCoverageTests.swift`
for the pure helper: both flags return `true`, while either flag alone and an
empty argument list return `false`. Update `LaunchArgumentsTests` for the new
constant's exact value, uniqueness, dash prefix, and non-empty invariant.

### Accessibility discovery gate

The final test must not assume that macOS exposes this SwiftUI presentation as
`app.alerts[...]`. The first focused UI run is an explicit discovery spike:

1. Launch with the three test arguments and navigate to the fixture with the
   normal `openGameplay(in:)` helper.
2. Wait for `gameplayRoot`, then capture `app.debugDescription` if the
   presentation is not immediately discoverable.
3. Inspect whether the presentation is exposed as an alert, sheet, dialog, or
   another window-attached element. Use the observed stable element type and
   title in the permanent assertion; remove the diagnostic dump after the
   element shape is known.

The rest of the test refers to this result as the `presentedAlert` element and
does not make the acceptance criteria depend on a specific XCUITest container
type. The discovery run is required before committing the final query shape,
because this repository has no existing macOS `.alert` query precedent.

### UI test flow

Add a dedicated `GameplayBGMFailureUITests` macOS UI-test class, using the
existing setup/activation helpers, with these launch arguments:

- `-UITesting`
- `-ResetState`
- `-UITestingBGMFailure`

The test will open the existing `Thunder Beat` / `Rock Masters` / `Easy`
fixture with the existing `openGameplay(in:)` helper unchanged. Its final
play/pause lookup checks existence only; it does not tap or require hittability,
so no new navigation-helper parameter is needed. If the discovery run proves
that the modal prunes the parent window's accessibility tree, that finding must
be documented before introducing a narrowly scoped helper change.

Once gameplay is mounted, the test will:

1. Resolve the discovered `presentedAlert` element and wait for it with
   `waitForExistence(timeout:)`.
2. Assert it contains `UI test injected failure` and
   `Playing with the metronome only.` using case-insensitive `label`/`value`
   substring predicates. The alert message is one concatenated `Text`, so exact
   element-string matching would be incorrect.
3. Resolve the discovered `OK` button, wait for it, and tap it.
4. Assert the presented element disappears with the existing
   `waitForNonExistence` helper and the gameplay root remains mounted.

The UI test's `-ResetState` and normal fixture seeding use the existing test
startup path; the new failure seam does not edit a persisted `Song` or
`bgmFilePath`.

Existing ViewModel tests remain the coverage for the real invalid-path failure
and no-BGM branch. The new UI test owns only the end-to-end presentation and
dismissal contract. Existing normal `-UITesting` gameplay tests remain the
negative path: they launch without `-UITestingBGMFailure` and successfully
exercise gameplay controls, which would be blocked by a stray modal.

Because the project uses `PBXFileSystemSynchronizedRootGroup` for the
`VirgoUITests` target, adding `GameplayBGMFailureUITests.swift` under
`VirgoUITests/` requires no manual `project.pbxproj` edit.

## Acceptance criteria

- A real app launch with the failure-injection argument presents the
  `Background Music Unavailable` alert element after gameplay mounts.
- The injection helper returns `true` only when both `-UITesting` and
  `-UITestingBGMFailure` are present; either flag alone does not activate it.
- The failure-injection call site is absent from Release builds; the pure gate
  helper remains unit-testable in every build configuration.
- `LaunchArgumentsTests` covers the new flag's value, uniqueness, dash prefix,
  and non-empty invariant.
- The visible alert contains the injected error message.
- The visible alert tells the user that playback continues with the metronome
  only.
- The visible alert exposes an `OK` dismissal action that removes the alert.
- The gameplay root remains mounted after dismissal.
- No user-facing production behavior changes are required; the launch
  argument and its guarded handling are narrowly scoped test seams.
- The diff contains only the launch constant and guarded BGM seam, its pure
  unit coverage, the updated launch-argument tests, and the dedicated UI test
  class.
- The focused UI test and the full macOS unit-test suite pass with parallel
  testing disabled.

## Verification

Run the focused `VirgoUITests/GameplayBGMFailureUITests` case on macOS first
with `-parallel-testing-enabled NO`, including the accessibility discovery
spike before finalizing its query shape. Then run the full `VirgoTests` macOS
suite using the repository's required non-parallel `xcodebuild test` command.
Review the final diff to confirm the implementation contains only the guarded
launch seam, pure/unit coverage, launch-argument updates, and the dedicated UI
test class. CI already runs the full macOS UI-test target in Debug through
`.github/workflows/ui-tests.yml`; the local gate does not need to repeat the
entire UI suite before review.
