# HPA-88 BGM Failure Alert Coverage Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Exercise the real macOS gameplay alert end to end when BGM setup fails, including its message, fallback copy, OK dismissal, and the repository's non-parallel UI-test CI policy.

**Architecture:** Add a pure, always-compiled dual-launch-argument predicate to GameplayViewModel, but compile the failure injection call site only for Debug builds. Drive the seam from a dedicated macOS XCUITest using the existing seeded Thunder Beat fixture, discover the native alert's actual accessibility element shape, then assert the observed presentation and dismissal contract.

**Tech Stack:** Swift 5.9, SwiftUI, @Observable GameplayViewModel, Swift Testing unit tests, XCTest/XCUITest macOS UI tests, xcodebuild, GitHub Actions.

## Global Constraints

- Preserve the existing GameplayView alert title, message copy, button, and playback behavior.
- The failure seam activates only when both -UITesting and -UITestingBGMFailure are present.
- Compile the failure injection call site only under #if DEBUG; keep the pure predicate available to unit tests in every configuration.
- Do not mutate persisted Song data or add BGM paths to UI-test fixtures.
- Keep the render harness windowless; do not add alert-window enumeration to SwiftUITestUtilities.
- Run focused and full local tests with -parallel-testing-enabled NO.
- Limit the final implementation diff to the launch constant, guarded seam, unit/launch-argument coverage, dedicated UI test, and the one-line UI workflow flag.

---

### Task 1: Write the failing launch-seam and argument tests

**Files:**
- Modify: VirgoTests/GameplayViewModelPlaybackBGMCoverageTests.swift near the existing setupBGMPlayer tests
- Modify: VirgoTests/LoggerTests.swift in LaunchArgumentsTests

**Interfaces:**
- Consumes: the intended GameplayViewModel.shouldInjectBGMFailure(arguments: [String]) -> Bool predicate and LaunchArguments.uiTestingBGMFailure constant.
- Produces: failing tests that define the dual-flag contract and require the exact launch-argument value in all existing invariants.

- [ ] Step 1: Add the predicate contract test before production code.

Add this Swift Testing case:

~~~swift
@Test("BGM failure injection requires both UI testing flags")
func shouldInjectBGMFailureRequiresBothFlags() {
    #expect(
        GameplayViewModel.shouldInjectBGMFailure(
            arguments: [LaunchArguments.uiTesting, LaunchArguments.uiTestingBGMFailure]
        )
    )
    #expect(!GameplayViewModel.shouldInjectBGMFailure(arguments: [LaunchArguments.uiTesting]))
    #expect(!GameplayViewModel.shouldInjectBGMFailure(arguments: [LaunchArguments.uiTestingBGMFailure]))
    #expect(!GameplayViewModel.shouldInjectBGMFailure(arguments: []))
}
~~~

- [ ] Step 2: Extend all LaunchArgumentsTests invariants.

Add #expect(LaunchArguments.uiTestingBGMFailure == "-UITestingBGMFailure") to the value test and include the new constant in the arrays/individual assertions used by uniqueness, dash-prefix, and non-empty tests.

- [ ] Step 3: Run the focused unit target and verify the expected RED state.

~~~bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/LaunchArgumentsTests \
  -only-testing:VirgoTests/GameplayViewModelPlaybackBGMCoverageTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
~~~

Expected result: compilation fails because the new constant and predicate do not exist yet.

- [ ] Step 4: Commit the red tests.

~~~bash
git add VirgoTests/GameplayViewModelPlaybackBGMCoverageTests.swift VirgoTests/LoggerTests.swift
git commit -m "test: specify HPA-88 BGM failure injection gate"
~~~

### Task 2: Implement the minimal Debug-only BGM failure seam

**Files:**
- Modify: Virgo/utilities/LaunchArguments.swift
- Modify: Virgo/viewmodels/GameplayViewModel+BGM.swift near setupBGMPlayer()

**Interfaces:**
- Consumes: the failing tests from Task 1.
- Produces: LaunchArguments.uiTestingBGMFailure and internal GameplayViewModel.shouldInjectBGMFailure(arguments: [String]) -> Bool.

- [ ] Step 1: Add the exact launch constant.

~~~swift
static let uiTestingBGMFailure = "-UITestingBGMFailure"
~~~

- [ ] Step 2: Add the pure dual-flag predicate inside the GameplayViewModel extension.

~~~swift
static func shouldInjectBGMFailure(arguments: [String]) -> Bool {
    arguments.contains(LaunchArguments.uiTesting)
        && arguments.contains(LaunchArguments.uiTestingBGMFailure)
}
~~~

- [ ] Step 3: Add the Debug-only injection immediately after the fatal-timing guard and before the song-path guard.

~~~swift
#if DEBUG
if Self.shouldInjectBGMFailure(arguments: ProcessInfo.processInfo.arguments) {
    let reason = "UI test injected failure"
    bgmLoadingError = "Failed to load BGM: \(reason)"
    Logger.error("Failed to setup BGM player: \(reason)")
    bgmPlayer = nil
    return
}
#endif
~~~

This preserves the real no-BGM early return, avoids double-prefixing the log reason, and cannot activate from a Release build.

- [ ] Step 4: Run the focused unit command from Task 1 and verify GREEN.

Expected result: LaunchArgumentsTests and GameplayViewModelPlaybackBGMCoverageTests pass with parallel testing disabled.

- [ ] Step 5: Commit the minimal seam.

~~~bash
git add Virgo/utilities/LaunchArguments.swift Virgo/viewmodels/GameplayViewModel+BGM.swift
git commit -m "feat: add Debug-only BGM failure test seam"
~~~

### Task 3: Discover and add the real macOS alert UI test

**Files:**
- Create: VirgoUITests/GameplayBGMFailureUITests.swift
- Do not modify VirgoUITests/UITestHelpers.swift unless discovery proves the modal removes the gameplay control hierarchy.
- Do not modify Virgo.xcodeproj/project.pbxproj; VirgoUITests is a file-system-synchronized group.

**Interfaces:**
- Consumes: the Debug-only launch seam and existing openGameplay(in:), requireGameplayRoot(in:), and waitForNonExistence(timeout:) helpers.
- Produces: one dedicated UI test proving the native presented alert contains both required substrings, dismisses, and leaves gameplay mounted.

- [ ] Step 1: Add the dedicated UI-test setup and discovery spike.

Match GameplayViewUITests setup/teardown, but append -UITesting, -ResetState, and -UITestingBGMFailure before launching. Start the test body with:

~~~swift
@MainActor
func testBGMFailurePresentationDiscovery() throws {
    try openGameplay(in: app)

    let snapshot = app.debugDescription
    print("BGM failure accessibility snapshot:\n\(snapshot)")

    let candidates = [
        app.alerts["Background Music Unavailable"],
        app.sheets["Background Music Unavailable"],
        app.dialogs["Background Music Unavailable"],
        app.windows["Background Music Unavailable"]
    ]
    XCTAssertTrue(
        candidates.contains(where: { $0.waitForExistence(timeout: 2) }),
        "Expected a presented BGM failure element. Snapshot: \(snapshot)"
    )
}
~~~

- [ ] Step 2: Run the discovery test with parallel testing disabled.

~~~bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoUITests/GameplayBGMFailureUITests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
~~~

Use the printed accessibility snapshot to identify the stable container type, title exposure, message descendants, and OK button. If the modal prunes the parent tree and makes openGameplay fail, make the smallest helper adjustment supported by that evidence; otherwise keep UITestHelpers.swift unchanged.

- [ ] Step 3: Replace the diagnostic spike with the permanent assertion.

Use the observed container query as presentedAlert. Query descendants with case-insensitive label/value predicates for the two independent substrings, because the production message is one concatenated Text value. Resolve the discovered OK button inside the presented element, tap it, wait for presentedAlert.waitForNonExistence(timeout: 5), and assert app.descendants(matching: .any)["gameplayRoot"].exists.

- [ ] Step 4: Run the permanent focused UI test.

Repeat the focused macOS UI command from Step 2. Expected result: the alert query, both substring assertions, OK tap, disappearance, and retained gameplay root pass.

- [ ] Step 5: Commit the UI test.

~~~bash
git add VirgoUITests/GameplayBGMFailureUITests.swift
git add VirgoUITests/UITestHelpers.swift
git commit -m "test: cover BGM failure alert in macOS UI"
~~~

Only include UITestHelpers.swift if the discovery evidence required a minimal hierarchy fix.

### Task 4: Align CI and run the verification gates

**Files:**
- Modify: .github/workflows/ui-tests.yml at the shared xcodebuild test-without-building command.

**Interfaces:**
- Consumes: the focused UI test from Task 3.
- Produces: a CI workflow that disables parallel testing for both the default full target and the optional TEST_TARGET focused path.

- [ ] Step 1: Add the CI flag.

Insert this argument into the shared workflow command:

~~~yaml
            -parallel-testing-enabled NO \
~~~

Keep TEST_TARGET, the macOS destination, and Debug configuration unchanged.

- [ ] Step 2: Run the full macOS unit suite non-parallel.

~~~bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES -destination-timeout 300 \
  -derivedDataPath ./DerivedData
~~~

- [ ] Step 3: Verify the workflow command statically.

Confirm the workflow contains one -parallel-testing-enabled NO on the shared test command and that TEST_TARGET still supports both the full VirgoUITests target and a specific VirgoUITests/<test> target.

- [ ] Step 4: Review and commit the workflow fix.

~~~bash
git diff --check
git diff --stat
git status --short
git add .github/workflows/ui-tests.yml
git commit -m "ci: disable parallel UI test workers"
~~~

- [ ] Step 5: Re-read the approved design and report evidence.

Report focused UI results, full unit results, workflow verification, and CI status separately. Do not claim the full UI suite passed locally unless that command was actually run; the design delegates that full-suite gate to CI after this correction.

