# iOS CI Build Job Design

**Date:** 2026-07-04
**Status:** Approved for implementation planning
**Scope:** Add a compile-only iPad/iOS build job to `.github/workflows/ci.yml` so `#if os(iOS)` code paths are compiled in CI.
**Linear:** [HPA-90](https://linear.app/cwchanap/issue/HPA-90/add-ipadios-build-job-to-ci-to-catch-if-osios-regressions-root-cause)

## 1. Context

`ci.yml` only builds and tests against `platform=macOS`. The app also targets iPadOS (`TARGETED_DEVICE_FAMILY = 2`, the only supported iOS-class device per `CLAUDE.md`), but the `#if os(iOS)` code paths are never compiled in CI.

This let a **P1 build break** ship undetected: `GameplayViewModel`'s haptic generators were declared `private` in the core file but referenced from a cross-file extension (`GameplayViewModel+Computations.swift`) inside an iOS-only branch. Swift's `private` does not permit cross-file extension access, so every iPad build failed:

```
error: 'hitHapticGenerator' is inaccessible due to 'private' protection level
error: 'comboBreakHapticGenerator' is inaccessible due to 'private' protection level
** BUILD FAILED **
```

The symptom was fixed in HPA-91 by removing `private`, but the **root cause — no iOS CI coverage** — remains. This spec closes that gap with the highest-ROI fix: a compile-only iOS build.

## 2. Goals

- CI compiles the app against the iOS Simulator SDK on every push/PR to `main`.
- Any `#if os(iOS)` compile regression fails CI before merge.
- Fast feedback: the iOS build runs in parallel with the existing macOS `test` job rather than waiting on it.

## 3. Non-Goals

- Running iOS-simulator unit tests (significant runner time + simulator-bootstrap flakiness). Full iOS test execution is an explicit follow-up; compile-only captures the entire class of "`#if os(iOS)` breakage" for a fraction of the cost.
- Duplicating the "Validate supported Apple platforms" step already present in the `test` job (it runs in parallel and independently gates the PR; iPad-only targeting is also enforced by `TARGETED_DEVICE_FAMILY = 2` in the project itself).
- iPhone targeting. The existing platform-validation guard must continue to pass; this job must not introduce `TARGETED_DEVICE_FAMILY = "1,2"` or any iPhone destination.
- Coverage/artifact upload from the iOS build (a compile-only build produces nothing to export).

## 4. Design

### 4.1 New job: `build-ios`

A new job added to `.github/workflows/ci.yml`, placed after `build-archive` for readability.

- `runs-on: macos-latest`
- **No `needs:`** — runs in parallel with `test`. This gives the fastest feedback on the `#if os(iOS)` regression class. The trade-off is marginally higher runner-minute spend when `test` independently fails, which is acceptable: the iOS build is fast (compile-only) and the regression class it catches is distinct from macOS test failures.

### 4.2 Steps

Four steps, mirroring the conventions of the existing jobs:

1. `actions/checkout@v4`
2. `maxim-lobanov/setup-xcode@v1` with `xcode-version: '26.1.1'` (matches `test` and `build-archive`)
3. Generate `ServerEndpoints.env` via `bash .github/scripts/generate-endpoints-env.sh`, passing `GRAPHQL_ENDPOINT` / `R2_BASE_URL` from `${{ vars.* }}`. **Required** so the iOS build resolves `ServerConfig`; the script degrades gracefully (local-dev fallback) on forks without the vars, so the job stays green there.
4. `xcodebuild build`:

   ```yaml
   run: |
     xcodebuild build \
       -project Virgo.xcodeproj \
       -scheme Virgo \
       -destination 'generic/platform=iOS Simulator' \
       -configuration Debug \
       ONLY_ACTIVE_ARCH=NO \
       CODE_SIGNING_REQUIRED=NO \
       CODE_SIGNING_ALLOWED=NO
   ```

### 4.3 Build-command rationale

- **`generic/platform=iOS Simulator`** (not a named simulator) — avoids device-availability flakiness across runner images. The issue calls this out explicitly; a named device like `iPad Pro 11-inch (M4)` would break when the runner image rotates its simulator catalog.
- **`Debug`** (not `Release`) — the goal is to compile the iOS code paths, not to ship. Debug is faster and matches the `test` job's configuration.
- **No `-derivedDataPath`** — there are no tests or coverage bundles to export from this job, so the default derived-data location is fine and avoids colliding with other jobs' paths.
- **No tests, no `-resultBundlePath`, no artifact upload** — nothing to upload from a compile-only build.

### 4.4 Workflow rename

The workflow's top-level `name: macOS CI` becomes `name: CI`, since the workflow now covers both macOS and iPadOS.

`ui-tests.yml` keeps its `macOS UI Tests` name. It runs only macOS UI tests today; its in-file comment already documents that any future simulator UI tests must use iPad simulator destinations only.

## 5. Verification

Acceptance criteria from HPA-90, and how each is met:

| Criterion | How verified |
|---|---|
| CI runs a `build-ios` job that compiles for the iOS Simulator SDK | The new job appears in the workflow and runs `xcodebuild build` against `generic/platform=iOS Simulator`. |
| A deliberately-introduced `#if os(iOS)` compile error fails CI | Local/manual probe before merge: temporarily add `#if os(iOS)\nlet _ = NonexistentType()\n#endif` to a Swift file, run the same `xcodebuild build` command locally against `generic/platform=iOS Simulator`, confirm it fails, then revert. Documented in the implementation plan as a verification step. |
| Existing macOS test + archive jobs still pass | `test`, `build-archive`, and `codecov` jobs are unchanged; they continue to pass on the PR. |
| Job does NOT add iPhone targeting | No `TARGETED_DEVICE_FAMILY` change anywhere; destination is iPad-class (`generic/platform=iOS Simulator` respects the project's `TARGETED_DEVICE_FAMILY = 2`). The platform-validation guard in `test` still runs and must pass. |

## 6. Future Work

- iOS-simulator unit-test execution (would catch runtime/iOS-specific test failures, not just compile failures). Higher runner cost; tracked as a separate follow-up.
