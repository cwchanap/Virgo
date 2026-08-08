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
- One monotonically increasing `UInt64` generation owns stale-request invalidation; cooperative task cancellation is optional and not required.
- `isPlaying` becomes true only after the underlying player start succeeds.
- A stale completion cannot cache/install a player, mutate published state, start a timer, or deactivate the iOS audio session.
- `startProgressTimer()` always invalidates the previous timer before creating another.
- Obsolete `AVAudioPlayerDelegate` callbacks cannot mutate the active player state; active-player callbacks retain their existing behavior.
- Deterministic stale-load tests use continuation-driven request waiting, not sleeps or bounded `Task.yield()` polling loops.
- Do not include HPA-85 server BGM format work or HPA-579/HPA-580 performance restructuring.
- Run tests with `-parallel-testing-enabled NO` per repository policy.
- A non-blocking SwiftLint size warning alone is not a reason to introduce a new type or cross-file abstraction.

## Existing-test migration map

These current tests encode behavior that changes during HPA-576. Migrate them deliberately instead of mechanically renaming `currentlyPlayingSong`:

| Existing test | Owning task | Required change |
| --- | --- | --- |
| `testPlayPreviewWithInvalidPath` | Task 1 | Replace optimistic `isPlaying == true` + sleep with controlled loader failure; assert stopped while pending and stopped after failure. |
| `testTogglePlaybackDifferentSongStartsPlayback` | Task 1 | Use an inserted song + controlled load; assert no playing ID while pending, then playing only after load + start success. |
| `testPlayPreviewPlayFailureClearsState` | Task 1 | Complete the controlled load explicitly and make `startPlayback` return `false`; no fixed sleep. |
| `testTogglePlaybackPauseAndResume` | Task 3 | Stop hand-stuffing state. Install the real player through the service, then pause and resume it. |
| `testPlayPreviewFailureAfterSongSwitchKeepsCurrentState` | Task 2 | Delete it. The generation-driven stale-error regression replaces this hand-mutated sleep test. |
| `testAudioPlayerDidFinishPlayingStopsPlayback` | Task 3 | Install the callback player through the controlled load/start path before invoking the delegate. |
| `testAudioPlayerDecodeErrorStopsPlayback` | Task 3 | Install the callback player through the controlled load/start path before invoking the delegate. |
| `testAudioPlayerBeginInterruptionPausesPlayback` | Task 3 | Install the callback player through the controlled load/start path before invoking the delegate. |
| `testAudioPlayerEndInterruptionNoStateChangeOnMacOS` | Task 3 | Install the callback player first, then verify the current-player macOS callback remains a no-op. |
| cached replay / progress / FIFO eviction | Tasks 1/4 | Replace title assertions with `song.id`; keep their real-file coverage unless a touched assertion needs deterministic loader control. |

The purpose of this table is to avoid two failure modes during implementation: retaining sleeps that no longer model the state machine, and making delegate ownership tests pass or fail for the wrong player.

---

### Task 1: Establish stable identity, path-keyed cache, deterministic loading, and truthful initial starts

**Files:**
- Modify: `VirgoTests/AudioPlaybackServiceTests.swift`
- Modify: `Virgo/utilities/AudioPlaybackService.swift`
- Modify: `Virgo/views/DownloadedSongsView.swift`

**Interfaces:**
- Consumes: `Song.id`, `Song.previewFilePath`, existing `startPlayback: (AVAudioPlayer) -> Bool` injection.
- Produces: `AudioPlaybackService.currentlyPlaying: PersistentIdentifier?`; initializer parameter `loadPlayer: @escaping @MainActor (URL) async throws -> AVAudioPlayer`; `previewCacheKey(for:)`; path-keyed `audioCache`/`audioCacheOrder`; shared `startInstalledPlayer(_:songID:)` for cached and fresh starts.

This task is an internal checkpoint in one HPA-576 implementation PR. It intentionally does **not** solve stale async completion yet; Task 2 must land before the implementation PR is ready for review. Do not merge or release the Task 1 commit alone.

- [ ] **Step 1: Add a continuation-driven controlled loader to the service tests.**

Place this helper near the existing WAV/player factories in `AudioPlaybackServiceTests.swift`:

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
        let key = URL(fileURLWithPath: path).standardizedFileURL.path
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
        let key = URL(fileURLWithPath: path).standardizedFileURL.path
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

This removes the review's bounded-yield soft timeout and force-unwrapped continuation queue. `Task.yield()` may still be used once after a controlled completion to let the service's already-resumed main-actor task finish; it must not be used as a polling loop or timeout.

- [ ] **Step 2: Add an inserted-song helper for identity assertions.**

Keep the existing `makeSong` factory for tests that do not care about SwiftData identity. Add:

```swift
private func insertSong(title: String, previewPath: String? = nil) -> Song {
    let song = makeSong(title: title, previewPath: previewPath)
    TestContainer.shared.context.insert(song)
    return song
}
```

Call this only inside `TestSetup.withTestSetup { ... }`. Matching `PlaybackServiceTests`, saving is not required just to obtain/use the context-backed `song.id` in the same test.

- [ ] **Step 3: Write the duplicate-title and truthful-loading regressions before production changes.**

Add the same-title identity/cache regression using inserted songs:

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
        let firstPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: firstPath))
        let secondPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: secondPath))

        service.playPreview(for: first)
        #expect(!service.isPlaying)
        #expect(service.currentlyPlaying == nil)
        await loader.waitForRequest(path: firstPath)
        loader.succeed(path: firstPath, player: firstPlayer)
        await Task.yield()
        #expect(service.currentlyPlaying == first.id)
        #expect(service.isPlaying)

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

Rewrite `testPlayPreviewWithInvalidPath` as a controlled loader failure and assert `isPlaying == false` / `currentlyPlaying == nil` both while pending and after failure. Rewrite `testTogglePlaybackDifferentSongStartsPlayback` so the different song is inserted, the service remains stopped while the load is pending, and the ID appears only after controlled success. Rewrite `testPlayPreviewPlayFailureClearsState` so the loader succeeds but `startPlayback` returns `false`, then assert a fully stopped state without sleeping.

- [ ] **Step 4: Run the focused suite and verify RED.**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/AudioPlaybackServiceTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected result: compilation fails because `loadPlayer` and `currentlyPlaying` do not yet have the required interfaces; the old optimistic assertions also conflict with the new tests.

- [ ] **Step 5: Reuse Virgo's existing `PersistentIdentifier` naming and add the loader/cache seams.**

In `AudioPlaybackService.swift`, import SwiftData and replace the title identity:

```swift
@Published var currentlyPlaying: PersistentIdentifier?

private var audioCache: [String: AVAudioPlayer] = [:]
private var audioCacheOrder: [String] = []
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

Add the canonical key helper:

```swift
private func previewCacheKey(for path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}
```

Change `tryPlayCachedPreview` / `cacheAudioPlayer` to accept the canonical cache key rather than a title. Keep the ten-entry FIFO behavior unchanged.

- [ ] **Step 6: Add the shared truthful initial-start helper.**

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
        player.stop()
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

Both cached and newly loaded **current** players will ultimately use this helper. Task 2 will add the generation gate that defines "current" for async completions.

Do not set `currentlyPlaying` or `isPlaying` before this helper succeeds.

- [ ] **Step 7: Remove optimistic publication from selection/loading paths.**

Make `togglePlayback(for:)` only route intent:

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

Make `playPreview(for:)` clear the previous installed playback state before starting a replacement, but publish no new ID while the load is pending. For a missing preview path, remain stopped. For a cached player, call `startInstalledPlayer(cachedPlayer, songID: song.id)`. For a fresh load, call the injected `loadPlayer` and then the shared start helper.

At this checkpoint the pre-existing stale-completion race still exists for fresh async loads. Do not add temporary `pendingSongID` state just to make Task 1 independently shippable; Task 2 introduces the one final generation mechanism. The implementation PR cannot be marked ready before Task 2 is complete.

- [ ] **Step 8: Change downloaded-row preview highlighting to the existing ID convention.**

In `DownloadedSongsView.isPlaying(_:)`, use:

```swift
return audioPlaybackService.isPlaying
    && audioPlaybackService.currentlyPlaying == song.id
```

Keep the regular `PlaybackService` branch unchanged:

```swift
return currentlyPlaying == song.id
```

- [ ] **Step 9: Migrate direct property assertions required for Task 1 GREEN.**

Replace `currentlyPlayingSong` title assignments/assertions with inserted-song IDs where identity is meaningful. Tests that simply verify `stop()` clearing state may set `currentlyPlaying = insertedSong.id` inside `TestSetup.withTestSetup`.

Keep the old `testPlayPreviewFailureAfterSongSwitchKeepsCurrentState` only long enough for the Task 1 suite to compile; Task 2 explicitly deletes it rather than preserving its hand-mutated race model.

- [ ] **Step 10: Run focused tests and verify GREEN for the Task 1 checkpoint.**

Repeat the Step 4 command. Expected result: identity, path cache, missing/failed load, initial start-failure, and different-song loading behavior pass with truthful initial publication. The known stale-load race is not claimed fixed until Task 2.

- [ ] **Step 11: Commit the identity/cache/loading slice.**

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
- Consumes: controlled `loadPlayer`, truthful initial-start helper, path cache, and `song.id` identity from Task 1.
- Produces: private `requestGeneration: UInt64`; generation capture for every `playPreview(for:)`; invalidation in `stop()`; generation-gated success/error completion before cache/install/publish/session cleanup.

- [ ] **Step 1: Delete the superseded hand-mutated stale-error test.**

Remove `testPlayPreviewFailureAfterSongSwitchKeepsCurrentState`. Do not convert its direct published-state mutation to IDs. The tests in Steps 2-3 replace it with real request ordering through the loader seam.

- [ ] **Step 2: Add the out-of-order completion regression with inserted songs.**

```swift
@Test("older preview completion cannot replace a newer selection")
func olderCompletionCannotReplaceNewerSelection() async throws {
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
        let first = insertSong(title: "First", previewPath: firstPath)
        let second = insertSong(title: "Second", previewPath: secondPath)
        let firstPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: firstPath))
        let secondPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: secondPath))

        service.playPreview(for: first)
        await loader.waitForRequest(path: firstPath)
        service.playPreview(for: second)
        await loader.waitForRequest(path: secondPath)

        loader.succeed(path: secondPath, player: secondPlayer)
        await Task.yield()
        #expect(service.currentlyPlaying == second.id)
        #expect(service.isPlaying)

        loader.succeed(path: firstPath, player: firstPlayer)
        await Task.yield()
        #expect(service.currentlyPlaying == second.id)
        #expect(service.duration == secondPlayer.duration)

        service.stop()
        service.playPreview(for: first)
        await loader.waitForRequest(path: firstPath, count: 2)
    }
}
```

The final request proves the stale first completion did not enter the path-keyed cache.

- [ ] **Step 3: Add stop-during-load and stale-error regressions.**

Define the test-local error:

```swift
enum TestError: Error {
    case loadFailed
}
```

Add a test that:

1. starts inserted song A and waits until its loader request is pending;
2. calls `service.stop()`;
3. completes A successfully;
4. yields once for the resumed task;
5. asserts `isPlaying == false`, `currentlyPlaying == nil`, `duration == 0`;
6. calls `playPreview(for: A)` again and waits for loader request count 2, proving the stopped request was not cached.

Add another test that:

1. starts inserted A and suspends it;
2. starts inserted B and completes B successfully;
3. verifies B is active;
4. calls `loader.fail(path: firstPath, error: TestError.loadFailed)`;
5. yields once;
6. verifies B remains active and its duration/state are unchanged.

Do not add an audio-session protocol just to observe `setActive(false)`. The production stale-generation guard must execute before that existing iOS side effect; the generic iPad build in Task 4 verifies the guarded path compiles.

- [ ] **Step 4: Run the focused suite and verify RED.**

Run the Task 1 non-parallel `AudioPlaybackServiceTests` command. Expected failures: stale success can still replace/cache after B, stop does not invalidate a suspended load, and stale error can still reach current-request cleanup.

- [ ] **Step 5: Add one generation counter and central request invalidation.**

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

Make `playPreview(for:)` obtain:

```swift
let generation = nextRequestGeneration()
```

before replacement cleanup. Pass the captured generation only into the fresh async load path. A cached start is synchronous, but advancing the generation still invalidates any older in-flight load before the cache start occurs.

Make `stop()` call `invalidatePreviewRequests()` before the existing cleanup. Keep cleanup itself generation-neutral so one operation does not accidentally advance twice.

- [ ] **Step 6: Gate fresh success before cache/install/publication.**

Pass `generation` through `loadAndPlayPreview`. After `loadPlayer(url)` returns and before **any** cache/start/state mutation:

```swift
guard generation == requestGeneration else {
    player.stop()
    return
}
```

Only then call `cacheAudioPlayer(player, for: cacheKey)` and `startInstalledPlayer(player, songID: songID)`.

This is the final stale-cache boundary; do not retain or add a title/ID fallback guard around the cache.

- [ ] **Step 7: Gate fresh-load errors before state and iOS session cleanup.**

Change the error handler to accept the captured generation and begin with:

```swift
guard generation == requestGeneration else { return }
```

Only a current request may clear playback state or execute the existing iOS `AVAudioSession.sharedInstance().setActive(false)` error cleanup.

- [ ] **Step 8: Run focused tests and verify GREEN.**

Repeat the focused service suite command. The out-of-order completion, stop-during-load, stale-error, duplicate-title, truthful-start, and path-cache tests must all pass without fixed race sleeps or bounded-yield polling.

- [ ] **Step 9: Commit the stale-request slice.**

```bash
git add Virgo/utilities/AudioPlaybackService.swift VirgoTests/AudioPlaybackServiceTests.swift
git commit -m "fix: ignore stale preview load completions"
```

### Task 3: Make resume, timer ownership, and delegate ownership truthful

**Files:**
- Modify: `VirgoTests/AudioPlaybackServiceTests.swift`
- Modify: `Virgo/utilities/AudioPlaybackService.swift`

**Interfaces:**
- Consumes: current-generation installed player and `startPlayback` seam from Tasks 1-2.
- Produces: safe `resume()`; single active progress timer; player-identity guard on all delegate callbacks; active-player delegate tests that install the actual callback player.

- [ ] **Step 1: Add a test helper that installs the real player through the service.**

Add:

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

Use only inserted songs with this helper.

- [ ] **Step 2: Rewrite every existing active-player delegate test before adding the ownership guard.**

For `testAudioPlayerDidFinishPlayingStopsPlayback`:

1. create an inserted song, controlled loader, service with `startPlayback: { _ in true }`, path, and player;
2. call `await startPreview(...)` so `audioPlayer === player`;
3. invoke `service.audioPlayerDidFinishPlaying(player, successfully: true)`;
4. `await Task.yield()`;
5. assert `isPlaying == false`, `currentlyPlaying == nil`, `currentTime == 0`, and `duration == 0`.

Rewrite `testAudioPlayerDecodeErrorStopsPlayback` the same way and assert the installed player is stopped/cleared.

Rewrite `testAudioPlayerBeginInterruptionPausesPlayback` the same way and assert `isPlaying == false` while `currentlyPlaying == song.id` remains available for resume.

Rewrite `testAudioPlayerEndInterruptionNoStateChangeOnMacOS` so the callback player is the installed current player; on macOS, calling `audioPlayerEndInterruption(player, withOptions: 0)` must leave the active state unchanged.

Delete the old pattern that manually sets published fields and then passes a player that the service never installed. Once the ownership guard exists, that pattern tests only the negative path and cannot prove current-player behavior.

- [ ] **Step 3: Rewrite the existing pause/resume toggle test to use a real installed player.**

Create an inserted song + controlled load, start it through `startPreview`, then:

```swift
service.togglePlayback(for: song)
#expect(!service.isPlaying)
#expect(service.currentlyPlaying == song.id)

service.togglePlayback(for: song)
#expect(service.isPlaying)
#expect(service.currentlyPlaying == song.id)
```

This preserves the original pause/resume contract without relying on a nonexistent player.

- [ ] **Step 4: Add missing resume-failure regressions.**

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

Add a resume-start-failure test. Use a controlled loader and a `startPlayback` closure that succeeds exactly once:

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

Start an inserted song successfully, call `pause()`, then `resume()`. Assert the failed resume clears `isPlaying`, `currentlyPlaying`, current/duration, and the installed player/timer state rather than publishing a fake resume.

- [ ] **Step 5: Add timer single-owner coverage on the real lifecycle.**

Add the test-only reflection helper:

```swift
private func progressTimer(in service: AudioPlaybackService) -> Timer? {
    Mirror(reflecting: service).descendant("progressTimer") as? Timer
}
```

Exercise **play → pause → resume**, not `resume()` while already playing:

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

The service for this test uses a `startPlayback` seam that returns `true` for both initial start and resume.

- [ ] **Step 6: Add obsolete-player delegate regressions as separate negative-path tests.**

Start inserted song A/player A, then replace it with inserted song B/player B. Invoke callbacks with A after B is active.

At minimum cover finish and interruption-begin explicitly:

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

Also invoke `audioPlayerDecodeErrorDidOccur(firstPlayer, error: TestError.loadFailed)` and `audioPlayerEndInterruption(firstPlayer, withOptions: 0)` in a focused ownership test and assert B remains active. Keep these separate from the active-player tests in Step 2 so both positive and negative delegate contracts are visible.

- [ ] **Step 7: Run the focused suite and verify RED.**

Run the same non-parallel `AudioPlaybackServiceTests` command. Before production changes, expect failures for missing-player/failed resume semantics, timer replacement, and obsolete-player delegate callbacks. The rewritten active-player delegate tests should still exercise and preserve the current positive behavior.

- [ ] **Step 8: Make `resume()` reflect the real player start.**

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

`clearCurrentPlayback()` is the generation-neutral cleanup helper introduced while centralizing replacement state in Task 2. `resume()` is not a new load and must not advance `requestGeneration`.

- [ ] **Step 9: Enforce single timer ownership.**

Make the first line of `startProgressTimer()`:

```swift
stopProgressTimer()
```

Then schedule the existing 0.1-second timer unchanged.

- [ ] **Step 10: Guard every delegate state mutation by installed-player identity.**

Inside each existing `Task { @MainActor in ... }` body, add:

```swift
guard player === self.audioPlayer else { return }
```

Apply it before calling `stop()`, `pause()`, or `resume()` in:

- `audioPlayerDidFinishPlaying`;
- `audioPlayerDecodeErrorDidOccur`;
- `audioPlayerBeginInterruption`;
- `audioPlayerEndInterruption`.

The decode error may still be logged before the guard, but stale players cannot mutate service state.

- [ ] **Step 11: Run focused tests and verify GREEN.**

Repeat the focused service suite. Confirm:

- current-player finish/decode/interruption tests pass through a player actually installed by the service;
- obsolete-player callbacks are ignored;
- pause/resume uses a real player;
- failed/missing resume stays stopped;
- play → pause → resume replaces the timer safely;
- all Task 1-2 identity/cache/generation tests remain green.

- [ ] **Step 12: Commit the lifecycle slice.**

```bash
git add Virgo/utilities/AudioPlaybackService.swift VirgoTests/AudioPlaybackServiceTests.swift
git commit -m "fix: make preview playback lifecycle truthful"
```

### Task 4: Run UI-boundary and repository verification gates

**Files:**
- Verify: `Virgo/views/DownloadedSongsView.swift`
- Verify: `VirgoTests/SecondWaveCoverageTests.swift`
- Verify: `VirgoTests/SwiftUIRenderingLibraryAndResultsTests.swift`
- Verify: all files changed in Tasks 1-3

**Interfaces:**
- Consumes: final `currentlyPlaying`, stable cache/load lifecycle, generation gate, and existing downloaded-song view wiring.
- Produces: evidence that the service change compiles through SwiftUI callers on macOS/iPadOS and does not require broader view architecture changes.

- [ ] **Step 1: Keep the UI test surface narrow.**

Do not add a new XCUITest. Existing `SecondWaveCoverageTests` and `SwiftUIRenderingLibraryAndResultsTests` already mount `DownloadedSongsView`/`SongsTabView`. Update them only if compilation or a direct old-property reference requires it. Do not add a production test helper solely to inspect a background color or SF Symbol.

- [ ] **Step 2: Run focused service tests.**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/AudioPlaybackServiceTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected result: all identity, stale-generation, startup/resume, cache, timer, and active/obsolete delegate regressions pass.

- [ ] **Step 3: Run directly affected SwiftUI coverage.**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/SecondWaveCoverageTests \
  -only-testing:VirgoTests/SwiftUIRenderingLibraryAndResultsTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected result: downloaded/song-tab rendering continues to compile and mount with the ID-based preview service.

- [ ] **Step 4: Run the full macOS unit suite.**

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

Expected result: `TEST SUCCEEDED`.

- [ ] **Step 5: Compile the iPadOS path.**

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

Expected result: build succeeds, including the generation-gated iOS audio-session error path.

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

`AudioPlaybackService.swift` is already close to the repository's size-warning thresholds. Treat warnings and errors differently:

- a new non-serious `type_body_length` / `file_length` warning is reported but does not justify a media abstraction or access-widening refactor by itself;
- if a serious lint **error** appears, first reduce local verbosity or move behavior only when it can be extracted without widening private state or inventing a new architecture;
- do not create `AudioPlaybackService+...` files speculatively just because the warning threshold is crossed.

- [ ] **Step 7: Review scope against HPA-576 before handoff.**

The final production diff should contain only the local preview state-machine correction and ID-based downloaded-row check. Explicitly verify that it does **not** add AVAudioEngine, BGM `.ogg` conversion, actor pools, generalized caching/media abstractions, persistence migrations, compatibility code, or unrelated view refactors.

Also verify the test diff no longer contains the old hand-mutated stale-error sleep test or active delegate tests that invoke callbacks on a player the service never installed.

- [ ] **Step 8: Commit any verification-only rendering-test adjustments if required.**

If Steps 2-6 required mechanical updates in existing rendering tests because of the renamed property, commit only those files:

```bash
git add VirgoTests/SecondWaveCoverageTests.swift \
  VirgoTests/SwiftUIRenderingLibraryAndResultsTests.swift
git commit -m "test: align preview playback UI coverage"
```

If neither file changed, skip this commit rather than creating an empty commit.

## Plan self-review checklist

Before implementation handoff, re-read the design and this plan and verify:

- every identity assertion uses an inserted song and `song.id`;
- the cache key is resource path, never title or song ID;
- Task 1 publishes no fake loading state;
- Task 2 guards before cache/install/publication and before stale-error audio-session cleanup;
- the old hand-mutated stale-error test is removed rather than renamed;
- Task 3 current-player delegate tests install the callback player through the service;
- obsolete-player tests remain separate and prove the negative path;
- the timer test uses play → pause → resume;
- `ControlledPlayerLoader` has continuation-driven request waiting and no `!` on missing pending work;
- no task introduces HPA-85 work, off-main redesign, media abstractions, or migration/compatibility infrastructure.
