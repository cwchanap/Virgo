# HPA-88: BGM Failure Alert Coverage

**Date:** 2026-08-01  
**Status:** Approved design

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

## Goal

Prove that a non-nil `bgmLoadingError` reaches the user-facing alert in the
real `GameplayView`, including the error text, the metronome-only fallback
text, and the dismiss action.

## Non-goals

- Do not change `GameplayView`'s existing alert behavior or copy.
- Do not remove `bgmLoadingError` or its logging.
- Do not add a toast/banner or change playback behavior.
- Do not add a full app UI-test fixture that mutates persisted song data.

## Design

Add one serialized macOS Swift Testing case to
`VirgoTests/GameplayRenderCoverageTests.swift`, alongside the existing
populated gameplay render tests.

The test will:

1. Create a prepared ViewModel through
   `GameplayViewModelCoverageTestSupport.makePreparedViewModel()`.
2. Set `bgmLoadingError` to a deterministic test message before mounting the
   view.
3. Mount the real `GameplayView` through its `initialViewModel` injection seam
   and the existing `SwiftUITestUtilities` helpers.
4. Wait for render stabilization so the alert presentation has reached the
   AppKit window hierarchy.
5. Locate the visible macOS alert window titled `Background Music Unavailable`.
6. Inspect its rendered AppKit content with `SwiftUITestUtilities.renderedTexts`
   and assert the deterministic error, `Playing with the metronome only.`, and
   `OK` are present.
7. Close the alert and clean up the ViewModel so the serialized test does not
   leak an auxiliary window or audio resources.

The test suite is already marked `.serialized`, which prevents concurrent
alert-window tests from colliding. Existing ViewModel tests remain as the
coverage for the failure-producing and no-BGM branches; the new render test
owns only the presentation contract.

## Acceptance criteria

- A real `GameplayView` with non-nil `bgmLoadingError` presents the
  `Background Music Unavailable` alert.
- The visible alert contains the original error message.
- The visible alert tells the user that playback continues with the metronome
  only.
- The visible alert exposes its `OK` dismissal action.
- No production source changes are required unless the focused test reveals a
  real presentation defect.
- The focused test and the full macOS unit-test suite pass with parallel
  testing disabled.

## Verification

Run the focused `GameplayRenderCoverageTests` suite first, then run the full
`VirgoTests` macOS suite using the repository's required non-parallel
`xcodebuild test` command. Review the final diff to confirm the implementation
contains only the test coverage and any narrowly necessary test-support fix.
