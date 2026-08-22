# HPA-85: Native Server BGM Format Design

**Date:** 2026-08-13  
**Status:** Proposed  
**Linear:** HPA-85  
**Revalidated:** 2026-08-22 against `main` `5d62cc62d50d4bc9f0d483e057e7151571c9c4db`

## Context

Virgo's server-song BGM path still uses OGG naming end to end even though gameplay loads BGM with `AVAudioPlayer`:

```text
GraphQL Simfile.files
        |
        v
SimfileMapper expects bgm.ogg
        |
        v
ServerSongDownloader requests {R2}/{id}/bgm.ogg
        |
        v
ServerSongFileManager persists Documents/BGM/{songId}.ogg
        |
        v
Song.bgmFilePath
        |
        v
GameplayViewModel.setupBGMPlayer()
        |
        v
AVAudioPlayer(contentsOf:)
```

Latest `main` still has these small ownership seams:

- `SimfileMapper` owns server BGM availability detection and R2 URL assembly.
- `ServerSongFileManager` owns local downloaded BGM naming and song-id cleanup.
- `ServerSongDownloader` composes mapper URL -> raw download -> file-manager persistence without codec-specific logic.
- `ServerSongCache.refreshCatalog` maps every fetched DTO through `SimfileMapper.makeServerSong`, so catalog `hasBGM` is a real downstream consumer of the mapper contract.
- `GameplayViewModel+BGM` consumes `Song.bgmFilePath` directly with `AVAudioPlayer(contentsOf:)` and does not switch on extensions.
- `LocalDTXFixtureImporter` already resolves bundled BGM as `bgm.m4a`.

The GraphQL schema does not encode the BGM filename or codec. `Simfile.files` is an R2 file listing, so switching from `bgm.ogg` to `bgm.m4a` requires no GraphQL schema or Apollo-codegen change.

HPA-577 also established Virgo's pre-release current-format-only persistence policy: stale development representations may be reset/reseeded rather than migrated. HPA-85 should follow that policy rather than adding `.ogg` compatibility machinery.

## Goals

1. Make freshly downloaded server-song BGM playable by the existing `AVAudioPlayer` path on macOS and iPadOS.
2. Standardize backend publication on AAC-in-M4A named `bgm.m4a`.
3. Make `SimfileMapper` recognize/request only `bgm.m4a`.
4. Persist server BGM locally as `{songId}.m4a`.
5. Keep downloader and gameplay production logic unchanged.
6. Pin the contract at mapper, catalog-consumer, downloader, and file-manager seams.
7. Keep implementation small: no codec/transcode/migration framework.

## Non-goals

- Supporting OGG playback in Virgo.
- Adding FFmpeg, libvorbis, VLCKit, or another decoder.
- Transcoding on macOS/iPadOS after download.
- Runtime codec/container probing in the client.
- Supporting both `bgm.ogg` and `bgm.m4a`.
- Migrating persisted development `.ogg` paths.
- Deleting orphaned legacy `.ogg` files from old development containers.
- Changing preview `.mp3`, metronome, or SFX formats.
- Changing GraphQL schema/codegen.
- Reworking gameplay BGM setup, synchronization, rate control, or error UI.
- Adding a network-dependent CI test.

## Decision

Use one current server-BGM contract:

```text
Backend media:        AAC audio in an MPEG-4/M4A container
R2 object name:       bgm.m4a
Catalog availability: Simfile.files lastPathComponent == "bgm.m4a"
Download URL:         {R2_BASE_URL}/{simfileId}/bgm.m4a
Local filename:       Documents/BGM/{simfileId}.m4a
Playback:             existing AVAudioPlayer(contentsOf:) path
```

There is no OGG compatibility path after the cutover.

## Why this architecture

The fix belongs at the two filename-contract owners, not in playback:

- `SimfileMapper` already owns the remote filename.
- `ServerSongFileManager` already owns the local filename.
- `ServerSongDownloader` already composes those two seams.
- Gameplay already accepts an arbitrary local path and should remain format-agnostic.

A format enum, media abstraction, decoder, transcode pipeline, or fallback array would add machinery for a single supported BGM format and would not improve the product.

## Backend readiness is a hard gate

A filename or successful HTTP response does not prove that the backend produced playable media. The original bug is about the bytes that reach `AVAudioPlayer`, so the rollout gate must verify those bytes before the client cutover begins.

For at least one representative published simfile:

1. `Simfile.files` exposes `<id>/bgm.m4a`.
2. Download the exact R2 object to a local file.
3. Inspect it with `afinfo`; it must be an MPEG-4/M4A container containing AAC audio.
4. Open that local file with `AVAudioPlayer(contentsOf:)`; initialization and `prepareToPlay()` must succeed.
5. Record the simfile id/title plus the media-inspection and AVAudioPlayer results in the implementation PR.

An HTTP `200`, filename, or MIME value alone is insufficient. If the bytes fail the gate, fix backend/media ingestion before changing Virgo. Do not add fallback/transcode behavior to compensate.

This validation is a rollout check, not production codec-probing code.

## Atomic client cutover

The remote and local filename changes are logically one shipping unit.

A mapper-only state would request M4A bytes while `ServerSongFileManager` still writes them as `{songId}.ogg`. That intermediate state is not an acceptable release state because it can recreate the same class of playback failure the ticket is meant to remove.

Therefore:

- the implementation is one PR;
- mapper and file-manager work may use separate commits for TDD/review;
- neither commit may be merged, cherry-picked, or released independently;
- the implementation PR is not mergeable until both remote and local contracts are `.m4a` and the combined focused suites pass.

No additional transaction/framework is needed; this is a PR/release boundary, not runtime coordination.

## Client design

### 1. `SimfileMapper` owns the remote contract

Change the two BGM-specific literals only:

```swift
hasBGM: hasFile(named: "bgm.m4a", in: dto.fileKeys)
```

```swift
static func bgmURL(base: URL, songId: String) -> URL {
    base.appendingPathComponent(songId).appendingPathComponent("bgm.m4a")
}
```

Keep exact last-path-component matching. Do not widen this to suffix matching or alternate extensions.

The active GraphQL integration spec currently describes this as a suffix match; implementation should correct that documentation to match the existing exact `lastPathComponent` behavior.

### 2. Pin `ServerSongCache` as the real `hasBGM` consumer

`ServerSongCache.refreshCatalog` maps every DTO through `SimfileMapper.makeServerSong`. The current replacement fixture uses server `fileKeys: ["bgm.ogg", "preview.mp3"]` but does not assert `hasBGM`, so the suite could remain green after the mapper cutover while silently losing catalog BGM availability.

Update the **current server DTO** fixture to:

```swift
fileKeys: ["bgm.m4a", "preview.mp3"]
```

and assert the replacement row has BGM:

```swift
#expect(byID["a"]?.hasBGM == true)
```

Keep local persisted paths such as `/tmp/a.ogg` where the test intentionally models stale development data. Current server-key semantics and stale local-data semantics are different concerns.

### 3. `ServerSongFileManager` owns the local contract

Persist downloaded bytes as:

```text
Documents/BGM/{songId}.m4a
```

Change `saveBGMFile(_:for:)` and `deleteFiles(forSongId:)` to use `.m4a`.

Do not transcode the bytes. The backend gate guarantees that the downloaded media is already AAC-in-M4A.

`deleteBGMFile(at:)` remains path-based and unchanged.

### 4. `ServerSongDownloader` remains orchestration-only

No production branch is needed in `ServerSongDownloader`:

```text
SimfileMapper.bgmURL(...)
        -> downloader.downloadData(...)
        -> ServerSongFileManager.saveBGMFile(...)
        -> Song.bgmFilePath
```

Update its existing regression test to expect the new URL/path, but do not make production downloader code inspect extensions or codecs.

### 5. Gameplay remains format-agnostic

Do not change `GameplayViewModel.setupBGMPlayer()`.

It should continue to create the player from the persisted path:

```swift
AVAudioPlayer(contentsOf: URL(fileURLWithPath: bgmFilePath))
```

The fix is to ensure that path points at media known to be playable, not to duplicate the format contract in gameplay.

## Development-data policy

Old `.ogg` development rows/files are disposable under HPA-577's current-format-only policy:

- no startup migration rewrites `.ogg` paths;
- no catalog refresh backfills local BGM paths;
- no dual-file lookup is added;
- no broad `.ogg` cleanup is added;
- delete/reset and re-download stale server imports after the backend/client cutover.

Existing deletion already uses the persisted file paths, so stale rows can be removed without a special legacy-extension cleanup path.

## Failure behavior

The existing failure model remains sufficient:

- no `bgm.m4a` key -> `hasBGM == false`, so optional BGM download is skipped;
- R2 download failure -> chart import continues without BGM, as today;
- persistence failure -> chart import continues without BGM, as today;
- unexpected playback failure -> existing `bgmLoadingError`/logging surfaces it.

Do not silently request `bgm.ogg` when M4A is absent.

## Tests

### Mapper

`SimfileMapperTests` should prove:

- `bgm.m4a` -> `hasBGM == true`;
- `bgm.ogg` -> `hasBGM == false`;
- `intro-bgm.m4a` does not match;
- assembled BGM URL ends in `/bgm.m4a`;
- preview remains `.mp3`.

### Catalog consumer

`ServerSongCatalogRefreshTests` should use `bgm.m4a` in the refreshed/current DTO and assert the resulting cached row has `hasBGM == true`.

Keep intentional stale local `/tmp/*.ogg` path fixtures when they are testing current-format-only local-data preservation/status projection rather than server-key semantics.

### File manager

`ServerSongFileManagerTests` should prove:

- saved BGM path ends in `/BGM/{songId}.m4a`;
- downloaded bytes are preserved exactly;
- song-id deletion removes current `.m4a` BGM and `.mp3` preview;
- generic path deletion and bundle protection remain unchanged.

No legacy `.ogg` cleanup test is needed.

### Downloader

`ServerSongDownloaderTests` should prove:

- optional BGM request is `.../bgm.m4a`;
- mock file manager returns an `.m4a` path;
- imported `Song.bgmFilePath` receives that path.

`ServerSongDownloaderTests` should contain no `bgm.ogg` expectation after the cutover.

### Representative GraphQL fixtures

`ApolloSimfileClientTests` and `GraphQLQuerySchemaTests` may be updated later in the same implementation PR so representative current R2 keys use `bgm.m4a`. These tests do not drive `SimfileMapper`, so they are fixture hygiene rather than part of the red/green mapper checkpoint.

## Native-playback verification

The pre-implementation gate proves backend-produced media can be opened by the shipping API before client work begins. Final smoke still verifies the full fresh-download path after the client cutover:

1. refreshed catalog reports BGM available;
2. download persists a `.m4a` path;
3. gameplay creates the BGM player without `bgmLoadingError`;
4. audio is audible on macOS;
5. the same fresh-download flow initializes/plays on iPadOS.

Do not add a network end-to-end test to CI.

## Documentation

Update `docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md` so the active contract says:

- BGM is AAC-in-M4A (`bgm.m4a`);
- BGM URL is `{R2_base}/{id}/bgm.m4a`;
- availability uses exact `lastPathComponent == "bgm.m4a"`, not suffix matching;
- binary examples use `.m4a`;
- backend media ingestion owns conversion/publication; Virgo does not transcode or decode OGG.

Do not change GraphQL types, codegen, pagination, or preview `.mp3`.

## KISS guardrails

- One server BGM format: `.m4a`.
- One remote filename and one local extension.
- One implementation PR for both filename cutovers.
- No new production type solely to represent audio format.
- No runtime codec probing.
- No client transcode pipeline.
- No third-party OGG dependency.
- No migration/backfill/startup repair.
- No dual-format fallback.
- No GraphQL schema/codegen change.
- No gameplay audio refactor.
- No network-dependent CI test.
- Keep preview `.mp3` untouched.

## Acceptance criteria

- [ ] Before client work, one representative published `bgm.m4a` is downloaded and `afinfo` confirms AAC-in-M4A.
- [ ] Before client work, that same downloaded object initializes and prepares successfully with `AVAudioPlayer(contentsOf:)`.
- [ ] Mapper and file-manager cutovers are delivered in one implementation PR and are never shipped independently.
- [ ] `SimfileMapper` recognizes only `bgm.m4a` and assembles the `.m4a` R2 URL.
- [ ] Catalog refresh coverage asserts that a current `bgm.m4a` DTO maps to `hasBGM == true`.
- [ ] `ServerSongFileManager` persists and deletes `{songId}.m4a`.
- [ ] `ServerSongDownloader` production logic remains unchanged and format-agnostic.
- [ ] Gameplay continues using the existing `AVAudioPlayer` path with no codec-specific logic.
- [ ] Mapper tests explicitly reject legacy `bgm.ogg`.
- [ ] Downloader tests contain no `bgm.ogg` expectations.
- [ ] Representative current GraphQL/catalog keys use `bgm.m4a`; intentional stale local `.ogg` fixtures remain only where semantically required.
- [ ] The active GraphQL integration spec documents `.m4a` and exact `lastPathComponent` matching.
- [ ] Fresh server-song BGM reaches gameplay successfully on macOS and iPadOS.
- [ ] Old development `.ogg` rows/files are not migrated; reset/delete-and-redownload is the policy.

## Expected change surface

Production code remains limited to:

- `Virgo/utilities/SimfileMapper.swift`
- `Virgo/utilities/ServerSongFileManager.swift`

Supporting tests/docs may include:

- `VirgoTests/SimfileMapperTests.swift`
- `VirgoTests/ServerSongCatalogRefreshTests.swift`
- `VirgoTests/ServerSongFileManagerTests.swift`
- `VirgoTests/ServerSongDownloaderTests.swift`
- `VirgoTests/ApolloSimfileClientTests.swift`
- `VirgoTests/GraphQLQuerySchemaTests.swift`
- `docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md`

`ServerSongDownloader.swift`, GraphQL generated code, SwiftData models, gameplay implementation, audio engine, and dependency manifests are expected to remain unchanged.
