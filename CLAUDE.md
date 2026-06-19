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

### Code Quality
```bash
swiftlint lint         # Manual lint
swiftlint lint --fix   # Auto-fix
```

### Initial Setup
```bash
./scripts/setup-git-hooks.sh   # Installs SwiftLint pre-commit hook
```

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
Five primary models in `models/DrumTrack.swift`:
- `Song`: Local track metadata (title, artist, BPM, time signature, duration, genre, bgmFilePath, previewFilePath)
- `Chart`: Difficulty-specific charts linked to songs
- `Note`: Individual drum notes (interval, type, measureNumber, measureOffset)
- `ServerSong` / `ServerChart`: Server-based tracks with download/cache support

### Metronome System (Three-Layer Architecture)
`MetronomeEngine` is the public facade that composes two internal engines:
- `MetronomeAudioEngine`: Implements `AudioDriverProtocol`, handles AVFoundation audio buffer playback and iOS audio session management
- `MetronomeTimingEngine`: Uses `DispatchSourceTimer` for nanosecond-precision beat scheduling; exposes `onBeat` callback and `@Published currentBeat`
- `MetronomeEngine`: Wires the two together, exposes `@Published` state for UI, handles haptic feedback (iOS). Accepts an `AudioDriverProtocol` in `init` for test injection.

### Gameplay Architecture
`GameplayView` delegates all state to `GameplayViewModel` (`@Observable @MainActor`):
- Caches SwiftData relationships (`cachedNotes`, `cachedSong`) to avoid main-thread blocking
- Pre-computes layout data (`cachedDrumBeats`, `cachedMeasurePositions`, `cachedBeamGroups`, `cachedBeatPositions`) to avoid per-frame recalculation
- Manages BGM (`AVAudioPlayer`) synchronized with metronome via `CFAbsoluteTime`
- Handles speed changes with trailing-edge debounce (100ms) to avoid slider jitter
- `GameplayView+InputManagerDelegate.swift` and `GameplayView+Preview.swift` are extensions of `GameplayView`

### Services Layer
All services are `@MainActor` and live in `services/`:
- `PlaybackService`: Simple song playback state for the library list
- `PracticeSettingsService`: Speed control (0.25x–1.5x), per-chart persistence via `UserDefaults` with `CryptoKit` SHA-256 keying
- `DatabaseMaintenanceService`: SwiftData relationship maintenance and cleanup
- `HighScoreService`: Per-chart best-score persistence via `UserDefaults` with `CryptoKit` SHA-256 keying

`AudioPlaybackService` (song preview playback, FIFO cache of 10 `AVAudioPlayer` instances) lives in `utilities/` despite being a service.

### Server Song Management
`ServerSongService` is the public facade (coordinator) over four focused utilities under `utilities/`:
- `ServerSongDownloader`: Downloads DTX files from FastAPI backend
- `ServerSongFileManager`: Local file system operations for downloaded songs
- `ServerSongCache`: In-memory caching for server song metadata
- `ServerSongStatusManager`: Tracks download/delete state and syncs with SwiftData
- `DTXAPIClient`: HTTP client for the FastAPI backend (list/download endpoints)

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
- For DTX fixture audio on macOS, do not rely on OGG playback through `AVAudioPlayer`. Store a playable audio path such as `bgm.m4a` in `Song.bgmFilePath`, and refresh existing imported fixture records as well as new imports so stale persisted `bgm.ogg` paths do not silently disable BGM.
- Gameplay layout must know the available row width before `setupGameplay()` builds the first visible notation layout. Seed the GeometryReader width before setup, and keep pre-setup row-width updates from building throwaway layouts; otherwise the user sees a first layout and then a later repack with different measure grouping.
- On macOS UI tests, `app.windows.count` can include auxiliary XCTest/accessibility windows. To check whether gameplay and the tab shell are mounted simultaneously, assert one window contains `gameplayRoot` and assert `appTabShell`/tab bars are absent instead of asserting the raw window count.
- Swift Testing method selectors can report "Executed 0 tests" when the generated test name does not match the guessed selector. Prefer suite/class selectors for focused verification unless the exact selector is already proven.
- Avoid running concurrent `xcodebuild` commands against the same `-derivedDataPath`; they can lock `XCBuildData/build.db`. Run Xcode build/test verification sequentially when sharing derived data.
- Regression coverage for bundled DTX fixtures only works if the required audio/chart assets are available in CI or committed/generated by a reliable setup step. An ignored local `bgm.m4a` is not enough to prevent future audio regressions on fresh checkouts.

## Project Structure
```text
Virgo/
├── Virgo.xcodeproj/
├── Virgo/
│   ├── VirgoApp.swift           # App entry point; creates ModelContainer and MetronomeEngine
│   ├── components/              # Reusable UI components (song rows, difficulty badges, metronome)
│   ├── views/                   # Feature views (ContentView, GameplayView, SongsTabView, etc.)
│   │   └── subviews/            # View decompositions
│   ├── viewmodels/
│   │   └── GameplayViewModel.swift  # All gameplay state and logic
│   ├── models/                  # SwiftData models (DrumTrack.swift, DrumType+Extensions.swift)
│   ├── services/                # Business logic services (PlaybackService, HighScoreService, etc.)
│   ├── utilities/               # Shared utilities: audio engines, DTX parser, input, MIDI, logging, AudioPlaybackService
│   ├── constants/               # Drum type definitions
│   ├── layout/                  # Musical notation layout calculations
│   └── Assets.xcassets/
├── VirgoTests/                  # Unit tests (Swift Testing framework, not XCTest)
├── VirgoUITests/                # UI automation tests
├── scripts/                     # setup-git-hooks.sh
└── server/                      # FastAPI backend (main.py, dtx_files/, requirements.txt)
```

## FastAPI Backend Server

```bash
# Initial setup (uses uv, not pip)
cd server && uv sync

# Start local server
cd server && uv run uvicorn main:app --host 127.0.0.1 --port 8001 --reload
```

- Local dev: `http://127.0.0.1:8001` (configurable via UserDefaults)
- Endpoints: list, download, and parse DTX files from `server/dtx_files/`
- Parses `SET.def` files with multi-encoding fallback (UTF-16 → Shift-JIS → UTF-8)
- CORS-enabled; Cloudflare Workers deployment supported
