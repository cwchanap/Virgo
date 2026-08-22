# HPA-85 Native Server BGM Format Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans. This ticket is one implementation PR. Task checkpoints may be separate commits, but Tasks 1 and 2 are one atomic shipping boundary and must never land independently.

**Goal:** Cut Virgo's server-song BGM contract from OGG to playable AAC-in-M4A without adding client transcoding, codec dependencies, compatibility migration, or dual-format fallback.

**Architecture:** The external GraphQL/R2 backend publishes one current BGM object, `bgm.m4a`. `SimfileMapper` recognizes and assembles that filename, `ServerSongFileManager` persists the downloaded bytes as `{songId}.m4a`, and the existing `ServerSongDownloader` -> `Song.bgmFilePath` -> `AVAudioPlayer` flow remains unchanged. Old `.ogg` development data is reset/re-downloaded rather than migrated.

**Tech stack:** Current Xcode project in Swift 5 language mode, SwiftUI/SwiftData, Foundation `URLSession`, AVFoundation `AVAudioPlayer`, Swift Testing, GraphQL catalog DTOs backed by Cloudflare R2.

## Global constraints

- Supported Apple targets remain macOS 14.0+ and iPadOS 17.5+; the project is iPad-only (`TARGETED_DEVICE_FAMILY = 2`).
- Backend/R2 must publish verified playable AAC-in-M4A bytes as `bgm.m4a` before client implementation starts.
- The current server BGM filename is exactly `bgm.m4a`; do not support `bgm.ogg` as a fallback.
- Tasks 1 and 2 may be separate commits for review/TDD, but they are not independently shippable. Do not merge, cherry-pick, or release the mapper-only state.
- Do not add FFmpeg, libvorbis, VLCKit, client transcode, runtime codec probing, or another audio abstraction.
- Do not add startup migration, path backfill, dual-file lookup, or legacy `.ogg` cleanup.
- Do not change preview `.mp3`, metronome/SFX audio, GraphQL schema/codegen, or gameplay BGM synchronization.
- Keep `ServerSongDownloader.swift` and gameplay production logic unchanged unless a focused regression test proves a real dependency.
- Use Swift Testing (`import Testing`, `#expect`) and run tests with parallel testing disabled.

## Latest-main revalidation

Revalidated on 2026-08-22 against `main` `5d62cc62d50d4bc9f0d483e057e7151571c9c4db` after HPA-581 merged. Latest `main` still has the same HPA-85 seams:

- `SimfileMapper` recognizes/assembles `bgm.ogg`;
- `ServerSongFileManager` persists/deletes `{songId}.ogg`;
- `ServerSongDownloader` remains format-agnostic orchestration;
- `ServerSongCache.refreshCatalog` maps fetched DTOs through `SimfileMapper.makeServerSong`;
- gameplay still passes `Song.bgmFilePath` directly to `AVAudioPlayer`;
- local fixture import already resolves `bgm.m4a`.

The intervening notation/performance work does not expand HPA-85's production scope.

---

## Pre-implementation gate: prove the backend bytes, not the filename

The original failure is an audio-playability failure. A `200` response or an object named `bgm.m4a` is not sufficient evidence because mislabeled or wrongly encoded bytes can still recreate the bug.

Before Task 1 starts, choose one representative published simfile and verify all of the following outside Virgo:

1. `Simfile.files` contains `<simfile-id>/bgm.m4a`.
2. Download that exact public R2 object to a local file.
3. `afinfo` identifies the downloaded object as an MPEG-4/M4A container carrying AAC audio.
4. The local file can be opened by the same API gameplay uses: `AVAudioPlayer(contentsOf:)`; `prepareToPlay()` must succeed.
5. Record the representative simfile id/title plus the `afinfo` summary and AVAudioPlayer probe result in the implementation PR.

Example verification flow on macOS:

```bash
curl --fail --location \
  "$R2_BASE_URL/$SIMFILE_ID/bgm.m4a" \
  --output /tmp/virgo-hpa85-bgm.m4a

afinfo /tmp/virgo-hpa85-bgm.m4a
```

Then run a tiny local AVFoundation probe using the downloaded file:

```swift
import AVFoundation
import Foundation

let url = URL(fileURLWithPath: "/tmp/virgo-hpa85-bgm.m4a")
let player = try AVAudioPlayer(contentsOf: url)
precondition(player.prepareToPlay())
```

HTTP status/MIME alone is not the gate. If container/codec inspection or AVAudioPlayer initialization fails, stop and fix backend media ingestion. Do not compensate in Virgo with fallback, transcoding, or an OGG decoder.

---

## File map

### Production files

- `Virgo/utilities/SimfileMapper.swift`
  - Remote BGM availability detection and R2 URL assembly.
- `Virgo/utilities/ServerSongFileManager.swift`
  - Local downloaded BGM filename and song-id cleanup path.

### Core regression tests

- `VirgoTests/SimfileMapperTests.swift`
  - Exact `bgm.m4a` catalog-key/URL semantics and explicit legacy OGG rejection.
- `VirgoTests/ServerSongCatalogRefreshTests.swift`
  - Pins the real catalog consumer so a current `bgm.m4a` DTO survives `ServerSongCache -> SimfileMapper` with `hasBGM == true`.
- `VirgoTests/ServerSongDownloaderTests.swift`
  - Pins mapper URL -> optional download -> persisted path composition.
- `VirgoTests/ServerSongFileManagerTests.swift`
  - Pins `.m4a` persistence/deletion and byte identity.

### Later fixture hygiene

- `VirgoTests/ApolloSimfileClientTests.swift`
  - Representative current R2 BGM keys should use `bgm.m4a`; tests remain GraphQL mapping tests.
- `VirgoTests/GraphQLQuerySchemaTests.swift`
  - Representative current R2 BGM keys should use `bgm.m4a`; no GraphQL type/codegen change.

### Documentation

- `docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md`
  - Active GraphQL/R2 client integration contract; replace server-BGM `.ogg` wording and correct the old suffix-match description to exact `lastPathComponent` matching.

No new production file or type is planned.

---

## Task 1: Cut the remote contract and pin the catalog consumer

**Files:**

- Modify: `VirgoTests/SimfileMapperTests.swift`
- Modify: `VirgoTests/ServerSongCatalogRefreshTests.swift`
- Modify: `VirgoTests/ServerSongDownloaderTests.swift`
- Modify: `Virgo/utilities/SimfileMapper.swift`

### Step 1: Update mapper contract tests first

In `SimfileMapperTests`:

- current positive key: `song-1/bgm.m4a`;
- explicit negative key: `song-1/bgm.ogg`;
- similar-name negative: `song-1/intro-bgm.m4a`;
- BGM URL: `.../song-1/bgm.m4a`;
- preview stays `preview.mp3`.

The explicit OGG negative proves this is a hard cutover rather than dual-format support.

### Step 2: Pin the real catalog consumer in the same task

In `ServerSongCatalogRefreshTests.makeChangedAWithNewBPM()` change only the current server DTO key:

```swift
fileKeys: ["bgm.m4a", "preview.mp3"]
```

In `testCompleteReplacementOverwritesMetadataAndPreservesLocalSong`, add:

```swift
#expect(byID["a"]?.hasBGM == true)
```

Keep the local persisted path assertion as stale development data:

```swift
#expect(local.bgmFilePath == "/tmp/a.ogg")
```

That distinction is intentional: current **server keys** follow the new contract, while old local rows are not migrated.

### Step 3: Update the downloader composition test

In `ServerSongDownloaderTests`:

- mock BGM path becomes `/tmp/mock-bgm.m4a`;
- response is seeded at `.../multi-diff/bgm.m4a`;
- imported `Song.bgmFilePath` expects `/tmp/mock-bgm.m4a`;
- requested URL order expects `/bgm.m4a`;
- chart and preview URLs stay unchanged.

### Step 4: Run the red tests

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/SimfileMapperTests \
  -only-testing:VirgoTests/ServerSongCatalogRefreshTests \
  -only-testing:VirgoTests/ServerSongDownloaderTests \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

Before the production edit, the M4A mapper expectations and catalog `hasBGM` assertion must fail; the downloader should request the old OGG URL.

### Step 5: Make the minimal mapper production change

```swift
hasBGM: hasFile(named: "bgm.m4a", in: dto.fileKeys)
```

```swift
static func bgmURL(base: URL, songId: String) -> URL {
    base.appendingPathComponent(songId).appendingPathComponent("bgm.m4a")
}
```

Do not add an audio-format enum, alternate extension array, suffix matching, or fallback request.

### Step 6: Re-run Task 1 tests

Run the command from Step 4. Expected: all selected suites pass.

### Step 7: Confirm downloader production code stayed unchanged

```bash
git diff --exit-code main...HEAD -- Virgo/utilities/ServerSongDownloader.swift
```

Expected: exit 0.

### Step 8: Optional Task 1 checkpoint commit

A separate commit is fine for review/TDD:

```bash
git add \
  Virgo/utilities/SimfileMapper.swift \
  VirgoTests/SimfileMapperTests.swift \
  VirgoTests/ServerSongCatalogRefreshTests.swift \
  VirgoTests/ServerSongDownloaderTests.swift
git commit -m "fix: request native server BGM"
```

**Do not merge or release this commit by itself.** The branch is intentionally non-shippable until Task 2 changes local persistence to `.m4a`.

---

## Task 2: Persist server BGM as `{songId}.m4a`

**Files:**

- Modify: `VirgoTests/ServerSongFileManagerTests.swift`
- Modify: `Virgo/utilities/ServerSongFileManager.swift`

### Step 1: Update file-manager tests first

Require:

```swift
#expect(savedPath.hasSuffix("/BGM/\(songId).m4a"))
```

Keep the payload round-trip assertion unchanged. Update format-shaped test-only paths such as missing/outside-bundle examples to `.m4a` where they represent current storage. Do not add legacy `.ogg` cleanup tests.

### Step 2: Run the red file-manager suite

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/ServerSongFileManagerTests \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

Expected before the production edit: the returned path still ends in `.ogg`.

### Step 3: Change local persistence and song-id cleanup together

In `saveBGMFile`:

```swift
let bgmFilePath = bgmDirectory.appendingPathComponent("\(songId).m4a")
```

In `deleteFiles(forSongId:)`:

```swift
let bgm = documents
    .appendingPathComponent("BGM")
    .appendingPathComponent("\(songId).m4a")
```

Keep preview `.mp3`. Do not transform bytes and do not probe/delete an OGG sibling.

### Step 4: Re-run file-manager tests

Expected: `ServerSongFileManagerTests` passes.

### Step 5: Atomic cutover checkpoint

Tasks 1 and 2 are now jointly shippable. Run all four core suites together:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/SimfileMapperTests \
  -only-testing:VirgoTests/ServerSongCatalogRefreshTests \
  -only-testing:VirgoTests/ServerSongDownloaderTests \
  -only-testing:VirgoTests/ServerSongFileManagerTests \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

Then audit the production pipeline:

```bash
git grep -n 'bgm\.ogg' -- \
  Virgo/utilities/SimfileMapper.swift \
  Virgo/utilities/ServerSongFileManager.swift \
  Virgo/utilities/ServerSongDownloader.swift
```

Expected: no matches.

### Step 6: Optional Task 2 checkpoint commit

```bash
git add \
  Virgo/utilities/ServerSongFileManager.swift \
  VirgoTests/ServerSongFileManagerTests.swift
git commit -m "fix: persist server BGM as m4a"
```

The implementation PR must contain both Task 1 and Task 2 before it is mergeable.

---

## Task 3: Update the active contract and representative GraphQL fixtures

**Files:**

- Modify: `docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md`
- Modify: `VirgoTests/ApolloSimfileClientTests.swift`
- Modify: `VirgoTests/GraphQLQuerySchemaTests.swift`

### Step 1: Update the active GraphQL/R2 integration spec

Use one server BGM contract throughout:

```text
BGM object: {R2_base}/{id}/bgm.m4a
Availability: Simfile.files contains lastPathComponent == "bgm.m4a"
Local use: downloaded bytes are persisted as a native-playable `.m4a` path for AVAudioPlayer
```

Update at minimum:

- full BGM format descriptions;
- file-delivery contract;
- audio URL assembly;
- availability semantics;
- binary download/caching examples;
- architecture text;
- field-consumption map.

Correct the existing integration-spec wording that describes availability as a suffix match. Production uses exact `lastPathComponent` equality and the documentation must say so.

Add one concise backend-responsibility statement:

> The backend/media-ingestion path publishes Virgo BGM as AAC-in-M4A (`bgm.m4a`); the client does not transcode or decode OGG.

Do not change GraphQL types, codegen, pagination, chart URLs, or preview `.mp3`.

### Step 2: Normalize representative current GraphQL keys

In `ApolloSimfileClientTests.swift` and `GraphQLQuerySchemaTests.swift`, change representative **current server/R2 BGM keys** from `bgm.ogg` to `bgm.m4a`.

These are hygiene edits only; do not add codec logic or schema assertions.

### Step 3: Audit the active spec

```bash
git grep -n 'bgm\.ogg' -- \
  docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md
```

Expected: no active-contract matches.

```bash
git grep -n 'bgm\.m4a' -- \
  docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md
```

Expected: file-delivery, URL, availability, and field-map sections all carry the M4A contract.

---

## Task 4: Full verification and fresh-download smoke

### Step 1: Run the complete macOS unit suite

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

### Step 2: Build the iPad target

Use an installed iPad simulator, never iPhone:

```bash
xcodebuild \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' \
  build
```

If that simulator is unavailable, use another installed iPad destination and record it in the PR.

### Step 3: Run lint and diff checks

```bash
swiftlint lint
git diff --check main...HEAD
```

Do not refactor unrelated warning-level size debt.

### Step 4: Classify every remaining `bgm.ogg`

```bash
git grep -n 'bgm\.ogg' -- Virgo VirgoTests
```

Expected classification:

- `SimfileMapper.swift`: zero `bgm.ogg` matches.
- `ServerSongFileManager.swift`: zero `bgm.ogg` matches.
- `ServerSongDownloaderTests.swift`: zero `bgm.ogg` matches.
- `SimfileMapperTests.swift`: the intentional `bgm.ogg` **negative** fixture may remain to prove legacy OGG is rejected.
- `ServerSongCatalogRefreshTests.swift`: current DTO `fileKeys` use `bgm.m4a`; local `Song.bgmFilePath` values such as `/tmp/a.ogg` may remain only when intentionally modeling stale development data/extension-agnostic status behavior.
- `ApolloSimfileClientTests.swift` and `GraphQLQuerySchemaTests.swift`: representative current server keys use `bgm.m4a`.
- Format-irrelevant arbitrary URL/network tests may retain `.ogg` if they are not modeling the current server BGM contract.
- Unrelated metronome/SFX/fixture references remain out of scope.

Also confirm no production code contains compatibility concepts such as `legacyBGM`, `migrateBGM`, `oggFallback`, alternate-extension loops, or client transcode logic.

### Step 5: Reset stale development data

Use the normal development reset/reseed flow or delete the previously downloaded server song. Do not hand-edit an old `.ogg` path into `.m4a`; the smoke must exercise a fresh download.

Deletion is already path-based for persisted audio, so stale development rows can be deleted and then downloaded again without a dedicated `.ogg` cleanup implementation.

### Step 6: Fresh-download smoke on macOS

Using the same representative backend object from the pre-implementation gate:

1. refresh the server catalog;
2. confirm the row reports BGM available;
3. download/import it;
4. confirm the persisted BGM path ends in `.m4a`;
5. open gameplay;
6. confirm `AVAudioPlayer` initializes without `bgmLoadingError`;
7. start playback and confirm BGM is audible and remains synchronized through existing controls.

Record the simfile id/title in the implementation PR.

### Step 7: Fresh-download smoke on iPadOS

Repeat fresh download -> gameplay on an iPad simulator/device environment with working audio output. Confirm `.m4a` persistence and successful player initialization.

If simulator audio cannot prove audibility, record that limitation and perform an actual-device smoke before closing HPA-85. Do not replace this with a network-dependent CI test.

### Step 8: Review final scope

Expected production diff:

```text
Virgo/utilities/SimfileMapper.swift
Virgo/utilities/ServerSongFileManager.swift
```

Expected supporting diff:

```text
VirgoTests/SimfileMapperTests.swift
VirgoTests/ServerSongCatalogRefreshTests.swift
VirgoTests/ServerSongDownloaderTests.swift
VirgoTests/ServerSongFileManagerTests.swift
VirgoTests/ApolloSimfileClientTests.swift
VirgoTests/GraphQLQuerySchemaTests.swift
docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md
```

No GraphQL generated files, SwiftData models, downloader production changes, gameplay implementation changes, audio engine, dependency manifest, migration helper, or codec library should be necessary.

---

## Completion checklist

- [ ] A representative published `bgm.m4a` is downloaded and proven AAC-in-M4A by `afinfo` before client work starts.
- [ ] The same downloaded file opens through `AVAudioPlayer(contentsOf:)` and prepares successfully before client work starts.
- [ ] Mapper and file-manager cutovers are in the same implementation PR and are never shipped independently.
- [ ] Mapper recognizes only `bgm.m4a` and assembles the M4A URL.
- [ ] Catalog-refresh coverage proves a current `bgm.m4a` DTO maps to `hasBGM == true`.
- [ ] File manager persists/deletes `{songId}.m4a`.
- [ ] Downloader production logic remains orchestration-only.
- [ ] Gameplay production logic remains format-agnostic and unchanged.
- [ ] Mapper tests explicitly reject legacy server `bgm.ogg` availability.
- [ ] Active GraphQL integration documentation uses exact `lastPathComponent` matching and `.m4a` everywhere relevant.
- [ ] Representative current GraphQL/catalog server fixtures use `bgm.m4a`; intentional stale/local `.ogg` fixtures remain only where their semantics require them.
- [ ] No migration, fallback, runtime codec probing, codec dependency, or client transcode is added.
- [ ] Focused tests, full macOS tests, iPad build, SwiftLint, and diff checks pass.
- [ ] Fresh server download reaches audible/initialized gameplay BGM on macOS and iPadOS.
