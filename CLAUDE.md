# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Virgo is a SwiftUI-based drum notation and metronome application for iPadOS and macOS. The app provides interactive drum track visualization with musical notation, metronome functionality, and gameplay-style views for practicing drum patterns.

- **SwiftUI + SwiftData**: Modern declarative UI with persistent storage
- **Supported platforms**: macOS 14.0+ and iPadOS via the iOS SDK
- **AVFoundation**: Audio engine for metronome and song preview playback
- **No iPhone target**: Do not add iPhone destinations, iPhone UI assumptions, or `TARGETED_DEVICE_FAMILY = "1,2"` back to the project. The app target should remain iPad-only for iOS-family builds (`TARGETED_DEVICE_FAMILY = 2`). Xcode build settings may still mention `iphoneos`/`iphonesimulator`; those SDK platform names are also used for iPad builds.

## Development Commands

### Build & Test (macOS target is sufficient for development)
```bash
# Build for macOS
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build

# Build for iPad simulator compatibility (use an available iPad simulator, never iPhone)
xcodebuild -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' build

# Run all unit tests (CI format - recommended)
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData

# Run specific test class
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/MetronomeEngineTests test

# Run specific test method
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/DTXFileParserTests/testComplexDTXContent test
```

### Running Tests (preferred: XcodeBuildMCP, fallback: xcodebuild)

**Always disable parallel testing** — this machine does not have enough resources for concurrent test workers, and parallel `xcodebuild test` leaves orphaned clones in `~/Library/Developer/XCTestDevices` that accumulate to tens of GB.

**Preferred — via XcodeBuildMCP** (configured in Devin CLI):
1. Call `session_show_defaults` first to verify the active project/scheme/destination.
2. If defaults are unset, call `session_set_defaults` with `projectPath`, `scheme`, and `simulatorName` (or macOS destination as appropriate).
3. Run `test_sim` (iPad simulator) or `test_macos` (macOS) with `extraArgs: ["-parallel-testing-enabled", "NO"]` to disable cloning. `test_sim` must target an iPad simulator destination only — never an iPhone simulator.

**Fallback — direct xcodebuild** (when XcodeBuildMCP is unavailable):
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

### Code Quality
```bash
swiftlint lint         # Manual lint
swiftlint lint --fix   # Auto-fix
```

### Initial Setup
```bash
./scripts/setup-git-hooks.sh   # Installs SwiftLint pre-commit hook
cp Virgo/Config/ServerEndpoints.env.example Virgo/Config/ServerEndpoints.env
```

`Virgo/Config/ServerEndpoints.env` supplies `GRAPHQL_ENDPOINT` and `R2_BASE_URL`. It is gitignored;
CI regenerates it from repository variables via `.github/scripts/generate-endpoints-env.sh`. When the
file is missing or a key is empty, `ServerConfig` falls back to a local-dev placeholder endpoint and
disables audio downloads, so a fresh checkout still builds and tests green.

`AGENTS.md` is a symlink to `CLAUDE.md` — edit `CLAUDE.md` only.

### SwiftLint Size Limits (frequent refactor blockers)
- Line: 120 (warn) / 150 (error)
- Function body: 50 / 100 lines
- Type body: 300 / 600 lines
- File: 600 / 1000 lines

### CI
GitHub Actions: `.github/workflows/ci.yml` (macOS build + unit tests, plus a guard that rejects iPhone targeting), `ui-tests.yml` (macOS UI tests). If simulator UI tests are added later, use iPad simulator destinations only.

## Architecture

### Data Model (SwiftData)
Seven `@Model` types, all registered in the `Schema` in `VirgoApp.swift`. Adding a model requires
adding it there too, or SwiftData will fault at runtime.

`models/DrumTrack.swift`:
- `Song`: Local track metadata (title, artist, BPM, time signature, duration, genre, bgmFilePath, previewFilePath)
- `Chart`: Difficulty-specific charts linked to songs
- `Note`: Individual drum notes (interval, type, measureNumber, measureOffset) plus normalized rhythm tick fields
- `ServerSong` / `ServerChart`: Server-based tracks with download/cache support

Other model files:
- `models/ChartControlEvent.swift`: non-note notation events (`stop`, `choke`, `damp`) with the same
  normalized tick fields as `Note`
- `models/ScoreRecord.swift`: one persisted row per completed gameplay run
- `models/RhythmMetadata.swift`: rhythm value types (not `@Model`) — the resolved/analyzed rhythm
  payloads that cross into layout. `Song+Fixtures.swift` holds sample data split out of `DrumTrack.swift`
  for the SwiftLint file-length limit.

### Metronome System (Three-Layer Architecture)
`MetronomeEngine` is the public facade that composes two internal engines:
- `MetronomeAudioEngine`: Implements `AudioDriverProtocol`, handles AVFoundation audio buffer playback and iOS audio session management
- `MetronomeTimingEngine`: Uses `DispatchSourceTimer` for nanosecond-precision beat scheduling; exposes `onBeat` callback and `@Published currentBeat`
- `MetronomeEngine`: Wires the two together, exposes `@Published` state for UI, handles haptic feedback (iOS). Accepts an `AudioDriverProtocol` in `init` for test injection.

### Rhythm & Notation Pipeline
The largest subsystem. DTX timing is normalized into an integer-tick timeline before it ever reaches
layout, so the stages must be understood in order:

1. `DTXRhythmParser` (`utilities/`): extracts measure-length ratios, time signatures, and diagnostics
   from raw DTX text
2. `RhythmTimelineBuilder`: turns notes + control events into `RhythmSourceEvent`s and picks a
   canonical `ticksPerWholeNote` (LCM-based) for the chart
3. `RhythmTimelineResolver`: assigns stable `RhythmEventID`s and resolves each event to a
   `RhythmEventPosition` (measureIndex / localTick / absoluteTick)
4. `RhythmBeatGroupBuilder` + `RhythmTimeline`: groups ticks into `RhythmBeatGroup`s per measure.
   `RhythmBeatGroupBuilder.count(...)` is the **single source of truth** for how many groups a measure
   materializes — both group construction and the timeline's pre-allocation bound route through it, so
   expanded layout measures cannot drift from the persisted timeline. Do not recompute it locally.
5. `NotationRhythmAnalyzer` (`layout/`): infers note durations, rests, and tuplets from tick spacing
6. `NotationLayoutEngine` (+`Beams`/`Rests`/`Controls`/`TabGrid`/`RhythmRendering` extensions):
   produces the drawable layout

Normalized tick fields are persisted on `Note` and `ChartControlEvent` during current DTX import.
Virgo does not backfill older imported development rows after representation changes; reset/reseed
local development data instead. Runtime missing-metadata fallback remains separate from import-time
backfill. `RhythmMetronomeSchedule` derives the metronome schedule from the same timeline.

### Drum Tab Golden Coverage
`VirgoTests/Fixtures/DrumTabFixtureCatalog*.swift` holds 11 DTX fixtures driven through the real
import path by `DrumTabFixtureHarness` (`persistenceProjection()` + `setRhythmMetadata`, **not**
`toNotes`/`toControlEvents` — the latter leaves `rhythmMetadataState == .missing` and stamps control
ticks at each chip's native grid size). `NotationLayoutDigest` serializes the result to text, compared
against `VirgoTests/Goldens/<fixture>.txt`.

Regenerate with `TEST_RUNNER_VIRGO_UPDATE_GOLDENS=1` (via `xcodebuild test` — `xcodebuild` forwards
only `TEST_RUNNER_`-prefixed variables into the spawned test host, stripping the prefix before exec;
the bare `VIRGO_UPDATE_GOLDENS=1` only works via an Xcode scheme's test-action environment). The run
always **fails** afterwards so CI cannot self-approve a regression. Review `git diff` before
committing. Golden lines starting with `#` are stripped before comparison, so `# SUSPECT: HPA-<id> …`
marks a golden that pins known-suspect output.

`RhythmLayoutSnapshotBuilder` (`Virgo/layout/`) is shared by `GameplayViewModel` and the harness on
purpose — a parallel copy in tests would let goldens pass while production rendering broke.

Four suites cover this: `DrumTabGoldenTests` (full-digest goldens per fixture),
`DrumTabRegressionInvariantTests` (geometric invariants — beam extent within member stems and within
the beat group, head-to-grid routing, simultaneous-column identity, painted-bounds containment),
`DrumTabRenderProbeTests` (differential `ImageRenderer` ink probe; gates that `NotationNoteHeadView`
actually paints, and deliberately does not gate production's mounting of it), and
`DrumTabPlayheadAlignmentTests` (playhead x and measure index against the rendered note columns).

### Gameplay Architecture
`GameplayView` delegates all state to `GameplayViewModel` (`@Observable @MainActor`), which is split
across `GameplayViewModel.swift` plus `+BGM`, `+Computations`, `+Playback`, `+SpeedControl`, and
`+VisualUpdates` extension files (SwiftLint type-body limits). The view model:
- Caches SwiftData relationships (`cachedNotes`, `cachedSong`) to avoid main-thread blocking
- Pre-computes layout data (`cachedDrumBeats`, `cachedMeasurePositions`, `cachedBeamGroups`, `cachedBeatPositions`) to avoid per-frame recalculation
- Manages BGM (`AVAudioPlayer`) synchronized with metronome via `CFAbsoluteTime`
- Handles speed changes with trailing-edge debounce (100ms) to avoid slider jitter

`GameplayView+InputManagerDelegate.swift` and `GameplayView+Preview.swift` are extensions of the
view, not the view model.

### Services Layer
All services are `@MainActor` and live in `services/`:
- `PlaybackService`: Simple song playback state for the library list
- `PracticeSettingsService`: Speed control (0.25x–1.5x), per-chart persistence via `UserDefaults`
- `ScorePersistenceService`: SwiftData-backed per-chart scores (`ScoreRecord`). Keeps the 10 most
  recent attempts and tracks an all-time best from **full-speed runs only**

Per-chart `UserDefaults` keys (practice settings) are derived by `PersistentIdentifierPersistenceKey`
(`CryptoKit` SHA-256 over the SwiftData `PersistentIdentifier`) — the single place that keying lives.

`AudioPlaybackService` (song preview playback, FIFO cache of 10 `AVAudioPlayer` instances) lives in `utilities/` despite being a service.

### Catalog Layer (GraphQL)
The song catalog is fetched over GraphQL; the legacy REST configuration layer was removed.

- `SimfileDTO.swift` defines the `SimfileFetching` protocol and plain DTOs. **This is the seam** —
  `ApolloSimfileClient` is the only type that touches generated Apollo code, so the rest of the app
  never imports `Apollo`.
- `ServerConfig` resolves endpoints in precedence order: `UserDefaults` override (settings UI) →
  `EndpointDefaults` from the bundled `.env` → hard-coded local-dev fallback. No `r2BaseURL` means
  audio downloads are skipped rather than failed.
- Generated code lives in `Virgo/GraphQL/Generated/` and **is committed** (CI runs no codegen step).
  It is excluded from SwiftLint. To regenerate after editing `Virgo/GraphQL/Operations/*.graphql` or
  `Virgo/schema.graphql`, run the `apollo-ios-cli` binary from the SPM artifact directory against
  `apollo-codegen-config.json`; locate it with
  `find ~/Library/Developer/Xcode/DerivedData -name apollo-ios-cli -type f`.
- Partial GraphQL responses are preserved: `ApolloSimfileClient` only throws when `data` is absent,
  since field-level errors (e.g. one chart's `fileUrl`) can coexist with a valid payload.

### Server Song Management
`ServerSongService` is the public facade (coordinator) over four focused utilities under `utilities/`:
- `ServerSongDownloader`: Downloads DTX/audio files from the public R2 URLs in the catalog response
- `ServerSongFileManager`: Local file system operations for downloaded songs
- `ServerSongCache`: SwiftData-backed catalog cache; manual refresh validates a complete GraphQL snapshot, projects download status by exact `Song.serverSongId`, and replaces server cache metadata in one save. A vanished catalog ID never prunes local songs or audio.
- `ServerSongStatusManager`: Tracks download/delete state and syncs with SwiftData. Download completion reconciles status through the current cache/context rather than directly mutating a retained cache object.
- `DTXAPIClient`: now **only** a `FileDownloading` implementation (raw HTTP GET). It no longer does
  catalog access or server-URL configuration.

### Input System
- `InputManager`: Real-time MIDI and keyboard input; delegates hit events to `InputTimingMatcher`
- `InputTimingMatcher`: Pure value-type struct that maps raw hit timestamps to note positions and returns a `NoteMatchResult` (Perfect/Great/Good/Miss + timing error). Accuracy windows: Perfect ±25ms, Great ±50ms, Good ±100ms.
- `ScoreEngine`: Pure value-type scoring engine; owns combo multiplier tiers, per-hit scoring, and produces immutable `SessionResult` snapshots — no I/O or SwiftUI dependencies
- `InputSettingsManager`: Configurable key/MIDI mappings persisted in `UserDefaults`

### MIDI Subsystem
- `MIDIDeviceRegistry`: Discovers and tracks connected CoreMIDI sources; implements `MIDISourceProviding` and `MIDISourceChangeListening` protocols
- `MIDIEventRouter`: Stateless struct that decodes raw `MIDIPacketBytes` into `MIDINoteEvent` values; handles running status and filters clock/sysex bytes
- `MIDILearnSession`: `@MainActor ObservableObject` that manages the MIDI learn capture flow (10s timeout, conflict detection)
- `MIDIHostTimeConverter`: Converts CoreMIDI host timestamps (`mach_absolute_time`) to `Date` for timing comparison
- `MIDIPreviewMonitor`: Passes incoming MIDI events to `MIDIDiagnosticsStore` for the diagnostics UI
- `MIDIDiagnosticsStore`: `@MainActor ObservableObject` holding the last decoded `MIDIDiagnosticSnapshot` for display in settings

### Design System (`Virgo/design/`)
Two color "worlds" (`SurfaceWorld.paper` / `.ink`) resolve into a semantic `VirgoTheme`
(background/raised/primary/secondary/rule/accent). The resolution convention is deliberate:

- Paper-world screens and **all** world-shared components (button styles, etc.) read
  `@Environment(\.theme)` so they adapt to whichever surface hosts them.
- Fixed-world Ink screens (gameplay, session results) reference `Palette.*` directly — their world
  never flips, and notation primitives render in tight `ForEach`/`Path` loops where skipping the
  environment lookup matters. They still apply `.surface(.ink)` at the root so hosted shared
  components resolve correctly.

Fonts are bundled `.ttf` files registered at runtime by `AppFonts.registerAll()` (called from
`VirgoApp.init`), not via Info.plist — it falls back to scanning `Bundle.allBundles` so fonts also
resolve in the XCTest host.

## Key Technical Patterns

### SwiftData Concurrency
Accessing `song.charts` or `chart.notes` during UI rendering causes crashes. Use the async caching pattern:
```swift
@State private var cachedItems: [Item] = []
// In .task modifier: load asynchronously, update @State on main thread
```
`SwiftDataRelationshipLoader` provides standardized helpers for this.

### @Observable vs @ObservableObject
`GameplayViewModel` uses Swift 5.9's `@Observable` macro (not `ObservableObject`). This requires `import Observation` and avoids the `@Published` wrapper—all stored properties are automatically tracked.

### SwiftUI Performance: Avoid @Published in Complex View Hierarchies
Frequently-updating `@Published` properties on `@EnvironmentObject` or `@ObservedObject` force re-evaluation of every dependent view. `MetronomeEngine.$currentBeat` must NOT be observed directly in `GameplayView` (which contains hundreds of notation subviews). Instead, `GameplayViewModel` subscribes via Combine and batches visual updates.

### Test Environment Detection
`TestEnvironment.isRunningTests` (checks `XCTestCase` class existence) is used by audio components to skip AVFoundation initialization. `LaunchArguments` defines shared constants (`-UITesting`, `-ResetState`, `-SkipSeed`) for UI test launch configuration. `ContentStartupPolicy` encodes the pure startup-action decision logic as a testable enum.

### Test Framework
All unit tests use **Swift Testing** (`import Testing`, `#expect`, `#require`, `@Suite`), not XCTest. `TestContainer` in `TestHelpers.swift` provides isolated in-memory `ModelContainer`/`ModelContext` instances per test to prevent SwiftData state leakage.

### Audio/Metronome Synchronization
BGM (`AVAudioPlayer`) and metronome are synchronized using a common `CFAbsoluteTime` start point, converted to `AVAudioTime` for sample-accurate scheduling. Speed changes reschedule both engines with a shared `startTime` to prevent drift.

### Gameplay Regression Debugging Lessons
- Treat gameplay timing, BGM audio, notation layout, row scrolling, and input timing as one system when investigating sync drift or lag. `GameplayViewModel` is the hub to inspect first because it fans out to the playhead, current row, scoring, metronome configuration, BGM clock, and input timing.
- For DTX fixture audio on macOS, do not rely on OGG playback through `AVAudioPlayer`. Persist a playable path such as `bgm.m4a`; stable-ID re-import re-resolves BGM/preview paths from current fixture assets and clears paths for missing assets. Reset/reseed local development data after non-path representation changes.
- Gameplay layout must know the available row width before `setupGameplay()` builds the first visible notation layout. Seed the GeometryReader width before setup, and keep pre-setup row-width updates from building throwaway layouts; otherwise the user sees a first layout and then a later repack with different measure grouping.
- On macOS UI tests, `app.windows.count` can include auxiliary XCTest/accessibility windows. To check whether gameplay and the tab shell are mounted simultaneously, assert one window contains `gameplayRoot` and assert `appTabShell`/tab bars are absent instead of asserting the raw window count.
- Swift Testing method selectors can report "Executed 0 tests" when the generated test name does not match the guessed selector. Prefer suite/class selectors for focused verification unless the exact selector is already proven.
- Avoid running concurrent `xcodebuild` commands against the same `-derivedDataPath`; they can lock `XCBuildData/build.db`. Run Xcode build/test verification sequentially when sharing derived data.
- Regression coverage for bundled DTX fixtures only works if the required audio/chart assets are available in CI or committed/generated by a reliable setup step. An ignored local `bgm.m4a` is not enough to prevent future audio regressions on fresh checkouts.
- The repository commits the fixture assets tests actually need from `Virgo/Fixtures/soukyuu_e_no_shouka/` (`SET.def`, the `.dtx` charts, `bgm.m4a`, and `preview.mp3`); `.gitignore` excludes the `.ogg`/`.xa`/`.jpg` drum samples. Do not add tests that depend on them.
- Do not apply `.appThemeRoot()`, `.preferredColorScheme()`, or any other modifier to `VirgoApp.rootView`'s `WindowGroup` content. macOS derives its window-restoration identifier from the SwiftUI view-type signature; changing it makes restoration fail after rapid launch/terminate cycles (UI tests), leaving the app running with no window. `MainMenuView` applies those modifiers inside its own body and resolves its own theme for exactly this reason.

## Project Structure
```text
Virgo/
├── Virgo.xcodeproj/
├── Virgo/
│   ├── VirgoApp.swift           # App entry point; SwiftData Schema, MetronomeEngine, font registration
│   ├── components/              # Reusable UI components (song rows, difficulty badges, metronome)
│   ├── views/                   # Feature views (MainMenuView is the root screen, GameplayView, etc.)
│   │   └── subviews/            # View decompositions
│   ├── viewmodels/              # GameplayViewModel + its 5 extension files
│   ├── models/                  # SwiftData models + rhythm value types
│   ├── services/                # Business logic services (PlaybackService, ScorePersistenceService, etc.)
│   ├── utilities/               # Audio engines, DTX/rhythm parsing, timeline, input, MIDI, server, logging
│   ├── design/                  # Theme, Palette, Typography, Spacing, font registration
│   ├── layout/                  # Musical notation layout + rhythm analysis
│   ├── constants/               # Drum type definitions
│   ├── GraphQL/                 # .graphql operations + committed Apollo-generated code
│   ├── Config/                  # ServerEndpoints.env (gitignored) + .example template
│   ├── Fixtures/                # Bundled DTX fixture (soukyuu_e_no_shouka)
│   ├── Resources/Fonts/         # Bundled .ttf files
│   └── Assets.xcassets/
├── VirgoTests/                  # Unit tests (Swift Testing framework, not XCTest)
├── VirgoUITests/                # UI automation tests
├── docs/                        # PRD, architecture blueprint, superpowers plans/specs
├── scripts/                     # setup-git-hooks.sh
└── server/                      # Legacy local REST fixture server (not the GraphQL backend)
```

## `server/` — Legacy REST Fixture Server

**This is not the backend the app talks to.** The catalog now goes through GraphQL
(`ServerConfig.graphQLEndpoint` → `ApolloSimfileClient`); `server/main.py` only exposes REST routes
(`/dtx/list`, `/dtx/download/...`, `/dtx/metadata/...`) over `server/dtx_files/` and is kept for local
DTX experimentation. Point `GRAPHQL_ENDPOINT` at a real GraphQL backend for catalog work.

```bash
# Initial setup (uses uv, not pip)
cd server && uv sync

# Start local server
cd server && uv run uvicorn main:app --host 127.0.0.1 --port 8001 --reload
```

- Parses `SET.def` files with multi-encoding fallback (UTF-16 → Shift-JIS → UTF-8)
- CORS-enabled; Cloudflare Workers deployment supported

Note: `.github/README.md` is stale — its example commands use iPhone simulator destinations, which
contradicts the iPad-only rule that `ci.yml` actively enforces. Use the commands in this file instead.
