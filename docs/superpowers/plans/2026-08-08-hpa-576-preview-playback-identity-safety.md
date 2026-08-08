# HPA-576 Preview Playback Identity and Request Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make downloaded-song preview playback use stable song/resource identity, ignore stale asynchronous loads and obsolete player callbacks, and publish playing state only after real `AVAudioPlayer` startup succeeds.

**Architecture:** Keep `AudioPlaybackService` as the single preview-playback owner. Add one main-actor async player-loader seam for deterministic tests, key the existing FIFO cache by canonical preview path, track active UI selection by `PersistentIdentifier`, and reject stale completions with one `UInt64` request generation. Do not add a new media layer or move AVFoundation work off-main in this ticket.

**Tech Stack:** Swift, SwiftUI, SwiftData `PersistentIdentifier`, AVFoundation `AVAudioPlayer`, Swift Testing, `Timer`, xcodebuild, SwiftLint.

## Global Constraints

- Keep `AVAudioPlayer`; do not introduce `AVAudioEngine` or a third-party decoder.
- Keep `AudioPlaybackService` as the preview playback owner; no repository/coordinator/actor hierarchy.
- Use `Song.persistentModelID` for active song identity and canonical preview file path for cache identity.
- One monotonically increasing `UInt64` generation owns stale-request invalidation; cooperative task cancellation is optional and not required.
- `isPlaying` becomes true only after the underlying player start succeeds.
- A stale completion cannot cache/install a player, mutate published state, start a timer, or deactivate the iOS audio session.
- `startProgressTimer()` always invalidates the previous timer before creating another.
- Obsolete `AVAudioPlayerDelegate` callbacks cannot mutate the active player state.
- Do not include HPA-85 server BGM format work or HPA-579/HPA-580 performance restructuring.
- Run tests with `-parallel-testing-enabled NO` per repository policy.

---

### Task 1: Establish stable song identity, resource cache identity, and a deterministic loader seam

**Files:**
- Modify: `VirgoTests/AudioPlaybackServiceTests.swift`
- Modify: `Virgo/utilities/AudioPlaybackService.swift`
- Modify: `Virgo/views/DownloadedSongsView.swift`

**Interfaces:**
- Consumes: `Song.persistentModelID`, `Song.previewFilePath`, existing `startPlayback: (AVAudioPlayer) -> Bool` injection.
- Produces: `AudioPlaybackService.currentlyPlayingSongID: PersistentIdentifier?`; initializer parameter `loadPlayer: @escaping @MainActor (URL) async throws -> AVAudioPlayer`; path-keyed `audioCache`/`audioCacheOrder`.

- [ ] **Step 1: Add a controlled async loader helper to the service test file.**

Place this helper near the existing WAV/player factories in `AudioPlaybackServiceTests.swift`:

```swift
@MainActor
private final class ControlledPlayerLoader {
    private var pending: [String: [CheckedContinuation<AVAudioPlayer, Error>]] = [:]
    private(set) var requests: [String] = []

    func load(_ url: URL) async throws -> AVAudioPlayer {
        let key = url.standardizedFileURL.path
        requests.append(key)
        return try await withCheckedThrowingContinuation { continuation in
            pending[key, default: []].append(continuation)
        }
    }

    func succeed(path: String, player: AVAudioPlayer) {
        let key = URL(fileURLWithPath: path).standardizedFileURL.path
        let continuation = pending[key]!.removeFirst()
        continuation.resume(returning: player)
    }

    func fail(path: String, error: Error) {
        let key = URL(fileURLWithPath: path).standardizedFileURL.path
        let continuation = pending[key]!.removeFirst()
        continuation.resume(throwing: error)
    }

    func waitForRequest(path: String, count: Int = 1) async {
        let key = URL(fileURLWithPath: path).standardizedFileURL.path
        for _ in 0..<1_000 {
            if requests.filter({ $0 == key }).count >= count { return }
            await Task.yield()
        }
        Issue.record("Expected preview load request for \(key), count \(count)")
    }
}
```

The helper deliberately controls only player creation. Keep `startPlayback` as the existing independent seam.

- [ ] **Step 2: Write the duplicate-title regression before production changes.**

Add a test equivalent to:

```swift
@Test("same-title songs use distinct preview identities and cache keys")
func sameTitleSongsUseDistinctPreviewIdentities() async throws {
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
    let first = makeSong(title: "Collision", previewPath: firstPath)
    let second = makeSong(title: "Collision", previewPath: secondPath)
    let firstPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: firstPath))
    let secondPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: secondPath))

    service.playPreview(for: first)
    await loader.waitForRequest(path: firstPath)
    loader.succeed(path: firstPath, player: firstPlayer)
    await Task.yield()
    #expect(service.currentlyPlayingSongID == first.persistentModelID)

    service.stop()
    service.playPreview(for: second)
    await loader.waitForRequest(path: secondPath)
    loader.succeed(path: secondPath, player: secondPlayer)
    await Task.yield()

    #expect(service.currentlyPlayingSongID == second.persistentModelID)
    #expect(service.duration == secondPlayer.duration)
    #expect(loader.requests == [
        URL(fileURLWithPath: firstPath).standardizedFileURL.path,
        URL(fileURLWithPath: secondPath).standardizedFileURL.path
    ])
}
```

This must force a second load despite the equal display title. With the current title-keyed cache/identity, the test cannot pass.

- [ ] **Step 3: Run the focused suite and verify RED.**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/AudioPlaybackServiceTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected result: compilation fails because `loadPlayer` and `currentlyPlayingSongID` do not exist yet.

- [ ] **Step 4: Add the minimal loader and stable identities.**

In `AudioPlaybackService.swift`, import SwiftData and change the published identity/cache fields:

```swift
@Published var currentlyPlayingSongID: PersistentIdentifier?

private var audioCache: [String: AVAudioPlayer] = [:]
private var audioCacheOrder: [String] = []
private let loadPlayer: @MainActor (URL) async throws -> AVAudioPlayer
private let startPlayback: (AVAudioPlayer) -> Bool
```

Use this initializer shape:

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

Add one canonical path helper and use it for both cache lookup and insertion:

```swift
private func previewCacheKey(for path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}
```

At this task boundary, load the player with the injected closure inside the existing `Task` path and publish `song.persistentModelID` rather than `song.title`. Do not add request-generation logic yet; Task 2 owns that behavior.

- [ ] **Step 5: Change downloaded-row preview highlighting to persistent identity.**

In `DownloadedSongsView.isPlaying(_:)`, replace the title comparison with:

```swift
return audioPlaybackService.isPlaying
    && audioPlaybackService.currentlyPlayingSongID == song.persistentModelID
```

Keep the regular `PlaybackService`/`currentlyPlaying` branch unchanged for non-preview playback.

- [ ] **Step 6: Update existing direct state assertions for the renamed published property.**

In `AudioPlaybackServiceTests.swift`, replace manual title assignments/assertions with the corresponding test `Song.persistentModelID`. Where a test does not have a `Song`, create one with `makeSong(title:)` rather than inventing an identifier.

- [ ] **Step 7: Run the focused suite and verify GREEN.**

Repeat the command from Step 3. Expected result: duplicate-title identity/cache coverage and all updated existing service tests pass.

- [ ] **Step 8: Commit the identity/cache slice.**

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
- Consumes: controlled `loadPlayer` seam and path/song identities from Task 1.
- Produces: private `requestGeneration: UInt64`; generation capture for each `playPreview(for:)`; invalidation in `stop()`; generation-gated success/error completion.

- [ ] **Step 1: Add the out-of-order completion regression.**

Use two same-actor suspended loads and complete B before A:

```swift
@Test("older preview completion cannot replace a newer selection")
func olderCompletionCannotReplaceNewerSelection() async throws {
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
    let first = makeSong(title: "First", previewPath: firstPath)
    let second = makeSong(title: "Second", previewPath: secondPath)
    let firstPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: firstPath))
    let secondPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: secondPath))

    service.playPreview(for: first)
    await loader.waitForRequest(path: firstPath)
    service.playPreview(for: second)
    await loader.waitForRequest(path: secondPath)

    loader.succeed(path: secondPath, player: secondPlayer)
    await Task.yield()
    #expect(service.currentlyPlayingSongID == second.persistentModelID)

    loader.succeed(path: firstPath, player: firstPlayer)
    await Task.yield()
    #expect(service.currentlyPlayingSongID == second.persistentModelID)
    #expect(service.duration == secondPlayer.duration)

    service.stop()
    service.playPreview(for: first)
    await loader.waitForRequest(path: firstPath, count: 2)
}
```

The final request proves the stale first completion did not populate the cache.

- [ ] **Step 2: Add stop-during-load and stale-error regressions.**

Add one test that suspends A, calls `stop()`, then completes A and asserts `isPlaying == false`, `currentlyPlayingSongID == nil`, `duration == 0`, and a subsequent A request reaches the loader again.

Add a second test that suspends A, starts/finishes B successfully, then calls `loader.fail(path: firstPath, error: TestError.loadFailed)` and asserts B remains the active ID with `isPlaying == true` and B's duration. Define a tiny test-local error enum:

```swift
enum TestError: Error { case loadFailed }
```

Do not add an audio-session protocol solely to observe iOS deactivation; the production generation guard must return before that side effect.

- [ ] **Step 3: Run the focused suite and verify RED.**

Run the Task 1 focused `AudioPlaybackServiceTests` command. Expected result: stale-completion/stop tests fail because old async work can still mutate or cache state.

- [ ] **Step 4: Add request generation and central replacement cleanup.**

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

Make `playPreview(for:)` obtain `let generation = nextRequestGeneration()` before clearing the installed player/timer/state. Keep that cleanup in a private helper that does **not** advance the generation itself, so one call owns one generation.

Make `stop()` call `invalidatePreviewRequests()` before the same cleanup helper.

- [ ] **Step 5: Gate loaded-player success before any cache/install/state mutation.**

Pass the captured generation through the async load path and use:

```swift
guard generation == requestGeneration else {
    player.stop()
    return
}
```

Place this guard before `cacheAudioPlayer`, `audioPlayer = player`, published-property writes, and timer startup. A stale player is discarded, not cached.

- [ ] **Step 6: Gate the error path before state and iOS session cleanup.**

Change the error handler to accept the request generation and begin with:

```swift
guard generation == requestGeneration else { return }
```

Only a current request may clear playback state or execute the existing `AVAudioSession.sharedInstance().setActive(false)` path on iOS.

- [ ] **Step 7: Run focused tests and verify GREEN.**

Repeat the focused service suite command. The out-of-order completion, stop-during-load, and stale-error cases must pass without fixed race sleeps.

- [ ] **Step 8: Commit the stale-request slice.**

```bash
git add Virgo/utilities/AudioPlaybackService.swift VirgoTests/AudioPlaybackServiceTests.swift
git commit -m "fix: ignore stale preview load completions"
```

### Task 3: Make playback publication, timer ownership, and delegate callbacks truthful

**Files:**
- Modify: `VirgoTests/AudioPlaybackServiceTests.swift`
- Modify: `Virgo/utilities/AudioPlaybackService.swift`

**Interfaces:**
- Consumes: current-generation loaded/cached player and `startPlayback` seam.
- Produces: one shared successful-start path; safe `resume()`; single active progress timer; player-identity guard on all delegate callbacks.

- [ ] **Step 1: Replace sleep-based start-failure coverage with controlled completion and add resume failures.**

Update the existing `playPreview` start-failure test to use `ControlledPlayerLoader`, complete the player explicitly, then assert:

```swift
#expect(service.isPlaying == false)
#expect(service.currentlyPlayingSongID == nil)
#expect(service.currentTime == 0)
#expect(service.duration == 0)
```

Add a fresh-service test:

```swift
@Test("resume without an installed player stays stopped")
func resumeWithoutPlayerStaysStopped() {
    let service = AudioPlaybackService(startPlayback: { _ in true })
    service.resume()
    #expect(service.isPlaying == false)
    #expect(service.currentlyPlayingSongID == nil)
}
```

Add a resume-start-failure test using a `startPlayback` closure that returns `true` on the initial play and `false` after `pause()`:

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

After the initial successful load, pause and resume. Expect the failed resume to clear playing/selection state and leave no progress updates active.

- [ ] **Step 2: Add timer single-owner coverage without widening production visibility.**

Add a test-only reflection helper:

```swift
private func progressTimer(in service: AudioPlaybackService) -> Timer? {
    Mirror(reflecting: service).descendant("progressTimer") as? Timer
}
```

After a successful preview start, capture the first timer. Call `resume()` while the same player is installed, capture the replacement timer, and assert:

```swift
#expect(firstTimer?.isValid == false)
#expect(secondTimer?.isValid == true)
#expect(firstTimer !== secondTimer)
```

This verifies replacement invalidation directly without adding a timer factory/test API to production.

- [ ] **Step 3: Add obsolete-player delegate coverage.**

Load player A, replace it with player B, then manually invoke a delegate callback with A:

```swift
service.audioPlayerDidFinishPlaying(firstPlayer, successfully: true)
await Task.yield()
#expect(service.currentlyPlayingSongID == second.persistentModelID)
#expect(service.isPlaying)
```

Add the same ownership expectation for `audioPlayerBeginInterruption(firstPlayer)`. The implementation will apply the identical ownership guard to finish, decode-error, interruption-begin, and interruption-end callbacks.

- [ ] **Step 4: Run the focused suite and verify RED.**

Run the same non-parallel `AudioPlaybackServiceTests` command. Expected failures: optimistic state/resume behavior, timer replacement, and stale delegate callbacks.

- [ ] **Step 5: Introduce one shared player-start helper.**

Add a private helper with this contract:

```swift
@discardableResult
private func startInstalledPlayer(
    _ player: AVAudioPlayer,
    songID: PersistentIdentifier
) -> Bool
```

The helper should:

1. assign `audioPlayer = player` and `player.delegate = self`;
2. set `player.currentTime = 0`, `duration = player.duration`, `currentTime = 0`;
3. call `startPlayback(player)`;
4. on failure, stop/discard the player and clear `audioPlayer`, selection ID, duration/current time, `isPlaying`, and timer;
5. on success, set `currentlyPlayingSongID = songID`, then `isPlaying = true`, then start the progress timer.

Both cached and newly loaded player paths use this helper. Cache a newly loaded player only after its generation is current; do not publish playing state before the helper succeeds.

- [ ] **Step 6: Make `togglePlayback` and `resume` reflect real state.**

Use persistent ID in the toggle:

```swift
let songID = song.persistentModelID
if currentlyPlayingSongID == songID && isPlaying {
    pause()
} else if currentlyPlayingSongID == songID {
    resume()
} else {
    playPreview(for: song)
}
```

Implement `resume()` as:

```swift
guard let player = audioPlayer, currentlyPlayingSongID != nil else {
    clearCurrentPlayback()
    return
}
guard startPlayback(player) else {
    clearCurrentPlayback()
    return
}
isPlaying = true
startProgressTimer()
```

`clearCurrentPlayback()` here means the private cleanup helper from Task 2 and must not accidentally advance request generation; `resume()` is not starting a new load.

- [ ] **Step 7: Enforce single timer ownership.**

Make the first line of `startProgressTimer()`:

```swift
stopProgressTimer()
```

Then schedule the existing 0.1-second timer unchanged.

- [ ] **Step 8: Guard every AVAudioPlayer delegate mutation by object identity.**

Inside each `Task { @MainActor in ... }` body, add:

```swift
guard player === self.audioPlayer else { return }
```

Apply it before calling `stop()`, `pause()`, or `resume()` in:

- `audioPlayerDidFinishPlaying`;
- `audioPlayerDecodeErrorDidOccur`;
- `audioPlayerBeginInterruption`;
- `audioPlayerEndInterruption`.

The decode error may still be logged, but stale players cannot mutate service state.

- [ ] **Step 9: Run focused tests and verify GREEN.**

Repeat the focused service suite. Ensure the existing cached-replay/progress tests still pass after their old title-based assertions are converted to persistent IDs.

- [ ] **Step 10: Commit the lifecycle slice.**

```bash
git add Virgo/utilities/AudioPlaybackService.swift VirgoTests/AudioPlaybackServiceTests.swift
git commit -m "fix: make preview playback state truthful"
```

### Task 4: Run UI-boundary and repository verification gates

**Files:**
- Verify: `Virgo/views/DownloadedSongsView.swift`
- Verify: `VirgoTests/SecondWaveCoverageTests.swift`
- Verify: `VirgoTests/SwiftUIRenderingLibraryAndResultsTests.swift`
- Verify: all files changed in Tasks 1-3

**Interfaces:**
- Consumes: final `currentlyPlayingSongID`, stable cache/load lifecycle, and existing downloaded-song view wiring.
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

Expected result: all identity, stale-generation, startup/resume, cache, timer, and delegate regressions pass.

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

- [ ] **Step 7: Review scope against HPA-576 before handoff.**

The final production diff should contain only the local preview state-machine correction and ID-based downloaded-row check. Explicitly verify that it does **not** add AVAudioEngine, BGM `.ogg` conversion, actor pools, generalized caching/media abstractions, persistence migrations, or unrelated view refactors.

- [ ] **Step 8: Commit any verification-only test adjustments if required.**

If Steps 2-6 required mechanical updates in existing rendering tests because of the renamed property, commit only those files:

```bash
git add VirgoTests/SecondWaveCoverageTests.swift \
  VirgoTests/SwiftUIRenderingLibraryAndResultsTests.swift
git commit -m "test: align preview playback UI coverage"
```

If neither file changed, skip this commit rather than creating an empty commit.
