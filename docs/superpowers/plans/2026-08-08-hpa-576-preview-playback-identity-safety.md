# HPA-576 Preview Playback Identity and Request Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make downloaded-song preview playback use stable song/resource identity, ignore stale asynchronous loads and obsolete player callbacks, and publish playing state only after real `AVAudioPlayer` startup succeeds.

**Architecture:** Keep `AudioPlaybackService` as the single preview-playback owner. Reuse Virgo's existing `song.id` / `PersistentIdentifier` active-song convention, add one main-actor async player-loader seam for deterministic tests, key the existing FIFO cache by canonical preview path, and reject stale completions with one `UInt64` request generation. Keep `AVAudioPlayer`, the existing `startPlayback` seam, and the current timer/cache shapes; do not add a media layer or move AVFoundation work off-main in this ticket.

**Tech Stack:** Swift, SwiftUI, SwiftData `PersistentIdentifier`, AVFoundation `AVAudioPlayer`, Swift Testing, `Timer`, xcodebuild, SwiftLint.

## Global Constraints

- Keep `AVAudioPlayer`; do not introduce `AVAudioEngine` or a third-party decoder.
- Keep `AudioPlaybackService` as the preview playback owner; no repository/coordinator/actor hierarchy.
- Use the repository's existing `song.id` / `PersistentIdentifier` convention for active song identity and canonical preview file path for cache identity.
- Identity-bearing service tests insert `Song` objects into `TestContainer.shared.context` before comparing `song.id`.
- Add one `loadPlayer` closure with a default implementation; do not create an audio-loader protocol.
- One monotonically increasing `UInt64` generation owns stale-request invalidation; cooperative task cancellation is optional and not required.
- `isPlaying` becomes true only after the underlying player start succeeds.
- The previous instant row highlight while a preview is loading is intentionally removed; do not add pending-selection UI in this ticket.
- A stale completion cannot cache/install a player, mutate published state, start a timer, or deactivate the iOS audio session.
- A successfully decoded/prepared player remains in the cache if a subsequent `play()` attempt returns `false`; do not add an eviction/reload rule for that transient start failure.
- `startProgressTimer()` always invalidates the previous timer before creating another.
- Obsolete `AVAudioPlayerDelegate` callbacks cannot mutate active playback; current-player callbacks retain their existing behavior.
- Deterministic stale-load tests use continuations, not fixed sleeps or bounded `Task.yield()` polling loops.
- Apply `.timeLimit(.minutes(1))` to the serialized `AudioPlaybackServiceTests` suite so a missed continuation/request fails instead of hanging indefinitely.
- Do not include HPA-85 server BGM format work or HPA-579/HPA-580 performance restructuring.
- Run tests with `-parallel-testing-enabled NO` per repository policy.
- A non-blocking SwiftLint size warning alone is not a reason to introduce a new type or cross-file abstraction.

## Existing-test migration map

Migrate each existing test once, at the task where its final intended form becomes available. Do not mechanically rename `currentlyPlayingSong` and then rewrite the same test again later.

| Existing test | Owning task | Final migration |
| --- | --- | --- |
| `testTogglePlaybackPauseAndResume` | Task 1 | Install a real player through the controlled loader; then pause/resume the same inserted song. |
| `testStopResetsPlaybackState` | Task 1 | Start an inserted song through the service, call `stop()`, assert all published state resets. |
| `testPlayPreviewWithInvalidPath` | Task 1 | Use controlled loader failure; assert stopped while pending and after failure, no fixed sleep. |
| `testPlayPreviewFailureAfterSongSwitchKeepsCurrentState` | Task 1 | **Delete immediately.** Task 2's deterministic stale-error generation test replaces it; do not migrate it to IDs first. |
| `testAudioPlayerDidFinishPlayingStopsPlayback` | Task 1 | Install the callback player through the service before invoking the delegate. |
| `testAudioPlayerDecodeErrorStopsPlayback` | Task 1 | Install the callback player through the service before invoking the delegate. |
| `testAudioPlayerBeginInterruptionPausesPlayback` | Task 1 | Install the callback player through the service before invoking the delegate. |
| `testTogglePlaybackDifferentSongStartsPlayback` | Task 1 | Insert the song, use controlled loading, assert no playing identity while pending, then success after real start. |
| `testPlayPreviewUsesCachedPlayer` | Task 1 | Put the song in `TestSetup.withTestSetup`, compare `currentlyPlaying` to `song.id`; retain the short real-file waits because this is cache/file coverage, not race coordination. |
| `testPlayPreviewUpdatesProgress` | Task 1 | Keep the real-file/timer coverage; no identity rewrite is required unless compilation reveals a direct old-property reference. |
| `testPlayPreviewPlayFailureClearsState` | Task 1 | Complete the controlled load explicitly and make `startPlayback` return `false`; assert stopped state and later cached reuse behavior separately. |
| `testPlayPreviewEvictsOldestCachedPlayer` | Task 1 | Run inside `TestSetup.withTestSetup`, insert all 11 songs, compare active state with `song.id`; retain existing real-file waits/FIFO behavior. |
| `testAudioPlayerEndInterruptionNoStateChangeOnMacOS` | Task 1 | Install the callback player through the service before invoking the macOS no-op callback. |
| obsolete-player finish/decode/interruption cases | Task 3 | New negative-path coverage after current-player positive tests already use installed players. |

The purpose of this table is to prevent two failure modes: keeping sleep-driven tests that no longer model the state machine, and testing delegate ownership with a player the service never installed.

---

### Task 1: Establish stable identity, deterministic loading, path-keyed cache, and truthful initial starts

**Files:**
- Modify: `VirgoTests/AudioPlaybackServiceTests.swift`
- Modify: `Virgo/utilities/AudioPlaybackService.swift`
- Modify: `Virgo/views/DownloadedSongsView.swift`

**Interfaces:**
- Consumes: `Song.id`, `Song.previewFilePath`, existing `startPlayback: (AVAudioPlayer) -> Bool` injection.
- Produces: `AudioPlaybackService.currentlyPlaying: PersistentIdentifier?`; initializer parameter `loadPlayer: @escaping @MainActor (URL) async throws -> AVAudioPlayer`; `previewCacheKey(for:)`; path-keyed `audioCache`/`audioCacheOrder`; shared `startInstalledPlayer(_:songID:)` for cached and fresh starts.

This is an internal checkpoint in one HPA-576 implementation PR. It intentionally does **not** close stale async completion yet; Task 2 must land before the implementation PR is ready for review. Do not merge or release the Task 1 commit alone.

- [ ] **Step 1: Bound the service test suite and add the controlled async loader.**

Change the suite declaration to:

```swift
@Suite(
    "AudioPlaybackService Tests",
    .serialized,
    .timeLimit(.minutes(1))
)
@MainActor
struct AudioPlaybackServiceTests {
```

Add this helper near the existing WAV/player factories:

```swift
@MainActor
private final class ControlledPlayerLoader {
    private struct RequestWaiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var pending: [String: [CheckedContinuation<AVAudioPlayer, Error>]] = [:]
    private var waiters: [String: [RequestWaiter]] = [:]
    private(set) var requests: [String] = []

    func load(_ url: URL) async throws -> AVAudioPlayer {
        let key = url.standardizedFileURL.path
        requests.append(key)
        resumeSatisfiedWaiters(for: key)
        return try await withCheckedThrowingContinuation { continuation in
            pending[key, default: []].append(continuation)
        }
    }

    func waitForRequest(path: String, count: Int = 1) async {
        let key = canonical(path)
        if requestCount(for: key) >= count { return }

        await withCheckedContinuation { continuation in
            if requestCount(for: key) >= count {
                continuation.resume()
            } else {
                waiters[key, default: []].append(
                    RequestWaiter(count: count, continuation: continuation)
                )
            }
        }
    }

    func succeed(path: String, player: AVAudioPlayer) {
        guard let continuation = takePendingContinuation(path: path) else { return }
        continuation.resume(returning: player)
    }

    func fail(path: String, error: Error) {
        guard let continuation = takePendingContinuation(path: path) else { return }
        continuation.resume(throwing: error)
    }

    private func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func requestCount(for key: String) -> Int {
        requests.lazy.filter { $0 == key }.count
    }

    private func resumeSatisfiedWaiters(for key: String) {
        let count = requestCount(for: key)
        let registered = waiters.removeValue(forKey: key) ?? []
        var remaining: [RequestWaiter] = []

        for waiter in registered {
            if count >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }

        if !remaining.isEmpty {
            waiters[key] = remaining
        }
    }

    private func takePendingContinuation(
        path: String
    ) -> CheckedContinuation<AVAudioPlayer, Error>? {
        let key = canonical(path)
        guard var queue = pending[key], !queue.isEmpty else {
            Issue.record("No pending preview load for \(key)")
            return nil
        }

        let continuation = queue.removeFirst()
        if queue.isEmpty {
            pending.removeValue(forKey: key)
        } else {
            pending[key] = queue
        }
        return continuation
    }
}
```

The suite-level time limit is the hang guard. `waitForRequest` itself remains continuation-driven and contains no polling budget.

- [ ] **Step 2: Add inserted-song and installed-preview test helpers.**

Keep `makeSong` for tests that do not care about persistent identity. Add:

```swift
private func insertSong(title: String, previewPath: String? = nil) -> Song {
    let song = makeSong(title: title, previewPath: previewPath)
    TestContainer.shared.context.insert(song)
    return song
}
```

Call `insertSong` only inside `TestSetup.withTestSetup { ... }`.

Add a helper that starts a preview through the service instead of hand-stuffing published state:

```swift
private func startPreview(
    service: AudioPlaybackService,
    loader: ControlledPlayerLoader,
    song: Song,
    path: String,
    player: AVAudioPlayer
) async {
    service.playPreview(for: song)
    await loader.waitForRequest(path: path)
    loader.succeed(path: path, player: player)
    await Task.yield()
    #expect(service.currentlyPlaying == song.id)
    #expect(service.isPlaying)
}
```

A single `Task.yield()` after explicitly resuming a continuation is allowed to let the already-unblocked main-actor task finish. Do not use `Task.yield()` in a loop as a timeout.

- [ ] **Step 3: Write identity and truthful-publication tests before changing production code.**

Add a duplicate-title test inside `TestSetup.withTestSetup`:

```swift
@Test("same-title songs use distinct preview identities and cache resources")
func sameTitleSongsUseDistinctPreviewIdentities() async throws {
    try await TestSetup.withTestSetup {
        let loader = ControlledPlayerLoader()
        let service = AudioPlaybackService(
            loadPlayer: { try await loader.load($0) },
            startPlayback: { _ in true }
        )
        let firstPath = try makeTemporaryWAVPath(durationSeconds: 1.0)
        let secondPath = try makeTemporaryWAVPath(durationSeconds: 2.0)
        defer {
            try? FileManager.default.removeItem(atPath: firstPath)
            try? FileManager.default.removeItem(atPath: secondPath)
        }

        let first = insertSong(title: "Collision", previewPath: firstPath)
        let second = insertSong(title: "Collision", previewPath: secondPath)
        #expect(first.id != second.id)

        let firstPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: firstPath))
        let secondPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: secondPath))

        service.playPreview(for: first)
        #expect(!service.isPlaying)
        #expect(service.currentlyPlaying == nil)
        await loader.waitForRequest(path: firstPath)
        loader.succeed(path: firstPath, player: firstPlayer)
        await Task.yield()
        #expect(service.currentlyPlaying == first.id)

        service.stop()
        service.playPreview(for: second)
        await loader.waitForRequest(path: secondPath)
        loader.succeed(path: secondPath, player: secondPlayer)
        await Task.yield()

        #expect(service.currentlyPlaying == second.id)
        #expect(service.duration == secondPlayer.duration)
        #expect(loader.requests == [
            URL(fileURLWithPath: firstPath).standardizedFileURL.path,
            URL(fileURLWithPath: secondPath).standardizedFileURL.path
        ])
    }
}
```

Also add/convert the different-song test so `togglePlayback(for:)` leaves `isPlaying == false` and `currentlyPlaying == nil` while the controlled load is pending, then publishes only after `startPlayback` succeeds.

- [ ] **Step 4: Run the focused suite and verify RED.**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/AudioPlaybackServiceTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected result: compilation/test failures because `loadPlayer`, persistent-ID preview state, and truthful pending semantics do not exist yet.

- [ ] **Step 5: Add the loader seam and stable public identity.**

In `AudioPlaybackService.swift`, import SwiftData and replace the title property:

```swift
@Published var currentlyPlaying: PersistentIdentifier?
```

Add:

```swift
private let loadPlayer: @MainActor (URL) async throws -> AVAudioPlayer
private let startPlayback: (AVAudioPlayer) -> Bool
```

Use this initializer:

```swift
init(
    loadPlayer: @escaping @MainActor (URL) async throws -> AVAudioPlayer = { url in
        let player = try AVAudioPlayer(contentsOf: url)
        player.volume = 1.0
        _ = player.prepareToPlay()
        return player
    },
    startPlayback: @escaping (AVAudioPlayer) -> Bool = { $0.play() }
) {
    self.loadPlayer = loadPlayer
    self.startPlayback = startPlayback
    super.init()
    if !TestEnvironment.isRunningTests {
        setupAudioSession()
    }
}
```

Remove player construction/preparation from `loadAndPlayPreview`; it now awaits `loadPlayer(url)`.

- [ ] **Step 6: Re-key the existing FIFO cache by canonical preview path.**

Add:

```swift
private func previewCacheKey(for path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}
```

Use that key for `audioCache` lookup, insertion, replacement, and `audioCacheOrder`. Keep `maxCacheSize = 10` and the existing FIFO eviction order unchanged.

Do not add a cache wrapper, LRU tracking, or generic key type.

- [ ] **Step 7: Add one shared truthful initial-start path.**

Add:

```swift
@discardableResult
private func startInstalledPlayer(
    _ player: AVAudioPlayer,
    songID: PersistentIdentifier
) -> Bool {
    audioPlayer = player
    player.delegate = self
    player.currentTime = 0
    duration = player.duration
    currentTime = 0

    guard startPlayback(player) else {
        audioPlayer = nil
        currentlyPlaying = nil
        isPlaying = false
        duration = 0
        currentTime = 0
        stopProgressTimer()
        return false
    }

    currentlyPlaying = songID
    isPlaying = true
    startProgressTimer()
    return true
}
```

Both cached and newly loaded **current** players eventually use this helper. A newly loaded/prepared player may be inserted into the cache before this start attempt. If `startPlayback` returns `false`, leave the cached resource in place; clear active playback state only.

At Task 1, do not add generation logic yet. The pre-existing stale-completion race remains until Task 2, which is why this task cannot ship independently.

- [ ] **Step 8: Make toggle/loading state truthful and update the downloaded row.**

Use:

```swift
func togglePlayback(for song: Song) {
    if currentlyPlaying == song.id && isPlaying {
        pause()
    } else if currentlyPlaying == song.id {
        resume()
    } else {
        playPreview(for: song)
    }
}
```

`playPreview(for:)` clears the previous installed playback/timer state before resolving the new preview. Do not set `currentlyPlaying` or `isPlaying` merely because loading started.

In `DownloadedSongsView.isPlaying(_:)`, use:

```swift
return audioPlaybackService.isPlaying
    && audioPlaybackService.currentlyPlaying == song.id
```

Keep the regular `PlaybackService` branch unchanged.

- [ ] **Step 9: Migrate existing `AudioPlaybackServiceTests` once and delete the superseded race test now.**

Make all of these changes before expecting Task 1 GREEN:

1. Delete `testPlayPreviewFailureAfterSongSwitchKeepsCurrentState` outright.
2. Rewrite `testTogglePlaybackPauseAndResume` using an inserted song and `startPreview(...)`; never manually set playback identity.
3. Rewrite `testStopResetsPlaybackState` to start a real inserted preview and then call `stop()`.
4. Rewrite `testPlayPreviewWithInvalidPath` to use `ControlledPlayerLoader.fail(...)`; while pending, assert `isPlaying == false` and `currentlyPlaying == nil`; after failure, assert the same.
5. Rewrite `testAudioPlayerDidFinishPlayingStopsPlayback` so the exact callback player was installed by `startPreview(...)` before invoking the delegate.
6. Rewrite `testAudioPlayerDecodeErrorStopsPlayback` the same way.
7. Rewrite `testAudioPlayerBeginInterruptionPausesPlayback` the same way; after callback, expect `isPlaying == false` while `currentlyPlaying == song.id` remains for resume.
8. Rewrite `testTogglePlaybackDifferentSongStartsPlayback` with inserted identity + controlled load and truthful pending state.
9. Rewrite `testPlayPreviewPlayFailureClearsState` with controlled completion and `startPlayback: { _ in false }`; assert stopped state after the explicit completion.
10. Rewrite `testAudioPlayerEndInterruptionNoStateChangeOnMacOS` so its callback player is installed by the service before the macOS no-op callback.
11. Wrap `testPlayPreviewUsesCachedPlayer` in `TestSetup.withTestSetup`, insert its song, and compare `currentlyPlaying == song.id`. Retain its existing short real-file waits because they verify actual cached replay after the source file disappears.
12. Wrap `testPlayPreviewEvictsOldestCachedPlayer` in `TestSetup.withTestSetup`, insert all 11 songs, and replace title comparisons with `song.id`. Retain the existing real-file waits because they exercise the actual ten-entry FIFO/cache behavior rather than scheduling a race.
13. Keep `testPlayPreviewUpdatesProgress` as real-file/timer coverage unless a direct old-property reference needs a mechanical identity update.
14. Search `VirgoTests/AudioPlaybackServiceTests.swift` for `currentlyPlayingSong`; Task 1 is not GREEN until zero references remain.

This is intentionally the only migration pass for those tests. Task 3 adds obsolete-player negative cases but does not re-migrate the current-player positive tests.

- [ ] **Step 10: Run the focused suite and verify GREEN for Task 1's owned behavior.**

Repeat the focused command from Step 4.

Expected result: identity, truthful initial publication, cached replay/FIFO, current-player delegate behavior, and migrated existing tests pass. This does **not** mean HPA-576 is complete; stale completion remains intentionally uncovered until Task 2.

- [ ] **Step 11: Commit the identity/cache/loader slice.**

```bash
git add Virgo/utilities/AudioPlaybackService.swift \
  Virgo/views/DownloadedSongsView.swift \
  VirgoTests/AudioPlaybackServiceTests.swift
git commit -m "fix: make preview playback identity-safe"
```

### Task 2: Reject stale loads and stopped requests with one generation counter

**Files:**
- Modify: `VirgoTests/AudioPlaybackServiceTests.swift`
- Modify: `Virgo/utilities/AudioPlaybackService.swift`

**Interfaces:**
- Consumes: controlled `loadPlayer`, path cache key, truthful start path, and inserted song IDs from Task 1.
- Produces: private `requestGeneration: UInt64`; generation capture for each `playPreview(for:)`; invalidation in `stop()`; generation-gated success/error completion before cache/install/publication/session cleanup.

- [ ] **Step 1: Add out-of-order completion coverage.**

Inside `TestSetup.withTestSetup`, start inserted song A and wait until its load is suspended. Start inserted song B and suspend it too. Complete B first, then A:

```swift
loader.succeed(path: secondPath, player: secondPlayer)
await Task.yield()
#expect(service.currentlyPlaying == second.id)
#expect(service.duration == secondPlayer.duration)

loader.succeed(path: firstPath, player: firstPlayer)
await Task.yield()
#expect(service.currentlyPlaying == second.id)
#expect(service.duration == secondPlayer.duration)
```

Then:

```swift
service.stop()
service.playPreview(for: first)
await loader.waitForRequest(path: firstPath, count: 2)
```

The second request proves stale A was not inserted into the cache.

- [ ] **Step 2: Add stop-during-load and stale-error coverage.**

Add one test that suspends A, calls `stop()`, then completes A. Assert:

```swift
#expect(!service.isPlaying)
#expect(service.currentlyPlaying == nil)
#expect(service.duration == 0)
#expect(service.currentTime == 0)
```

Start A again and require a second loader request to prove the stopped stale completion did not populate the cache.

Define:

```swift
enum TestError: Error { case loadFailed }
```

Add a stale-error test: suspend A, start and complete B successfully, then fail A. Assert B remains active and its state does not change.

Do not add an audio-session protocol just to observe iOS deactivation. The production generation guard must return before the existing audio-session cleanup, and the generic iPad build in Task 4 protects compilation of that branch.

- [ ] **Step 3: Run the focused suite and verify RED.**

Run the Task 1 focused command.

Expected result: stale success/error/stop tests fail on the pre-generation implementation because old async work can still cache or mutate state.

- [ ] **Step 4: Add generation advancement and generation-neutral cleanup.**

In `AudioPlaybackService.swift`:

```swift
private var requestGeneration: UInt64 = 0

private func nextRequestGeneration() -> UInt64 {
    requestGeneration &+= 1
    return requestGeneration
}

private func invalidatePreviewRequests() {
    requestGeneration &+= 1
}
```

Extract one generation-neutral cleanup helper for the installed playback state:

```swift
private func clearCurrentPlayback() {
    audioPlayer?.stop()
    audioPlayer = nil
    isPlaying = false
    currentlyPlaying = nil
    currentTime = 0
    duration = 0
    stopProgressTimer()
}
```

`playPreview(for:)` obtains `let generation = nextRequestGeneration()` before calling `clearCurrentPlayback()`. `stop()` calls `invalidatePreviewRequests()` and then `clearCurrentPlayback()`.

Do not let `clearCurrentPlayback()` advance the generation itself; callers own that decision.

- [ ] **Step 5: Gate loaded success before cache/install/publication.**

Pass the captured generation through the async load path. Immediately after a player is returned:

```swift
guard generation == requestGeneration else {
    player.stop()
    return
}
```

This guard occurs **before**:

- `cacheAudioPlayer`;
- `audioPlayer = player`;
- `currentlyPlaying`/`isPlaying`/duration/current-time writes;
- progress timer startup.

After the guard, cache the loaded/prepared resource and call `startInstalledPlayer(_:songID:)`.

- [ ] **Step 6: Gate errors before state mutation and iOS session deactivation.**

Make the error path receive the request generation and begin its stateful handling with:

```swift
guard generation == requestGeneration else { return }
```

Logging may occur before that guard, but only a current request may clear active state or execute the existing iOS `AVAudioSession.sharedInstance().setActive(false)` cleanup.

- [ ] **Step 7: Run focused tests and verify GREEN.**

Repeat the non-parallel service suite.

Expected result: out-of-order success, stop-during-load, stale-error, duplicate-title, cache/FIFO, and all migrated existing tests pass.

- [ ] **Step 8: Commit the stale-request slice.**

```bash
git add Virgo/utilities/AudioPlaybackService.swift VirgoTests/AudioPlaybackServiceTests.swift
git commit -m "fix: ignore stale preview load completions"
```

### Task 3: Make resume, timer ownership, and obsolete-player callbacks safe

**Files:**
- Modify: `VirgoTests/AudioPlaybackServiceTests.swift`
- Modify: `Virgo/utilities/AudioPlaybackService.swift`

**Interfaces:**
- Consumes: current-generation installed player and truthful initial-start path from Tasks 1-2.
- Produces: safe `resume()`; single active progress timer; installed-player identity guard on all delegate callbacks; separate obsolete-player negative coverage.

- [ ] **Step 1: Add missing resume-failure tests.**

Add:

```swift
@Test("resume without an installed player stays stopped")
func resumeWithoutPlayerStaysStopped() {
    let service = AudioPlaybackService(startPlayback: { _ in true })
    service.resume()
    #expect(!service.isPlaying)
    #expect(service.currentlyPlaying == nil)
}
```

Add a failed-resume test using an inserted song + controlled loader. Make `startPlayback` succeed exactly once:

```swift
var attempts = 0
let service = AudioPlaybackService(
    loadPlayer: { try await loader.load($0) },
    startPlayback: { _ in
        attempts += 1
        return attempts == 1
    }
)
```

Start successfully, call `pause()`, then `resume()`. Expect the failed resume to clear playing identity/current/duration/player timer state rather than publish a fake resume.

- [ ] **Step 2: Add timer ownership coverage on the real lifecycle.**

Add the test-only reflection helper:

```swift
private func progressTimer(in service: AudioPlaybackService) -> Timer? {
    Mirror(reflecting: service).descendant("progressTimer") as? Timer
}
```

Use a service whose `startPlayback` returns `true` for initial start and resume. After a real installed preview:

```swift
let firstTimer = progressTimer(in: service)
service.pause()
#expect(firstTimer?.isValid == false)

service.resume()
let resumedTimer = progressTimer(in: service)
#expect(firstTimer?.isValid == false)
#expect(resumedTimer?.isValid == true)
#expect(firstTimer !== resumedTimer)
```

- [ ] **Step 3: Add obsolete-player callbacks as separate negative-path tests.**

Start inserted song A/player A through the service, then replace it with inserted song B/player B. Invoke A's callbacks after B is active.

At minimum assert finish and interruption-begin separately:

```swift
service.audioPlayerDidFinishPlaying(firstPlayer, successfully: true)
await Task.yield()
#expect(service.currentlyPlaying == second.id)
#expect(service.isPlaying)

service.audioPlayerBeginInterruption(firstPlayer)
await Task.yield()
#expect(service.currentlyPlaying == second.id)
#expect(service.isPlaying)
```

Also invoke `audioPlayerDecodeErrorDidOccur(firstPlayer, error: TestError.loadFailed)` and `audioPlayerEndInterruption(firstPlayer, withOptions: 0)` in focused ownership coverage; B must remain active.

Do not merge these with the current-player positive tests from Task 1. Both contracts must remain visible.

- [ ] **Step 4: Run the focused suite and verify RED.**

Run the same non-parallel service suite.

Expected failures: missing/failed resume semantics, timer replacement, and obsolete-player callbacks.

- [ ] **Step 5: Make `resume()` truthful.**

Implement:

```swift
func resume() {
    guard let player = audioPlayer, currentlyPlaying != nil else {
        clearCurrentPlayback()
        return
    }

    guard startPlayback(player) else {
        clearCurrentPlayback()
        return
    }

    isPlaying = true
    startProgressTimer()
}
```

`clearCurrentPlayback()` is generation-neutral. Resume is not a new load and must not advance `requestGeneration`.

- [ ] **Step 6: Make progress timer ownership explicit.**

Make the first line of `startProgressTimer()`:

```swift
stopProgressTimer()
```

Then schedule the existing 0.1-second repeating timer unchanged.

- [ ] **Step 7: Guard every delegate mutation by installed-player identity.**

Inside each `Task { @MainActor in ... }` body, before any state mutation:

```swift
guard player === self.audioPlayer else { return }
```

Apply to:

- `audioPlayerDidFinishPlaying`;
- `audioPlayerDecodeErrorDidOccur`;
- `audioPlayerBeginInterruption`;
- `audioPlayerEndInterruption`.

Decode errors may still be logged before the guard, but obsolete players cannot stop/pause/resume current state.

- [ ] **Step 8: Run focused tests and verify GREEN.**

Repeat the service suite. Confirm:

- current-player finish/decode/interruption tests from Task 1 still pass;
- obsolete-player callbacks are ignored;
- pause/resume uses a real installed player;
- missing/failed resume stays stopped;
- play → pause → resume replaces the timer safely;
- all identity/cache/generation tests remain green.

- [ ] **Step 9: Commit the lifecycle slice.**

```bash
git add Virgo/utilities/AudioPlaybackService.swift VirgoTests/AudioPlaybackServiceTests.swift
git commit -m "fix: make preview playback lifecycle truthful"
```

### Task 4: Run UI-boundary, repository, and platform verification gates

**Files:**
- Verify: `Virgo/views/DownloadedSongsView.swift`
- Verify: `VirgoTests/SecondWaveCoverageTests.swift`
- Verify: `VirgoTests/SwiftUIRenderingLibraryAndResultsTests.swift`
- Verify: all files changed in Tasks 1-3

**Interfaces:**
- Consumes: final `currentlyPlaying`, path-keyed cache, generation gate, truthful playback lifecycle, and existing downloaded-song wiring.
- Produces: evidence that HPA-576's focused behavior is green, the SwiftUI callers still mount, iPad code compiles, and any unrelated full-suite instability is distinguished from a branch regression with a fresh main baseline only when necessary.

- [ ] **Step 1: Keep the UI test surface narrow.**

Do not add a new XCUITest. Existing `SecondWaveCoverageTests` and `SwiftUIRenderingLibraryAndResultsTests` mount `DownloadedSongsView`/`SongsTabView`. Update them only if compilation or a direct old-property reference requires a mechanical change. Do not add production test hooks solely to inspect a row background or SF Symbol.

- [ ] **Step 2: Run the focused service tests — hard green gate.**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/AudioPlaybackServiceTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected result: `AudioPlaybackServiceTests` pass with zero failures/timeouts.

- [ ] **Step 3: Run directly affected SwiftUI coverage — hard green gate.**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/SecondWaveCoverageTests \
  -only-testing:VirgoTests/SwiftUIRenderingLibraryAndResultsTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected result: both directly affected rendering suites pass.

- [ ] **Step 4: Run the full macOS unit suite; baseline only if it fails.**

Run:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests \
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Primary expected result: `TEST SUCCEEDED`. Do not weaken this expectation preemptively.

If the branch run fails with an unrelated SwiftData/test-host crash or another failure outside the touched behavior, **then** run the identical command on a clean `origin/main` worktree before changing HPA-576 scope:

```bash
baseline_dir="$(mktemp -d /tmp/virgo-hpa576-main.XXXXXX)"
git worktree add --detach "$baseline_dir" origin/main
(
  cd "$baseline_dir"
  xcodebuild test \
    -project Virgo.xcodeproj \
    -scheme Virgo \
    -destination 'platform=macOS' \
    -configuration Debug \
    -only-testing:VirgoTests \
    -parallel-testing-enabled NO \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    -enableCodeCoverage YES \
    -destination-timeout 300 \
    -derivedDataPath ./DerivedData
)
baseline_status=$?
git worktree remove "$baseline_dir"
exit "$baseline_status"
```

Interpretation:

- If `main` passes, the branch full-suite failure is blocking; investigate it before handoff.
- If `main` reproduces the **same** unrelated failure signature, record it as pre-existing and do not pull that fix into HPA-576.
- A baseline reproduction never waives a focused HPA-576 failure. Steps 2-3 remain hard green gates.
- Do not treat a different random failure on `main` as proof that a branch-specific failure is safe.

- [ ] **Step 5: Compile the iPadOS path — hard green gate.**

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

Expected result: build succeeds, including the generation-gated `#if os(iOS)` audio-session error path.

- [ ] **Step 6: Run lint and diff hygiene.**

```bash
swiftlint lint --no-cache \
  Virgo/utilities/AudioPlaybackService.swift \
  Virgo/views/DownloadedSongsView.swift \
  VirgoTests/AudioPlaybackServiceTests.swift

git diff --check
git status --short
```

Expected result: no serious SwiftLint violations in touched files and no whitespace errors.

`AudioPlaybackService.swift` is already near the repository's size-warning thresholds. Treat warnings and errors differently:

- a new non-serious `type_body_length` / `file_length` warning is reported but does not justify a media abstraction or access-widening refactor by itself;
- if a serious lint **error** appears, first reduce local verbosity or make only the smallest extraction that preserves encapsulation;
- do not create `AudioPlaybackService+...` files speculatively just because the warning threshold is crossed.

- [ ] **Step 7: Review final scope against HPA-576.**

The production diff should contain only the local preview state-machine correction and ID-based downloaded-row check. Explicitly verify that it does **not** add:

- `AVAudioEngine` or another audio framework;
- BGM `.ogg` conversion/decoder work;
- actor pools or generalized cancellation infrastructure;
- cache/media repository abstractions;
- pending-selection/loading UI;
- persistence migrations or compatibility code;
- unrelated view refactors.

Also verify the test diff:

- contains no `currentlyPlayingSong` references;
- deleted the old hand-mutated stale-error sleep test in Task 1;
- current-player delegate tests install their callback player through the service;
- obsolete-player tests remain separate;
- loader-driven waits are continuation-based and bounded by the suite `.timeLimit`;
- real-file cache/progress/FIFO sleeps remain only where they observe AVFoundation/cache behavior rather than coordinate race order.

- [ ] **Step 8: Commit only mechanical rendering-test adjustments if verification required them.**

If Steps 1-6 required changes in existing rendering tests because of the property rename, commit only those files:

```bash
git add VirgoTests/SecondWaveCoverageTests.swift \
  VirgoTests/SwiftUIRenderingLibraryAndResultsTests.swift
git commit -m "test: align preview playback UI coverage"
```

If neither file changed, skip this commit.

## Plan self-review checklist

Before implementation handoff, re-read the design and verify:

- every identity-bearing service test inserts songs and compares `song.id`;
- active selection identity is `PersistentIdentifier`; cache identity is canonical preview path;
- Task 1 publishes no fake playing identity/state while loading;
- Task 1 deletes the old stale-error race test instead of migrating it twice;
- Task 1 migrates cached replay and FIFO tests before its GREEN checkpoint;
- Task 1 current-player delegate tests install the actual callback player;
- Task 2 guards before cache/install/publication and before stale-error audio-session cleanup;
- a start failure clears active state but does not evict an already-decoded cached resource;
- Task 3 keeps obsolete-player tests separate from current-player positive behavior;
- timer ownership uses play → pause → resume;
- `ControlledPlayerLoader` has no force unwrap on pending work and no polling timeout loop;
- the suite time limit turns missing continuation progress into a test timeout instead of an infinite hang;
- the full-suite gate expects success first and uses an identical clean-main baseline only after an unrelated failure;
- no task introduces HPA-85 work, off-main redesign, media abstractions, pending UI, or migration/compatibility infrastructure.
