# HPA-85 Native Server BGM Format Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut Virgo's server-song BGM contract from OGG to natively playable M4A/AAC without adding client transcoding, codec dependencies, or compatibility migration.

**Architecture:** The external GraphQL/R2 backend publishes one current BGM object, `bgm.m4a`. Virgo's existing mapper recognizes and assembles that filename, `ServerSongFileManager` persists the downloaded bytes as `{songId}.m4a`, and the existing `ServerSongDownloader` -> `Song.bgmFilePath` -> `AVAudioPlayer` flow remains intact. Old `.ogg` development data is intentionally reset/re-downloaded rather than migrated.

**Tech Stack:** Swift 6, SwiftUI/SwiftData, Foundation `URLSession` download seam, AVFoundation `AVAudioPlayer`, Swift Testing, GraphQL catalog DTOs backed by Cloudflare R2.

## Global Constraints

- Supported Apple targets remain macOS 14.0+ and iPadOS; do not add iPhone targeting.
- The external backend/R2 must publish `bgm.m4a` before the Virgo client cutover lands.
- The current server BGM filename is exactly `bgm.m4a`; do not support `bgm.ogg` as a fallback.
- Do not add FFmpeg, libvorbis, VLCKit, or any new client-side codec/transcode dependency.
- Do not add startup migration, path backfill, dual-file lookup, or legacy `.ogg` cleanup.
- Do not change preview `.mp3`, metronome/SFX audio, GraphQL schema/codegen, or gameplay BGM synchronization.
- Keep `ServerSongDownloader.swift` production logic unchanged unless a focused regression test proves a real dependency on the old extension.
- Use Swift Testing (`import Testing`, `#expect`) and run tests with parallel testing disabled.

---

## Pre-implementation gate: backend/R2 is ready

This repository does not own the active backend ingestion/storage code. Before Task 1 is merged, verify outside Virgo that at least one representative published simfile satisfies both conditions:

```text
Simfile.files contains: <simfile-id>/bgm.m4a
GET {R2_BASE_URL}/<simfile-id>/bgm.m4a -> successful M4A/AAC audio response
```

Do not work around a missing backend cutover by adding an OGG fallback in Virgo. If this gate is not satisfied, stop the implementation after the documentation/planning PR and complete the backend media conversion first.

## File map

### Production files

- `Virgo/utilities/SimfileMapper.swift`
  - Owns server BGM availability detection and R2 URL assembly.
- `Virgo/utilities/ServerSongFileManager.swift`
  - Owns local downloaded BGM filename and song-id cleanup path.

### Regression tests

- `VirgoTests/SimfileMapperTests.swift`
  - Pins exact `bgm.m4a` catalog-key and URL semantics and rejects legacy OGG.
- `VirgoTests/ServerSongFileManagerTests.swift`
  - Pins `.m4a` persistence/deletion while preserving byte identity and bundle guards.
- `VirgoTests/ServerSongDownloaderTests.swift`
  - Pins the composed download URL and persisted path used by imported server songs.

### Documentation

- `docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md`
  - Active GraphQL/R2 client integration contract; replace old `.ogg` wording with `.m4a`.

No new production file or type is planned.

---

### Task 1: Cut the remote server-BGM contract to `bgm.m4a`

**Files:**
- Modify: `VirgoTests/SimfileMapperTests.swift`
- Modify: `VirgoTests/ServerSongDownloaderTests.swift`
- Modify: `Virgo/utilities/SimfileMapper.swift`

**Interfaces:**
- Consumes: `SimfileDTO.fileKeys: [String]`, `SimfileMapper.makeServerSong(from:)`, `SimfileMapper.bgmURL(base:songId:)`.
- Produces: exact remote contract `bgm.m4a`; `ServerSong.hasBGM == true` only for that filename; R2 BGM URL ending in `/bgm.m4a`.

- [ ] **Step 1: Update `SimfileMapperTests` to describe the hard cutover**

Replace the current OGG positive fixture with M4A and add an explicit OGG negative assertion:

```swift
@Test("Audio availability comes from current file keys (exact lastPathComponent match)")
func testAudioAvailability() {
    let withBoth = SimfileMapper.makeServerSong(
        from: sampleDTO(fileKeys: ["song-1/bgm.m4a", "song-1/preview.mp3"]))
    #expect(withBoth.hasBGM == true)
    #expect(withBoth.hasPreview == true)

    let legacyOGG = SimfileMapper.makeServerSong(
        from: sampleDTO(fileKeys: ["song-1/bgm.ogg", "song-1/preview.mp3"]))
    #expect(legacyOGG.hasBGM == false)
    #expect(legacyOGG.hasPreview == true)

    let withNone = SimfileMapper.makeServerSong(
        from: sampleDTO(fileKeys: ["song-1/ext.dtx"]))
    #expect(withNone.hasBGM == false)
    #expect(withNone.hasPreview == false)

    let withSimilar = SimfileMapper.makeServerSong(
        from: sampleDTO(fileKeys: ["song-1/intro-bgm.m4a", "song-1/demo-preview.mp3"]))
    #expect(withSimilar.hasBGM == false)
    #expect(withSimilar.hasPreview == false)
}
```

Update the BGM URL assertion:

```swift
#expect(
    SimfileMapper.bgmURL(base: base, songId: "song-1")
        == URL(string: "https://r2.example/bucket/song-1/bgm.m4a")
)
```

Keep the preview assertion at `preview.mp3`.

- [ ] **Step 2: Update the downloader integration test to expect M4A from the mapper**

In `MockServerSongFileManager`, change only the mock BGM path:

```swift
var bgmPathToReturn = "/tmp/mock-bgm.m4a"
```

In `testDownloadAndImportSongMapsDifficultiesAndDownloadsOptionalFiles`, seed the response at:

```swift
mock.responses["\(r2Base)/multi-diff/bgm.m4a"] = Data([0x10, 0x11, 0x12])
```

and change the persisted-path assertion to:

```swift
#expect(importedSong?.bgmFilePath == "/tmp/mock-bgm.m4a")
```

and the requested URL sequence to contain:

```swift
"\(r2Base)/multi-diff/bgm.m4a"
```

Do not change chart or preview URLs.

- [ ] **Step 3: Run the focused tests and verify they fail against the old mapper**

Run:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/SimfileMapperTests \
  -only-testing:VirgoTests/ServerSongDownloaderTests \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

Expected failures before the production edit:

- the M4A catalog key does not set `hasBGM`;
- the OGG key still sets `hasBGM`;
- `bgmURL` still ends in `/bgm.ogg`;
- the downloader test requests `/bgm.ogg` instead of the seeded `/bgm.m4a` response.

- [ ] **Step 4: Make the minimal `SimfileMapper` production change**

Change the BGM availability literal in `makeServerSong(from:)`:

```swift
hasBGM: hasFile(named: "bgm.m4a", in: dto.fileKeys),
```

Change `bgmURL(base:songId:)`:

```swift
static func bgmURL(base: URL, songId: String) -> URL {
    base.appendingPathComponent(songId).appendingPathComponent("bgm.m4a")
}
```

Do not add an audio-format enum, alternate extension array, or fallback request.

- [ ] **Step 5: Re-run the focused tests**

Run the same `xcodebuild test` command from Step 3.

Expected: `SimfileMapperTests` and `ServerSongDownloaderTests` pass. The downloader's production source should have no diff; the new behavior comes through the mapper seam.

- [ ] **Step 6: Confirm `ServerSongDownloader.swift` stayed unchanged**

Run:

```bash
git diff --exit-code main...HEAD -- Virgo/utilities/ServerSongDownloader.swift
```

Expected: exit 0 and no diff.

If this file changed only to mention `.m4a`, revert that change. The codec/filename contract belongs in the mapper and file manager.

- [ ] **Step 7: Commit Task 1**

```bash
git add \
  Virgo/utilities/SimfileMapper.swift \
  VirgoTests/SimfileMapperTests.swift \
  VirgoTests/ServerSongDownloaderTests.swift
git commit -m "fix: request native server BGM"
```

---

### Task 2: Persist server BGM as `{songId}.m4a`

**Files:**
- Modify: `VirgoTests/ServerSongFileManagerTests.swift`
- Modify: `Virgo/utilities/ServerSongFileManager.swift`

**Interfaces:**
- Consumes: `ServerSongFileManager.saveBGMFile(_:for:)`, `deleteFiles(forSongId:)`.
- Produces: local BGM path `Documents/BGM/{songId}.m4a`; deletion targets the same current filename.

- [ ] **Step 1: Update the file-manager tests to require `.m4a`**

In `testSaveAndDeleteBGMFile`, change the path expectation to:

```swift
#expect(savedPath.hasSuffix("/BGM/\(songId).m4a"))
```

Leave the payload round-trip assertion unchanged:

```swift
let loadedData = try Data(contentsOf: URL(fileURLWithPath: savedPath))
#expect(loadedData == payload)
```

In `testDeleteOnNonExistentPaths`, use an M4A-shaped missing BGM path:

```swift
fileManager.deleteBGMFile(at: missingBase.appendingPathComponent("bgm.m4a").path)
```

The existing `testDeleteBySongId` should continue to save through `saveBGMFile`, then prove `deleteFiles(forSongId:)` removes the returned path. Do not add a test that deletes a legacy `.ogg` sibling.

In `testIsPathInsideBundle`, update the outside-bundle example to the current local contract:

```swift
#expect(!ServerSongFileManager.isPath(
    "/Users/u/Documents/BGM/song.m4a", inside: bundleRoot))
```

- [ ] **Step 2: Run the focused file-manager suite and verify the old extension fails**

Run:

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

Expected before the production edit: `testSaveAndDeleteBGMFile` fails because the returned path ends in `.ogg`; `testDeleteBySongId` may also expose that cleanup still targets the old extension depending on execution order.

- [ ] **Step 3: Change the local BGM filename in `saveBGMFile`**

Replace:

```swift
let bgmFilePath = bgmDirectory.appendingPathComponent("\(songId).ogg")
```

with:

```swift
let bgmFilePath = bgmDirectory.appendingPathComponent("\(songId).m4a")
```

Do not transform the bytes. The backend has already produced the correct media container/codec.

- [ ] **Step 4: Change song-id cleanup to the same current extension**

In `deleteFiles(forSongId:)`, replace the BGM path with:

```swift
let bgm = documents
    .appendingPathComponent("BGM")
    .appendingPathComponent("\(songId).m4a")
```

Keep preview cleanup at `.mp3`.

Do not probe for or delete `\(songId).ogg` as a fallback.

- [ ] **Step 5: Re-run the focused file-manager suite**

Run the command from Step 2.

Expected: all `ServerSongFileManagerTests` pass.

- [ ] **Step 6: Audit production code for legacy server-BGM literals**

Run:

```bash
git grep -n 'bgm\.ogg' -- \
  Virgo/utilities/SimfileMapper.swift \
  Virgo/utilities/ServerSongFileManager.swift \
  Virgo/utilities/ServerSongDownloader.swift
```

Expected: no matches.

This audit is deliberately scoped to the server-song pipeline. Do not convert unrelated fixture/SFX references merely because they contain `.ogg`.

- [ ] **Step 7: Commit Task 2**

```bash
git add \
  Virgo/utilities/ServerSongFileManager.swift \
  VirgoTests/ServerSongFileManagerTests.swift
git commit -m "fix: persist server BGM as m4a"
```

---

### Task 3: Update the active GraphQL/R2 integration contract

**Files:**
- Modify: `docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md`

**Interfaces:**
- Consumes: the code contract completed by Tasks 1-2.
- Produces: one documented server BGM contract: `bgm.m4a` / M4A-AAC.

- [ ] **Step 1: Replace the obsolete `.ogg` contract statements**

Update the integration spec so all active server-BGM references say:

```text
BGM object: {R2_base}/{id}/bgm.m4a
Availability: Simfile.files contains lastPathComponent == "bgm.m4a"
Local use: downloaded bytes are persisted as a native-playable `.m4a` path for AVAudioPlayer
```

At minimum update:

- Goals/non-goals where full BGM download is described;
- File delivery contract;
- Audio URL assembly and availability;
- Caching/refresh binary examples;
- Architecture/implementation approach;
- field-consumption map rows that currently name `bgm.ogg`.

Do not change `DtxFile.fileUrl`, `preview.mp3`, GraphQL types, pagination, or cache-refresh semantics.

- [ ] **Step 2: State the backend responsibility directly**

Add one concise sentence in the audio-delivery section:

```markdown
The backend/media-ingestion path publishes Virgo BGM as M4A/AAC (`bgm.m4a`); the client does not transcode or decode OGG.
```

Do not document dual-format fallback.

- [ ] **Step 3: Check the active integration spec for contradictory server-BGM references**

Run:

```bash
git grep -n 'bgm\.ogg' -- docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md
```

Expected: no active-contract matches. Historical prose should also be updated when it would mislead a future implementer; this document identifies itself as the current client integration spec, not an immutable historical record.

Then run:

```bash
git grep -n 'bgm\.m4a' -- docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md
```

Expected: the file-delivery, URL-assembly, availability, and field-map sections contain M4A references.

- [ ] **Step 4: Commit Task 3**

```bash
git add docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md
git commit -m "docs: update server BGM contract to m4a"
```

---

### Task 4: Verify the complete fresh-download path and breaking-data policy

**Files:**
- Verify only: `Virgo/utilities/SimfileMapper.swift`
- Verify only: `Virgo/utilities/ServerSongFileManager.swift`
- Verify only: `Virgo/utilities/ServerSongDownloader.swift`
- Verify only: `Virgo/viewmodels/GameplayViewModel+BGM.swift`
- Verify only: focused/full test targets and documentation changed above

**Interfaces:**
- Consumes: backend/R2 `bgm.m4a`, completed Virgo client cutover.
- Produces: evidence that fresh server downloads persist a native BGM path and gameplay consumes it without codec-specific changes.

- [ ] **Step 1: Run the three focused regression suites together**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/SimfileMapperTests \
  -only-testing:VirgoTests/ServerSongFileManagerTests \
  -only-testing:VirgoTests/ServerSongDownloaderTests \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all selected tests pass.

- [ ] **Step 2: Run the complete macOS unit suite**

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

Expected: unit suite passes with only already-documented expected/known issues, if any.

- [ ] **Step 3: Build the iPad target**

Use an available iPad simulator destination, never iPhone. Example when present:

```bash
xcodebuild \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' \
  build
```

Expected: build succeeds. If that exact simulator is unavailable, select another installed iPad simulator and record the actual destination in the PR.

- [ ] **Step 4: Run SwiftLint and whitespace checks**

```bash
swiftlint lint
git diff --check main...HEAD
```

Expected: no SwiftLint errors and no whitespace errors. Existing warning-level size debt is not a reason to refactor unrelated files.

- [ ] **Step 5: Prove there is no compatibility implementation**

Run:

```bash
git grep -n 'bgm\.ogg' -- Virgo VirgoTests
```

Classify every remaining match. Expected server-song result:

- no `.ogg` match in `SimfileMapper.swift`;
- no `.ogg` match in `ServerSongFileManager.swift`;
- no `.ogg` mock/expectation in `ServerSongDownloaderTests.swift` except the intentional `SimfileMapperTests` negative assertion proving legacy OGG is rejected;
- unrelated metronome/SFX/fixture references may remain and are out of scope.

Also confirm no new code contains terms such as `legacyBGM`, `migrateBGM`, `transcode`, `oggFallback`, or alternate-extension loops.

- [ ] **Step 6: Reset stale development data before the real smoke**

Use Virgo's normal development reset/reseed flow or delete the previously downloaded server song so the smoke starts from a fresh `Song` row. Do not hand-edit an old `.ogg` `bgmFilePath` into `.m4a`; that would not prove the new download path.

- [ ] **Step 7: Smoke-test a fresh published server song on macOS**

With the backend prerequisite satisfied:

1. refresh the server catalog;
2. choose a published song whose `Simfile.files` contains `bgm.m4a`;
3. download/import it;
4. confirm the persisted BGM path ends in `.m4a`;
5. open gameplay;
6. confirm no BGM loading error is shown/logged;
7. start playback and confirm BGM is audible and remains synchronized through the existing gameplay controls.

Record the representative simfile id/title in the implementation PR verification notes.

- [ ] **Step 8: Smoke-test the same fresh-download contract on iPadOS**

Repeat the fresh-download -> gameplay path on an iPad simulator/device environment with working audio output. Confirm the same `.m4a` path is used and `AVAudioPlayer` initializes successfully.

If the simulator environment cannot validate audible output, record that limitation and verify player initialization plus an actual-device smoke before marking HPA-85 done. Do not replace this with a network-dependent CI test.

- [ ] **Step 9: Review the final diff for scope**

Expected production diff:

```text
Virgo/utilities/SimfileMapper.swift
Virgo/utilities/ServerSongFileManager.swift
```

Expected supporting diff:

```text
VirgoTests/SimfileMapperTests.swift
VirgoTests/ServerSongFileManagerTests.swift
VirgoTests/ServerSongDownloaderTests.swift
docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md
```

No GraphQL generated files, SwiftData models, gameplay implementation, audio engine, dependency manifest, or migration helper should be necessary.

- [ ] **Step 10: Commit any final verification-only documentation correction**

Only if Task 4 uncovered an inaccurate documentation statement:

```bash
git add docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md
git commit -m "docs: clarify native server BGM verification"
```

If no correction is needed, do not create an empty verification commit.

---

## Completion checklist

- [ ] Backend/R2 exposes a real playable `bgm.m4a` before client rollout.
- [ ] Mapper recognizes only `bgm.m4a` and assembles the M4A URL.
- [ ] File manager persists/deletes `{songId}.m4a`.
- [ ] Downloader production logic remains orchestration-only.
- [ ] Gameplay production logic remains format-agnostic and unchanged.
- [ ] Unit tests explicitly reject legacy server `bgm.ogg` availability.
- [ ] Active GraphQL integration documentation says `.m4a` everywhere relevant.
- [ ] No migration, fallback, codec dependency, or client transcode was added.
- [ ] Focused tests, full macOS tests, iPad build, SwiftLint, and diff checks pass.
- [ ] Fresh server download reaches audible/initialized gameplay BGM on macOS and iPadOS.
