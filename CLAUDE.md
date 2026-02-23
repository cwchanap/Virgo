# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Virgo is a SwiftUI-based drum notation and metronome application for iOS and macOS. The app provides interactive drum track visualization with musical notation, metronome functionality, and gameplay-style views for practicing drum patterns.

- **SwiftUI + SwiftData**: Modern declarative UI with persistent storage
- **Multi-platform**: iOS 18.5+ and macOS 14.0+
- **AVFoundation**: Audio engine for metronome and song preview playback

## Development Commands

### Build & Test (macOS target is sufficient for development)
```bash
# Build for macOS
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build

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
All services are `@MainActor`:
- `PlaybackService`: Simple song playback state for the library list
- `AudioPlaybackService`: Song preview playback (cached `AVAudioPlayer` instances, FIFO cache of 10)
- `PracticeSettingsService`: Speed control (0.25x–1.5x), per-chart persistence via `UserDefaults` with `CryptoKit` SHA-256 keying
- `DatabaseMaintenanceService`: SwiftData relationship maintenance and cleanup

### Server Song Management
Refactored into focused utilities under `utilities/`:
- `ServerSongDownloader`: Downloads DTX files from FastAPI backend
- `ServerSongFileManager`: Local file system operations for downloaded songs
- `ServerSongCache`: In-memory caching for server song metadata
- `ServerSongStatusManager`: Tracks download/delete state and syncs with SwiftData

### Input System
- `InputManager`: Real-time MIDI and keyboard input with timing accuracy scoring (Perfect/Great/Good/Miss)
- `InputSettingsManager`: Configurable key/MIDI mappings persisted in `UserDefaults`

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
`TestEnvironment.isRunningTests` (checks `XCTestCase` class existence) is used by audio components to skip AVFoundation initialization. `LaunchArguments` defines shared constants (`-UITesting`, `-ResetState`, `-SkipSeed`) for UI test launch configuration.

### Audio/Metronome Synchronization
BGM (`AVAudioPlayer`) and metronome are synchronized using a common `CFAbsoluteTime` start point, converted to `AVAudioTime` for sample-accurate scheduling. Speed changes reschedule both engines with a shared `startTime` to prevent drift.

## Project Structure
```
Virgo/
├── Virgo.xcodeproj/
├── Virgo/
│   ├── VirgoApp.swift           # App entry point; creates ModelContainer and MetronomeEngine
│   ├── components/              # Reusable UI components (song rows, difficulty badges, metronome)
│   ├── views/                   # Feature views (ContentView, GameplayView, SongsTabView, etc.)
│   │   ├── subviews/            # View decompositions
│   │   └── helpers/             # (deprecated path - logic moved to ViewModel)
│   ├── viewmodels/
│   │   └── GameplayViewModel.swift  # All gameplay state and logic
│   ├── models/                  # SwiftData models (DrumTrack.swift, DrumType+Extensions.swift)
│   ├── services/                # Business logic services
│   ├── utilities/               # Shared utilities (audio engines, parsers, input, logging)
│   ├── constants/               # Drum type definitions
│   ├── layout/                  # Musical notation layout calculations
│   └── Assets.xcassets/
├── VirgoTests/                  # Unit tests (Swift Testing framework, not XCTest)
├── VirgoUITests/                # UI automation tests
├── scripts/                     # setup-git-hooks.sh
└── server/                      # FastAPI backend (main.py, dtx_files/, requirements.txt)
```

## FastAPI Backend Server
- Local dev: `http://127.0.0.1:8001` (configurable via UserDefaults)
- Endpoints: list, download, and parse DTX files
- Shift-JIS encoding support for Japanese DTX files
- CORS-enabled; Cloudflare Workers deployment supported

## Memory Archive

### SwiftUI Performance - @Published and Massive View Re-renders
- **Critical**: `@Published` on `@EnvironmentObject` triggers re-evaluation of ALL dependent views, even those not using the changed property
- **Case**: `MetronomeEngine.$currentBeat` as `@EnvironmentObject` in `GameplayView` caused complete UI unresponsiveness (scrolling >5s delay) because every beat tick forced re-render of hundreds of notation subviews
- **Fix**: Use `GameplayViewModel` (`@Observable`) as the intermediary; it subscribes to metronome beats and batches visual state updates

### SwiftData Concurrency
- Accessing SwiftData relationships during UI rendering causes threading crashes
- Always use async caching pattern: load in `.task`, cache in `@State`, render from cache
