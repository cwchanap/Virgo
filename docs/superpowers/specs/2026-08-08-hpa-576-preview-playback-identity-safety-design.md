# HPA-576: Preview Playback Identity and Request Safety

**Date:** 2026-08-08  
**Status:** Approved design — implementation not started

## Context

`AudioPlaybackService` owns short preview playback for downloaded server songs. Its current state machine uses `Song.title` as both the active-selection identity and the audio-cache key. That creates correctness bugs when two distinct songs share a title: they can be treated as the same selection and can reuse the wrong cached `AVAudioPlayer`.

The service also launches asynchronous player creation without a request identity. A load that finishes after the user selects another song, stops playback, or starts a newer request can still reach the completion/error path. The current title check prevents some stale state mutation, but it does not make the whole completion atomic: a stale failure can still reach iOS audio-session cleanup, and stale `AVAudioPlayer` delegate callbacks can stop or pause a newer player.

Playback publication is optimistic in several places. `togglePlayback(for:)` and `loadAndPlayPreview(song:previewPath:)` set `isPlaying = true` before `AVAudioPlayer.play()` succeeds, while `resume()` sets `isPlaying = true` even when there is no installed player or `play()` returns `false`. `startProgressTimer()` also creates a timer without first invalidating an existing one.

HPA-576 is intentionally a local correctness fix. It should make the existing preview player deterministic without becoming a media subsystem redesign.

## Goal

Make preview playback identity-safe and stale-request-safe so the published service state always describes the currently installed, successfully playing song preview.

## Non-goals

- Do not replace `AVAudioPlayer` with `AVAudioEngine`.
- Do not introduce a media repository, playback coordinator, actor hierarchy, or protocol per audio operation.
- Do not move general DTX/file work off the main actor; HPA-579/HPA-580 own evidence-based performance decisions.
- Do not solve server BGM format compatibility; HPA-85 remains the `.ogg`/native-playback issue.
- Do not add loading spinners or redesign downloaded-song controls.
- Do not introduce persistence or migration for preview playback state.

## Design

### 1. Separate selection identity from audio-cache identity

The active song must use SwiftData identity, not display text. Replace the published title-based state with:

```swift
@Published var currentlyPlayingSongID: PersistentIdentifier?
```

`AudioPlaybackService` already accepts `Song` values, so using `song.persistentModelID` does not introduce a new domain dependency. `DownloadedSongsView.isPlaying(_:)` will compare `currentlyPlayingSongID` with `song.persistentModelID` when the row uses preview playback.

Paused playback keeps `currentlyPlayingSongID` so selecting the same row can resume the installed player. `stop()`, a failed start, or replacement by another song clears it. A preview that is still loading is not published as playing.

The reusable player cache has a different identity concern: it should represent the audio resource. Keep the existing FIFO cache, but key `audioCache` and `audioCacheOrder` by a canonicalized preview file path:

```swift
URL(fileURLWithPath: previewPath).standardizedFileURL.path
```

Do not add a cache wrapper or new cache model. The existing ten-entry FIFO policy is sufficient.

### 2. Add one minimal deterministic player-loader seam

Keep the existing `startPlayback: (AVAudioPlayer) -> Bool` injection and add one initializer dependency for player creation:

```swift
loadPlayer: @escaping @MainActor (URL) async throws -> AVAudioPlayer
```

Its default implementation creates `AVAudioPlayer(contentsOf:)` and prepares the player exactly as today. The closure remains main-actor isolated; moving AVFoundation construction off-main is not required by this bug ticket.

Tests can supply a controlled async loader whose continuations complete in any order. This makes stale-request tests deterministic without fixed sleeps or a generalized media abstraction.

### 3. Give every load a request generation

Add one private monotonic counter:

```swift
private var requestGeneration: UInt64 = 0
```

`playPreview(for:)` increments the counter and captures the resulting generation for that request. It also stops/clears any installed player and progress timer before resolving the new preview. `stop()` increments the counter before cleanup so an in-flight load becomes stale even when no replacement song is selected.

A loaded player may affect the service only when its captured generation still equals the current generation. The generation check occurs before the completion can:

- enter the cache,
- replace `audioPlayer`,
- publish `currentlyPlayingSongID`, `duration`, `currentTime`, or `isPlaying`,
- start the progress timer,
- deactivate the iOS audio session after an error.

A stale successful load is stopped/discarded. A stale error may be logged, but it returns before mutating service/audio-session state. Actual task cancellation is optional; request invalidation is the correctness boundary.

No special overflow machinery is needed. Increment with wrapping arithmetic (`&+= 1`); equality with the captured generation is the only required operation.

### 4. Publish playback state only after the player starts

Use one small private helper for the shared cached/new-player start path. It should install the candidate player, set its delegate/current time, call the existing `startPlayback` seam, and publish playing state only when the call returns `true`.

On success:

- `audioPlayer` refers to the started player,
- `currentlyPlayingSongID` is the selected song's `persistentModelID`,
- `duration` comes from that player,
- `currentTime` starts at zero,
- `isPlaying` becomes `true`,
- the progress timer starts.

On failure, stop/discard the candidate and leave the service in a fully stopped state with no selected song ID and no progress timer.

`togglePlayback(for:)` becomes identity-based:

1. same `PersistentIdentifier` + playing → `pause()`;
2. same `PersistentIdentifier` + paused → `resume()`;
3. different/no active ID → `playPreview(for:)`.

`playPreview(for:)` owns replacement cleanup, so the toggle path does not need a separate pre-stop sequence.

`resume()` must require both an installed player and an active song ID. It calls `startPlayback(player)` and sets `isPlaying = true`/starts the timer only on success. Missing player state or a failed start clears playback state instead of pretending to resume.

### 5. Keep one progress timer owner

`startProgressTimer()` must call `stopProgressTimer()` before scheduling a replacement. This is intentionally simpler than adding a scheduler/clock abstraction.

The existing progress behavior test remains useful. A focused lifecycle test may inspect the private timer through a test-only `Mirror` helper to prove that starting progress again invalidates the previous `Timer`; do not widen production visibility solely for this assertion.

### 6. Ignore callbacks from obsolete players

Every `AVAudioPlayerDelegate` callback enters a `Task { @MainActor in ... }` as it does today, but the actor-isolated body first checks:

```swift
guard player === audioPlayer else { return }
```

Apply this ownership check to finish, decode-error, interruption-begin, and interruption-end callbacks. A player that belonged to a previous request must not stop, pause, or resume the current player.

Logging the supplied decode error may remain outside the ownership guard, but all state mutation stays behind it.

## Request lifecycle

A replacement selection follows this sequence:

1. `playPreview(for:)` advances `requestGeneration`.
2. Existing player/timer/published playback state is cleared.
3. Missing preview path exits in the stopped state.
4. Resolve the canonical preview path and stable `PersistentIdentifier`.
5. If a cached player exists for that path, attempt to start it immediately.
6. Otherwise await `loadPlayer(url)` with the captured generation.
7. On completion, reject stale generations before cache/install/state mutation.
8. Attempt actual playback.
9. Only a successful start publishes the song ID and `isPlaying = true`.

`stop()` advances `requestGeneration` and performs the same cleanup, so a later completion from step 6 cannot resurrect playback.

## Testing strategy

Keep the behavior coverage in `VirgoTests/AudioPlaybackServiceTests.swift` and replace sleep-driven race tests with deterministic loader completion where the new seam applies.

Add/adjust focused tests for:

- two songs with the same title and different preview paths never share playback identity or cached audio;
- request A completing after request B is ignored;
- stopping while request A is suspended prevents A from installing or publishing later;
- a stale failed request cannot clear a newer successful selection;
- failed initial `startPlayback` leaves the service stopped;
- `resume()` with no player or a failed player start leaves the service stopped;
- repeated progress-timer starts invalidate the previous timer;
- a delegate finish/decode/interruption callback from an obsolete player cannot mutate the active player's state;
- cached replay still works after the source file is removed, keyed by canonical preview path rather than title.

Update any existing tests that directly set/assert `currentlyPlayingSong` to use `currentlyPlayingSongID` and real `PersistentIdentifier` values. Preserve the serialized suite because AVFoundation/timer behavior is process-global enough that parallel execution is unnecessary here.

For the UI boundary, update `DownloadedSongsView.isPlaying(_:)` to use the service's persistent ID. Existing SwiftUI rendering coverage should continue to mount `DownloadedSongsView`/`SongsTabView`; add only a narrowly focused row-state assertion if the current rendering helper can observe the play/pause state without new test infrastructure.

## Expected production files

- `Virgo/utilities/AudioPlaybackService.swift`
- `Virgo/views/DownloadedSongsView.swift`

Expected focused test files:

- `VirgoTests/AudioPlaybackServiceTests.swift`
- optionally an existing `DownloadedSongsView` rendering suite only if needed to assert the ID-based row state

Do not change `ContentView` or `SongsTabView` merely because they pass `AudioPlaybackService` through; their existing ownership/wiring remains valid.

## Acceptance criteria

- Two different `Song` objects with the same title cannot pause/resume each other or reuse the wrong cached preview.
- Preview cache reuse is keyed by canonical preview resource path, not display title.
- A superseded or stopped async load cannot install a player, enter the cache, publish playback state, start a progress timer, or deactivate the audio session for a newer request.
- `isPlaying` becomes `true` only after the real `AVAudioPlayer` start succeeds.
- `resume()` cannot publish playing state without an installed player and successful start.
- Only one progress timer remains active at a time.
- Delegate callbacks from obsolete players cannot mutate the current playback state.
- `DownloadedSongsView` highlights preview playback by persistent song identity rather than title.
- Focused regressions are deterministic and do not require new media architecture or fixed race sleeps.
- HPA-85 BGM-format work and evidence-gated off-main performance work remain separate.

## Verification

Run the focused `AudioPlaybackServiceTests` first with parallel testing disabled. Then run any directly affected `DownloadedSongsView` rendering suite, the full macOS `VirgoTests` target using the repository's non-parallel command, SwiftLint on touched Swift files, and a generic iPad Simulator Debug build so the `#if os(iOS)` audio-session path still compiles.

Review the final production diff before implementation is considered complete: it should remain a local state-machine correction with one loader seam, one generation counter, path-based cache identity, ID-based UI selection, and focused tests. No new audio framework or compatibility layer should appear.
