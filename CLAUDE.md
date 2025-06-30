# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Virgo is a SwiftUI-based drum tracks music application for iOS and macOS. The app provides a library of drum tracks with features like search, playback controls, and track metadata display.

### Architecture

- **SwiftUI + SwiftData**: Modern declarative UI with Core Data replacement
- **Multi-platform**: Supports iOS 18.5+ and macOS 14.0+
- **Model-View Architecture**: Clean separation with SwiftData models and SwiftUI views
- **Navigation**: Tab-based navigation with NavigationStack for detailed views

### Key Components

- `VirgoApp.swift`: Main app entry point with SwiftData ModelContainer setup
- `MainMenuView.swift`: Animated splash screen with navigation to main app
- `ContentView.swift`: Primary tabbed interface with drum tracks list, search, and playback
- `DrumTrack.swift`: SwiftData model for drum track entities with sample data

### Data Model

The app uses SwiftData with a single `DrumTrack` model containing:
- Basic metadata (title, artist, genre, duration)
- Playback properties (BPM, difficulty level)
- User interaction data (play count, favorites, play state)

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

# Run specific test
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:VirgoTests/VirgoTests/example test
```

### Project Structure
```
Virgo/
├── Virgo.xcodeproj/          # Xcode project configuration
├── Virgo/                    # Main app source code
│   ├── VirgoApp.swift       # App entry point and data setup
│   ├── MainMenuView.swift   # Splash screen with animations
│   ├── ContentView.swift    # Main tabbed interface
│   ├── DrumTrack.swift      # SwiftData model
│   ├── Assets.xcassets/     # App icons and colors
│   └── Info.plist          # App configuration
├── VirgoTests/              # Unit tests (uses Swift Testing framework)
└── VirgoUITests/            # UI automation tests
```

## Development Notes

- The app uses Swift Testing framework (not XCTest) for unit tests
- SwiftData automatically handles sample data insertion on first launch
- Multi-platform target supports both iOS and macOS with adaptive UI
- Custom button styles and animations enhance the user experience
- Search functionality filters tracks by title and artist in real-time