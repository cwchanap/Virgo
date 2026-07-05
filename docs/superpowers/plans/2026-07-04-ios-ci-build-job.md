# iOS CI Build Job Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a compile-only iPad/iOS build job to `.github/workflows/ci.yml` so `#if os(iOS)` code paths are compiled in CI, closing the root-cause gap (Linear [HPA-90](https://linear.app/cwchanap/issue/HPA-90)) behind the prior P1 build break (whose symptom was fixed in HPA-91).

**Architecture:** One new GitHub Actions job (`build-ios`) added to the existing `ci.yml` workflow, running in parallel with `test` (no `needs:`). It compiles the `Virgo` scheme against `generic/platform=iOS Simulator` in Debug with code signing disabled — no tests, no coverage, no artifacts. The iOS job pins `macos-15` because the current `macos-latest` image resolves to `macos-26`, which has Xcode 26.1.1 but not the matching iOS 26.1 simulator runtime. The workflow's top-level name changes from `macOS CI` to `CI` since it now spans both platforms. Verification is the regression-probe pattern: temporarily introduce an `#if os(iOS)`-gated reference to a nonexistent symbol, prove the local iOS build fails, revert, then ship the YAML.

**Tech Stack:** GitHub Actions (`actions/checkout@v4`, `maxim-lobanov/setup-xcode@v1`), `xcodebuild`, Xcode 26.1.1, `macos-15` runner.

## Global Constraints

- **Primary workflow change:** `.github/workflows/ci.yml`. The `#if os(iOS)` regression probe is temporary and must be reverted before commit. A follow-up CI-failure fix also hardens `GameplayViewModelPlaybackTimingTests.swift` because the same workflow run exposed a hosted-runner timing assumption in the macOS test job.
- **No iPhone targeting:** destination must remain iPad-class. `generic/platform=iOS Simulator` respects the project's `TARGETED_DEVICE_FAMILY = 2`. The existing "Validate supported Apple platforms" step in the `test` job (unchanged) independently enforces this and must keep passing.
- **Runner and Xcode pinned:** `macos-15` + Xcode `26.1.1` — `macos-15` carries the matching iOS 26.1 simulator runtime. Do not use `macos-latest` for this job while it resolves to `macos-26` without that runtime.
- **Endpoints generation:** the new job must run `.github/scripts/generate-endpoints-env.sh` before building, so the iOS build resolves `ServerConfig`. The script degrades gracefully when `GRAPHQL_ENDPOINT`/`R2_BASE_URL` are unset, so the job stays green on forks.
- **Build command (reused verbatim in the job and in local verification):**
  ```
  xcodebuild build \
    -project Virgo.xcodeproj \
    -scheme Virgo \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO
  ```
- **No commits of probe code:** the regression probe is verified locally and reverted before any commit.

---

## Task 1: Add `build-ios` job and rename the workflow

**Files:**
- Modify: `.github/workflows/ci.yml` (line 1 rename; append new `build-ios` job after the `build-archive` job, i.e. after current line 171 and before the `codecov:` job at line 173)

**Interfaces:**
- Consumes: the existing `.github/scripts/generate-endpoints-env.sh` script and the `${{ vars.GRAPHQL_ENDPOINT }}` / `${{ vars.R2_BASE_URL }}` repository variables (same as `test` and `build-archive`).
- Produces: a CI job named `build-ios` (display name `Build (iPad Simulator)`) that gates every push/PR to `main` on a successful iOS-SDK compile. No outputs consumed by other jobs.

- [ ] **Step 1: Establish the local iOS build baseline (current code must compile for iOS)**

Run from the repo root:
```bash
xcodebuild build \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```
Expected: `** BUILD SUCCEEDED **`. This confirms (a) the destination string is valid on this machine, and (b) the repo currently compiles for iOS after the HPA-91 `private`-removal fix. If it fails for an unrelated reason, stop and fix that first — the baseline must be green before the probe is meaningful.

- [ ] **Step 2: Add the `#if os(iOS)` regression probe**

Append the following to the end of `Virgo/VirgoApp.swift` (chosen because it is guaranteed to be compiled in every target configuration, including iOS):
```swift

#if os(iOS)
enum CIRegressionProbe { static let probe = NonexistentTypeForCIProbe() }
#endif
```
This is a type declaration at file scope, so it requires no `main`/function context. On macOS the entire `#if` block is skipped; on iOS the reference to `NonexistentTypeForCIProbe` fails to resolve.

- [ ] **Step 3: Run the iOS build and confirm the probe FAILS it**

Run the exact command from Step 1.
Expected: `** BUILD FAILED **` with an error like:
```
error: cannot find type 'NonexistentTypeForCIProbe' in scope
```
This proves the destination genuinely exercises `#if os(iOS)` paths — i.e. a real iOS regression would be caught.

- [ ] **Step 4: Confirm the macOS build is unaffected by the probe**

Run:
```bash
xcodebuild build \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData
```
Expected: `** BUILD SUCCEEDED **`. This confirms the probe is invisible to the macOS path — which is exactly why the iOS build job is needed.

- [ ] **Step 5: Revert the probe**

Remove the block added in Step 2 from `Virgo/VirgoApp.swift` so the file is byte-identical to `HEAD`. Verify with:
```bash
git diff --stat Virgo/VirgoApp.swift
```
Expected: no output (clean working tree for that file).

- [ ] **Step 6: Rename the workflow**

In `.github/workflows/ci.yml`, change line 1:
```yaml
name: macOS CI
```
to:
```yaml
name: CI
```

- [ ] **Step 7: Add the `build-ios` job**

Insert the following job block into `.github/workflows/ci.yml`, placed immediately after the end of the `build-archive` job (after its final step, before the `codecov:` job). The indentation is 2 spaces for the job key, matching the existing jobs.

```yaml

  build-ios:
    name: Build (iPad Simulator)
    runs-on: macos-15

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Select Xcode version
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '26.1.1'

      - name: Generate ServerEndpoints.env from CI variables
        env:
          GRAPHQL_ENDPOINT: ${{ vars.GRAPHQL_ENDPOINT }}
          R2_BASE_URL: ${{ vars.R2_BASE_URL }}
        run: bash .github/scripts/generate-endpoints-env.sh

      - name: Build for iPad Simulator
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

Notes for the implementer:
- **No `needs:` key** — this job runs in parallel with `test`, per the approved spec §4.1.
- **No "Validate supported Apple platforms" step** here — it already runs in `test` (in parallel) and independently gates the PR; duplicating it would be redundant (spec §3, §4.2).
- **No `-derivedDataPath`, no `-resultBundlePath`, no artifact upload** — a compile-only build produces nothing to export (spec §4.3).
- **`generic/platform=iOS Simulator`** (not a named device) avoids simulator-availability flakiness across runner images (spec §4.3).

- [ ] **Step 8: Validate the YAML syntax**

Run:
```bash
python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/ci.yml")); print("YAML OK")'
```
Expected: `YAML OK`. If PyYAML is not installed locally, install with `python3 -m pip install --user pyyaml` or skip this step — GitHub Actions will surface any syntax error when the branch is pushed. Optionally also run `actionlint .github/workflows/ci.yml` if it is installed.

- [ ] **Step 9: Visually confirm the job ordering and structure**

Run:
```bash
git --no-pager diff .github/workflows/ci.yml
```
Confirm the workflow diff shows:
1. Line 1: `name: macOS CI` → `name: CI`.
2. A new top-level `build-ios:` job (2-space indent) sitting between the `build-archive` job and the `codecov` job, with the four steps from Step 7.
3. The `build-ios` job runs on `macos-15`, not `macos-latest`, so Xcode 26.1.1 has its matching iOS 26.1 simulator runtime.

- [ ] **Step 10: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add iPad Simulator build job to catch #if os(iOS) regressions (HPA-90)"
```
(No source files are staged — `Virgo/VirgoApp.swift` was reverted in Step 5.)

- [ ] **Step 11: Verify in CI**

Push the branch and open (or update) the PR:
```bash
git push -u origin jack65786656/hpa-90-add-ipadios-build-job-to-ci-to-catch-if-osios-regressions
```
On the PR checks, confirm:
1. A new `Build (iPad Simulator)` check appears and **passes**.
2. The existing `Run Tests on macOS`, `Test Archive Build (macOS)`, and coverage/codecov checks still run and pass.
3. The "Validate supported Apple platforms" step inside `Run Tests on macOS` still passes (no iPhone targeting introduced).

This satisfies all four HPA-90 acceptance criteria: CI compiles for the iOS Simulator SDK; the probe in Step 3 proved an iOS compile error would fail it; the existing macOS workflow path remains in place; and iPhone targeting is not added.
