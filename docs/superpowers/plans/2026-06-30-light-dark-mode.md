# App-wide Light/Dark Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a single consistent Light/Dark mode (System / Light / Dark, default System) that all pages and the Metronome follow, and fix the white-on-light contrast bug — while the immersive gameplay play view and Session Results stay a fixed dark stage.

**Architecture:** The app root reads one `@AppStorage("appearanceMode")` value and applies `.preferredColorScheme`, which both sets the effective `@Environment(\.colorScheme)` for the whole tree and aligns all system chrome. Every follow-mode screen uses a new `.appSurface()` modifier that maps `colorScheme` → `SurfaceWorld` (dark→ink, light→paper) and applies the existing `.surface(_:)`. Gameplay/Session Results keep `.surface(.ink)`/`Palette.stage` and pin `.colorScheme(.dark)`.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing (unit). Engraved design system: `@Environment(\.theme)` (`VirgoTheme` paper/ink), `Palette`, `.surface(_:)`, `AppType`, `Spacing`/`Radius`, `GhostButtonStyle`, `LedgerRow`.

## Global Constraints

- iPad-only for the iOS family (`TARGETED_DEVICE_FAMILY = 2`); macOS 14+ and iPadOS. No iPhone destinations/assumptions.
- Unit tests use **Swift Testing** only (`import Testing`, `#expect`, `@Suite`) in `VirgoTests` — never XCTest there.
- **Never** edit `Virgo.xcodeproj/project.pbxproj`; Xcode 16 synchronized groups pick up new files automatically.
- New UI reads `@Environment(\.theme)` / `.appSurface()` and uses design tokens only — no raw `Color.white/.black/.gray`. The accent is world-invariant (`Palette.vermillion == theme.accent` in both worlds).
- Preserve existing accessibility identifiers; add only the new `appearanceModePicker`.
- Build/lint/test results are authoritative; ignore stale SourceKit "cannot find type" diagnostics (a known same-module index artifact on this branch).
- Verification runs sequentially; never share `-derivedDataPath` across concurrent `xcodebuild`. Tests run with `-parallel-testing-enabled NO`.
- This machine currently has a broken codesign/keychain: `xcodebuild build`/test may fail at the CodeSign step. For compile/test verification add `CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`. Swift Testing focused suites must use the **type name** selector (e.g. `VirgoTests/AppearanceModeTests`), not the `@Suite` display name, or 0 tests run.
- Commit trailers on every commit:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_013d9nW77M3PamgkL7GnWCyd
  ```

## Reference (already in the codebase — consume, don't redefine)

- `enum SurfaceWorld { case paper; case ink }` and `func surface(_ world: SurfaceWorld) -> some View` in `Virgo/design/Theme.swift` (`.surface` = `.environment(\.theme, …).background(theme.background.ignoresSafeArea())`).
- `VirgoTheme` roles: `background, raised, primary, secondary, rule, accent`. `.paper` (light) and `.ink` (dark). Both worlds' `accent == Palette.vermillion`.
- `Palette`: `paper, paperRaised, ink, inkMuted, rule, vermillion` (paper world) and `stage, stageRaised, chalk, chalkMuted, gridline` (ink world).
- Raw→theme mapping for the re-theme: `stage→theme.background`, `stageRaised→theme.raised`, `chalk→theme.primary`, `chalkMuted→theme.secondary`, `gridline→theme.rule`, `vermillion→theme.accent`.
- `AppType.{display,title,headline,numericLarge}`, `.plexMono(_:weight:)`, `Spacing`, `Radius.md`.

---

### Task 1: `AppearanceMode` enum + unit tests

**Files:**
- Create: `Virgo/design/AppearanceMode.swift`
- Test: `VirgoTests/AppearanceModeTests.swift`

**Interfaces:**
- Produces: `enum AppearanceMode: String, CaseIterable, Identifiable { case system, light, dark; var id: String; static let storageKey: String; var preferredColorScheme: ColorScheme?; var label: String }`.

- [ ] **Step 1: Write the failing test**

`VirgoTests/AppearanceModeTests.swift`:
```swift
import Testing
import SwiftUI
@testable import Virgo

@Suite("AppearanceMode")
struct AppearanceModeTests {
    @Test("system maps to no preferred color scheme")
    func systemIsNil() {
        #expect(AppearanceMode.system.preferredColorScheme == nil)
    }

    @Test("light forces light")
    func lightForcesLight() {
        #expect(AppearanceMode.light.preferredColorScheme == .light)
    }

    @Test("dark forces dark")
    func darkForcesDark() {
        #expect(AppearanceMode.dark.preferredColorScheme == .dark)
    }

    @Test("unknown stored value has no case (falls back via AppStorage default)")
    func unknownRawValueIsNil() {
        #expect(AppearanceMode(rawValue: "bogus") == nil)
    }

    @Test("all three modes are selectable")
    func allCases() {
        #expect(AppearanceMode.allCases == [.system, .light, .dark])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/AppearanceModeTests -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```
Expected: FAIL to compile — "Cannot find 'AppearanceMode' in scope".

- [ ] **Step 3: Write the implementation**

`Virgo/design/AppearanceMode.swift`:
```swift
//
//  AppearanceMode.swift
//  Virgo
//
//  User-selectable app appearance. Drives `.preferredColorScheme` at the app
//  root; every follow-mode screen resolves its world from the resulting
//  color scheme via `.appSurface()`.
//

import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// UserDefaults key shared by the app root and the Appearance setting.
    static let storageKey = "appearanceMode"

    /// `nil` means "follow the OS appearance".
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run the Step 2 command. Expected: TEST SUCCEEDED, 5 tests in `AppearanceMode` passing (look for `✔ Test run with 5 tests`).

- [ ] **Step 5: Commit**

```bash
git add Virgo/design/AppearanceMode.swift VirgoTests/AppearanceModeTests.swift
git commit -m "feat(theme): add AppearanceMode (system/light/dark)"
# (append the standard trailers)
```

---

### Task 2: `SurfaceWorld.forColorScheme` + `.appSurface()` modifier

**Files:**
- Modify: `Virgo/design/Theme.swift` (append extensions at end of file)
- Test: `VirgoTests/SurfaceWorldColorSchemeTests.swift`

**Interfaces:**
- Consumes: `SurfaceWorld`, `func surface(_:)` (existing).
- Produces: `static func SurfaceWorld.forColorScheme(_ scheme: ColorScheme) -> SurfaceWorld` and `func View.appSurface() -> some View`.

- [ ] **Step 1: Write the failing test**

`VirgoTests/SurfaceWorldColorSchemeTests.swift`:
```swift
import Testing
import SwiftUI
@testable import Virgo

@Suite("SurfaceWorld colorScheme mapping")
struct SurfaceWorldColorSchemeTests {
    @Test("dark scheme resolves to ink")
    func darkIsInk() {
        #expect(SurfaceWorld.forColorScheme(.dark) == .ink)
    }

    @Test("light scheme resolves to paper")
    func lightIsPaper() {
        #expect(SurfaceWorld.forColorScheme(.light) == .paper)
    }
}
```

Note: `SurfaceWorld` must be `Equatable` for `==`. It is a simple `enum SurfaceWorld { case paper; case ink }` with no associated values, so Swift synthesizes `Equatable` automatically — no change needed.

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/SurfaceWorldColorSchemeTests -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```
Expected: FAIL to compile — "Type 'SurfaceWorld' has no member 'forColorScheme'".

- [ ] **Step 3: Write the implementation**

Append to `Virgo/design/Theme.swift` (after the existing `extension View { func surface(_:) … }`):
```swift
extension SurfaceWorld {
    /// Maps the effective SwiftUI color scheme to a surface world.
    /// Dark → ink, otherwise paper.
    static func forColorScheme(_ scheme: ColorScheme) -> SurfaceWorld {
        scheme == .dark ? .ink : .paper
    }
}

private struct AppSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.surface(.forColorScheme(colorScheme))
    }
}

extension View {
    /// Themed background + theme injection that follows the global appearance
    /// mode via the effective color scheme. Use on screens that should flip with
    /// Light/Dark; fixed-world screens keep `.surface(.ink)` instead.
    func appSurface() -> some View {
        modifier(AppSurfaceModifier())
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run the Step 2 command. Expected: TEST SUCCEEDED, 2 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Virgo/design/Theme.swift VirgoTests/SurfaceWorldColorSchemeTests.swift
git commit -m "feat(theme): add appSurface() modifier + colorScheme->world mapping"
# (trailers)
```

---

### Task 3: Page screens follow the mode (`.surface(.paper)` → `.appSurface()`)

**Files (each: replace the single `.surface(.paper)` call with `.appSurface()`):**
- Modify: `Virgo/views/MainMenuView.swift:123`
- Modify: `Virgo/views/SongsTabView.swift:154`
- Modify: `Virgo/views/LibraryView.swift:52`
- Modify: `Virgo/views/SettingsView.swift:92`
- Modify: `Virgo/views/InputSettingsView.swift:163`
- Modify: `Virgo/views/AudioSettingsView.swift:112`
- Modify: `Virgo/views/DrumNotationSettingsView.swift:67`
- Modify: `Virgo/views/ProfileView.swift:68`
- Modify: `Virgo/views/ChartScoresView.swift:44`
- Modify: `Virgo/views/SongScoresView.swift:51`
- Modify: `Virgo/views/subviews/DifficultyPickerSheet.swift:33`

**Interfaces:**
- Consumes: `.appSurface()` (Task 2). Produces: no new interface.

- [ ] **Step 1: Apply the swap in every file above**

In each file, change the line:
```swift
        .surface(.paper)
```
to:
```swift
        .appSurface()
```
(Same leading indentation as the original. Do not touch any `.surface(.ink)` — those are intentionally fixed. There is exactly one `.surface(.paper)` per file listed.)

- [ ] **Step 2: Verify no `.surface(.paper)` remain and build**

```bash
grep -rn "\.surface(\.paper)" Virgo/ || echo "none remain (expected)"
swiftlint lint --quiet
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -derivedDataPath ./DerivedData CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```
Expected: grep prints "none remain"; SwiftLint no new violations; BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Virgo/views
git commit -m "feat(theme): page screens follow global appearance via appSurface()"
# (trailers)
```

---

### Task 4: Metronome follows the mode (re-theme off raw `Palette`)

**Files:**
- Modify: `Virgo/views/MetronomeView.swift`
- Modify: `Virgo/components/MetronomeSettingsComponent.swift`
- Modify: `Virgo/components/MetronomeComponent.swift` (currently unused on any live screen — re-themed for consistency so the metronome stack is fully migrated)
- Modify: `Virgo/views/ContentView.swift` (the inactive-Metronome-tab placeholder, ~lines 194–201)

**Interfaces:**
- Consumes: `.appSurface()` (Task 2), `@Environment(\.theme)`, the raw→theme mapping table. Produces: no new interface.

**Rule for all four files:** apply the mapping `Palette.stage→theme.background`, `Palette.stageRaised→theme.raised`, `Palette.chalk→theme.primary`, `Palette.chalkMuted→theme.secondary`, `Palette.vermillion→theme.accent`. Any view/struct that gains a `theme.*` reference must declare `@Environment(\.theme) private var theme`. `Palette.vermillion` may remain only where there is no environment (it equals `theme.accent` in both worlds).

- [ ] **Step 1: Re-theme `MetronomeView.swift`**

Replace the whole file body with (adds `@Environment(\.theme)` to both structs, swaps `.surface(.ink)`→`.appSurface()`, maps tokens):
```swift
//
//  MetronomeView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 13/7/2025.
//

import SwiftUI

struct MetronomeView: View {
    @EnvironmentObject private var metronome: MetronomeEngine
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 8) {
                    Text("Metronome")
                        .font(AppType.display)
                        .foregroundColor(theme.primary)

                    Text("Perfect your timing with precision beats")
                        .font(.plexMono(13))
                        .foregroundColor(theme.secondary)
                }
                .padding(.top, 20)

                Spacer()

                // Main metronome settings
                MetronomeSettingsView(metronome: metronome)
                    .padding(.horizontal, 20)

                Spacer()

                // Practice tips section
                VStack(spacing: 16) {
                    Text("Practice Tips")
                        .font(AppType.headline)
                        .foregroundColor(theme.primary)

                    VStack(spacing: 12) {
                        PracticeTipRow(
                            icon: "1.circle.fill",
                            title: "Start Slow",
                            description: "Begin at a comfortable tempo and gradually increase"
                        )

                        PracticeTipRow(
                            icon: "2.circle.fill",
                            title: "Stay Consistent",
                            description: "Focus on maintaining steady timing throughout"
                        )

                        PracticeTipRow(
                            icon: "3.circle.fill",
                            title: "Use Accents",
                            description: "Listen for the emphasized downbeat to stay oriented"
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .appSurface()
    }
}

struct PracticeTipRow: View {
    let icon: String
    let title: String
    let description: String

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(theme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(theme.primary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(theme.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.raised)
        .cornerRadius(Radius.md)
    }
}

#Preview {
    MetronomeView()
        .environmentObject(MetronomeEngine())
        .modelContainer(for: Song.self, inMemory: true)
}
```

- [ ] **Step 2: Re-theme `MetronomeSettingsComponent.swift`**

Make these changes (everything else in the file stays):
1. Add `@Environment(\.theme) private var theme` to `MetronomeSettingsView` (after `@State private var selectedTimeSignature`).
2. Map tokens in `MetronomeSettingsView.body`: every `Palette.chalk`→`theme.primary`, `Palette.chalkMuted`→`theme.secondary`, `Palette.vermillion`→`theme.accent`, and the final `.background(Palette.stageRaised)`→`.background(theme.raised)`. (The Start/Stop button keeps `.background(theme.accent)` for its fill and `.foregroundColor(theme.primary)` for its label.)
3. Replace `MetronomeButtonStyle` with an `@Environment`-reading wrapper (a `ButtonStyle` cannot read `@Environment` directly):
```swift
struct MetronomeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.theme) private var theme

        var body: some View {
            configuration.label
                .font(.caption)
                .foregroundColor(theme.primary)
                .frame(width: 40, height: 30)
                .background(theme.raised)
                .cornerRadius(6)
                .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
        }
    }
}
```
4. The `#Preview` at the bottom may keep `.background(Palette.stage)` (a fixed preview backdrop) — leave it as-is.

- [ ] **Step 3: Re-theme `MetronomeComponent.swift`**

Add `@Environment(\.theme) private var theme` to `MetronomeComponent` (after `let timeSignature`). Map all `Palette.chalk`→`theme.primary`, `Palette.chalkMuted`→`theme.secondary`, `Palette.vermillion`→`theme.accent`, and `.background(Palette.stageRaised)`→`.background(theme.raised)` in its `body`. Leave the `#Preview`'s `.background(Palette.stage)` as a fixed backdrop.

- [ ] **Step 4: Re-theme the Metronome-tab placeholder in `ContentView.swift`**

Replace the inactive-tab placeholder (the `else` branch around lines 194–201):
```swift
                } else {
                    // Placeholder view when tab is not active to avoid metronome updates
                    Palette.stage
                        .overlay(
                            Text("Metronome")
                                .font(AppType.title)
                                .foregroundColor(Palette.chalk)
                        )
                }
```
with a mode-following placeholder (system `.primary` adapts to the forced color scheme; `.appSurface()` paints the themed backdrop):
```swift
                } else {
                    // Placeholder view when tab is not active to avoid metronome updates
                    Text("Metronome")
                        .font(AppType.title)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .appSurface()
                }
```

- [ ] **Step 5: Verify no metronome `Palette.chalk/stage` on live paths and build**

```bash
grep -nE "Palette\.(chalk|stage|stageRaised|chalkMuted)" Virgo/views/MetronomeView.swift Virgo/components/MetronomeSettingsComponent.swift Virgo/components/MetronomeComponent.swift
# Expected: matches only inside #Preview backdrops (Palette.stage), nothing in the live bodies.
swiftlint lint --quiet
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -derivedDataPath ./DerivedData CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```
Expected: grep shows only `#Preview` `Palette.stage` lines; SwiftLint clean; BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Virgo/views/MetronomeView.swift Virgo/components/MetronomeSettingsComponent.swift Virgo/components/MetronomeComponent.swift Virgo/views/ContentView.swift
git commit -m "feat(theme): metronome follows global appearance (re-theme off raw Palette)"
# (trailers)
```

---

### Task 5: Pin gameplay + Session Results to the dark stage

**Files:**
- Modify: `Virgo/views/GameplayView.swift` (~line 144)
- Modify: `Virgo/views/subviews/SessionResultsView.swift:113`

**Interfaces:**
- Consumes: nothing new. Produces: no new interface. Keeps the immersive play flow dark regardless of the app's Light/Dark mode, so its system chrome (status bar, controls) stays dark-appropriate.

- [ ] **Step 1: Pin `GameplayView` to dark**

In `Virgo/views/GameplayView.swift`, the outer `body` ends with:
```swift
        .background(Palette.stage)
        .foregroundColor(Palette.chalk)
        .onDisappear {
```
Insert `.colorScheme(.dark)` between `.foregroundColor(Palette.chalk)` and `.onDisappear`:
```swift
        .background(Palette.stage)
        .foregroundColor(Palette.chalk)
        .colorScheme(.dark)
        .onDisappear {
```

- [ ] **Step 2: Pin `SessionResultsView` to dark**

In `Virgo/views/subviews/SessionResultsView.swift`, the line:
```swift
            .surface(.ink)
```
becomes:
```swift
            .surface(.ink)
            .colorScheme(.dark)
```
(Same indentation; `.colorScheme(.dark)` immediately after `.surface(.ink)`. The sheet gets its own environment, so it is pinned independently of the GameplayView pin.)

- [ ] **Step 3: Build**

```bash
swiftlint lint --quiet
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -derivedDataPath ./DerivedData CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```
Expected: SwiftLint clean; BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Virgo/views/GameplayView.swift Virgo/views/subviews/SessionResultsView.swift
git commit -m "feat(theme): pin gameplay + session results to the dark stage"
# (trailers)
```

---

### Task 6: Wire the app root + Appearance setting (turns the mode on)

**Files:**
- Modify: `Virgo/VirgoApp.swift` (root `preferredColorScheme`)
- Create: `Virgo/views/AppearanceSettingsView.swift`
- Modify: `Virgo/views/SettingsView.swift` (activate the disabled "Appearance" row)

**Interfaces:**
- Consumes: `AppearanceMode` (Task 1), `.appSurface()` (Task 2). Produces: `AppearanceSettingsView`.

- [ ] **Step 1: Apply `preferredColorScheme` at the app root**

In `Virgo/VirgoApp.swift`, add the stored mode to the `VirgoApp` struct (after `@StateObject private var sharedPracticeSettings`):
```swift
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode: AppearanceMode = .system
```
Then apply it in `rootView`:
```swift
    @ViewBuilder
    private var rootView: some View {
        MainMenuView()
            .environmentObject(sharedMetronome)
            .environmentObject(sharedPracticeSettings)
            .preferredColorScheme(appearanceMode.preferredColorScheme)
    }
```
(`@AppStorage` supports `RawRepresentable` String enums natively, so `AppearanceMode` binds directly.)

- [ ] **Step 2: Create `AppearanceSettingsView.swift`**

`Virgo/views/AppearanceSettingsView.swift`:
```swift
//
//  AppearanceSettingsView.swift
//  Virgo
//
//  Lets the user choose System / Light / Dark. Persisted via @AppStorage and
//  applied at the app root through `.preferredColorScheme`.
//

import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode: AppearanceMode = .system
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Appearance")
                            .font(AppType.display)
                            .foregroundColor(theme.primary)
                        Text("Choose Light, Dark, or follow your device")
                            .font(.plexMono(13))
                            .foregroundColor(theme.secondary)
                    }
                    Spacer()
                    Image(systemName: "paintbrush.fill")
                        .font(.title2)
                        .foregroundColor(theme.secondary)
                }
                .padding(.horizontal)
                .padding(.top)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            LedgerRow {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Theme")
                        .font(AppType.headline)
                        .foregroundColor(theme.primary)

                    Picker("Appearance", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .tint(Palette.vermillion)
                    .accessibilityIdentifier("appearanceModePicker")

                    Text("“System” follows your device’s Light/Dark setting.")
                        .font(.hanken(14))
                        .foregroundColor(theme.secondary)
                }
            }

            Spacer()
        }
        .appSurface()
        .navigationTitle("Appearance")
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
```

- [ ] **Step 3: Activate the "Appearance" row in `SettingsView.swift`**

Replace the disabled placeholder (lines 77–81):
```swift
                settingsRowDisabled(
                    icon: "paintbrush.fill",
                    title: "Appearance",
                    subtitle: "Customize app theme and visual preferences"
                )
```
with an active navigation link:
```swift
                NavigationLink(destination: AppearanceSettingsView()) {
                    settingsRow(
                        icon: "paintbrush.fill",
                        title: "Appearance",
                        subtitle: "Light, dark, or follow system"
                    )
                }
                .buttonStyle(PlainButtonStyle())
```

- [ ] **Step 4: Build + re-run the unit suites from Tasks 1–2**

```bash
swiftlint lint --quiet
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -derivedDataPath ./DerivedData CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/AppearanceModeTests -only-testing:VirgoTests/SurfaceWorldColorSchemeTests -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```
Expected: SwiftLint clean; BUILD SUCCEEDED; both suites pass.

- [ ] **Step 5: Commit**

```bash
git add Virgo/VirgoApp.swift Virgo/views/AppearanceSettingsView.swift Virgo/views/SettingsView.swift
git commit -m "feat(theme): wire appearance setting + root preferredColorScheme"
# (trailers)
```

---

### Task 7: Final verification + visual audit

**Files:** none (verification only).

- [ ] **Step 1: Full unit suite (macOS)**

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests -parallel-testing-enabled NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData
```
Expected: TEST SUCCEEDED (look for `✔ Test run with N tests`). If a build step fails with `lipo … Operation not permitted` / a corrupted `VirgoUITests-Runner.app`, remove `./DerivedData/Build/Products/Debug/VirgoUITests-Runner.app` and `./DerivedData/Build/Intermediates.noindex/Virgo.build/Debug/VirgoUITests.build` and re-run (a known stale-artifact issue on this machine).

- [ ] **Step 2: iPad simulator build**

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' -derivedDataPath ./DerivedDataSim CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
rm -rf ./DerivedDataSim
```
Expected: BUILD SUCCEEDED. (Separate derived-data path so it never collides with the macOS one.)

- [ ] **Step 3: Visual audit in both modes (the contrast-bug confirmation)**

Using XcodeBuildMCP (or Xcode): run the app on the iPad Pro 11" (M5) simulator. For each of Light and Dark (set via Settings ▸ Appearance, and/or the simulator's system appearance for "System"):
- Songs tab: confirm the "Downloaded / Server" segmented picker labels and song text are readable (no white-on-light, no dark-on-dark).
- Metronome tab: confirm it matches the page background and all text/controls are readable.
- Spot-check Settings ▸ Appearance picker switches the whole app live.
- Spot-check that gameplay still renders as the dark stage in both app modes.

Capture a screenshot of Songs + Metronome in Light and in Dark and report them. (Color contrast is not practical to assert in XCUITest; this is a manual gate.)

- [ ] **Step 4: No commit** (verification only). If Step 3 surfaces a contrast miss, fix the offending view's color to a `theme.*` role and amend the relevant task's commit or add a follow-up `fix(theme): …` commit.

---

## Notes for the Executor

- The branch is `redesign/engraved-ui` — do not branch off (continues the prior work).
- Tasks 1–2 are pure/testable (TDD). Tasks 3–6 are SwiftUI wiring verified by build; Task 4 is the largest (the metronome re-theme + the `ButtonStyle` env-wrapper). Task 7 is the visual gate that actually confirms the reported white-on-light bug is gone.
- After Task 3 alone, pages already follow the OS appearance (because `.appSurface()` reads the ambient `colorScheme`); Task 6 adds the explicit System/Light/Dark control on top. This is expected and fine.
- Do not re-theme the gameplay notation primitives (`NotationPrimitiveViews`, `GameplaySheetMusicView`, `MusicNotationViews`, etc.) — they stay on raw `Palette.chalk` by design (fixed dark stage).
