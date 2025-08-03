# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Virgo is a SwiftUI-based drum notation and metronome application for iOS and macOS. The app provides interactive drum track visualization with musical notation, metronome functionality, and gameplay-style views for practicing drum patterns.

### Architecture

- **SwiftUI + SwiftData**: Modern declarative UI with Core Data replacement
- **Multi-platform**: Supports iOS 18.5+ and macOS 14.0+
- **Component-Based Architecture**: Modular design with reusable components
- **AVFoundation**: Audio engine for metronome and sound playback
- **Organized File Structure**: Clear separation by feature (components, views, models, utilities)

### Key Components

- `VirgoApp.swift`: Main app entry point with SwiftData ModelContainer and shared MetronomeEngine
- `MainMenuView.swift`: Animated splash screen with navigation to main app
- `ContentView.swift`: Primary track listing interface with unified Songs tab supporting local and server DTX files
- `GameplayView.swift`: Full-screen musical notation display with playback controls
- `DrumTrack.swift`: SwiftData models (Song, Chart, Note) with relationships for complex drum patterns
- `MetronomeComponent.swift`: Advanced metronome with sample-accurate timing and volume control
- `DTXAPIClient.swift`: Network client for DTX server integration with file listing, metadata, and download capabilities
- `DTXFileParser.swift`: Parser for importing DTX drum chart files with complete note parsing

### Data Model

The app uses SwiftData with five primary models:
- `Song`: Local track metadata (title, artist, BPM, time signature, duration, genre)
- `Chart`: Difficulty-specific charts linked to songs with relationships to Notes
- `Note`: Individual drum notes with interval, type, measure number, and timing offset
- `ServerSong`: Server-based tracks with download and caching support
- `ServerChart`: Server chart data with DTX file integration
- Rich sample data with complex multi-measure drum patterns
- Unified interface combining local SwiftData entries with server DTX files

## Development Setup

### Initial Setup
```bash
# One-time setup after cloning
./scripts/setup-git-hooks.sh
```

This sets up:
- SwiftLint pre-commit hooks for code quality
- Automatic linting on staged files before commit
- Blocks commits with linting errors

### Code Quality
```bash
# Manual linting
swiftlint lint

# Auto-fix linting issues
swiftlint lint --fix
```

## Development Commands

### Building
```bash
# Build for iOS Simulator
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPhone 15' build

# Build for macOS
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build

# Build all targets
xcodebuild -project Virgo.xcodeproj -scheme Virgo build
```

### Testing
```bash
# Run unit tests
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPhone 15' test

# Run UI tests
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:VirgoUITests test

# Run specific test class
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:VirgoTests/VirgoTests test

# Run specific test method
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:VirgoTests/VirgoTests/testAppLaunchConfiguration test
```

### Project Structure
```
Virgo/
├── Virgo.xcodeproj/              # Xcode project configuration
├── Virgo/                        # Main app source code
│   ├── VirgoApp.swift           # App entry point with SwiftData and MetronomeEngine
│   ├── components/              # Reusable UI components
│   │   ├── GameplayControlsView.swift
│   │   ├── GameplayHeaderView.swift
│   │   ├── MetronomeComponent.swift    # Core metronome with AVFoundation
│   │   └── MetronomeSettingsComponent.swift
│   ├── views/                   # Main view controllers
│   │   ├── ContentView.swift    # Track listing
│   │   ├── GameplayView.swift   # Musical notation display
│   │   ├── MainMenuView.swift   # Splash screen
│   │   ├── BeamView.swift       # Musical beam notation
│   │   ├── DrumBeatView.swift   # Individual note rendering
│   │   ├── MetronomeView.swift  # Metronome interface
│   │   └── MusicNotationViews.swift
│   ├── models/                  # SwiftData models
│   │   └── DrumTrack.swift      # Track and Note models with sample data
│   ├── utilities/               # Helper utilities
│   │   ├── BeamGroupingLogic.swift  # Musical notation beam grouping
│   │   ├── Logger.swift         # Centralized logging
│   │   ├── DTXAPIClient.swift   # Server integration for DTX files
│   │   ├── DTXFileParser.swift   # DTX file format parser
│   │   └── ServerSongService.swift # Server integration service
│   ├── constants/               # App constants
│   │   └── Drum.swift          # Drum type definitions
│   ├── layout/                  # Layout calculations
│   │   └── gameplay.swift       # Musical notation positioning
│   └── Assets.xcassets/         # App icons, colors, and audio assets
├── VirgoTests/                  # Unit tests (Swift Testing framework)
├── VirgoUITests/               # UI automation tests
├── scripts/                    # Development scripts
    ├── setup-git-hooks.sh      # Git hooks installation
    └── git-hooks/              # Pre-commit hooks
└── server/                     # FastAPI backend server
    ├── main.py                # Server entry point
    ├── dtx_files/             # DTX file storage
    └── requirements.txt       # Python dependencies
```

## Development Notes

- The app uses Swift Testing framework (not XCTest) for unit tests
- SwiftData models include complex Note relationships with detailed drum patterns
- MetronomeEngine uses AVFoundation for sample-accurate audio timing
- Musical notation rendering with precise positioning and beam grouping
- Component architecture separates UI from business logic effectively
- Test environment detection disables audio components during testing
- Centralized logging with categorized output (audioPlayback, userAction, debug)
- Multi-platform target supports both iOS and macOS with adaptive UI
- SwiftLint configuration customized for the project with relaxed rules for necessary patterns

### SwiftData Concurrency
- **Issue**: Accessing SwiftData relationships (`song.charts`, `chart.notes`) during UI rendering causes concurrency crashes and blocks the main thread
- **Solution**: Use async caching pattern with `@State` variables and `.task` modifier to load relationship data in background, then update UI on main thread
- **Implementation**: Views cache relationship counts/data locally and refresh asynchronously when song changes, ensuring immediate UI responsiveness

## Key Technical Features

### Metronome System
- `MetronomeEngine`: Core audio engine with AVFoundation integration
- Sample-accurate timing with buffer scheduling
- Volume control with accent patterns (stronger beat 1)
- Thread-safe audio buffer caching with `AudioBufferCache` actor
- Test environment detection for unit testing compatibility

### Musical Notation
- Complex drum pattern visualization with proper musical notation
- Beam grouping logic for connected eighth/sixteenth notes
- Multi-measure layout with staff lines, clefs, and time signatures
- Real-time playback indication with beat highlighting
- Scrollable gameplay view with measure-based positioning

### Audio Architecture
- Cached audio assets using NSDataAsset for ticker sounds
- Configurable audio session for iOS (playback category with mix-with-others)
- Non-fatal error handling for audio engine failures
- Proper resource cleanup in deinitializer

### Server Integration
- `DTXAPIClient`: Network client for connecting to FastAPI backend server
- Configurable server URL (defaults to http://127.0.0.1:8001)
- REST API endpoints for listing, downloading, and parsing DTX files
- Error handling for network connectivity and server responses
- User preferences for server configuration with UserDefaults storage
- Network entitlements configured for client/server communication
- Unified Songs tab combines local SwiftData entries with server DTX files
- Caching system for downloaded DTX files with local storage support

## FastAPI Backend Server

The project includes a Python FastAPI server (`server/`) for serving DTX files:
- Local development server at `http://localhost:8000`
- Cloudflare Workers deployment support
- REST API for listing, downloading, and parsing DTX files
- CORS-enabled for local iOS/macOS client development
- Shift-JIS encoding support for Japanese DTX files

## Memory Archive

### SwiftData and Concurrency
- SwiftData concurrency issue discovered where complex Note relationships cause threading conflicts during background model updates

### SwiftUI Performance - @Published Properties and Massive View Re-renders
- **Critical Issue**: `@Published` properties in `@EnvironmentObject` or `@ObservedObject` can cause massive UI performance issues in complex view hierarchies
- **Specific Case**: `MetronomeEngine` with `@Published var currentBeat` used as `@EnvironmentObject` in `GameplayView` caused complete UI unresponsiveness during playback
- **Root Cause**: Every time `currentBeat` updated (every metronome beat), SwiftUI re-evaluated the entire `GameplayView` hierarchy containing hundreds of `DrumBeatView`, `BeamGroupView`, staff lines, and other complex musical notation views
- **Symptoms**: 
  - UI becomes completely unresponsive during playback (scrolling takes >5 seconds)
  - Other UI elements (buttons, sliders) respond slowly (1-2 seconds delay)
  - Performance issues disappear when playback is paused
- **Solution**: Isolate frequently-updating `@Published` properties from complex view hierarchies
  - Move audio-only state updates to non-published properties
  - Use separate, lightweight UI state objects for views that need frequent updates
  - Cache expensive UI calculations to prevent re-computation on every state change
- **Key Insight**: In SwiftUI, changing any `@Published` property forces re-evaluation of all dependent views, regardless of whether those views actually use the changed property
- **Performance Pattern**: Avoid `@EnvironmentObject` or `@ObservedObject` with frequently-updating `@Published` properties in views with complex, expensive rendering