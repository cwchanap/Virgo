# Virgo — Project Architecture Blueprint

> **Generated:** 2026-02-28  
> **Technology Stack:** Swift 5.9+ / SwiftUI / SwiftData / AVFoundation / CoreMIDI  
> **Architecture Pattern:** MVVM + Service Layer  
> **Platforms:** iOS 18.5+ · macOS 14.0+  
> **Detail Level:** Implementation-Ready

---

## Table of Contents

1. [Architectural Overview](#1-architectural-overview)
2. [Architecture Visualization](#2-architecture-visualization)
3. [Core Architectural Components](#3-core-architectural-components)
4. [Architectural Layers and Dependencies](#4-architectural-layers-and-dependencies)
5. [Data Architecture](#5-data-architecture)
6. [Cross-Cutting Concerns](#6-cross-cutting-concerns)
7. [Swift/SwiftUI Architectural Patterns](#7-swiftswiftui-architectural-patterns)
8. [Implementation Patterns](#8-implementation-patterns)
9. [Testing Architecture](#9-testing-architecture)
10. [Deployment Architecture](#10-deployment-architecture)
11. [Extension and Evolution Patterns](#11-extension-and-evolution-patterns)
12. [Architectural Pattern Examples](#12-architectural-pattern-examples)
13. [Architectural Decision Records](#13-architectural-decision-records)
14. [Architecture Governance](#14-architecture-governance)
15. [Blueprint for New Development](#15-blueprint-for-new-development)

---

## 1. Architectural Overview

Virgo is a **SwiftUI-first, single-process, multi-platform application** structured around a strict **MVVM + Service Layer** architecture. The guiding principles are:

| Principle | Implementation |
|-----------|---------------|
| **Single source of truth** | SwiftData for relational models; UserDefaults for key-value state; each scoped to one owning type |
| **Main-actor isolation** | Every service, ViewModel, and UI component is `@MainActor`; background work is explicit async/await |
| **Value-type engines** | Scoring and layout logic are pure value types (`struct`); no side effects, fully testable in isolation |
| **Dependency injection** | All service dependencies injected at construction; UserDefaults is injected for testability |
| **Protocol-based hardware abstraction** | Audio and input hardware hidden behind protocols (`AudioDriverProtocol`, `InputManagerDelegate`) |
| **Async data loading** | SwiftData relationships loaded only inside `.task` modifiers to prevent main-thread crashes |

### Architectural Boundaries

```
┌─────────────────────────────────────────────────────────────────┐
│                          App Layer                               │
│  VirgoApp.swift — ModelContainer + @StateObject shared services  │
└─────────────────────────────┬───────────────────────────────────┘
                              │ .environmentObject / .modelContainer
┌─────────────────────────────▼───────────────────────────────────┐
│                          View Layer                              │
│  SwiftUI Views — render state, forward user actions             │
│  (GameplayView, SongsTabView, MetronomeView, SettingsView …)    │
└─────────────────────────────┬───────────────────────────────────┘
                              │ @State ViewModel / @EnvironmentObject
┌─────────────────────────────▼───────────────────────────────────┐
│                       ViewModel Layer                            │
│  @Observable @MainActor — session state, orchestration          │
│  (GameplayViewModel)                                            │
└──────────┬──────────────────┬──────────────────────────────────┘
           │ calls            │ calls
┌──────────▼──────┐   ┌───────▼──────────────────────────────────┐
│  Engine Layer   │   │            Service Layer                  │
│  (value types)  │   │  @MainActor ObservableObject / class       │
│  ScoreEngine    │   │  HighScoreService, PracticeSettingsService │
│  GameplayLayout │   │  PlaybackService, AudioPlaybackService     │
│  MeasureUtils   │   │  DatabaseMaintenanceService               │
│  BeamGrouping   │   └───────┬──────────────────────────────────┘
└─────────────────┘           │ reads/writes
                    ┌──────────▼─────────────────────────────────┐
                    │          Persistence Layer                  │
                    │  SwiftData (ModelContext/ModelContainer)     │
                    │  UserDefaults (key-value, per-chart)         │
                    └────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│                       Utility Layer                              │
│  InputManager · MetronomeEngine · DTXFileParser · Logger        │
│  ServerSongDownloader · SwiftDataRelationshipLoader · etc.      │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Architecture Visualization

### C4 Context Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                    External Systems                               │
│                                                                  │
│   ┌──────────────────┐         ┌────────────────────────────┐   │
│   │  FastAPI Backend  │         │   MIDI Hardware / Keyboard │   │
│   │  (localhost:8001) │         │   (CoreMIDI / NSEvent)     │   │
│   └────────┬─────────┘         └──────────────┬─────────────┘   │
└────────────┼───────────────────────────────────┼────────────────┘
             │ HTTP (DTX files)                  │ Hardware events
┌────────────▼───────────────────────────────────▼────────────────┐
│                        Virgo App                                  │
│                                                                  │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │ Songs/Library│  │   Gameplay   │  │      Metronome          │ │
│  │ (Browse/DL) │  │  (Practice)  │  │   (Standalone mode)     │ │
│  └─────────────┘  └──────────────┘  └─────────────────────────┘ │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   SwiftData Store                          │  │
│  │    Song · Chart · Note · ServerSong · ServerChart          │  │
│  └───────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

### Component Interaction Diagram

```
VirgoApp
  ├── ModelContainer (shared SQLite store)
  ├── MetronomeEngine (@StateObject, injected via .environmentObject)
  └── PracticeSettingsService (@StateObject, injected via .environmentObject)

MainMenuView
  └── ContentView
        ├── SongsTabView
        │     └── ExpandableSongRow → [select chart] → GameplayView
        ├── MetronomeView (active only when tab selected)
        ├── LibraryView → ServerSongsView → download flow
        ├── SettingsView → AudioSettingsView / InputSettingsView
        └── ProfileView

GameplayView
  ├── GameplayViewModel (@Observable @MainActor) [owned as @State]
  │     ├── ScoreEngine (struct, owned by value)
  │     ├── InputManager → GameplayInputHandler (delegate)
  │     ├── MetronomeEngine (injected reference)
  │     ├── PracticeSettingsService (injected reference)
  │     └── HighScoreService (created internally)
  ├── GameplayHeaderView (score, combo, transport)
  ├── GameplaySheetMusicView (notation canvas)
  ├── GameplayControlsView (speed, progress)
  └── SessionResultsView (sheet, on completion)
```

### Data Flow — Gameplay Session

```
User (MIDI/Keyboard)
    │
    ▼
InputManager.processInput()
    │  calculateNoteMatch() → NoteMatchResult {timingError, timingAccuracy}
    ▼
GameplayInputHandler.didMatchNote()   [InputManagerDelegate]
    │  onNoteResult?(result)
    ▼
GameplayViewModel.recordHit(result:)
    │  scanForMissedNotes()
    │  scoreEngine.processHit(accuracy:)
    ▼
ScoreEngine (struct mutation)
    │  score, combo, maxCombo, perfectCount, greatCount, goodCount, missCount
    ▼
GameplayHeaderView (live score display)

--- Session End ---

GameplayViewModel.handlePlaybackCompletion()
    │  HighScoreService.saveIfHighScore()
    │  sessionScoreEngine = scoreEngine  (snapshot)
    │  isShowingSessionResults = true
    ▼
SessionResultsView (sheet presentation)
```

---

## 3. Core Architectural Components

### 3.1 App Bootstrap (`VirgoApp.swift`)

**Purpose:** Single initialization point for shared infrastructure.

**Responsibilities:**
- Creates the `ModelContainer` with the full schema (5 SwiftData models)
- Creates shared `@StateObject` services: `MetronomeEngine`, `PracticeSettingsService`
- Injects shared services into the view hierarchy via `.environmentObject`
- Attaches `ModelContainer` to the `WindowGroup` via `.modelContainer`
- Detects UI testing launch arguments to disable animations

**Key pattern:**
```swift
@main
struct VirgoApp: App {
    @StateObject private var sharedMetronome = MetronomeEngine()
    @StateObject private var sharedPracticeSettings = PracticeSettingsService()
    // ModelContainer created as lazy stored property (not @State — App lifecycle)
    var sharedModelContainer: ModelContainer = { … }()
}
```

**Extension point:** Add new app-wide services here as `@StateObject`, inject via `.environmentObject`.

---

### 3.2 View Layer

**Location:** `Virgo/views/`, `Virgo/views/subviews/`, `Virgo/components/`

**Conventions:**
- Views are pure renderers — no business logic
- All mutable state owned by ViewModels or bound via `@EnvironmentObject`
- `@State` used only for truly local UI state (e.g., `expandedSongId`)
- Lazy ViewModel initialization inside `.task` to access environment values
- `.onDisappear` always calls `cleanup()` on ViewModels

**Component hierarchy:**

| Type | Location | Convention | Example |
|------|----------|------------|---------|
| Feature views | `views/` | `{Feature}View` | `GameplayView`, `MetronomeView` |
| Subview decompositions | `views/subviews/` | `{Parent}{Purpose}View` | `SessionResultsView`, `GameplaySheetMusicView` |
| Reusable components | `components/` | `{Feature}{Widget}View` | `GameplayHeaderView`, `DifficultyBadge` |
| View extensions | `views/` | `{View}+{Feature}.swift` | `GameplayView+InputManagerDelegate.swift` |

---

### 3.3 ViewModel Layer (`GameplayViewModel`)

**Location:** `Virgo/viewmodels/GameplayViewModel.swift`

**Pattern:** `@Observable @MainActor` (Swift 5.9 Observation framework — NOT `ObservableObject`)

> **Critical distinction:** `@Observable` does NOT require `@Published`. All stored properties are automatically tracked. This avoids the `@Published` re-render cascade problem.

**Responsibilities:**
- Owns all gameplay session state (playback, scoring, visual sync, BGM)
- Orchestrates three subsystems: MetronomeEngine, InputManager, ScoreEngine
- Caches SwiftData relationships to avoid main-thread blocking during rendering
- Pre-computes layout data (measure positions, beat positions, beam groups)
- Manages speed changes with debounce (100ms trailing-edge)

**Lifecycle:**
```
init()              ← Constructor injection of chart, metronome, practiceSettings
loadChartData()     ← Async SwiftData relationship loading
setupGameplay()     ← BGM, caches, persisted speed
startPlayback()     ← Start all engines, input listening
[session running]   ← updateVisualElementsFromMetronome() on each beat
handlePlaybackCompletion() ← Save score, snapshot engine, show results
cleanup()           ← Cancel tasks, save speed, stop engines
```

---

### 3.4 Engine Layer (Pure Value Types)

**Location:** `Virgo/utilities/ScoreEngine.swift`, `Virgo/layout/gameplay.swift`, `Virgo/utilities/MeasureUtils.swift`

**Pattern:** `struct` with `mutating` methods — no I/O, no SwiftUI dependencies, fully unit-testable.

#### ScoreEngine

```swift
struct ScoreEngine {
    private(set) var score: Int = 0
    private(set) var combo: Int = 0
    private(set) var maxCombo: Int = 0
    private(set) var perfectCount, greatCount, goodCount, missCount: Int

    mutating func processHit(accuracy: TimingAccuracy)
    mutating func processMissedNote()
    mutating func reset()
    func sessionResult(totalNotes:previousHighScore:) -> SessionResult
    static func comboMultiplier(for combo: Int) -> Double
    static func milestone(crossedFrom:to:) -> Int?
}
```

**Scoring formula:** `points = Int(100.0 × accuracy.scoreMultiplier × comboMultiplier(combo))`

#### GameplayLayout

Namespace struct containing all layout constants and calculation methods:
- Staff geometry (line spacing, row height, margins)
- `calculateMeasurePositions(totalMeasures:timeSignature:)` — wraps measures into rows
- `noteXPosition(measurePosition:beatIndex:timeSignature:)` — precise note x coordinate
- `NotePosition` enum — all staff positions with y-offsets

#### MeasureUtils

Stateless helpers for time-position arithmetic:
- `timePosition(measureNumber:measureOffset:) -> Double` — canonical position representation
- `measureIndex(from:) -> Int` — reverse conversion

---

### 3.5 Service Layer

**Location:** `Virgo/services/`

**Pattern:** `@MainActor final class`, `ObservableObject`, injected `UserDefaults` for testability.

| Service | Persistence | Responsibility |
|---------|-------------|----------------|
| `HighScoreService` | UserDefaults `[String: Int]` | Per-chart high scores, SHA-256 keyed |
| `PracticeSettingsService` | UserDefaults `[String: Double]` | Speed multiplier per chart (0.25–1.5×) |
| `PlaybackService` | Transient `@Published` | Song play/stop state for library list |
| `AudioPlaybackService` | FIFO cache (10 players) | Preview audio for downloaded songs |
| `DatabaseMaintenanceService` | ModelContext mutations | Schema migrations, duplicate cleanup |

All services follow the **UserDefaults service contract**:
1. `@MainActor` for thread safety
2. Injected `UserDefaults` for test isolation
3. SHA-256 / JSONEncoder stable key generation for `PersistentIdentifier`
4. Write verification (read-after-write)
5. Tolerant numeric decoding (NSNumber bridging)
6. Session-level in-memory cache to reduce UserDefaults reads

---

### 3.6 Utility Layer

**Location:** `Virgo/utilities/`

Multi-purpose infrastructure not fitting service or engine categories:

| Utility | Type | Purpose |
|---------|------|---------|
| `MetronomeEngine` | `@MainActor ObservableObject` | Facade over timing + audio engines |
| `MetronomeTimingEngine` | `@MainActor ObservableObject` | `DispatchSourceTimer`, nanosecond precision |
| `MetronomeAudioEngine` | `@MainActor ObservableObject` | `AVAudioEngine` buffer playback |
| `InputManager` | `ObservableObject` | CoreMIDI + NSEvent keyboard input |
| `InputSettingsManager` | — | Key/MIDI mapping persisted in UserDefaults |
| `DTXFileParser` | struct | Shift-JIS/UTF-8 DTX chart parsing |
| `DTXAPIClient` | actor/class | HTTP requests to FastAPI backend |
| `ServerSong*` family | class | Download orchestration and status |
| `AudioPlaybackService` | `@MainActor` | Preview audio with FIFO cache |
| `SwiftDataRelationshipLoader` | `@MainActor ObservableObject` | Async relationship loading protocol |
| `Logger` | struct (static) | `os.Logger` unified logging |
| `TestEnvironment` | enum (static) | Test process detection |
| `LaunchArguments` | enum (static) | UI test launch argument constants |
| `BeamGroupingLogic` | struct | Beam grouping calculation |
| `NotePositionKey` | struct | Hashable note position key |

---

### 3.7 Three-Layer Metronome Architecture

```
MetronomeEngine (public facade, @MainActor ObservableObject)
  ├── MetronomeTimingEngine  — DispatchSourceTimer, beat scheduling
  │     └── onBeat callback → MetronomeEngine.handleBeat()
  └── MetronomeAudioEngine   — AVAudioEngine, PCM buffer playback
        (conforms to AudioDriverProtocol for testability)
```

**Synchronization API:**
- `startAtTime(bpm:timeSignature:startTime:totalBeatsElapsed:)` — scheduled start for BGM sync
- `getCurrentPlaybackTime()` — shared time reference for visual sync
- `convertToAudioEngineTime(_:)` — `CFAbsoluteTime` → `AVAudioTime` for sample-accurate BGM

**Test injection:** `MetronomeEngine.init(audioDriver: AudioDriverProtocol?)` accepts a mock audio driver.

---

## 4. Architectural Layers and Dependencies

### Dependency Rules

```
View → ViewModel → Engine/Service → Persistence
  ↕          ↕           ↕
Utility ← Utility ← Utility
```

**Enforced rules:**
- Views NEVER access SwiftData models directly during render (only read from cached `@State`)
- Views NEVER own `AVAudioPlayer` or audio engines directly
- Services NEVER import SwiftUI
- Engines (value types) NEVER hold references to services or views
- All SwiftData access on `@MainActor`

### Layer Isolation Mechanisms

| Boundary | Mechanism |
|----------|-----------|
| View ↔ ViewModel | `@State var viewModel: GameplayViewModel?` (lazily initialized) |
| ViewModel ↔ Engine | Value-type copy semantics (`scoreEngine = ScoreEngine()`) |
| ViewModel ↔ Metronome | Combine subscription (`setupMetronomeSubscription()`) |
| ViewModel ↔ Input | Delegate pattern (`InputManagerDelegate`) + closure (`onNoteResult`) |
| View ↔ SwiftData | `.task` async load → `@State` cache |
| Service ↔ Persistence | Injected `UserDefaults` + `ModelContext` |
| Hardware ↔ Logic | `AudioDriverProtocol`, `InputManagerDelegate` protocols |

### Circular Dependency Prevention

- `GameplayViewModel` holds `MetronomeEngine` by **reference** (injected, not created)
- `MetronomeEngine` knows nothing about `GameplayViewModel`
- The subscription is one-directional: metronome beats → ViewModel callback
- `ScoreEngine` is a value type — no back-references possible

---

## 5. Data Architecture

### SwiftData Model Hierarchy

```
Song (@Model)
  │  title, artist, bpm, duration, genre, timeSignature
  │  isPlaying, dateAdded, playCount, isSaved
  │  bgmFilePath?, previewFilePath?
  │
  └─ @Relationship(deleteRule: .cascade)
     Chart (@Model)
       │  difficulty: Difficulty, level: Int, _timeSignature?
       │  Convenience: title, artist, bpm, duration, genre (forwarded from Song)
       │
       └─ @Relationship(deleteRule: .cascade, inverse: \Note.chart)
          Note (@Model)
            interval: NoteInterval, noteType: NoteType
            measureNumber: Int, measureOffset: Double

ServerSong (@Model)                           [separate domain]
  │  songId, title, artist, bpm, lastUpdated
  │  isDownloaded, hasBGM, bgmDownloaded, hasPreview, previewDownloaded
  │
  └─ @Relationship(deleteRule: .cascade)
     ServerChart (@Model)
       difficulty, difficultyLabel, level, filename, size
```

### Enumerations (Domain Vocabulary)

| Enum | Values | Role |
|------|--------|------|
| `Difficulty` | easy, medium, hard, expert | Chart difficulty classification |
| `NoteType` | bass, snare, highTom, … (13 types) | What drum to hit |
| `DrumType` | kick, snare, hiHat, … (10 types) | Physical drum pad (input mapping) |
| `NoteInterval` | full, half, quarter, … | Note duration for notation display |
| `TimeSignature` | fourFour, threeFour, … (8 values) | Rhythm structure |
| `TimingAccuracy` | perfect (±25ms), great (±50ms), good (±100ms), miss | Hit quality |

### Data Access Patterns

**SwiftData queries (reactive):**
```swift
@Query private var allSongs: [Song]          // ContentView — reactive list
@Query private var serverSongs: [ServerSong] // ContentView — server list
```

**Async relationship loading (in ViewModel):**
```swift
// In .task — prevents main-thread blocking during render
await vm.loadChartData()
// Internally: cachedSong = chart.song; cachedNotes = chart.safeNotes
```

**Safe concurrent access guards:**
```swift
var notesCount: Int {
    guard !isDeleted else { return 0 }
    return notes.filter { !$0.isDeleted }.count
}
```

### UserDefaults Persistence Schema

| Key | Type | Owner | Keying Strategy |
|-----|------|-------|-----------------|
| `"HighScorePerChart"` | `[String: Int]` | `HighScoreService` | JSONEncoder(PersistentIdentifier) → SHA-256 |
| `"PracticeSettingsSpeedMultipliers"` | `[String: Double]` | `PracticeSettingsService` | Same stable keying |
| MIDI/keyboard mappings | `[String: *]` | `InputSettingsManager` | `DrumType.storageKey` (e.g., `"drum_kick"`) |

### Caching Strategy (GameplayViewModel)

Pre-computed at session start, immutable during play:
```swift
private(set) var cachedNotes: [Note]
private(set) var cachedSong: Song?
private(set) var cachedDrumBeats: [DrumBeat]
private(set) var cachedMeasurePositions: [GameplayLayout.MeasurePosition]
private(set) var cachedBeamGroups: [[DrumBeat]]
private(set) var cachedBeatPositions: [UInt64: (x: Double, y: Double)]
```

---

## 6. Cross-Cutting Concerns

### 6.1 Logging

**Framework:** Apple's `os.Logger` unified logging system (NOT `print`)

**Categories:**
```swift
struct Logger {
    static let general  = os.Logger(subsystem: "com.cwchanap.Virgo", category: "General")
    static let database = os.Logger(subsystem: "…", category: "Database")
    static let audio    = os.Logger(subsystem: "…", category: "Audio")
    static let ui       = os.Logger(subsystem: "…", category: "UI")
    static let network  = os.Logger(subsystem: "…", category: "Network")
}
```

**Convenience API:**
```swift
Logger.database("…")           // .info on database logger
Logger.audioPlayback("…")      // .info on audio logger
Logger.userAction("…")         // .info on ui logger
Logger.debug("…")              // .debug, DEBUG builds only
Logger.warning("…")            // .notice with ⚠️ prefix
Logger.error("…")              // .error with ❌ prefix
Logger.critical("…")           // .critical with 🚨 prefix
```

**All string interpolation uses `privacy: .public`** — no PII logged.

---

### 6.2 Error Handling

| Layer | Strategy | Example |
|-------|----------|---------|
| View lifecycle | Guard + nil check | `guard let vm = viewModel else { return }` |
| Async boundaries | Task cancellation checks | `guard !Task.isCancelled else { return }` |
| Audio init | `TestEnvironment.isRunningTests` guard | Skip `AVAudioEngine` in tests |
| SwiftData writes | `try context.save()` + `Logger.databaseError` | `DatabaseMaintenanceService` |
| Network | `throws` propagation | `DTXAPIClient` throws; caught by `ServerSongService` |
| UserDefaults writes | Read-after-write verification | `HighScoreService.saveIfHighScore` |
| Value validation | Clamp + log | `PracticeSettingsService.setSpeed(_ speed:)` |
| Input matching | Tolerance windows | Notes >±200ms → `.miss`, no crash |

**No `fatalError` in production code** except `ModelContainer` creation failure (unrecoverable).

---

### 6.3 Test Environment Detection

**Multi-method detection** in `TestEnvironment.isRunningTests`:
1. `-XCTestConfigurationFilePath` launch argument
2. Bundle identifier suffix `"Tests"`
3. `XCTestConfigurationFilePath` environment variable
4. Process name containing `"xctest"`

**Used by:** `InputManager` (skip CoreMIDI setup), `MetronomeAudioEngine` (skip `AVAudioEngine` init)

---

### 6.4 Configuration Management

| Configuration | Source | Scope |
|--------------|--------|-------|
| Backend URL | `UserDefaults` (configurable) | App-wide |
| Speed per chart | `UserDefaults` | Per-chart |
| High score per chart | `UserDefaults` | Per-chart |
| Key/MIDI mapping | `UserDefaults` | App-wide |
| Audio session | Hardcoded (`.playback`, `.mixWithOthers`) | iOS only |
| BPM range | Static constants `MetronomeEngine.minBPM/maxBPM` | App-wide |

---

### 6.5 Thread Safety

- **All services are `@MainActor`** — no manual locking needed for service state
- **`ScoreEngine` is a value type** — copies are inherently thread-safe
- **`MetronomeTimingEngine`** uses a dedicated `DispatchQueue` (`qos: .userInitiated`) for the timer callback; UI updates hop back via `DispatchQueue.main`
- **SwiftData context** always accessed on `@MainActor`; background operations use background `ModelContext`

---

## 7. Swift/SwiftUI Architectural Patterns

### 7.1 `@Observable` vs `ObservableObject`

| Usage | When |
|-------|------|
| `@Observable @MainActor` (Swift 5.9) | `GameplayViewModel` — fine-grained property tracking, no `@Published` needed |
| `@MainActor ObservableObject` | Services (`HighScoreService`, `PracticeSettingsService`) — `@StateObject` / `@EnvironmentObject` compatible |
| `struct` | Engines (`ScoreEngine`, `GameplayLayout`) — immutable, value-type, testable |

> **Critical performance rule:** Do NOT observe `MetronomeEngine.$currentBeat` directly in views containing hundreds of subviews. Use a ViewModel intermediary that batches visual state updates.

### 7.2 Environment Propagation

```
VirgoApp
  MetronomeEngine      → .environmentObject → all descendant views
  PracticeSettingsService → .environmentObject → all descendant views
  ModelContainer       → .modelContainer → @Query, @Environment(\.modelContext)
```

### 7.3 Navigation Pattern

```swift
// Leaf navigation via @State binding
@State private var navigateToGameplay = false
@State private var selectedChart: Chart?

NavigationStack {
    // …
    .navigationDestination(isPresented: $navigateToGameplay) {
        if let chart = selectedChart {
            GameplayView(chart: chart, metronome: metronome)
        }
    }
}
```

Sheets use `isPresented` binding:
```swift
.sheet(isPresented: Binding(
    get: { viewModel?.isShowingSessionResults ?? false },
    set: { viewModel?.isShowingSessionResults = $0 }
))
```

### 7.4 SwiftData Async Loading Pattern

**Problem:** Accessing `chart.notes` during render causes threading crashes.

**Solution:** Load in `.task`, store in `@State`:

```swift
// In .task modifier
await vm.loadChartData()

// Inside loadChartData() — GameplayViewModel
func loadChartData() async {
    self.cachedSong = chart.song
    self.cachedNotes = chart.safeNotes
    // compute layout caches from cachedNotes
}
```

### 7.5 Metronome Tab Performance Optimization

```swift
// MetronomeView only mounted when tab is active
Group {
    if selectedTab == 1 {
        MetronomeView()
    } else {
        Color.black  // Placeholder — prevents beat tick re-renders
    }
}
```

### 7.6 Speed Control Debounce Pattern

```swift
// Slider → debounced apply (100ms trailing-edge)
// Prevents rapid re-scheduling of metronome + BGM on slider drag
private var speedDebounceTask: Task<Void, Never>?

func updateSpeed(_ newSpeed: Double) {
    speedDebounceTask?.cancel()
    speedDebounceTask = Task {
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard !Task.isCancelled else { return }
        await applySpeedChangeInternal(newSpeed)
    }
}
```

---

## 8. Implementation Patterns

### 8.1 UserDefaults Service Pattern

```swift
@MainActor
final class MySettingsService: ObservableObject {
    private let settingsKey = "MySettings"
    private let userDefaults: UserDefaults
    private var sessionCache: [PersistentIdentifier: ValueType] = [:]
    private let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e
    }()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func value(for chartID: PersistentIdentifier) -> ValueType {
        if let cached = sessionCache[chartID] { return cached }
        let key = persistenceKey(for: chartID)
        return readPersisted()[key] ?? .default
    }

    @discardableResult
    func save(_ value: ValueType, for chartID: PersistentIdentifier) -> Bool {
        let key = persistenceKey(for: chartID)
        var stored = readPersisted()
        stored[key] = value
        sessionCache[chartID] = value
        userDefaults.set(stored, forKey: settingsKey)
        return readPersisted()[key] == value  // write verification
    }

    private func persistenceKey(for chartID: PersistentIdentifier) -> String {
        if let data = try? jsonEncoder.encode(chartID),
           let str = String(data: data, encoding: .utf8) { return str }
        // SHA-256 fallback
        let digest = SHA256.hash(data: Data(String(describing: chartID).utf8))
        return "chart_\(digest.compactMap { String(format: "%02x", $0) }.joined().prefix(32))"
    }

    private func readPersisted() -> [String: ValueType] { … tolerant NSNumber decoding … }
}
```

### 8.2 Pure Value-Type Engine Pattern

```swift
// No imports beyond Foundation. No @Published. No ObservableObject.
struct MyEngine {
    private(set) var stateA: Int = 0
    private(set) var stateB: Double = 0.0

    mutating func processEvent(_ event: MyEvent) {
        // pure mutation — no side effects
    }

    mutating func reset() {
        stateA = 0; stateB = 0.0
    }

    func result() -> MyResult {
        MyResult(a: stateA, b: stateB)
    }

    static func pureHelper(for input: Int) -> Double { … }
}
```

### 8.3 Protocol-Based Hardware Abstraction

```swift
// Protocol — implemented by real hardware + test mock
@MainActor
protocol AudioDriverProtocol {
    func playTick(volume: Float, isAccented: Bool, atTime: AVAudioTime?)
    func stop()
    func resume()
    func convertToAudioEngineTime(_ cfTime: CFAbsoluteTime) -> AVAudioTime?
}

// Production implementation
@MainActor
class MetronomeAudioEngine: AudioDriverProtocol { … }

// Injection point
class MetronomeEngine {
    init(audioDriver: AudioDriverProtocol? = nil) {
        self.audioDriver = audioDriver ?? MetronomeAudioEngine()
    }
}
```

### 8.4 Delegate + Closure Bridge Pattern

```swift
// Protocol for hardware events
protocol InputManagerDelegate: AnyObject {
    func inputManager(_ manager: InputManager, didMatchNote result: NoteMatchResult)
}

// Delegate class — translates protocol to closure
class GameplayInputHandler: InputManagerDelegate {
    var onNoteResult: ((NoteMatchResult) -> Void)?

    func inputManager(_ manager: InputManager, didMatchNote result: NoteMatchResult) {
        onNoteResult?(result)  // Bridge to ViewModel closure
    }
}

// ViewModel wiring — avoids retain cycle via [weak self]
func wireInputHandler() {
    inputHandler.onNoteResult = { [weak self] result in
        self?.recordHit(result: result)
    }
}
```

### 8.5 SwiftData Cascade Delete Pattern

```swift
@Model final class Song {
    @Relationship(deleteRule: .cascade)
    var charts: [Chart]   // Deleting Song deletes all Charts
}

@Model final class Chart {
    @Relationship(deleteRule: .cascade, inverse: \Note.chart)
    var notes: [Note]     // Deleting Chart deletes all Notes
}
```

### 8.6 Scored Note Deduplication Pattern

```swift
// Set-based deduplication prevents double-scoring rapid inputs
private var scoredNoteIDs: Set<ObjectIdentifier> = []

func recordHit(result: NoteMatchResult) {
    if let note = result.matchedNote {
        guard scoredNoteIDs.insert(ObjectIdentifier(note)).inserted else { return }
    }
    scoreEngine.processHit(accuracy: result.timingAccuracy)
}
```

### 8.7 Forward-Only Miss Scan Pattern

```swift
// O(new notes per tick) instead of O(totalNotes) per tick
private var sortedNotesByTimePosition: [Note] = []
private var missedNoteScanCursor: Int = 0
private var lastScannedTimePosition: Double = 0.0

func scanForMissedNotes(upToTimePosition playheadPosition: Double) {
    let scanBoundary = playheadPosition - lateWindowInMeasures
    guard scanBoundary > lastScannedTimePosition else { return }

    while missedNoteScanCursor < sortedNotesByTimePosition.count {
        let note = sortedNotesByTimePosition[missedNoteScanCursor]
        let notePos = MeasureUtils.timePosition(…)
        if notePos >= scanBoundary { break }
        if !scoredNoteIDs.contains(ObjectIdentifier(note)) {
            scoredNoteIDs.insert(ObjectIdentifier(note))
            scoreEngine.processMissedNote()
        }
        missedNoteScanCursor += 1
    }
    lastScannedTimePosition = scanBoundary
}
```

---

## 9. Testing Architecture

### Framework

**Swift Testing framework** (not XCTest) — `@Suite`, `@Test`, `#expect`

```swift
import Testing
@testable import Virgo

@Suite("ScoreEngine Tests")
struct ScoreEngineTests {
    @Test("Perfect hit earns 100 points")
    func testPerfectHitScore() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        #expect(engine.score == 100)
    }
}
```

### Test Infrastructure

| Helper | Purpose |
|--------|---------|
| `TestContainer` | In-memory `ModelContainer` with per-test isolation |
| `TestModelFactory` | Factory methods: `createSong`, `createChart`, `createNote`, `createSongWithChart` |
| `TestHelpers.waitFor(condition:timeout:)` | Polling-based async condition wait |
| `CombineTestUtilities.waitForPublished` | Publisher-based async state wait (no race conditions) |
| `TestUserDefaults.makeIsolated()` | Isolated `UserDefaults` suite per test |
| `TestSetup.withTestSetup` | Scoped test execution with setup/teardown |
| `TestEnvironment.isRunningTests` | Prevents AVFoundation/CoreMIDI init in tests |

### Test Boundaries

| Test Type | Location | What It Tests |
|-----------|----------|---------------|
| Unit — Engines | `ScoreEngineTests`, `MetronomeTimingTests` | Pure logic, no I/O |
| Unit — Services | `HighScoreServiceTests`, `PracticeSettingsServiceTests` | UserDefaults with injected mock |
| Unit — Models | `DrumTrackTests`, `NoteModelTests` | SwiftData model behaviour |
| Unit — Parsing | `DTXFileParserTests` | DTX chart format parsing |
| Integration | `ScoringIntegrationTests`, `GameplayProgressionTests` | Multi-component workflows |
| UI | `VirgoUITests/` | End-to-end navigation, session flow |

### Test Isolation Strategies

```swift
// SwiftData isolation — in-memory per test
let (song, chart) = try await TestModelFactory.createSongWithChart(
    in: TestContainer.shared.context
)

// UserDefaults isolation
let (userDefaults, suiteName) = TestUserDefaults.makeIsolated()
let service = HighScoreService(userDefaults: userDefaults)

// Audio isolation — automatic via TestEnvironment
// MetronomeAudioEngine checks TestEnvironment.isRunningTests → skips AVAudioEngine.init
```

---

## 10. Deployment Architecture

### Platform Targets

| Platform | Min Version | Notes |
|----------|-------------|-------|
| iOS | 18.5+ | Full feature set incl. MIDI, haptics |
| macOS | 14.0+ | NSEvent keyboard input; no haptics |

### Build Configurations

```
Debug   — DEBUG flag, Logger.debug() active, animations can be disabled for UI tests
Release — Production, debug logs suppressed
```

### Backend

- **FastAPI server** (`server/main.py`) at `http://127.0.0.1:8001` (local dev)
- **CORS enabled** — Cloudflare Workers deployment supported
- **Endpoints:** list songs, download chart DTX, download BGM/preview files
- **Shift-JIS encoding** support for Japanese DTX files
- URL configurable via `UserDefaults` (Settings view)

### SwiftData Storage

- SQLite database stored in app's `Application Support` directory
- `isStoredInMemoryOnly: false` — persists across launches
- In-memory only for tests (`TestContainer`)

### Code Signing

```
# Unit test builds — signing disabled for CI
CODE_SIGNING_REQUIRED=NO
CODE_SIGNING_ALLOWED=NO
```

---

## 11. Extension and Evolution Patterns

### Adding a New Per-Chart Service

1. Copy `HighScoreService.swift` pattern
2. Change `settingsKey`, stored value type, and business logic
3. Add to `VirgoApp` as `@StateObject` if app-wide, or create locally in ViewModel
4. Inject via `init(userDefaults: UserDefaults = .standard)` for testability

### Adding a New SwiftData Model

1. Add `@Model final class MyModel { … }` to `DrumTrack.swift`
2. Add `MyModel.self` to `Schema([…])` in `VirgoApp.sharedModelContainer`
3. Add `MyModel.self` to `Schema([…])` in `TestContainer.resolveContainer()`
4. Define `deleteRule` on all relationships

### Adding a New View

1. Create `{Feature}View.swift` in `views/`
2. Add tab entry in `ContentView.swift` or navigation destination
3. If feature view needs stateful orchestration → create `{Feature}ViewModel.swift`
4. Access shared services via `@EnvironmentObject`
5. Load SwiftData data in `.task`, cache in `@State`

### Adding a New Scoring Metric

1. Add `private(set) var myCount: Int = 0` to `ScoreEngine`
2. Add increment in relevant `mutating func processHit` / `processMissedNote`
3. Add `reset()` clause
4. Add to `SessionResult` struct
5. Populate in `sessionResult(totalNotes:previousHighScore:)`
6. Add tests in `ScoreEngineTests.swift`

### Extending SessionResultsView

1. `ScoreEngine` already passed directly — new computed properties are automatically available
2. Add new `let` prop to `SessionResultsView` init only if data comes from outside `ScoreEngine`
3. Update `GameplayView.swift` `.sheet` call to pass new argument
4. Create new SwiftUI component in `components/` for complex visual representations

### Integration of New External System

**Pattern:** Adapter + protocol abstraction

```swift
// 1. Define protocol at the ViewModel boundary
protocol MyExternalServiceProtocol {
    func fetchData() async throws -> [MyData]
}

// 2. Production adapter
class MyExternalServiceAdapter: MyExternalServiceProtocol {
    func fetchData() async throws -> [MyData] { … }
}

// 3. Test mock
class MockMyExternalService: MyExternalServiceProtocol {
    func fetchData() async throws -> [MyData] { return [] }
}
```

---

## 12. Architectural Pattern Examples

### Example 1: ScoreEngine — Snapshot Pattern

The `sessionResult()` method captures an immutable snapshot at session end, before `reset()` clears live state:

```swift
func handlePlaybackCompletion() {
    let finalScore = scoreEngine.score
    let isNewRecord = highScoreService.saveIfHighScore(finalScore, for: chart.persistentModelID)
    sessionScoreEngine = scoreEngine     // ← Snapshot (value copy)
    resetPlaybackState()                 // ← Clears scoreEngine
    sessionFinalScore = finalScore       // ← Survives reset
    sessionIsNewRecord = isNewRecord
    isShowingSessionResults = true
}
```

Consuming in SessionResultsView:
```swift
SessionResultsView(
    finalScore: vm.sessionFinalScore,
    scoreEngine: vm.sessionScoreEngine,  // ← Snapshot used here
    …
)
```

### Example 2: Write Verification Pattern

```swift
func saveIfHighScore(_ score: Int, for chartID: PersistentIdentifier) -> Bool {
    guard score > 0 else { return false }
    let key = persistenceKey(for: chartID)
    var scores = readPersistedScores()
    guard score > (scores[key] ?? 0) else { return false }
    scores[key] = score
    userDefaults.set(scores, forKey: settingsKey)
    let verified = readPersistedScores()         // ← Read-back verification
    if verified[key] == score {
        Logger.debug("New high score \(score) saved")
        return true
    } else {
        Logger.error("Write verification failed — score not persisted")
        return false
    }
}
```

### Example 3: Hardware Abstraction + Test Injection

```swift
// Production
let metronome = MetronomeEngine()           // uses MetronomeAudioEngine

// Test
class MockAudioDriver: AudioDriverProtocol {
    var playTickCallCount = 0
    func playTick(volume: Float, isAccented: Bool, atTime: AVAudioTime?) {
        playTickCallCount += 1
    }
    func stop() {}
    func resume() {}
    func convertToAudioEngineTime(_ cfTime: CFAbsoluteTime) -> AVAudioTime? { nil }
}

let mockDriver = MockAudioDriver()
let engine = MetronomeEngine(audioDriver: mockDriver)
engine.start(bpm: 120, timeSignature: .fourFour)
// assert mockDriver.playTickCallCount > 0
```

### Example 4: Lazy ViewModel Initialization

```swift
struct GameplayView: View {
    @State var viewModel: GameplayViewModel?

    var body: some View {
        content
        .task {
            // EnvironmentObjects available here — not in init()
            if viewModel == nil {
                viewModel = GameplayViewModel(
                    chart: chart,
                    metronome: metronome,
                    practiceSettings: practiceSettings   // @EnvironmentObject
                )
            }
            guard let vm = viewModel else { return }
            await vm.loadChartData()                    // async SwiftData load
            guard !Task.isCancelled else { return }
            vm.setupGameplay()
        }
        .onDisappear {
            viewModel?.cleanup()                         // Always cleanup
        }
    }
}
```

---

## 13. Architectural Decision Records

### ADR-01: `@Observable` over `ObservableObject` for GameplayViewModel

**Context:** `GameplayView` contains hundreds of notation subviews. Using `@Published` on an `@EnvironmentObject` caused complete UI unresponsiveness (>5 second scroll delay).

**Decision:** `GameplayViewModel` uses Swift 5.9's `@Observable` macro. Only accessed properties trigger re-renders, not all properties.

**Consequences (+):** Fine-grained rendering; no `@Published` noise; no `@ObservedObject` wrapper needed.  
**Consequences (-):** `@Observable` types cannot be used as `@EnvironmentObject`; ViewModel must be `@State` in its owning view.

---

### ADR-02: Value-Type `ScoreEngine`

**Context:** Scoring logic needed to be testable in isolation, snapshotted at session end, and reset without risk of stale observer callbacks.

**Decision:** `struct ScoreEngine` with pure `mutating` methods. No dependencies, no `@Published`.

**Consequences (+):** Copy semantics make snapshots trivial (`sessionScoreEngine = scoreEngine`). No threading concerns. 100% testable without any mocking.  
**Consequences (-):** Cannot be observed by SwiftUI directly; ViewModel must bridge updates.

---

### ADR-03: SHA-256 Keyed UserDefaults

**Context:** `PersistentIdentifier` from SwiftData is not guaranteed stable as a `description` string across OS versions.

**Decision:** JSONEncoder-encoded representation as primary key, SHA-256 of description as fallback.

**Consequences (+):** Stable across app updates; same key regardless of internal SwiftData version.  
**Consequences (-):** Keys are unreadable in UserDefaults inspector; slightly more complex than raw `.description`.

---

### ADR-04: Three-Layer Metronome Architecture

**Context:** Metronome needs nanosecond-precision audio scheduling (hardware timer) and separate UI beat publishing.

**Decision:** `MetronomeEngine` (facade) orchestrates `MetronomeTimingEngine` (DispatchSourceTimer) and `MetronomeAudioEngine` (AVAudioEngine). Audio driver behind `AudioDriverProtocol` for test injection.

**Consequences (+):** Each layer independently testable; audio can be mocked; precise CFAbsoluteTime-based scheduling for BGM sync.  
**Consequences (-):** Three classes for one feature; higher initial complexity.

---

### ADR-05: `@MainActor` on All Services

**Context:** SwiftData requires `@MainActor`; services are accessed from views and ViewModels (both MainActor).

**Decision:** Annotate all service classes `@MainActor`. Background I/O uses `async` functions that hop off-actor internally.

**Consequences (+):** No manual locking; actor isolation enforced by compiler; consistent threading model.  
**Consequences (-):** Services cannot be called from background threads without `await`.

---

### ADR-06: Swift Testing Framework (not XCTest)

**Context:** New project with Swift 5.9+ target; Apple recommends Swift Testing for new projects.

**Decision:** All unit tests use `@Suite`, `@Test`, `#expect` from the `Testing` module.

**Consequences (+):** Parallel test execution by default; expressible parameterized tests; Swift-native.  
**Consequences (-):** Some XCTest integration points (e.g., UI tests, performance tests) still require XCTest.

---

## 14. Architecture Governance

### Automated Checks

- **SwiftLint** — enforced via pre-commit hook (`scripts/setup-git-hooks.sh`)
  - Auto-fix mode available: `swiftlint lint --fix`
  - Configuration: `codecov.yml` (root level)
- **CI Test Suite** — full unit test run on every push
  - `xcodebuild test -only-testing:VirgoTests` (macOS destination)
  - Code coverage enabled (`-enableCodeCoverage YES`)

### Architectural Compliance Rules

| Rule | Enforcement |
|------|-------------|
| No UI imports in services/engines | SwiftLint custom rule possible; code review |
| SwiftData on MainActor | Compiler (`@MainActor` annotations) |
| Value-type engines | `struct` keyword — compiler enforced |
| Async boundary checks | Task cancellation guard pattern — code review |
| Write verification on persistence | Manual review; tests verify verified return value |
| `@Observable` for complex ViewModels | Code review |

### Documentation Practices

- Inline `// MARK: -` sections in all Swift files
- Public API documented with `///` doc comments
- Complex algorithms annotated with inline comments
- Architecture decisions recorded as ADRs in this document
- Performance-critical patterns annotated with context (e.g., "O(n) amortized")

---

## 15. Blueprint for New Development

### Development Workflow by Feature Type

#### Type A: New Scoring/Gameplay Metric

1. **Engine** (`ScoreEngine.swift`) — add state property, mutating method, reset clause, `SessionResult` field
2. **Tests** (`ScoreEngineTests.swift`) — add test cases before or alongside implementation
3. **ViewModel** (`GameplayViewModel.swift`) — pass new data through in `recordHit()` or `handlePlaybackCompletion()`
4. **Component** (`components/`) — create new SwiftUI component if complex visualization needed
5. **Results View** (`SessionResultsView.swift`) — integrate component, update initializer if needed
6. **GameplayView** (`GameplayView.swift`) — pass new ViewModel property to sheet

#### Type B: New Per-Chart Persistent Setting

1. **Service** (`services/MySettingService.swift`) — copy `PracticeSettingsService.swift`, adapt
2. **Tests** (`VirgoTests/MySettingServiceTests.swift`) — use `TestUserDefaults.makeIsolated()`
3. **ViewModel** — create service internally, call in setup/cleanup
4. **View** — expose via `@EnvironmentObject` or pass directly

#### Type C: New Server Song Feature

1. **API Types** (`utilities/DTXAPITypes.swift`) — add new response types
2. **API Client** (`utilities/DTXAPIClient.swift`) — add new endpoint method
3. **Downloader/Parser** — extend `ServerSongDownloader` or `DTXFileParser`
4. **Model** — extend `ServerSong` or `ServerChart` with new field
5. **Status Manager** — update refresh logic
6. **UI** — update `ServerSongsView` / `ServerSongRow`

#### Type D: New View/Screen

1. Create `{Feature}View.swift` in `views/`
2. If stateful: create `{Feature}ViewModel.swift` in `viewmodels/` using `@Observable @MainActor`
3. Add navigation destination or tab in `ContentView.swift`
4. Access shared services via `@EnvironmentObject private var myService: MyService`
5. Load SwiftData in `.task { await vm.loadData() }`

---

### Implementation Templates

#### New Engine (Value Type)

```swift
// File: Virgo/utilities/MyEngine.swift
import Foundation

struct MyResult: Equatable {
    let value1: Int
    let value2: Double
}

struct MyEngine {
    // MARK: - State
    private(set) var value1: Int = 0
    private(set) var value2: Double = 0.0

    // MARK: - Mutating API
    mutating func process(event: MyEvent) { … }
    mutating func reset() { value1 = 0; value2 = 0.0 }

    // MARK: - Snapshot
    func result() -> MyResult { MyResult(value1: value1, value2: value2) }

    // MARK: - Pure Helpers
    static func calculate(for input: Int) -> Double { … }
}
```

#### New UserDefaults Service

```swift
// File: Virgo/services/MyService.swift
import Foundation
import SwiftData
import CryptoKit

@MainActor
final class MyService: ObservableObject {
    private let settingsKey = "MySettingsKey"
    private let userDefaults: UserDefaults
    private var cache: [PersistentIdentifier: ValueType] = [:]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func value(for chartID: PersistentIdentifier) -> ValueType { … }

    @discardableResult
    func save(_ value: ValueType, for chartID: PersistentIdentifier) -> Bool {
        // Write + verify
    }

    private func persistenceKey(for chartID: PersistentIdentifier) -> String { … }
    private func readPersisted() -> [String: ValueType] { … }
}
```

#### New Test Suite

```swift
// File: VirgoTests/MyEngineTests.swift
import Testing
@testable import Virgo

@Suite("MyEngine Tests")
struct MyEngineTests {

    @Test("Initial state is zero")
    func testInitialState() {
        let engine = MyEngine()
        #expect(engine.value1 == 0)
    }

    @Test("Processing event updates state")
    func testProcessEvent() {
        var engine = MyEngine()
        engine.process(event: .someEvent)
        #expect(engine.value1 == 1)
    }

    @Test("Reset clears all state")
    func testReset() {
        var engine = MyEngine()
        engine.process(event: .someEvent)
        engine.reset()
        #expect(engine.value1 == 0)
    }
}
```

#### New SwiftUI Component

```swift
// File: Virgo/components/MyComponent.swift
import SwiftUI

struct MyComponent: View {
    let value: Double
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.1f", value))
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    MyComponent(value: 95.5, label: "MY METRIC", color: .green)
        .background(Color.black)
}
```

---

### Common Pitfalls

| Pitfall | Consequence | Correct Pattern |
|---------|-------------|-----------------|
| Accessing `chart.notes` in view body | Main-thread SwiftData crash | Load in `.task`, store in `@State` |
| `@Published` on `@EnvironmentObject` with many views | Complete UI freeze on each publish | Use `@Observable` + intermediary ViewModel |
| Observing `metronome.$currentBeat` in complex view | Hundreds of subview re-renders per beat | Subscribe in ViewModel, batch visual updates |
| Not checking `Task.isCancelled` after async boundaries | Work continues on dismissed/deallocated view | Guard after every `await` |
| Breaking `processHit` API | Compile errors across all callers | Use default parameter `timingError: Double? = nil` |
| Storing `[NoteMatchResult]` forever | Memory leak for long sessions | Value type arrays freed on `reset()` |
| Calling service from background thread | Actor isolation violation | All services are `@MainActor`; always `await` from background |
| Creating `ModelContainer` in tests without in-memory flag | Tests mutate production database | Use `TestContainer` with `isStoredInMemoryOnly: true` |
| Forgetting `cleanup()` on ViewModel | Audio continues after view dismissal | Always connect `cleanup()` to `.onDisappear` |
| Force-unwrapping SwiftData relationships | Runtime crash on concurrent access | Use `safeNotes`, `notesCount`, `!isDeleted` guards |

---

*This blueprint was generated from the Virgo codebase as of 2026-02-28. Update this document when:*
- *New architectural layers or patterns are introduced*
- *Significant refactoring changes component responsibilities*
- *New cross-cutting concerns (auth, analytics, etc.) are added*
- *ADRs are made for significant technical decisions*
