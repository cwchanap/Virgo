# HPA-581 Task 8A Verification Report

Date: 2026-08-14
Candidate: `00cc98747db8ba4cf23ff066f2b9ec313304c76a`
Worktree: `/Users/chanwaichan/workspace/Virgo/.worktrees/hpa-581-off-main-notation`

## Result

No source changes were needed. The strict-concurrency build passed, the required focused suites passed, and the complete `VirgoTests` unit target passed. The exact brief's full-scheme command ended with exit 65 because the scheme also launches `VirgoUITests`, whose runner hung before establishing its connection. The follow-up clean-main UI-target reproduction below reached the same signature, establishing this candidate UI failure as a host baseline. It is not the detached-context `Chart.difficulty` baseline signature.

## Toolchain and execution context

- `xcodebuild -version`: Xcode 26.6, build 17F113.
- `xcrun swift --version`: Swift 6.3.3 (`swift-driver` 1.148.6).
- Host: Darwin 25.5.0, arm64.
- All Xcode commands used `-derivedDataPath ./DerivedData` and were run serially with `-parallel-testing-enabled NO` for tests.
- The first strict-build attempt was blocked before compilation by the sandbox denying SwiftPM/Clang cache writes outside the worktree (`/Users/chanwaichan/.cache/clang/ModuleCache` and `/Users/chanwaichan/Library/Caches/org.swift.swiftpm`). The exact command was rerun with the required filesystem access; the result below is that rerun.

## Required verification commands

### 1. Strict-concurrency build

```text
xcodebuild build -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  SWIFT_STRICT_CONCURRENCY=complete \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData
```

Result: exit 0, `** BUILD SUCCEEDED **`.

The build emitted existing Swift 6 strict-concurrency warnings (555 `warning:` lines in the captured log, repeated across architectures and build phases) but no compiler errors. No HPA-581 source change was made to suppress them.

### 2. Required focused high-value suites

The exact nine-suite command from the brief was run serially:

```text
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -only-testing:VirgoTests/GameplaySheetMusicMountingTests \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  -only-testing:VirgoTests/DrumTabRegressionInvariantTests \
  -only-testing:VirgoTests/DrumTabPlayheadAlignmentTests \
  -only-testing:VirgoTests/GameplayNotationPreparationTests \
  -only-testing:VirgoTests/RhythmLayoutSnapshotBuilderTests \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -only-testing:VirgoTests/GameplayViewModelCleanupTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Result: exit 0, `147 tests in 9 suites passed`, `** TEST SUCCEEDED **` (Swift Testing: 3.333 seconds; xcodebuild test phase: 6.283 seconds).

### 3. Required full-scheme command

The exact full command from the brief was run serially:

```text
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Result: exit 65, `** TEST FAILED **` after 529.484 seconds. The `VirgoTests` target itself completed with `1857 tests in 177 suites passed after 174.946 seconds with 1 known issue`. The one known issue is the intentional `GoldenFileTests.swift:52:41` mismatch probe (`golden-file-mismatch-probe`), which records a readable diff and is explicitly expected to pass with one issue.

The scheme includes `VirgoUITests`. Its runner failed to establish a connection:

```text
Testing failed:
    VirgoUITests-Runner (18655) encountered an error (The test runner hung before establishing connection.)
```

The run's result bundle is at:
`DerivedData/Logs/Test/Test-Virgo-2026.08.14_10-35-28--0700.xcresult`.

Read-only process/diagnostic inspection showed the unit host had finished and the UI runner was the remaining failing process. There was no `Chart.difficulty` detached-context crash signature in this run. The clean-main reproduction in section 5 establishes the UI runner failure as host baseline. No source or shared-main changes were made.

### 4. Unit-target follow-up

To separate the passing full unit target from the hung UI runner, the following serial command was run after the required full command:

```text
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Result: exit 0, `1857 tests in 177 suites passed after 172.217 seconds with 1 known issue`, `** TEST SUCCEEDED **` (xcodebuild test phase: 185.674 seconds). The same intentional golden-mismatch issue was the only recorded issue.

### 5. Clean-main UI baseline reproduction

The shared checkout was confirmed clean before the reproduction: branch `main`, HEAD `74baccd78da72b4847bf75de7c7c410ae665c72d`, and no status entries. It was not edited. No Xcode test process was active before the run.

The single exact clean-main command requested by the follow-up was run with isolated temporary DerivedData:

```text
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoUITests -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath /private/tmp/hpa581-task8-clean-main-ui
```

Result: exit 65, `** TEST FAILED **` after 344.471 seconds. The exact same runner signature reproduced:

```text
Testing failed:
    VirgoUITests-Runner (32629) encountered an error (The test runner hung before establishing connection.)
```

The result bundle was `/private/tmp/hpa581-task8-clean-main-ui/Logs/Test/Test-Virgo-2026.08.14_10-59-26--0700.xcresult`. At the end of the run, read-only host probes reported `IOConsoleLocked = Yes` and `CGSSessionScreenIsLocked = Yes`; Accessibility reported no `Virgo` process (`false`), and querying its windows failed because that process was absent. This clean-main reproduction confirms the candidate's identical UI-runner failure is a host baseline under the current locked/no-AX-visible-window session. No broader retry loop or source change was made.

The exact temporary paths `/private/tmp/hpa581-task8-clean-main-ui` and `/private/tmp/hpa581-task8-clean-main-ui.log` were removed after capturing this evidence.

## Worktree integrity

- No source or test files were modified.
- The empty generated `default.profraw` artifact was removed after test execution.
- `git diff --check`: passed.
- The shared `main` checkout remained clean throughout the baseline reproduction.
- Final verification was performed from candidate `00cc987`; this report amendment is committed separately from source.
