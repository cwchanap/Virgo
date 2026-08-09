# HPA-576: Preview Playback Identity and Request Safety

**Date:** 2026-08-08<br>
**Status:** Approved design — implementation not started

## Context

`AudioPlaybackService` owns short preview playback for downloaded server songs. Its current state machine uses `Song.title` as both the active-selection identity and the audio-cache key. That creates correctness bugs when two distinct songs share a title: they can be treated as the same selection and can reuse the wrong cached `AVAudioPlayer`.

The service also launches asynchronous player creation without a request identity. A load that finishes after the user selects another song, stops playback, or starts a newer request can still reach the completion/error path. The current title check prevents some stale state mutation, but it does not make the whole completion atomic: stale work can still cache a player, and a stale failure can still reach iOS audio-session cleanup. Delayed `AVAudioPlayerDelegate` callbacks also ignore the callback player today, so an obsolete player can stop, pause, or resume newer playback.

Playback publication is optimistic in several places. `togglePlayback(for:)` and `loadAndPlayPreview(song:previewPath:)` set `isPlaying = true` before `AVAudioPlayer.play()` succeeds, while `resume()` sets `isPlaying = true` even when there is no installed player or `play()` returns `false`. `startProgressTimer()` also creates a timer without first invalidating an existing one.

HPA-576 is intentionally a local correctness fix. It should make the existing preview player deterministic without becoming a media subsystem redesign.

## Goal

Make preview playback identity-safe and stale-request-safe so the published service state describes the currently installed, successfully playing song preview.

## Non-goals

- Do not replace `AVAudioPlayer` with `AVAudioEngine`.
- Do not introduce a media repository, playback coordinator, actor hierarchy, cache type, or protocol per audio operation.
- Do not move general DTX/file work off the main actor; HPA-579/HPA-580 own evidence-based performance decisions.
- Do not solve server BGM format compatibility; HPA-85 remains the `.ogg`/native-playback issue.
- Do not add a loading spinner, pending-playback UI, or redesign downloaded-song controls.
- Do not introduce persistence or migration for preview playback state.
- Do not change the existing ten-entry FIFO cache policy to LRU.

## Design

### 1. Reuse Virgo's existing song-identity convention

The active preview selection must use SwiftData identity, not display text. `PlaybackService` already exposes:

```swift
@Published var currentlyPlaying: PersistentIdentifier?
```

and compares it with `song.id`. `AudioPlaybackService` should use the same public shape:

```swift
@Published var currentlyPlaying: PersistentIdentifier?
```

`DownloadedSongsView.isPlaying(_:)` will compare `audioPlaybackService.currentlyPlaying == song.id` for preview-backed rows. The regular `PlaybackService` path remains unchanged.

Paused playback keeps `currentlyPlaying` so selecting the same row can resume the installed player. `stop()`, a failed start, or replacement by another song clears it. A preview that is still loading is not published as playing.

This deliberately removes the current instant play-row highlight while a local preview file is still being opened. Truthful playback state is preferred over publishing a fake playing glyph before `AVAudioPlayer.play()` succeeds. Preview files are already local, so HPA-576 accepts that small feedback delay. If real usage later shows the delay matters, add a separately modeled pending selection then; do not add it speculatively here.

### 2. Keep cache identity tied to the audio resource

The reusable player cache has a different identity concern from UI selection. Keep the existing dictionary/FIFO implementation, but key `audioCache` and `audioCacheOrder` by the canonical preview resource path:

```swift
URL(fileURLWithPath: previewPath).standardizedFileURL.path
```

Do not add a cache wrapper or new cache model. The existing ten-entry FIFO policy is sufficient.

A successfully loaded/prepared player may enter the cache before the actual `play()` attempt. If `startPlayback(player)` then returns `false`, clear the active service state but retain that cached player, matching today's cache behavior. A failed `play()` can be transient and does not prove the decoded resource is invalid. HPA-576 does not add an eviction/reload-on-start-failure rule.

### 3. Add one minimal deterministic player-loader seam

Keep the existing `startPlayback: (AVAudioPlayer) -> Bool` injection and add one initializer dependency for player creation:

```swift
loadPlayer: @escaping @MainActor (URL) async throws -> AVAudioPlayer
```

Its default implementation creates `AVAudioPlayer(contentsOf:)`, sets volume, and prepares the player exactly as today. The closure remains main-actor isolated; moving AVFoundation construction off-main is not required by this bug ticket.

Tests can supply a controlled async loader whose continuations complete in any order. This makes stale-request tests deterministic without fixed sleeps or a generalized media abstraction.

### 4. Give every load one request generation

Add one private monotonic counter:

```swift
private var requestGeneration: UInt64 = 0
```

`playPreview(for:)` advances the counter and captures the resulting generation for that request. `stop()` also advances the counter before cleanup so an in-flight load becomes stale even when no replacement song is selected.

A loaded player may affect the service only when its captured generation still equals the current generation. The generation check occurs before the completion can:

- enter the cache;
- replace `audioPlayer`;
- publish `currentlyPlaying`, `duration`, `currentTime`, or `isPlaying`;
- start the progress timer;
- deactivate the iOS audio session after an error.

A stale successful load is stopped/discarded. A stale error may be logged, but it returns before mutating service or audio-session state. Actual task cancellation is optional; request invalidation is the correctness boundary.

No special overflow machinery is needed. Increment with wrapping arithmetic (`&+= 1`); equality with the captured generation is the only required operation. This follows the generation-invalidates-stale-work pattern already used elsewhere in Virgo without extracting a shared abstraction.

### 5. Publish playback state only after the player starts

Use one private helper for the shared cached/new-player start path:

```swift
@discardableResult
private func startInstalledPlayer(
    _ player: AVAudioPlayer,
    songID: PersistentIdentifier
) -> Bool
```

The helper installs the candidate player, assigns its delegate/current time, calls the existing `startPlayback` seam, and publishes playing state only when that call returns `true`.

On success:

- `audioPlayer` refers to the started player;
- `currentlyPlaying` is the selected song's `id`;
- `duration` comes from that player;
- `currentTime` starts at zero;
- `isPlaying` becomes `true`;
- the progress timer starts.

On failure, clear the installed/current state and timer, but do not evict an already-cached resource solely because `play()` returned `false`.

`togglePlayback(for:)` becomes identity-based:

1. same `song.id` + playing → `pause()`;
2. same `song.id` + paused → `resume()`;
3. different/no active ID → `playPreview(for:)`.

`playPreview(for:)` owns replacement cleanup, so the toggle path does not need a separate pre-stop sequence.

`resume()` must require both an installed player and an active song ID. It calls `startPlayback(player)` and sets `isPlaying = true`/starts the timer only on success. Missing-player state or a failed start clears playback state instead of pretending to resume.

### 6. Keep one progress timer owner

`startProgressTimer()` must call `stopProgressTimer()` before scheduling a replacement. This is intentionally simpler than adding a scheduler/clock abstraction.

Timer ownership is verified on the real `play → pause → resume` lifecycle. A test may inspect the private timer with the repository's established reflection style rather than widening production visibility or introducing a timer factory solely for tests.

### 7. Ignore callbacks from obsolete players

Every `AVAudioPlayerDelegate` callback still enters `Task { @MainActor in ... }`, but its actor-isolated state mutation first checks:

```swift
guard player === audioPlayer else { return }
```

Apply this ownership check to finish, decode-error, interruption-begin, and interruption-end callbacks. A player that belonged to a previous request must not stop, pause, or resume the current player.

This negative-path guard must not erase positive-path coverage: the existing active-player delegate tests are rewritten so their callback player is first installed through `AudioPlaybackService`. Separate obsolete-player tests prove that callbacks from an old instance are ignored.

Logging the supplied decode error may remain outside the ownership guard, but all playback-state mutation stays behind it.

## Request lifecycle

A replacement selection follows this sequence:

1. `playPreview(for:)` advances `requestGeneration`.
2. Existing player/timer/published playback state is cleared.
3. Missing preview path exits in the stopped state.
4. Resolve canonical preview path and `song.id`.
5. If a cached player exists for that path, attempt to start it immediately.
6. Otherwise await `loadPlayer(url)` with the captured generation.
7. On completion, reject stale generations before cache/install/state mutation.
8. Cache the current loaded/prepared resource according to the existing FIFO policy.
9. Attempt actual playback.
10. Only a successful start publishes the song ID and `isPlaying = true`.

`stop()` advances `requestGeneration` and performs the same cleanup, so a later completion from step 6 cannot resurrect playback.

## Testing strategy

Keep behavior coverage in `VirgoTests/AudioPlaybackServiceTests.swift`.

Identity-bearing tests should match `PlaybackServiceTests`: create the `Song` inside `TestSetup.withTestSetup`, insert it into `TestContainer.shared.context`, and compare with `song.id`. Saving is not required solely to use the context-backed identity in the same test.

The controlled loader uses continuations both for suspended player creation and for request-observation waiters. It must report missing/double completion through `Issue.record` instead of force-unwrapping queues. Do not use bounded `Task.yield()` polling as a timeout.

Apply Swift Testing's `.timeLimit(.minutes(1))` trait to the serialized `AudioPlaybackServiceTests` suite so a regression that never issues or completes an expected load fails rather than hanging the test run. This also bounds the existing real-file cache tests without changing their semantics.

Add/adjust focused coverage for:

- two inserted songs with the same title and different preview paths never share playback identity or cached audio;
- request A completing after request B is ignored;
- stopping while request A is suspended prevents A from installing or publishing later;
- a stale failed request cannot clear a newer successful selection or deactivate its audio session;
- failed initial `startPlayback` leaves the service stopped while retaining the decoded resource cache entry;
- `resume()` with no player or a failed player start leaves the service stopped;
- `startProgressTimer()` maintains a single timer through play/pause/resume;
- current-player finish/decode/interruption callbacks retain their existing behavior when the callback player was actually installed by the service;
- obsolete-player finish/decode/interruption callbacks cannot mutate the active player's state;
- cached replay still works after the source file is removed, keyed by canonical preview path rather than title;
- FIFO eviction remains ten entries and preserves the existing real-file coverage.

Delete the old sleep-based `testPlayPreviewFailureAfterSongSwitchKeepsCurrentState` when the controlled loader is introduced; do not first migrate it to the new identity property. The deterministic generation-driven stale-error test replaces it.

Existing real-file cache/progress/FIFO tests may retain their short sleeps where those sleeps are observing actual file/player behavior rather than coordinating a race. The new loader seam exists to remove race-order sleeps, not to rewrite every AVFoundation integration-style test.

For the UI boundary, update `DownloadedSongsView.isPlaying(_:)` to use the service's persistent ID. Existing SwiftUI rendering coverage should continue to mount `DownloadedSongsView`/`SongsTabView`; add no new XCUITest for the highlight change.

## Expected production files

- `Virgo/utilities/AudioPlaybackService.swift`
- `Virgo/views/DownloadedSongsView.swift`

Expected focused test files:

- `VirgoTests/AudioPlaybackServiceTests.swift`
- existing downloaded-song rendering suites only if a mechanical property rename requires them

Do not change `ContentView` or `SongsTabView` merely because they pass `AudioPlaybackService` through; their existing ownership/wiring remains valid.

## Acceptance criteria

- Two different `Song` objects with the same title cannot pause/resume each other or reuse the wrong cached preview.
- Preview cache reuse is keyed by canonical preview resource path, not display title.
- A superseded or stopped async load cannot install a player, enter the cache, publish playback state, start a progress timer, or deactivate the audio session for a newer request.
- `isPlaying` becomes `true` only after the real `AVAudioPlayer` start succeeds.
- The previous instant row highlight while a preview is merely loading is intentionally removed; the row reflects actual playback only.
- `resume()` cannot publish playing state without an installed player and successful start.
- A decoded/prepared player remains cacheable when a subsequent `play()` start attempt fails; HPA-576 adds no special eviction policy for that transient start failure.
- Only one progress timer remains active at a time.
- Current-player delegate callbacks still perform their intended finish/decode/interruption behavior.
- Delegate callbacks from obsolete players cannot mutate current playback state.
- `DownloadedSongsView` highlights preview playback by `song.id` rather than title.
- Focused regressions are deterministic, bounded by the suite time limit, and require no new media architecture or fixed race-order sleeps.
- HPA-85 BGM-format work and evidence-gated off-main performance work remain separate.

## Verification

Run `AudioPlaybackServiceTests` first with parallel testing disabled; this is the hard behavior gate for HPA-576. Then run directly affected downloaded-song rendering coverage, the full macOS `VirgoTests` command, SwiftLint on touched Swift files, and a generic iPad Simulator Debug build so the `#if os(iOS)` audio-session path still compiles.

The full-suite expectation remains `TEST SUCCEEDED`. If an unrelated SwiftData/test-host failure occurs, do not silently waive it and do not expand HPA-576 immediately. Run the identical full-suite command on a clean `main` worktree/ref. Only a failure reproduced on `main` with the same signature may be recorded as pre-existing; focused HPA-576 suites must remain green, and any new deterministic failure introduced by the branch is still blocking.

Review the final production diff before implementation is considered complete: it should remain a local state-machine correction with one loader seam, one generation counter, path-based cache identity, ID-based UI selection, and focused tests. No new audio framework or compatibility layer should appear.
