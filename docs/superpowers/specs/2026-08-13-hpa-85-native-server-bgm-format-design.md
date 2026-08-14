# HPA-85: Native Server BGM Format Design

**Date:** 2026-08-13  
**Status:** Proposed  
**Linear:** HPA-85

## Context

Virgo's server-song BGM path still uses OGG Vorbis end to end even though gameplay loads BGM with `AVAudioPlayer`:

```text
GraphQL `Simfile.files`
        |
        v
SimfileMapper expects `bgm.ogg`
        |
        v
ServerSongDownloader requests `{R2}/{id}/bgm.ogg`
        |
        v
ServerSongFileManager persists `Documents/BGM/{songId}.ogg`
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

That contract is internally inconsistent. `AVAudioPlayer` is the shipping gameplay BGM player on macOS and iPadOS, while Virgo's own regression guidance already says not to rely on OGG playback through `AVAudioPlayer` and uses `bgm.m4a` for bundled DTX fixtures.

The relevant production seams on current `main` are small:

- `Virgo/utilities/SimfileMapper.swift`
  - maps `hasBGM` by looking for `bgm.ogg` in `Simfile.files`;
  - assembles `{R2}/{id}/bgm.ogg`.
- `Virgo/utilities/ServerSongFileManager.swift`
  - persists downloaded BGM as `Documents/BGM/{songId}.ogg`;
  - `deleteFiles(forSongId:)` targets the same extension.
- `Virgo/utilities/ServerSongDownloader.swift`
  - delegates URL construction to `SimfileMapper` and persistence to `ServerSongFileManager`;
  - does not itself need to know the audio codec.
- `Virgo/viewmodels/GameplayViewModel+BGM.swift`
  - loads the persisted path directly with `AVAudioPlayer(contentsOf:)`.

The GraphQL schema does not encode the BGM filename or codec. `Simfile.files` is an R2 file listing, so switching the R2 object from `bgm.ogg` to `bgm.m4a` does not require a schema or Apollo-codegen change.

HPA-85 predates two important project decisions:

1. The legacy in-repo FastAPI server was retired. The active backend is the separate GraphQL/R2 service described by `docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md`.
2. HPA-577 established a pre-release current-format-only persistence policy. Virgo does not preserve old development representations after breaking format changes; local development data may be reset/reseeded instead of migrated.

This design updates HPA-85 to those current constraints.

## Goals

1. Make freshly downloaded server-song BGM natively playable by Virgo's existing `AVAudioPlayer` path on macOS and iPadOS.
2. Standardize the server BGM object contract on `bgm.m4a`.
3. Persist server BGM locally as `{songId}.m4a`.
4. Keep `ServerSongDownloader` and gameplay audio architecture unchanged.
5. Make the cutover testable at the mapper, file-manager, and downloader seams.
6. Update the GraphQL client integration documentation so code and contract agree.
7. Avoid compatibility, transcoding, codec-library, and media-pipeline infrastructure that Virgo does not need.

## Non-goals

- Supporting OGG playback in `AVAudioPlayer`.
- Adding FFmpeg, libvorbis, VLCKit, or another client-side codec dependency.
- Transcoding OGG to AAC/M4A on macOS or iPad after download.
- Supporting both `bgm.ogg` and `bgm.m4a` indefinitely.
- Migrating persisted development `Song.bgmFilePath` values from `.ogg` to `.m4a`.
- Deleting orphaned legacy `.ogg` files from old development app containers.
- Changing preview audio (`preview.mp3`).
- Changing metronome or SFX sample formats.
- Changing GraphQL schema/codegen merely to expose a BGM URL.
- Reworking `GameplayViewModel` BGM setup, synchronization, rate control, or error UI.
- Reintroducing the retired FastAPI server into Virgo.

## Approaches considered

### 1. Backend/R2 M4A cutover + hard client cutover — selected

The backend publishes `bgm.m4a` for each simfile that has full BGM. Virgo then:

- recognizes `bgm.m4a` in `Simfile.files`;
- requests `{R2}/{id}/bgm.m4a`;
- stores the bytes as `Documents/BGM/{songId}.m4a`;
- continues handing that path to `AVAudioPlayer` exactly as today.

This is the smallest architecture because it aligns the stored format with the playback API instead of adding a conversion layer.

### 2. Client-side transcode after download — rejected

A client transcode would need an OGG-capable decoder before AAC/M4A encoding can even begin. The AVFoundation path Virgo already uses is not an OGG decoder, so this option still implies a new codec dependency or a custom media pipeline. It also adds download latency, temporary storage, failure modes, and platform-specific test work for no product benefit.

### 3. Add an OGG playback/decoder library — rejected

This would make a third-party media dependency part of a hobby app solely to preserve a format the rest of Virgo already avoids. It increases build size and maintenance cost and leaves bundled/server BGM on different policies.

### 4. Prefer M4A but fall back to OGG — rejected

A dual-format fallback is compatibility code. Virgo has no production user base that justifies keeping the broken historical representation alive. It would also make tests and catalog semantics less crisp: `hasBGM` would mean "some format exists" while only one is guaranteed playable by the shipping player.

## Decision

Use one current server-BGM contract:

```text
R2 object name:       bgm.m4a
Catalog availability: Simfile.files contains a last path component exactly equal to `bgm.m4a`
Download URL:         {R2_BASE_URL}/{simfileId}/bgm.m4a
Local filename:       Documents/BGM/{simfileId}.m4a
Playback:             existing AVAudioPlayer(contentsOf:) path
```

There is no OGG compatibility path in the client after this cutover.

## External prerequisite and rollout order

The active GraphQL/R2 backend is outside this Virgo repository. The client implementation must not land before representative published simfiles expose `bgm.m4a` in `Simfile.files` and the corresponding public R2 object is downloadable.

Rollout order:

1. Backend/media ingestion produces AAC-in-M4A BGM as `bgm.m4a` and publishes the R2 object.
2. Confirm at least one representative published simfile exposes a `.../bgm.m4a` file key and the public URL returns the expected audio bytes.
3. Land the Virgo client cutover.
4. Reset/reseed or delete/re-download any stale local development data created under the old `.ogg` contract.
5. Smoke-test a fresh server download into gameplay on macOS and iPadOS.

No GraphQL schema change is required. The existing `files` list already carries arbitrary R2 keys.

If the backend prerequisite is not met, Virgo should remain on the old branch rather than add a temporary client compatibility layer.

## Client design

### 1. `SimfileMapper` owns the remote filename contract

Change only the two BGM-specific literals:

```swift
hasBGM: hasFile(named: "bgm.m4a", in: dto.fileKeys)
```

and:

```swift
static func bgmURL(base: URL, songId: String) -> URL {
    base.appendingPathComponent(songId).appendingPathComponent("bgm.m4a")
}
```

Keep the existing exact-last-path-component behavior. Do not widen it to suffix matching or alternate extensions.

This makes a catalog row report `hasBGM == true` only when the current playable server object exists.

### 2. `ServerSongFileManager` owns the local filename contract

Persist downloaded bytes as:

```text
Documents/BGM/{songId}.m4a
```

Change `saveBGMFile(_:for:)` and `deleteFiles(forSongId:)` to use `.m4a`.

Do not add a format enum or generic media-file abstraction. The current file manager has one server BGM format and one preview format; two direct filenames are easier to maintain than a new type hierarchy.

`deleteBGMFile(at:)` remains path-based and does not need a format change.

### 3. `ServerSongDownloader` remains orchestration-only

No production branch is needed in `ServerSongDownloader`.

Its existing flow already composes the two owning seams correctly:

```text
SimfileMapper.bgmURL(...)
        -> downloader.downloadData(...)
        -> ServerSongFileManager.saveBGMFile(...)
        -> Song.bgmFilePath
```

The implementation should update downloader tests to pin the new URL/path contract, but production downloader logic should remain unchanged unless the tests reveal an actual dependency on `.ogg`.

### 4. Gameplay remains format-agnostic

Do not change `GameplayViewModel.setupBGMPlayer()` for HPA-85.

It should continue to consume `Song.bgmFilePath` and create:

```swift
AVAudioPlayer(contentsOf: URL(fileURLWithPath: bgmFilePath))
```

The fix is to ensure the path points to natively decodable media, not to make gameplay inspect extensions or codecs.

Do not add an extension assertion, codec sniffing, or fallback player. Those would duplicate the server/file-manager contract at the wrong layer.

## Development-data policy

The original HPA-85 ticket required migration/refreshed handling for existing `.ogg` downloads. That requirement is obsolete after HPA-577.

For this pre-release project:

- no startup migration rewrites `.ogg` paths;
- no catalog refresh mutates an existing local `Song` solely to change its BGM extension;
- no dual-file lookup is added;
- stale local development data is reset/reseeded or the downloaded song is deleted and downloaded again after the backend cutover.

This is a breaking local-data change by design.

The implementation PR should state this explicitly so a reviewer does not reintroduce compatibility logic in response to old acceptance text.

## Failure behavior

The existing failure model is sufficient:

- If `Simfile.files` does not contain `bgm.m4a`, `hasBGM` is false and Virgo skips the BGM download.
- If the R2 download fails, `ServerSongDownloader` logs the optional-file failure and imports the playable chart without a BGM path, matching current optional-audio behavior.
- If file persistence fails, the optional-file failure is logged and the chart import continues without a BGM path.
- If a supposedly valid M4A later fails `AVAudioPlayer` setup, existing `bgmLoadingError`/logging handles it; HPA-85 does not need a second error surface.

Do not silently fall back to `bgm.ogg` when the M4A object is absent. That would restore the original bug.

## Tests

### `VirgoTests/SimfileMapperTests.swift`

Update the audio contract tests so they prove:

- `song-1/bgm.m4a` sets `hasBGM == true`;
- `song-1/bgm.ogg` does not set `hasBGM` under the new contract;
- similar names such as `intro-bgm.m4a` still do not match;
- `bgmURL(base:songId:)` returns `.../{id}/bgm.m4a`;
- preview behavior remains `.mp3` and unchanged.

The explicit `.ogg` negative assertion is useful here: it proves this is a hard cutover, not an accidental dual-format compatibility path.

### `VirgoTests/ServerSongFileManagerTests.swift`

Update BGM persistence expectations so:

- `saveBGMFile` returns a path ending in `/BGM/{songId}.m4a`;
- the bytes written to disk remain identical to the downloaded payload;
- `deleteFiles(forSongId:)` removes the `.m4a` BGM and `.mp3` preview;
- generic path deletion and app-bundle protection remain unchanged.

Do not add legacy `.ogg` cleanup tests.

### `VirgoTests/ServerSongDownloaderTests.swift`

Update the existing successful multi-difficulty import test so:

- the mock downloader provides `https://r2.example/multi-diff/bgm.m4a`;
- requested URL order includes `.m4a`;
- the mock file manager returns `/tmp/mock-bgm.m4a`;
- the persisted `Song.bgmFilePath` is `/tmp/mock-bgm.m4a`.

No new downloader abstraction is required. The existing test already spans URL assembly -> optional download -> persisted path.

### Native-playback verification

The unit-test contract above prevents Virgo from regressing back to an OGG path. Final verification still needs one real fresh server-song download because codec playability depends on the actual backend-produced bytes, not just the filename.

Use a representative published song and verify:

1. catalog shows BGM available;
2. download stores a `.m4a` BGM path;
3. gameplay creates the BGM player without `bgmLoadingError`;
4. audio is audible on macOS;
5. the same fresh-download flow works on an iPad simulator/device environment where audio output can be validated.

Do not add a network end-to-end test to CI for this ticket. It would make the unit suite depend on external backend/R2 availability.

## Documentation

Update `docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md` wherever the active integration contract still says:

- full BGM is `.ogg`;
- BGM URL is `{R2_base}/{id}/bgm.ogg`;
- availability checks for `bgm.ogg`;
- binary download examples refer to `.ogg`.

Replace those with `.m4a` and state that the backend publishes natively playable M4A/AAC for Virgo.

`CLAUDE.md` already carries the correct architectural lesson — use a playable path such as `bgm.m4a` and reset/reseed development data after representation changes — so no new compatibility guidance is needed there.

## KISS guardrails

- One server BGM format: `.m4a`.
- One remote filename and one local extension.
- No new production type solely to represent an audio format.
- No codec probing.
- No client transcode pipeline.
- No third-party OGG dependency.
- No migration/backfill/startup repair.
- No dual-format fallback.
- No GraphQL schema/codegen change.
- No gameplay audio refactor.
- No network-dependent CI test.
- Keep preview `.mp3` untouched.

## Acceptance criteria

- [ ] The external backend/R2 contract publishes `bgm.m4a` for representative published simfiles before the Virgo cutover lands.
- [ ] `SimfileMapper` recognizes only `bgm.m4a` as server BGM and assembles the `.m4a` R2 URL.
- [ ] `ServerSongFileManager` persists and deletes server BGM using `{songId}.m4a`.
- [ ] `ServerSongDownloader` requests `.m4a` and persists the returned `.m4a` path without new production branching.
- [ ] `GameplayViewModel` continues using the existing `AVAudioPlayer` path with no codec-specific logic added.
- [ ] Mapper, file-manager, and downloader tests pin the new contract, including an explicit negative check that `.ogg` is no longer accepted as server BGM.
- [ ] The GraphQL integration spec documents `.m4a` instead of `.ogg`.
- [ ] Fresh server-song BGM plays in gameplay on macOS and iPadOS.
- [ ] Old development `.ogg` rows/files are not migrated; reset/re-download is the documented pre-release policy.

## Expected change surface

Production code should remain limited to:

- `Virgo/utilities/SimfileMapper.swift`
- `Virgo/utilities/ServerSongFileManager.swift`

Tests/documentation:

- `VirgoTests/SimfileMapperTests.swift`
- `VirgoTests/ServerSongFileManagerTests.swift`
- `VirgoTests/ServerSongDownloaderTests.swift`
- `docs/superpowers/specs/2026-05-16-simfile-graphql-backend-requirements.md`

`ServerSongDownloader.swift`, GraphQL generated code, SwiftData models, and gameplay code are expected to remain unchanged.