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

The unit render harness is not suitable for this acceptance check. It mounts a
bare `NSHostingView` without a visible `NSWindow`, and its text walker only
descends from that mounted hierarchy. A macOS SwiftUI `.alert` is presented
outside that hierarchy, so the render harness cannot prove alert presentation
or button dismissal. The existing no-visible-windows test makes adding hidden
window infrastructure to that harness the wrong direction.

## Goal

Prove that a non-nil `bgmLoadingError` reaches the user-facing alert in the
real `GameplayView`, including the error text, the metronome-only fallback
text, and the dismiss action.

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
timing-fatal guard, it will set the deterministic message
`Failed to load BGM: UI test injected failure`, log the test-only fallback, and
return before the normal song-path guard.

This precedence is intentional: the existing UI-test sample songs have no
recorded BGM path, so the seam must simulate a configured-load failure without
turning ordinary metronome-only tracks into errors. Normal launches and normal
`-UITesting` launches remain unchanged.

### UI test flow

Add a dedicated macOS UI test, using the existing setup/activation helpers,
with these launch arguments:

- `-UITesting`
- `-ResetState`
- `-UITestingBGMFailure`

The test will open the existing `Thunder Beat` / `Rock Masters` / `Easy`
fixture. The shared gameplay-navigation helper will gain an optional way to
skip waiting for the playback button, because the modal alert should be
asserted before interacting with controls behind it.

Once gameplay is mounted, the test will:

1. Wait for `app.alerts["Background Music Unavailable"]`.
2. Assert the alert contains the injected error and
   `Playing with the metronome only.` using case-insensitive substring
   predicates. The alert message is one concatenated `Text`, so exact
   element-string matching would be incorrect.
3. Assert `app.alerts[...].buttons["OK"]` exists and tap it.
4. Assert the alert disappears and the gameplay root remains mounted.

The UI test's `-ResetState` and normal fixture seeding use the existing test
startup path; the new failure seam does not edit a persisted `Song` or
`bgmFilePath`.

Existing ViewModel tests remain the coverage for the real invalid-path failure
and no-BGM branch. The new UI test owns only the end-to-end presentation and
dismissal contract.

## Acceptance criteria

- A real app launch with the failure-injection argument reaches gameplay with
  non-nil `bgmLoadingError` and presents the `Background Music Unavailable`
  alert.
- The visible alert contains the injected error message.
- The visible alert tells the user that playback continues with the metronome
  only.
- The visible alert exposes an `OK` dismissal action that removes the alert.
- The gameplay root remains mounted after dismissal.
- No user-facing production behavior changes are required; the launch
  argument and its guarded handling are narrowly scoped test seams.
- The focused UI test and the full macOS unit-test suite pass with parallel
  testing disabled.

## Verification

Run the focused `VirgoUITests/GameplayBGMFailureUITests` case on macOS first,
then run the full `VirgoTests` macOS suite using the repository's required
non-parallel `xcodebuild test` command. Review the final diff to confirm the
implementation contains only the guarded launch seam, UI-test coverage, and
the minimal shared-navigation helper adjustment.
