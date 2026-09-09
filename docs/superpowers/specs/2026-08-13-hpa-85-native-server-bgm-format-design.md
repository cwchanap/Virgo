# HPA-85: Native Server BGM Format Design

**Date:** 2026-08-13
**Status:** Proposed
**Linear:** HPA-85
**Revalidated:** 2026-08-22 against `main` `5d62cc62d50d4bc9f0d483e057e7151571c9c4db`

## Context

Virgo's server-song path still expects OGG even though gameplay uses `AVAudioPlayer` directly from `Song.bgmFilePath`:

```text
GraphQL Simfile.files
        -> SimfileMapper
        -> ServerSongDownloader
        -> ServerSongFileManager
        -> Song.bgmFilePath
        -> AVAudioPlayer(contentsOf:)
```

Latest `main` confirms the useful existing seams are already small:

- `SimfileMapper` owns server BGM availability and R2 URL assembly.
- `ServerSongFileManager` owns local BGM persistence naming.
- `ServerSongCache.refreshCatalog` maps every server DTO through `SimfileMapper`.
- `ServerSongDownloader` only orchestrates mapper URL -> download -> save.
- `ServerSongStatusManager` deletes persisted audio by stored path, not by extension.
- gameplay consumes an arbitrary local path and has no format switch.
- `LocalDTXFixtureImporter` already uses `bgm.m4a` for the bundled fixture.

The GraphQL schema exposes an R2 file listing, not a codec field, so this cutover requires no schema/codegen change. HPA-577 also establishes current-format-only development persistence, so stale `.ogg` rows may be deleted/reset and downloaded again instead of migrated.

## Decision

Use one current server-BGM contract:

```text
Backend media:        AAC audio in MPEG-4/M4A
Server filename:      bgm.m4a
Availability:         Simfile.files lastPathComponent == "bgm.m4a"
Download URL:         {R2_BASE_URL}/{simfileId}/bgm.m4a
Local filename:       Documents/BGM/{simfileId}.m4a
Playback:             existing AVAudioPlayer(contentsOf:) path
```

There is no OGG fallback, client transcode, decoder dependency, migration, or runtime codec probing.

## One source of truth for the filename

The remote filename and local extension should not remain independent literals. Put the contract on the existing `SimfileMapper` type rather than adding a new format abstraction:

```swift
static let bgmFilename = "bgm.m4a"
static var bgmPathExtension: String {
    (bgmFilename as NSString).pathExtension
}
```

`SimfileMapper` uses `bgmFilename` for exact availability matching and URL assembly. `ServerSongFileManager` derives the local extension from `SimfileMapper.bgmPathExtension`.

This is simple deduplication on an existing type, not a new audio-format layer. It removes the two-place contract drift that would otherwise require process rules to keep mapper and persistence changes synchronized.

## Backend readiness gate

A successful URL or filename is not enough. Before client implementation starts, verify both catalog completeness and real media bytes.

### Catalog-wide naming gate

Fetch the complete published catalog through the existing GraphQL `simfiles` operation and inspect `Simfile.files` for every row.

The gate passes only when every simfile that exposes any BGM-shaped file key (`lastPathComponent` beginning with `bgm.`) also exposes `bgm.m4a`.

Record in the implementation PR:

- total published simfiles;
- count with any BGM-shaped key;
- count with `bgm.m4a`;
- mismatch count, which must be zero.

This allows old backend objects to remain physically present when `bgm.m4a` is also published, while preventing the hard client cutover from silently hiding BGM for a partially converted catalog.

### Byte-level playability gate

For one or two representative published `bgm.m4a` objects:

1. download the exact public R2 object;
2. use `afinfo` to confirm MPEG-4/M4A carrying AAC audio;
3. open the local file with `AVAudioPlayer(contentsOf:)`;
4. require `prepareToPlay()` to succeed;
5. record the simfile id/title and results in the implementation PR.

HTTP status or MIME alone is not the gate. If catalog completeness or byte validation fails, fix backend/media ingestion before changing Virgo.

## Runtime diagnostic for backend drift

After cutover, a missing `bgm.m4a` is valid for songs that genuinely have no BGM. The contract mismatch to surface is a row that advertises a `bgm.*` filename but does not expose `bgm.m4a` — i.e. a BGM-bearing simfile the backend has not converted. A legacy `bgm.*` object that coexists with `bgm.m4a` is permitted by the catalog gate and must not warn on every refresh, or it drowns out genuine drift.

In `SimfileMapper.makeServerSong(from:)`, log a warning when a file key has a `lastPathComponent` beginning with `bgm.` and no key equals `bgmFilename`:

```text
Simfile <id> publishes <filename>; expected bgm.m4a
```

The warning is diagnostic only. It does not set `hasBGM`, request a fallback, probe codecs, or change user-facing behavior.

## Client design

### `SimfileMapper`

- expose `bgmFilename` and derived `bgmPathExtension`;
- recognize only exact `bgmFilename` via existing `lastPathComponent` matching;
- assemble R2 URL using the shared filename;
- warn when a `bgm.*` filename exists but `bgm.m4a` does not (coexistence with `bgm.m4a` is silent);
- keep preview `.mp3` unchanged.

The active integration spec currently describes BGM availability as suffix matching; update it to the real exact `lastPathComponent` behavior.

### `ServerSongCache`

The refreshed-catalog fixture is a real consumer of mapper `hasBGM`. Change its current server DTO from `bgm.ogg` to `bgm.m4a` and assert the replacement row has `hasBGM == true`.

Keep local `/tmp/*.ogg` paths where they intentionally model stale development data. Server-key semantics and disposable local-data semantics are different concerns.

### `ServerSongFileManager`

Persist BGM using the shared extension:

```swift
let bgmFilePath = bgmDirectory
    .appendingPathComponent(songId)
    .appendingPathExtension(SimfileMapper.bgmPathExtension)
```

`deleteFiles(forSongId:)` has no production caller; production deletion already uses the persisted path. Delete that dead API and its dedicated test instead of porting another filename copy.

Keep `deleteBGMFile(at:)`, generic `deleteFile(at:)`, and bundle protection unchanged.

### Downloader and gameplay

Keep production logic unchanged.

`ServerSongDownloader` continues:

```text
SimfileMapper.bgmURL(...)
    -> downloadData(...)
    -> ServerSongFileManager.saveBGMFile(...)
    -> Song.bgmFilePath
```

Gameplay continues `AVAudioPlayer(contentsOf: URL(fileURLWithPath: bgmFilePath))`.

## Development-data policy

Old `.ogg` development rows/files are disposable:

- no startup migration;
- no dual-file lookup;
- no legacy cleanup scan;
- no catalog backfill of local paths;
- delete/reset and re-download stale server imports.

Because deletion uses the stored paths, stale `.ogg` files can already be removed without extension-specific compatibility code.

## Verification strategy

Use unit tests for the filename contract and one real smoke for playback:

- mapper: current M4A positive, legacy OGG negative, similar-name negative, URL assembly;
- catalog refresh: current DTO maps to `hasBGM == true`;
- downloader: requests `.m4a` and persists the file-manager result;
- file manager: saves current bytes to `.m4a`; dead song-id deletion API removed;
- GraphQL fixtures: representative current keys use `.m4a`;
- broad `.ogg` audit classifies every remaining source/test occurrence;
- macOS: byte-level `afinfo` + `AVAudioPlayer.prepareToPlay()` preflight on representative `bgm.m4a` objects fetched from R2. The full macOS fresh-download gameplay-mount smoke is waived by the maintainer for this pre-release filename-contract change — the end-to-end fresh-download + gameplay-mount path is exercised on the iPad simulator instead (see iPadOS bullet), and byte-level playability is verified on macOS via the preflight. A filename-only cutover on a natively supported codec (AAC-in-M4A) does not require a separate macOS gameplay-mount pass beyond those two gates.
- iPadOS: build succeeds and an iPad simulator launch confirms the fresh path ends in `.m4a` and gameplay mounts it without `bgmLoadingError`.

No actual-device audibility gate, no macOS fresh-download gameplay smoke, no audible-playback smoke, and no network-dependent CI test are required for this pre-release filename cutover.

## Risks

- **Partial backend cutover:** some songs could lose BGM after the hard client switch. Mitigation: catalog-wide preflight requiring `bgm.m4a` for every BGM-bearing simfile.
- **Future backend drift:** a newly published `bgm.ogg` or other `bgm.*` key could otherwise look like a song with no BGM. Mitigation: mapper warning at the contract boundary.
- **Invalid bytes behind a correct name:** renamed or incorrectly encoded media could still fail playback. Mitigation: `afinfo` plus `AVAudioPlayer` preflight on representative real objects.
- **Stale local development data:** old rows may still point to `.ogg`. Mitigation: current-format-only delete/reset and re-download policy.

## KISS guardrails

- One server BGM format: AAC-in-M4A.
- One shared filename constant on an existing type; no new production format type.
- No OGG decoder, transcode pipeline, fallback, migration, runtime codec probing, or media abstraction.
- No GraphQL schema/codegen change.
- No downloader or gameplay refactor.
- No network-dependent CI test.
- Keep preview `.mp3` untouched.

## Design acceptance criteria

- [ ] One shared `bgm.m4a` filename contract drives both remote URL/availability and local extension.
- [ ] Backend rollout is blocked unless the complete published catalog is M4A-ready and representative bytes pass `afinfo` + `AVAudioPlayer`.
- [ ] A `bgm.*` server key without `bgm.m4a` produces a warning; coexistence with `bgm.m4a` is silent. Never a fallback.
- [ ] Old local `.ogg` data is disposable; no compatibility implementation is added.

The implementation plan owns the executable test/build/smoke checklist.
