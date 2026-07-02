# Engraved Frontend Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Virgo's dark/purple UI with the "Engraved" editorial design system — a two-world (paper / ink-stage) visual language applied across every screen of the native SwiftUI app.

**Architecture:** Build a `Virgo/design/` foundation (color tokens delivered via `@Environment(\.theme)`, runtime-registered custom fonts, spacing, and reusable components), then migrate screens world-by-world (paper screens first, then the ink/stage screens). The project uses Xcode 16 file-system-synchronized groups, so new files under `Virgo/` are auto-included — no `project.pbxproj` edits.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing (`import Testing`), AVFoundation. Targets macOS 14+ and iPadOS (iPad-only iOS family). Custom fonts: Fraunces, Hanken Grotesk, IBM Plex Mono (all OFL).

## Global Constraints

- **Platform:** macOS 14.0+ and iPadOS (iPad-only). Never add iPhone targeting (`TARGETED_DEVICE_FAMILY` stays `2`).
- **Test framework:** Swift Testing only (`import Testing`, `#expect`, `#require`, `@Suite`). Never XCTest in `VirgoTests`. Use `TestContainer` from `TestHelpers.swift` for SwiftData.
- **Accessibility identifiers:** Every existing `accessibilityIdentifier` MUST be preserved verbatim (UI tests depend on them). Never rename or remove one; only add.
- **SwiftLint limits:** line 120 warn / 150 error; function body 50/100; type body 300/600; file 600/1000. Keep new files small.
- **Gameplay performance:** No new per-frame work and no new `@Published`/Combine observation inside `GameplayView`'s subview hierarchy. Styling only; reuse cached layout data.
- **No behavior changes:** Same 5 tabs, same flows, same data model, same audio/input/MIDI logic. Visual only.
- **Color values are intent:** Hex values below are the design target; minor tuning is allowed, but use the named tokens — never reintroduce raw `Color.purple/.black/.white/.gray` in migrated views.

### Standard verification commands (referenced by tasks as "Standard build" / "Standard tests")

**Standard macOS build:**
```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build
```

**Standard iPad-sim build (compile check):**
```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' build
```

**Standard tests (unit):**
```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -configuration Debug -only-testing:VirgoTests -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData
```

**Standard lint:**
```bash
swiftlint lint --quiet
```

> Note: one pre-existing flaky SwiftData test (`\Chart.difficulty` detached) is red on `main` regardless of this work. Do not treat it as a regression.

---

## File Structure

**New foundation files (`Virgo/design/`):**
- `Color+Hex.swift` — `Color(hex:)` initializer.
- `Palette.swift` — raw hex tokens (paper + ink worlds).
- `Theme.swift` — `VirgoTheme`, `SurfaceWorld`, `\.theme` environment, `.surface(_:)` modifier.
- `Typography.swift` — `Font.fraunces/hanken/plexMono` helpers + `AppType` semantic styles.
- `FontRegistration.swift` — runtime registration of bundled fonts.
- `Spacing.swift` — `Spacing`, `Radius`, `RuleWeight` constants.

**New component files (`Virgo/components/`):**
- `RuleDivider.swift`, `TempoMark.swift`, `DifficultyPips.swift`, `EngravedButtonStyles.swift`, `LedgerRow.swift`, `DrawnUnderline.swift`.

**New resources:**
- `Virgo/Resources/Fonts/*.ttf` (auto-bundled via synchronized group).

**New tests (`VirgoTests/`):**
- `DesignSystemTests.swift` (hex, theme, pips), `FontRegistrationTests.swift`.

**Modified screens (grouped by world):**
- Paper: `MainMenuView`, `ContentView`, `SongsTabView`, `DownloadedSongsView`, `ExpandableSongRow`, `DifficultyExpansionView`, `ServerSongRow`, `ServerSongsView`, `LibraryView`, `SettingsView`, `AudioSettingsView`, `InputSettingsView`, `DrumNotationSettingsView`, `MappingSections`, `ProfileView`, `ChartScoresView`, `SongScoresView`.
- Ink/stage: `MetronomeView`, `MetronomeComponent`, `MetronomeSettingsComponent`, `GameplayView`, `GameplayHeaderView`, `GameplayControlsView`, `GameplayPlaybackControls`, `GameplaySheetMusicView`, `NotationPrimitiveViews`, `MusicNotationViews`, `SessionResultsView`, `AccuracyCircleView`, `AccuracyBreakdownChart`, `TimingDeviationView`.
- Retired: `DifficultyBadge.swift` (deleted in Task 16 after all call sites migrate to `DifficultyPips`).

---

# PHASE 0 — Foundation

## Task 1: Color tokens + hex initializer

**Files:**
- Create: `Virgo/design/Color+Hex.swift`
- Create: `Virgo/design/Palette.swift`
- Test: `VirgoTests/DesignSystemTests.swift`

**Interfaces:**
- Produces: `Color(hex: UInt32)`; `enum Palette` with static `Color` tokens: `paper, paperRaised, ink, inkMuted, rule, vermillion, stage, stageRaised, chalk, chalkMuted, gridline`.

- [ ] **Step 1: Write the failing test**

```swift
// VirgoTests/DesignSystemTests.swift
import Testing
import SwiftUI
@testable import Virgo

@Suite("Design system")
struct DesignSystemTests {
    @Test("hex initializer maps RGB channels correctly")
    func hexChannels() throws {
        let c = Color(hex: 0xC8341F).cgColor
        let comps = try #require(c?.components)
        #expect(abs(comps[0] - 0xC8/255.0) < 0.001)
        #expect(abs(comps[1] - 0x34/255.0) < 0.001)
        #expect(abs(comps[2] - 0x1F/255.0) < 0.001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run Standard tests (filter `-only-testing:VirgoTests/DesignSystemTests`).
Expected: FAIL — `Color(hex:)` does not exist (compile error).

- [ ] **Step 3: Implement `Color(hex:)`**

```swift
// Virgo/design/Color+Hex.swift
import SwiftUI

extension Color {
    /// Creates an opaque sRGB color from a 24-bit `0xRRGGBB` value.
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }
}
```

- [ ] **Step 4: Implement `Palette`**

```swift
// Virgo/design/Palette.swift
import SwiftUI

/// Raw color tokens for the Engraved design system. Prefer `VirgoTheme`
/// (via `@Environment(\.theme)`) in views; use `Palette` only where a world
/// is fixed (e.g. the vermillion primary button).
enum Palette {
    // Paper world
    static let paper = Color(hex: 0xF4EFE4)
    static let paperRaised = Color(hex: 0xFBF7EE)
    static let ink = Color(hex: 0x1A1714)
    static let inkMuted = Color(hex: 0x6E665A)
    static let rule = Color(hex: 0xD9D0BF)
    static let vermillion = Color(hex: 0xC8341F)

    // Ink / stage world
    static let stage = Color(hex: 0x15120D)
    static let stageRaised = Color(hex: 0x211C15)
    static let chalk = Color(hex: 0xF4EFE4)
    static let chalkMuted = Color(hex: 0x9A9382)
    static let gridline = Color(hex: 0x2A2419)
}
```

- [ ] **Step 5: Run test to verify it passes**

Run Standard tests (filter `DesignSystemTests`). Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Virgo/design/Color+Hex.swift Virgo/design/Palette.swift VirgoTests/DesignSystemTests.swift
git commit -m "feat(design): add color hex initializer and Engraved palette"
```

---

## Task 2: Theme + environment + surface modifier

**Files:**
- Create: `Virgo/design/Theme.swift`
- Test: `VirgoTests/DesignSystemTests.swift` (append)

**Interfaces:**
- Consumes: `Palette` (Task 1).
- Produces: `struct VirgoTheme { background, raised, primary, secondary, rule, accent: Color }` with static `.paper` and `.ink`; `enum SurfaceWorld { case paper, ink }`; `EnvironmentValues.theme`; `View.surface(_ world: SurfaceWorld) -> some View`.

- [ ] **Step 1: Write the failing test**

```swift
// append to VirgoTests/DesignSystemTests.swift, inside the suite
@Test("paper and ink themes differ and share the vermillion accent")
func themeWorlds() {
    #expect(VirgoTheme.paper.background != VirgoTheme.ink.background)
    #expect(VirgoTheme.paper.primary != VirgoTheme.ink.primary)
    #expect(VirgoTheme.paper.accent == VirgoTheme.ink.accent)
    #expect(VirgoTheme.paper.accent == Palette.vermillion)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run Standard tests (filter `DesignSystemTests`). Expected: FAIL — `VirgoTheme` undefined.

- [ ] **Step 3: Implement `Theme.swift`**

```swift
// Virgo/design/Theme.swift
import SwiftUI

enum SurfaceWorld {
    case paper
    case ink
}

/// The active color world resolved into semantic roles. Injected via
/// `@Environment(\.theme)` so shared components adapt to paper vs. ink.
struct VirgoTheme: Equatable {
    let background: Color
    let raised: Color
    let primary: Color
    let secondary: Color
    let rule: Color
    let accent: Color

    static let paper = VirgoTheme(
        background: Palette.paper,
        raised: Palette.paperRaised,
        primary: Palette.ink,
        secondary: Palette.inkMuted,
        rule: Palette.rule,
        accent: Palette.vermillion
    )

    static let ink = VirgoTheme(
        background: Palette.stage,
        raised: Palette.stageRaised,
        primary: Palette.chalk,
        secondary: Palette.chalkMuted,
        rule: Palette.gridline,
        accent: Palette.vermillion
    )

    static func resolve(_ world: SurfaceWorld) -> VirgoTheme {
        world == .paper ? .paper : .ink
    }
}

private struct VirgoThemeKey: EnvironmentKey {
    static let defaultValue = VirgoTheme.paper
}

extension EnvironmentValues {
    var theme: VirgoTheme {
        get { self[VirgoThemeKey.self] }
        set { self[VirgoThemeKey.self] = newValue }
    }
}

extension View {
    /// Declares the color world for a screen: sets the themed background and
    /// injects the matching `VirgoTheme` into the environment.
    func surface(_ world: SurfaceWorld) -> some View {
        let theme = VirgoTheme.resolve(world)
        return self
            .environment(\.theme, theme)
            .background(theme.background.ignoresSafeArea())
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run Standard tests (filter `DesignSystemTests`). Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Virgo/design/Theme.swift VirgoTests/DesignSystemTests.swift
git commit -m "feat(design): add VirgoTheme worlds, environment, and surface modifier"
```

---

## Task 3: Bundle and register custom fonts + typography helpers

**Files:**
- Create: `Virgo/Resources/Fonts/` with the `.ttf` files listed below
- Create: `Virgo/design/FontRegistration.swift`
- Create: `Virgo/design/Typography.swift`
- Modify: `Virgo/VirgoApp.swift` (call registration in `init`)
- Test: `VirgoTests/FontRegistrationTests.swift`

**Interfaces:**
- Produces: `enum AppFonts { static func registerAll() }`; `Font.fraunces(_:weight:)`, `Font.hanken(_:weight:)`, `Font.plexMono(_:weight:)`; `enum AppType` semantic `Font` constants: `wordmark, display, title, headline, body, label, caption, numeric, numericLarge`; `enum AppFontFamily { static let serif, sans, mono: String }`.

- [ ] **Step 1: Obtain font files**

Download these OFL static weights and place them in `Virgo/Resources/Fonts/`:
- Fraunces: `Fraunces-Regular.ttf`, `Fraunces-SemiBold.ttf`, `Fraunces-Black.ttf` (from fonts.google.com/specimen/Fraunces — static instances)
- Hanken Grotesk: `HankenGrotesk-Regular.ttf`, `HankenGrotesk-Medium.ttf`, `HankenGrotesk-SemiBold.ttf`
- IBM Plex Mono: `IBMPlexMono-Regular.ttf`, `IBMPlexMono-Medium.ttf`

The synchronized group auto-adds them to Copy Bundle Resources.

- [ ] **Step 2: Write the failing test**

```swift
// VirgoTests/FontRegistrationTests.swift
import Testing
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import Virgo

@Suite("Font registration")
struct FontRegistrationTests {
    private func fontExists(_ name: String) -> Bool {
        #if canImport(UIKit)
        return UIFont(name: name, size: 12) != nil
        #elseif canImport(AppKit)
        return NSFont(name: name, size: 12) != nil
        #else
        return false
        #endif
    }

    @Test("registering bundled fonts makes the three families resolvable")
    func registersFamilies() {
        AppFonts.registerAll()
        #expect(fontExists("Fraunces"))
        #expect(fontExists("HankenGrotesk-Regular"))
        #expect(fontExists("IBMPlexMono-Regular"))
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run Standard tests (filter `-only-testing:VirgoTests/FontRegistrationTests`).
Expected: FAIL — `AppFonts` undefined.

- [ ] **Step 4: Implement runtime registration**

```swift
// Virgo/design/FontRegistration.swift
import CoreText
import Foundation

/// Registers bundled `.ttf` fonts at runtime so they resolve on both iOS and
/// macOS without relying on Info.plist paths. Idempotent.
enum AppFonts {
    private static var didRegister = false

    static func registerAll() {
        guard !didRegister else { return }
        didRegister = true
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            var error: Unmanaged<CFError>?
            // .none scope = process-wide; ignore "already registered" on re-runs.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }
}
```

- [ ] **Step 5: Implement typography helpers**

```swift
// Virgo/design/Typography.swift
import SwiftUI

enum AppFontFamily {
    static let serif = "Fraunces"
    static let sans = "HankenGrotesk-Regular"
    static let mono = "IBMPlexMono-Regular"
}

extension Font {
    static func fraunces(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppFontFamily.serif, size: size).weight(weight)
    }
    static func hanken(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppFontFamily.sans, size: size).weight(weight)
    }
    static func plexMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppFontFamily.mono, size: size).weight(weight)
    }
}

/// Semantic type styles. Use these at call sites; raw helpers above for one-offs.
enum AppType {
    static let wordmark = Font.fraunces(48, weight: .black)
    static let display = Font.fraunces(34, weight: .semibold)
    static let title = Font.fraunces(26, weight: .semibold)
    static let headline = Font.fraunces(19, weight: .medium)
    static let body = Font.hanken(16)
    static let label = Font.hanken(14, weight: .medium)
    static let caption = Font.hanken(12)
    static let numeric = Font.plexMono(15)
    static let numericLarge = Font.plexMono(64, weight: .medium)
}
```

- [ ] **Step 6: Register at app launch**

In `Virgo/VirgoApp.swift`, add an `init()` (or extend the existing one) that calls registration before the first view renders:

```swift
init() {
    AppFonts.registerAll()
}
```

- [ ] **Step 7: Run test to verify it passes**

Run Standard tests (filter `FontRegistrationTests`). Expected: PASS.
If a family name fails, temporarily print available names to find the exact registered name and update `AppFontFamily`:
```swift
#if canImport(UIKit)
print(UIFont.familyNames.filter { $0.contains("Fraun") || $0.contains("Hanken") || $0.contains("Plex") })
#endif
```

- [ ] **Step 8: Commit**

```bash
git add Virgo/Resources/Fonts Virgo/design/FontRegistration.swift Virgo/design/Typography.swift Virgo/VirgoApp.swift VirgoTests/FontRegistrationTests.swift
git commit -m "feat(design): bundle and register Fraunces/Hanken/Plex Mono fonts"
```

---

## Task 4: Spacing constants + reusable components

**Files:**
- Create: `Virgo/design/Spacing.swift`
- Create: `Virgo/components/RuleDivider.swift`
- Create: `Virgo/components/TempoMark.swift`
- Create: `Virgo/components/DifficultyPips.swift`
- Create: `Virgo/components/EngravedButtonStyles.swift`
- Create: `Virgo/components/LedgerRow.swift`
- Create: `Virgo/components/DrawnUnderline.swift`
- Test: `VirgoTests/DesignSystemTests.swift` (append)

**Interfaces:**
- Consumes: `VirgoTheme`/`\.theme` (Task 2), `Palette` (Task 1), `Difficulty` (existing, `constants/Drum.swift`: `.easy, .medium, .hard, .expert`).
- Produces:
  - `enum Spacing { xs=4, sm=8, md=16, lg=24, xl=40 }`, `enum Radius { sm=6, md=12 }`, `enum RuleWeight { hairline=1 }`
  - `struct RuleDivider: View`
  - `struct TempoMark: View` (`init(bpm: Int)`)
  - `enum DifficultyPipScale { static let total=5; static func filled(for: Difficulty) -> Int }`, `struct DifficultyPips: View` (`init(difficulty: Difficulty, showLabel: Bool = true)`)
  - `struct VermillionButtonStyle: ButtonStyle`, `struct GhostButtonStyle: ButtonStyle`
  - `struct LedgerRow<Content: View>: View`
  - `View.drawnUnderline(active: Bool) -> some View`

- [ ] **Step 1: Write the failing test (pip logic)**

```swift
// append to VirgoTests/DesignSystemTests.swift, inside the suite
@Test("difficulty pip fill scales with difficulty", arguments: [
    (Difficulty.easy, 2), (.medium, 3), (.hard, 4), (.expert, 5)
])
func pipFill(difficulty: Difficulty, expected: Int) {
    #expect(DifficultyPipScale.filled(for: difficulty) == expected)
    #expect(DifficultyPipScale.filled(for: difficulty) <= DifficultyPipScale.total)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run Standard tests (filter `DesignSystemTests`). Expected: FAIL — `DifficultyPipScale` undefined.

- [ ] **Step 3: Implement spacing**

```swift
// Virgo/design/Spacing.swift
import CoreGraphics

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 40
}

enum Radius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 12
}

enum RuleWeight {
    static let hairline: CGFloat = 1
}
```

- [ ] **Step 4: Implement components**

```swift
// Virgo/components/RuleDivider.swift
import SwiftUI

struct RuleDivider: View {
    @Environment(\.theme) private var theme
    var body: some View {
        Rectangle().fill(theme.rule).frame(height: RuleWeight.hairline)
    }
}
```

```swift
// Virgo/components/TempoMark.swift
import SwiftUI

/// The "♩ = N" tempo-mark motif used as a recurring header device.
struct TempoMark: View {
    let bpm: Int
    @Environment(\.theme) private var theme
    var body: some View {
        Text("♩ = \(bpm)")
            .font(.plexMono(14))
            .foregroundColor(theme.secondary)
            .accessibilityLabel("Tempo \(bpm) beats per minute")
    }
}
```

```swift
// Virgo/components/DifficultyPips.swift
import SwiftUI

enum DifficultyPipScale {
    static let total = 5
    static func filled(for difficulty: Difficulty) -> Int {
        switch difficulty {
        case .easy: return 2
        case .medium: return 3
        case .hard: return 4
        case .expert: return 5
        }
    }
}

/// Vermillion pip meter + small-caps label. Replaces the colored DifficultyBadge.
struct DifficultyPips: View {
    let difficulty: Difficulty
    var showLabel: Bool = true
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: 2) {
                ForEach(0..<DifficultyPipScale.total, id: \.self) { index in
                    Circle()
                        .fill(index < DifficultyPipScale.filled(for: difficulty) ? theme.accent : theme.rule)
                        .frame(width: 5, height: 5)
                }
            }
            if showLabel {
                Text(difficulty.rawValue.uppercased())
                    .font(.plexMono(10, weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(theme.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(difficulty.rawValue) difficulty")
    }
}
```

```swift
// Virgo/components/EngravedButtonStyles.swift
import SwiftUI

/// Solid vermillion primary action.
struct VermillionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hanken(16, weight: .semibold))
            .tracking(1)
            .foregroundColor(Palette.paper)
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, 14)
            .background(Palette.vermillion)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Outlined secondary action that adapts to the current world.
struct GhostButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hanken(16, weight: .medium))
            .foregroundColor(theme.primary)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 12)
            .overlay(Rectangle().stroke(theme.primary, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
```

```swift
// Virgo/components/LedgerRow.swift
import SwiftUI

/// A ruled ledger-line row container: content with a hairline rule beneath it.
struct LedgerRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.vertical, 14)
                .padding(.horizontal, Spacing.md)
            RuleDivider()
        }
    }
}
```

```swift
// Virgo/components/DrawnUnderline.swift
import SwiftUI

private struct DrawnUnderline: ViewModifier {
    let active: Bool
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomLeading) {
            theme.accent
                .frame(height: 2)
                .frame(maxWidth: active ? .infinity : 0, alignment: .leading)
                .animation(.easeOut(duration: 0.4), value: active)
        }
    }
}

extension View {
    /// Draws a vermillion underline that animates in when `active` becomes true.
    func drawnUnderline(active: Bool) -> some View {
        modifier(DrawnUnderline(active: active))
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run Standard tests (filter `DesignSystemTests`). Expected: PASS.

- [ ] **Step 6: Run Standard build**

Run Standard macOS build. Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Virgo/design/Spacing.swift Virgo/components/RuleDivider.swift Virgo/components/TempoMark.swift Virgo/components/DifficultyPips.swift Virgo/components/EngravedButtonStyles.swift Virgo/components/LedgerRow.swift Virgo/components/DrawnUnderline.swift VirgoTests/DesignSystemTests.swift
git commit -m "feat(design): add spacing scale and Engraved reusable components"
```

---

# PHASE 1 — Paper world screens

> For every Phase 1/2 task: declare the world once at the screen root with `.surface(.paper)` (or `.ink`), remove the old gradient/`Color.black` backgrounds, read colors from `@Environment(\.theme) private var theme`, and replace fonts with `AppType`/`Font` helpers. Preserve ALL `accessibilityIdentifier`s. Verification for visual tasks = Standard build + Standard iPad-sim build + Standard tests + Standard lint, plus a screenshot check.

## Task 5: Splash / MainMenuView

**Files:**
- Modify: `Virgo/views/MainMenuView.swift`

**Interfaces:**
- Consumes: `.surface(.paper)`, `AppType.wordmark`, `TempoMark`, `VermillionButtonStyle`, `theme`.

- [ ] **Step 1: Replace the gradient background with paper**

Remove the `LinearGradient` (purple/blue/indigo) in `body`. Wrap the root `GeometryReader { _ in ZStack { ... } }` content and apply `.surface(.paper)` to the `ZStack`. Delete the `.ignoresSafeArea()` gradient block.

- [ ] **Step 2: Restyle the wordmark and subtitle**

Replace:
```swift
Text("VIRGO")
    .font(.custom("Helvetica Neue", size: 48))
    .fontWeight(.ultraLight)
    .foregroundColor(.white)
    .tracking(8)
```
with:
```swift
Text("VIRGO")
    .font(AppType.wordmark)
    .foregroundColor(theme.primary)
    .tracking(6)
    .drawnUnderline(active: isAnimating)
```
Keep `.accessibilityIdentifier("logoText")`, `.scaleEffect(logoScale)`, and the existing onAppear animation. Change the music-note `Image(systemName: "music.note")` `foregroundColor` to `theme.accent`. Replace the subtitle line:
```swift
Text("Music App")  // -> keep identifier "subtitleText"
    .font(.plexMono(13))
    .foregroundColor(theme.secondary)
    .tracking(2)
```
Add a `TempoMark(bpm: 120)` above or below the subtitle for the motif.

- [ ] **Step 3: Restyle the START button**

Replace the `NavigationLink`'s manual `RoundedRectangle` background + `.buttonStyle(PressableButtonStyle())` with the shared style:
```swift
NavigationLink(destination: ContentView()) {
    HStack(spacing: Spacing.md) {
        Image(systemName: "play.fill")
        Text("START").tracking(2)
    }
}
.buttonStyle(VermillionButtonStyle())
.accessibilityIdentifier("startButton")
```
Add `@Environment(\.theme) private var theme` to the struct. Update the debug "Clear Database (Debug)" button `foregroundColor` to `theme.accent.opacity(0.8)`; keep it behind `#if DEBUG`.

- [ ] **Step 4: Remove now-unused `PressableButtonStyle`**

Delete the `PressableButtonStyle` struct at the bottom of the file (only used here; replaced by `VermillionButtonStyle`). Confirm no other references (grep already shows only `MainMenuView`).

- [ ] **Step 5: Verify**

Run Standard build, Standard iPad-sim build, Standard tests, Standard lint. Expected: all pass, identifiers `logoText`/`subtitleText`/`startButton` intact.

- [ ] **Step 6: Commit**

```bash
git add Virgo/views/MainMenuView.swift
git commit -m "feat(design): restyle splash to Engraved paper world"
```

---

## Task 6: Tab shell / ContentView

**Files:**
- Modify: `Virgo/views/ContentView.swift`

**Interfaces:**
- Consumes: `Palette.vermillion`, `theme`.

- [ ] **Step 1: Re-tint the TabView**

In `tabShell`, change `.tint(.purple)` to `.tint(Palette.vermillion)`. Keep `.accessibilityIdentifier("appTabShell")` and all `.tag(...)`/`tabItem` blocks unchanged.

- [ ] **Step 2: Apply a paper tab-bar appearance**

Add an `init()` to `ContentView` that configures the tab bar to ivory with vermillion selection (iOS) and is a no-op on macOS:
```swift
init() {
    #if canImport(UIKit)
    let appearance = UITabBarAppearance()
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = UIColor(Palette.paper)
    let selected = UIColor(Palette.vermillion)
    let normal = UIColor(Palette.inkMuted)
    appearance.stackedLayoutAppearance.selected.iconColor = selected
    appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selected]
    appearance.stackedLayoutAppearance.normal.iconColor = normal
    appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normal]
    UITabBar.appearance().standardAppearance = appearance
    UITabBar.appearance().scrollEdgeAppearance = appearance
    #endif
}
```
(`ContentView` has stored `@State`/`@Query` properties with initializers, so an explicit empty-bodied `init()` is safe to add. If the compiler objects to property initialization, keep the `init()` body to only the appearance config — the property wrappers self-initialize.)

- [ ] **Step 3: Restyle the Metronome placeholder**

Replace the inactive-tab placeholder:
```swift
Color.black.overlay(Text("Metronome").foregroundColor(.white))
```
with the stage world (this tab is an ink screen):
```swift
Palette.stage.overlay(Text("Metronome").font(AppType.title).foregroundColor(Palette.chalk))
```
Also update `startupPreparationView` background from `Color.black` to `Palette.stage` (keep `startupPreparationView` identifier and ProgressView).

- [ ] **Step 4: Verify**

Run Standard build, Standard iPad-sim build, Standard tests, Standard lint. Confirm `appTabShell` present and tabs switch.

- [ ] **Step 5: Commit**

```bash
git add Virgo/views/ContentView.swift
git commit -m "feat(design): vermillion paper tab bar and stage placeholders"
```

---

## Task 7: Songs tab — list, search, sub-tabs, rows

**Files:**
- Modify: `Virgo/views/SongsTabView.swift`
- Modify: `Virgo/views/DownloadedSongsView.swift`
- Modify: `Virgo/components/ExpandableSongRow.swift`
- Modify: `Virgo/components/DifficultyExpansionView.swift`

**Interfaces:**
- Consumes: `.surface(.paper)`, `theme`, `AppType`, `TempoMark`, `DifficultyPips`, `LedgerRow`, `RuleDivider`, `Font.plexMono`.

- [ ] **Step 1: SongsTabView background + header**

Replace the `LinearGradient([.black, .purple.opacity(0.3)])` ZStack background with `.surface(.paper)` applied to the root `ZStack`. Add `@Environment(\.theme) private var theme`.
- "Songs" title → `.font(AppType.display).foregroundColor(theme.primary)`.
- "N songs available" → `.font(.plexMono(13)).foregroundColor(theme.secondary)`.
- Refresh button icon `foregroundColor(theme.primary)`.

- [ ] **Step 2: Restyle the search field as an underlined input**

Replace the search `HStack` background/overlay block. Change `Color.white.opacity(0.1)` fill + rounded stroke to: no fill, `theme.primary` text, `theme.secondary` magnifier/clear icons, and a bottom `RuleDivider()` under the field instead of the rounded border. Keep `searchField` and `clearSearchButton` identifiers and the `TextField` binding.

- [ ] **Step 3: Restyle the segmented sub-tab picker**

Keep the `Picker`/`SegmentedPickerStyle`, but set its tint to vermillion via `.tint(Palette.vermillion)` (or, on iOS, `UISegmentedControl.appearance()` config in the view `init`). Labels unchanged.

- [ ] **Step 4: ExpandableSongRow → ledger row**

In `ExpandableSongRow.body`:
- Add `@Environment(\.theme) private var theme`.
- Play/pause button: `foregroundColor(isPlaying ? theme.accent : theme.primary)` (was `.red`/`.purple`).
- Title → `.font(AppType.headline).foregroundColor(theme.primary)`.
- Artist → `.font(.hanken(14)).foregroundColor(theme.secondary)`.
- The metadata `Label(...)` row → `.font(.plexMono(11)).foregroundColor(theme.secondary)`; render BPM as `"\(song.bpm) BPM"` (keep labels). Replace the BPM label icon usage with a `TempoMark(bpm: song.bpm)` if it reads cleaner.
- Save button: `foregroundColor(song.isSaved ? theme.accent : theme.secondary)` (keep `downloadedSongBookmarkButton` id + a11y value).
- Replace `DifficultyBadge(difficulty: difficulty, size: .small)` in the `ForEach` with `DifficultyPips(difficulty: difficulty, showLabel: false)`.
- Chevron + "N charts": `foregroundColor(theme.secondary)`, fonts `.plexMono(11)`.
- Replace the row background `.background(isPlaying ? Color.purple.opacity(0.2) : Color.white.opacity(0.1)).cornerRadius(12)` with: when playing, a thin `theme.accent` leading bar (`.overlay(alignment: .leading) { Rectangle().fill(theme.accent).frame(width: 2) }`); otherwise clear. Wrap the row in `LedgerRow { ... }` so a hairline rule sits beneath each entry.

- [ ] **Step 5: DownloadedSongsView**

Replace any `Color.black`/`.white`/`.gray`/`.purple` with theme tokens. Replace the `DifficultyBadge(...)` at line ~246 with `DifficultyPips(difficulty: difficulty, showLabel: false)`. Keep list/section structure and all identifiers.

- [ ] **Step 6: DifficultyExpansionView**

Replace `DifficultyBadge(difficulty: chart.difficulty, size: .normal)` (line ~74) with `DifficultyPips(difficulty: chart.difficulty)`. Restyle row chrome (backgrounds/fonts) to theme tokens; the per-chart start row uses `theme.primary`/`theme.secondary` and `Font.plexMono` for numbers. Preserve `onChartSelect` and identifiers.

- [ ] **Step 7: Verify**

Run Standard build, Standard iPad-sim build, Standard tests, Standard lint. Confirm `searchField`, `clearSearchButton`, `refreshServerSongsButton`, `downloadedSongBookmarkButton` intact; expansion still opens charts.

- [ ] **Step 8: Commit**

```bash
git add Virgo/views/SongsTabView.swift Virgo/views/DownloadedSongsView.swift Virgo/components/ExpandableSongRow.swift Virgo/components/DifficultyExpansionView.swift
git commit -m "feat(design): Engraved ledger song list with pips and underlined search"
```

---

## Task 8: Server songs — row + list

**Files:**
- Modify: `Virgo/components/ServerSongRow.swift`
- Modify: `Virgo/views/ServerSongsView.swift`

**Interfaces:**
- Consumes: `theme`, `AppType`, `DifficultyPips`, `LedgerRow`, `Font.plexMono`.

- [ ] **Step 1: Restyle ServerSongRow**

Add `@Environment(\.theme) private var theme`. Replace all `Color.black/.white/.gray/.purple/.blue` with theme tokens. Title `AppType.headline`, artist/metadata `theme.secondary`, download/status controls use `theme.accent` for the active action. If difficulty appears, use `DifficultyPips`. Wrap in `LedgerRow`. Preserve every download/state identifier and the download button behavior.

- [ ] **Step 2: Restyle ServerSongsView**

Replace background and any hardcoded colors with theme tokens / `.surface(.paper)` if it owns a background. Keep empty/loading state structure and identifiers.

- [ ] **Step 3: Verify + commit**

Run Standard build, iPad-sim build, tests, lint.
```bash
git add Virgo/components/ServerSongRow.swift Virgo/views/ServerSongsView.swift
git commit -m "feat(design): Engraved server song rows"
```

---

## Task 9: LibraryView

**Files:**
- Modify: `Virgo/views/LibraryView.swift`

**Interfaces:**
- Consumes: `.surface(.paper)`, `theme`, `AppType`, `DifficultyPips`, `LedgerRow`.

- [ ] **Step 1: Background + header**

Apply `.surface(.paper)`; remove hardcoded dark backgrounds. Header title `AppType.display`, counts `.plexMono(13)` + `theme.secondary`.

- [ ] **Step 2: Rows + difficulty**

Replace `DifficultyBadge(...)` (line ~205) with `DifficultyPips(difficulty: difficulty, showLabel: false)`. Convert saved-song rows to `LedgerRow` with theme tokens and `AppType` fonts. Preserve all identifiers and the empty-state.

- [ ] **Step 3: Verify + commit**

Run Standard build, iPad-sim build, tests, lint.
```bash
git add Virgo/views/LibraryView.swift
git commit -m "feat(design): Engraved Library screen"
```

---

## Task 10: Settings screens

**Files:**
- Modify: `Virgo/views/SettingsView.swift`
- Modify: `Virgo/views/AudioSettingsView.swift`
- Modify: `Virgo/views/InputSettingsView.swift`
- Modify: `Virgo/views/DrumNotationSettingsView.swift`
- Modify: `Virgo/views/subviews/MappingSections.swift`

**Interfaces:**
- Consumes: `.surface(.paper)`, `theme`, `AppType`, `RuleDivider`, `Font.plexMono`.

- [ ] **Step 1: SettingsView shell**

Apply `.surface(.paper)`. Section headers → `AppType.headline` + small-caps via `.plexMono` for labels; rows separated by `RuleDivider()` (printed-form look) rather than grouped-card fills. Replace hardcoded colors with theme tokens. Tint toggles/controls with `Palette.vermillion`.

- [ ] **Step 2: AudioSettingsView, InputSettingsView, DrumNotationSettingsView, MappingSections**

For each: `.surface(.paper)` (or inherit), replace all hardcoded `Color.*`, set control tints to vermillion, use `RuleDivider` between rows, numerics in `Font.plexMono`. `DrumNotationSettingsView` is large (~24K) and near the file-size limit — if edits push it over, extract a subview (e.g. a settings-section view) into a new file rather than exceeding limits. Preserve all identifiers and bindings.

- [ ] **Step 3: Verify + commit**

Run Standard build, iPad-sim build, tests, lint (watch the file-size warnings).
```bash
git add Virgo/views/SettingsView.swift Virgo/views/AudioSettingsView.swift Virgo/views/InputSettingsView.swift Virgo/views/DrumNotationSettingsView.swift Virgo/views/subviews/MappingSections.swift
git commit -m "feat(design): Engraved settings screens as printed forms"
```

---

## Task 11: Profile + score screens

**Files:**
- Modify: `Virgo/views/ProfileView.swift`
- Modify: `Virgo/views/ChartScoresView.swift`
- Modify: `Virgo/views/SongScoresView.swift`

**Interfaces:**
- Consumes: `.surface(.paper)`, `theme`, `AppType`, `DifficultyPips`, `RuleDivider`, `Font.plexMono`.

- [ ] **Step 1: ProfileView**

Apply `.surface(.paper)`; header `AppType.display`; stats rendered as a ruled ledger with `Font.plexMono` numerics and `RuleDivider`s. Replace hardcoded colors. Preserve identifiers.

- [ ] **Step 2: Score views**

`ChartScoresView`/`SongScoresView`: replace `DifficultyBadge(difficulty: chart.difficulty, size: .normal)` (SongScoresView line ~37) with `DifficultyPips(difficulty: chart.difficulty)`. Scores/dates in `Font.plexMono`; rows as ledger lines; theme tokens throughout. Preserve identifiers.

- [ ] **Step 3: Verify + commit**

Run Standard build, iPad-sim build, tests, lint.
```bash
git add Virgo/views/ProfileView.swift Virgo/views/ChartScoresView.swift Virgo/views/SongScoresView.swift
git commit -m "feat(design): Engraved profile and score ledgers"
```

---

# PHASE 2 — Ink / Stage screens

## Task 12: Metronome (stage showpiece)

**Files:**
- Modify: `Virgo/views/MetronomeView.swift`
- Modify: `Virgo/components/MetronomeComponent.swift`
- Modify: `Virgo/components/MetronomeSettingsComponent.swift`

**Interfaces:**
- Consumes: `.surface(.ink)`, `theme`, `AppType.numericLarge`, `TempoMark`, `Palette.vermillion`.

- [ ] **Step 1: MetronomeView stage**

Apply `.surface(.ink)`. The BPM value → `AppType.numericLarge` in `theme.primary` (chalk). Add `TempoMark`/time-signature in `Font.plexMono` + `theme.secondary`. Replace hardcoded colors with theme tokens.

- [ ] **Step 2: Beat visualizer**

Restyle the beat/pendulum indicator: inactive beats `theme.secondary.opacity(0.4)`, the downbeat/active beat `theme.accent` (vermillion). Keep the existing beat-driven state source (do not add new `@Published` observation); only swap colors/shape. This is the one expressive motion moment — keep the existing animation timing.

- [ ] **Step 3: MetronomeSettingsComponent**

Replace hardcoded colors with theme tokens; control tints vermillion; numerics `Font.plexMono`. Preserve identifiers and bindings.

- [ ] **Step 4: Verify + commit**

Run Standard build, iPad-sim build, tests, lint.
```bash
git add Virgo/views/MetronomeView.swift Virgo/components/MetronomeComponent.swift Virgo/components/MetronomeSettingsComponent.swift
git commit -m "feat(design): Engraved ink-stage metronome"
```

---

## Task 13: Gameplay chrome (header, controls, HUD)

**Files:**
- Modify: `Virgo/views/GameplayView.swift`
- Modify: `Virgo/components/GameplayHeaderView.swift`
- Modify: `Virgo/components/GameplayControlsView.swift`
- Modify: `Virgo/views/subviews/GameplayPlaybackControls.swift`

**Interfaces:**
- Consumes: `.surface(.ink)`, `theme`, `AppType`, `TempoMark`, `Palette` (stage/vermillion), `Font.plexMono`.

- [ ] **Step 1: GameplayView root**

Set the gameplay background to `Palette.stage` (replace existing dark/black). Keep the `gameplayRoot` accessibility identifier and all existing layout/geometry seeding logic untouched (per CLAUDE.md, row width must be seeded before setup — do NOT reorder this). Add `@Environment(\.theme)` only if needed for chrome; do not introduce new observation of `currentBeat`.

- [ ] **Step 2: GameplayHeaderView**

Replace hardcoded colors with stage tokens: title `AppType.headline` in `theme.primary` (chalk), BPM/time as `TempoMark`/`Font.plexMono` in `theme.secondary`, back/close controls `theme.primary`. Preserve identifiers.

- [ ] **Step 3: GameplayControlsView + GameplayPlaybackControls**

Recolor transport/speed controls: primary action `theme.accent`, inactive `theme.secondary`, surfaces `Palette.stageRaised`. Speed/score readouts in `Font.plexMono`. Preserve identifiers and the speed-change debounce behavior.

- [ ] **Step 4: Verify + commit**

Run Standard build, iPad-sim build, tests, lint. Confirm `gameplayRoot` intact.
```bash
git add Virgo/views/GameplayView.swift Virgo/components/GameplayHeaderView.swift Virgo/components/GameplayControlsView.swift Virgo/views/subviews/GameplayPlaybackControls.swift
git commit -m "feat(design): Engraved gameplay chrome on ink stage"
```

---

## Task 14: Gameplay notation recolor

**Files:**
- Modify: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Modify: `Virgo/views/NotationPrimitiveViews.swift`
- Modify: `Virgo/views/MusicNotationViews.swift`

**Interfaces:**
- Consumes: stage tokens via `Palette` (these primitives are perf-sensitive; prefer direct `Palette.chalk/.gridline/.vermillion` constants over environment lookups inside tight ForEach/Canvas loops).

- [ ] **Step 1: Recolor notation primitives**

In `NotationPrimitiveViews`/`MusicNotationViews`: staff lines/measure gridlines → `Palette.gridline`; note heads/stems/beams → `Palette.chalk`; accent/active or hit-target markers → `Palette.vermillion`. Replace every hardcoded `Color.white/.black/.gray/.purple`. Do NOT change geometry, sizing, or per-frame computation — color values only.

- [ ] **Step 2: GameplaySheetMusicView**

Recolor the scrolling sheet background to `Palette.stage`, playhead to `Palette.vermillion`, lane/grid to `Palette.gridline`. Keep all layout, scrolling, and the cached layout data flow exactly as-is.

- [ ] **Step 3: Verify + commit**

Run Standard build, iPad-sim build, tests, lint. (Manual: launch gameplay, confirm notation is legible chalk-on-stage and scrolls without lag.)
```bash
git add Virgo/views/subviews/GameplaySheetMusicView.swift Virgo/views/NotationPrimitiveViews.swift Virgo/views/MusicNotationViews.swift
git commit -m "feat(design): recolor gameplay notation to chalk-on-stage"
```

---

## Task 15: Session results "report card" + accuracy visuals

**Files:**
- Modify: `Virgo/views/subviews/SessionResultsView.swift`
- Modify: `Virgo/components/AccuracyCircleView.swift`
- Modify: `Virgo/components/AccuracyBreakdownChart.swift`
- Modify: `Virgo/components/TimingDeviationView.swift`

**Interfaces:**
- Consumes: `.surface(.ink)`, `theme`, `AppType`, `RuleDivider`, `DifficultyPips`, `Font.plexMono`, `Palette.vermillion`.

- [ ] **Step 1: SessionResultsView as a printed report card**

Apply `.surface(.ink)`. Layout as a typeset report: title `AppType.title`, the headline score in `AppType.numericLarge`, per-judgment counts (Perfect/Great/Good/Miss) as ruled rows (`RuleDivider`) with `Font.plexMono` numerals. If difficulty shown, use `DifficultyPips`. Judgment accents use `theme.accent` for the best tier. Preserve identifiers and dismiss/continue actions (use `VermillionButtonStyle` for the primary action).

- [ ] **Step 2: Accuracy visuals**

`AccuracyCircleView`: ring track `theme.secondary.opacity(0.3)`, progress `theme.accent`, center percentage `Font.plexMono`. `AccuracyBreakdownChart` + `TimingDeviationView`: bars/markers use `theme.accent` and `theme.secondary`, axis/gridlines `theme.rule`/`Palette.gridline`, labels `Font.plexMono`. Replace all hardcoded colors. Keep data inputs and identifiers.

- [ ] **Step 3: Verify + commit**

Run Standard build, iPad-sim build, tests, lint.
```bash
git add Virgo/views/subviews/SessionResultsView.swift Virgo/components/AccuracyCircleView.swift Virgo/components/AccuracyBreakdownChart.swift Virgo/components/TimingDeviationView.swift
git commit -m "feat(design): Engraved session results report card"
```

---

# PHASE 3 — Cleanup & verification

## Task 16: Retire DifficultyBadge, sweep stragglers, full verification

**Files:**
- Delete: `Virgo/components/DifficultyBadge.swift`
- Modify: any file still referencing hardcoded brand colors

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Confirm no remaining DifficultyBadge usages**

Run:
```bash
grep -rn "DifficultyBadge" Virgo --include="*.swift"
```
Expected: only the comment reference in `components/SongRowComponents.swift` (update/remove it) and the definition file. If any real usage remains, migrate it to `DifficultyPips` first.

- [ ] **Step 2: Delete the badge file and stale comment**

Delete `Virgo/components/DifficultyBadge.swift`. Remove the `// - DifficultyBadge.swift` line in `SongRowComponents.swift`.

- [ ] **Step 3: Sweep remaining hardcoded brand colors**

Run:
```bash
grep -rn "Color\.purple\|Color\.indigo\|Color(\"Helvetica" Virgo --include="*.swift"
grep -rnc "Color\.black\|Color\.white\|Color\.gray" Virgo --include="*.swift" | grep -v ':0'
```
Replace any remaining `Color.purple`/`.indigo` and stray brand colors with theme tokens. (`Color.black/.white` may legitimately remain in shadows/overlays or non-themed contexts — review each; convert UI-surface uses to tokens.)

- [ ] **Step 4: Full verification**

Run, in order (sequentially — never share `-derivedDataPath` concurrently):
1. Standard lint — expect no new violations (especially file/type size).
2. Standard macOS build — BUILD SUCCEEDED.
3. Standard iPad-sim build — BUILD SUCCEEDED.
4. Standard tests — pass (ignore only the known pre-existing flaky SwiftData test).

- [ ] **Step 5: Visual screenshot pass**

Build/run on macOS and an iPad simulator; capture each screen (splash, songs, library, settings, profile, metronome, gameplay, results) and confirm the paper/ink worlds render as intended. (Use XcodeBuildMCP `screenshot` per CLAUDE.md guidance.)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore(design): retire DifficultyBadge and finish Engraved color migration"
```

---

## Self-Review (completed by plan author)

**Spec coverage:** color tokens (T1–2), typography/fonts (T3), spacing+components incl. pips/tempo-mark/ledger/underline/buttons (T4), splash (T5), tab bar (T6), songs/library/server (T7–9), settings/profile/scores (T10–11), metronome (T12), gameplay chrome+notation (T13–14), session results (T15), badge retirement + sweep + cross-platform verification (T16). Paper-first then ink/stage ordering matches the spec rollout. Accessibility-ID preservation, SwiftLint limits, and gameplay-perf constraints are restated in Global Constraints and per-task notes. ✓

**Placeholder scan:** Foundation tasks (T1–4) carry full code. Screen tasks specify exact files, exact before→after edits, tokens, and preserved identifiers — concrete application of the foundation, not vague directives. ✓

**Type consistency:** `VirgoTheme` roles (`background/raised/primary/secondary/rule/accent`), `DifficultyPipScale.filled(for:)`, `AppType.*`, `Font.fraunces/hanken/plexMono`, `Palette.*`, and `.surface(_:)` are used identically everywhere they appear. Difficulty cases match `constants/Drum.swift` (`easy/medium/hard/expert`). ✓
