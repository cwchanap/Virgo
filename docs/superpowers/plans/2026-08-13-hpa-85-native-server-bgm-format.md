# HPA-85 Native Server BGM Format Implementation Plan

> **For agentic workers:** Implement this ticket in one PR. Keep the production change small: `SimfileMapper` + `ServerSongFileManager`; supporting test/doc edits stay in the same PR.

**Goal:** Cut Virgo's server-song BGM contract from OGG to playable AAC-in-M4A without client transcoding, codec dependencies, compatibility migration, or dual-format fallback.

**Architecture:** `SimfileMapper.bgmFilename` is the single source of truth for `bgm.m4a`. The mapper uses it for availability and R2 URL assembly; `ServerSongFileManager` derives the local extension from the same constant. `ServerSongDownloader` and gameplay remain format-agnostic.

**Tech stack:** Current Xcode project in Swift 5 language mode, SwiftUI/SwiftData, Foundation `URLSession`, AVFoundation `AVAudioPlayer`, Swift Testing, GraphQL/R2 backend.

## Global constraints

- macOS 14.0+ and iPadOS 17.5+; iPad-only mobile target.
- Do not add an audio-format type, decoder, FFmpeg/VLCKit/libvorbis, client transcode, fallback, migration, runtime codec probing, or GraphQL schema/codegen change.
- Keep preview `.mp3`, metronome/SFX, downloader production logic, and gameplay production logic unchanged.
- Old local `.ogg` rows/files are disposable development data; delete/reset and re-download rather than migrate.
- Use Swift Testing and run test suites with parallel testing disabled.

## Pre-implementation gate: prove the whole catalog is ready

Do this before changing Virgo.

### 1. Catalog-wide filename gate

Use the existing GraphQL published-catalog operation and page through the complete result set. For each `Simfile.files` list, compare `lastPathComponent` values.

A simfile is BGM-bearing when it exposes any filename beginning with `bgm.`. Every BGM-bearing simfile must also expose `bgm.m4a` before the hard client cutover starts.

Record in the implementation PR:

```text
published simfiles: <count>
BGM-bearing simfiles: <count>
with bgm.m4a: <count>
BGM-bearing rows missing bgm.m4a: 0
```

Do not commit a new verification tool unless the existing GraphQL client/query cannot perform this check. A one-off query/script outside production code is sufficient.

### 2. Byte-level playability gate

For one or two representative published `bgm.m4a` objects:

```bash
curl --fail --location \
  "$R2_BASE_URL/$SIMFILE_ID/bgm.m4a" \
  --output /tmp/virgo-hpa85-bgm.m4a

afinfo /tmp/virgo-hpa85-bgm.m4a
```

Require `afinfo` to report AAC audio in an MPEG-4/M4A container. Then open the downloaded file with the same API gameplay uses:

```swift
import AVFoundation
import Foundation

let url = URL(fileURLWithPath: "/tmp/virgo-hpa85-bgm.m4a")
let player = try AVAudioPlayer(contentsOf: url)
precondition(player.prepareToPlay())
```

Record the representative simfile ids/titles plus `afinfo` and AVAudioPlayer results. HTTP status, MIME, and filename alone are insufficient.

If either gate fails, stop and fix backend/media ingestion. Do not compensate in Virgo.

---

## File map

### Production

- `Virgo/utilities/SimfileMapper.swift`
  - add the shared `bgmFilename` / derived extension contract;
  - recognize/request current M4A;
  - warn when a `bgm.*` key exists but `bgm.m4a` is absent (coexistence with `bgm.m4a` is allowed).
- `Virgo/utilities/ServerSongFileManager.swift`
  - save BGM with the shared extension;
  - delete dead `deleteFiles(forSongId:)`.

### Core tests

- `VirgoTests/SimfileMapperTests.swift`
- `VirgoTests/ServerSongCatalogRefreshTests.swift`
- `VirgoTests/ServerSongDownloaderTests.swift`
- `VirgoTests/ServerSongFileManagerTests.swift`

### Fixture hygiene

- `VirgoTests/ApolloSimfileClientTests.swift`
- `VirgoTests/GraphQLQuerySchemaTests.swift`
- `VirgoTests/PatchCoverageTests.swift`

### Documentation

- `docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md`

No new production file or type is planned.

---

## Task 1: Centralize and cut the server BGM contract

**Files:**

- Modify: `Virgo/utilities/SimfileMapper.swift`
- Modify: `VirgoTests/SimfileMapperTests.swift`
- Modify: `VirgoTests/ServerSongCatalogRefreshTests.swift`
- Modify: `VirgoTests/ServerSongDownloaderTests.swift`

### Step 1: Update mapper tests first

Pin:

- `song-1/bgm.m4a` -> `hasBGM == true`;
- `song-1/bgm.ogg` -> `hasBGM == false`;
- `song-1/intro-bgm.m4a` -> `hasBGM == false`;
- BGM URL ends in `/song-1/bgm.m4a`;
- preview stays `.mp3`.

Do not widen matching beyond existing exact `lastPathComponent` equality.

The warning itself does not need a logging-capture test; mapper behavior is pinned by the positive/negative cases and the warning is diagnostic-only.

### Step 2: Pin the real catalog consumer

In `ServerSongCatalogRefreshTests.makeChangedAWithNewBPM()` change the current server key to:

```swift
fileKeys: ["bgm.m4a", "preview.mp3"]
```

Add:

```swift
#expect(byID["a"]?.hasBGM == true)
```

Keep the existing local stale path assertion such as `/tmp/a.ogg`; it intentionally models disposable local data, not the current server contract.

### Step 3: Update the downloader composition test

In `ServerSongDownloaderTests`:

- seed `.../multi-diff/bgm.m4a`;
- mock the saved BGM path as `/tmp/mock-bgm.m4a`;
- expect the imported `Song.bgmFilePath` to be that `.m4a` path;
- expect the requested URL list to contain `/bgm.m4a`;
- leave charts and preview unchanged.

### Step 4: Run the red suites

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

Before the production edit, the M4A mapper/catalog expectations and downloader M4A request must fail against current main.

### Step 5: Add the shared filename contract and hard cutover

In `SimfileMapper`:

```swift
static let bgmFilename = "bgm.m4a"

static var bgmPathExtension: String {
    (bgmFilename as NSString).pathExtension
}
```

Use `bgmFilename` in both places:

```swift
hasBGM: hasFile(named: Self.bgmFilename, in: dto.fileKeys)
```

```swift
static func bgmURL(base: URL, songId: String) -> URL {
    base.appendingPathComponent(songId).appendingPathComponent(Self.bgmFilename)
}
```

Before constructing the `ServerSong`, detect the real contract mismatch: a BGM-shaped key exists but the current `bgm.m4a` key is absent. The catalog gate allows a legacy `bgm.*` object to remain when `bgm.m4a` is also published, so a coexisting legacy key must not warn on every refresh and drown out genuine drift.

```swift
let lastComponents = dto.fileKeys.map { ($0 as NSString).lastPathComponent }
if !lastComponents.contains(Self.bgmFilename),
   let unexpectedBGM = lastComponents.first(where: { $0.hasPrefix("bgm.") }) {
    Logger.warning("Simfile \(dto.id) publishes \(unexpectedBGM); expected \(Self.bgmFilename)")
}
```

This warning is not fallback behavior. `hasBGM` remains true only for exact `bgm.m4a`.

### Step 6: Re-run Task 1 suites

Run the command from Step 4. Expected: selected suites pass.

A checkpoint commit is fine, but this ticket remains one implementation PR.

---

## Task 2: Persist with the shared extension and remove dead deletion API

**Files:**

- Modify: `Virgo/utilities/ServerSongFileManager.swift`
- Modify: `VirgoTests/ServerSongFileManagerTests.swift`

### Step 1: Update file-manager tests

Change the save expectation to:

```swift
#expect(savedPath.hasSuffix("/BGM/\(songId).m4a"))
```

Keep byte identity, generic deletion, missing-path tolerance, and bundle-protection coverage.

Delete `testDeleteBySongId`. Its only production target, `deleteFiles(forSongId:)`, has no production caller and duplicates filename knowledge.

Update format-shaped current-path examples from `.ogg` to `.m4a` where they are intended to represent current storage.

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

### Step 3: Save using the shared extension

Change only the current save path:

```swift
let bgmFilePath = bgmDirectory
    .appendingPathComponent(songId)
    .appendingPathExtension(SimfileMapper.bgmPathExtension)
```

Do not transform the bytes.

Delete `ServerSongFileManager.deleteFiles(forSongId:)` entirely. Production deletion already captures `Song.bgmFilePath` / `previewFilePath` and calls path-based deletion through `ServerSongStatusManager`.

### Step 4: Re-run the file-manager suite and core BGM suites

Run `ServerSongFileManagerTests`, then run the four core suites together:

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

---

## Task 3: Update the active contract and representative fixtures

**Files:**

- Modify: `docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md`
- Modify: `VirgoTests/ApolloSimfileClientTests.swift`
- Modify: `VirgoTests/GraphQLQuerySchemaTests.swift`
- Modify: `VirgoTests/PatchCoverageTests.swift`

### Step 1: Update the active GraphQL/R2 integration spec

Use one contract throughout:

```text
BGM object: {R2_base}/{id}/bgm.m4a
Availability: Simfile.files lastPathComponent == "bgm.m4a"
Local use: downloaded bytes persist to a native-playable .m4a path
```

Correct the current suffix-match wording to exact `lastPathComponent` equality. State that backend/media ingestion publishes AAC-in-M4A and Virgo does not transcode/decode OGG.

Do not change GraphQL types, codegen, pagination, chart URLs, or preview `.mp3`.

### Step 2: Normalize representative current server keys

Change representative current BGM keys in:

- `ApolloSimfileClientTests.swift` -> `bgm.m4a`;
- `GraphQLQuerySchemaTests.swift` -> `bgm.m4a`.

These are mapping/schema fixture hygiene only.

### Step 3: Remove misleading BGM mock extensions

In `PatchCoverageTests.swift`, change the two `saveBGMFile` mock return values from `/tmp/mock.ogg` to `/tmp/mock.m4a`.

Those tests are extension-agnostic and the mocked save results are not the behavior under test, so using the current format removes misleading stale strings without changing test purpose.

### Step 4: Audit the active integration spec

```bash
git grep -n 'bgm\.ogg' -- \
  docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md
```

Expected: no active-contract matches.

---

## Task 4: Full verification and smoke

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

### Step 2: Build iPad

Use an installed iPad simulator destination, never iPhone:

```bash
xcodebuild \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' \
  build
```

Use another installed iPad simulator if that exact destination is unavailable.

### Step 3: Lint and whitespace

```bash
swiftlint lint
git diff --check main...HEAD
```

Do not refactor unrelated warning-level debt.

### Step 4: Audit every remaining `.ogg`

Use the broad pattern, not only `bgm.ogg`:

```bash
git grep -n '\.ogg' -- Virgo VirgoTests
```

Classify every remaining source/test match. Expected categories:

- `SimfileMapperTests`: intentional `bgm.ogg` negative fixture proving rejection;
- `ServerSongCatalogRefreshTests`, `ServerSongStatusManagerTests`, `ServerSongServiceTests`: stale/local path fixtures may remain when explicitly testing current-format-only or extension-agnostic persistence/status behavior;
- `DTXAPIClientNetworkingTests`: arbitrary failing URL may remain format-irrelevant;
- gameplay coverage files: arbitrary audio-path fixtures may remain when format is not the assertion;
- metronome/SFX or other unrelated OGG assets remain out of scope;
- `PatchCoverageTests` BGM save mocks should now use `.m4a`.

Current server/R2 contract fixtures must not remain on `.ogg` except the explicit mapper negative case.

Also confirm no production code introduces migration/fallback/transcode concepts.

### Step 5: Fresh-download smoke on macOS

Using a representative server object already validated by the preflight:

1. refresh catalog;
2. confirm the row reports BGM available;
3. download/import;
4. confirm persisted path ends in `.m4a`;
5. open gameplay and confirm no `bgmLoadingError`;
6. start playback and confirm BGM is audible and synchronized through existing controls.

Record the simfile id/title in the implementation PR.

### Step 6: iPad simulator check

On an iPad simulator:

1. launch the app;
2. exercise the fresh/current BGM path far enough to confirm the persisted BGM path ends in `.m4a`;
3. confirm gameplay initializes without `bgmLoadingError`.

Do not gate HPA-85 on actual-device audibility. The iPad build + simulator initialization check is sufficient for this pre-release filename-contract change; macOS remains the audible smoke.

### Step 7: Review final scope

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
VirgoTests/PatchCoverageTests.swift
docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md
```

No generated GraphQL code, SwiftData model, downloader production code, gameplay production code, audio engine, dependency manifest, migration helper, or codec library should be necessary.

---

## Completion checklist

Verified 2026-09-07 (verification record: PR #62 comment 5578859690).

- [x] Complete published catalog has zero BGM-bearing rows missing `bgm.m4a` before client work starts. (319 published / 314 BGM-bearing / 314 with `bgm.m4a` / 0 missing.)
- [x] Representative real `bgm.m4a` bytes pass `afinfo` and `AVAudioPlayer` before client work starts. (Ids 392, 391, 369, 368 — all AAC-in-M4A, `prepareToPlay()` true.)
- [x] One shared `SimfileMapper.bgmFilename` contract drives remote naming and local extension.
- [x] Mapper warns when a `bgm.*` key exists but `bgm.m4a` is absent; coexistence with `bgm.m4a` is allowed and silent.
- [x] Catalog refresh coverage proves a current M4A DTO maps to `hasBGM == true`.
- [x] File manager saves BGM as `.m4a`; unused `deleteFiles(forSongId:)` is removed.
- [x] Downloader and gameplay production logic remain unchanged.
- [x] Active integration spec uses `.m4a` and exact `lastPathComponent` matching.
- [x] Current server/GraphQL fixtures use `.m4a`; broad `.ogg` audit classifies all intentional leftovers.
- [x] No migration, fallback, decoder, transcode, runtime codec probing, or schema/codegen change is added.
- [x] Focused tests, full macOS tests, iPad build, SwiftLint, and diff checks pass. (1866/1866 macOS tests; iPad Pro 11-inch (M5) build; 0 serious lint findings; `git diff --check` clean.)
- [x] iPad simulator initializes the `.m4a` path without `bgmLoadingError` (simfile 67 "Nosferatu" — persisted `BGM/67.m4a`, gameplay mounted with no BGM failure alert). macOS audible smoke waived by maintainer: the byte-level `AVAudioPlayer` gates plus the simulator initialization check cover this pre-release filename-contract change.

## Verification outcome notes (2026-09-07)

- Backend follow-up (outside Virgo): 7 published simfiles (ids 79, 71, 126, 154, 235, 238, 259) advertise chart entries whose `.dtx` objects are missing from R2. Their non-null `fileSizeBytes` resolver throws "DTX chart file not found in R2", null-propagating the whole GraphQL response — catalog refresh fails against the real endpoint on any Virgo build, including `main`. The catalog leg of the iPad smoke ran through a local forwarder that skipped those 7 rows; R2 audio downloads hit the real bucket. Fix on the DTXWeb side by re-uploading the chart files or unpublishing those chart rows.
- iPad smoke downloads across iterations (263, 316, 48, 67) all persisted `.m4a`.
