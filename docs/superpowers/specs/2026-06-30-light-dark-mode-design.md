# App-wide Light/Dark Mode — Design

**Date:** 2026-06-30
**Status:** Approved (design); spec under review
**Branch context:** Builds on the `redesign/engraved-ui` (Engraved) design system — `@Environment(\.theme)` (`VirgoTheme` paper/ink worlds), `Palette`, `.surface(_:)`, `AppType`, `Spacing`/`Radius`/`RuleWeight`, `GhostButtonStyle`, `LedgerRow`.

## Goal

Give the app a single, consistent Light/Dark mode driven by one user setting (System / Light / Dark, default System), and eliminate the white-on-light contrast bug. All "page" screens **and the Metronome** follow the global mode; the immersive gameplay play screen (and the post-play Session Results) stay a fixed dark "performance stage".

## Problem being solved

1. **White-on-light text (contrast bug).** The app force-paints fixed paper/ink surfaces per screen but never sets `.preferredColorScheme`. When the OS runs in dark mode, system-styled chrome — the "Downloaded/Server" segmented `Picker` (`SongsTabView.swift:125`), tab bar, default-colored labels/icons — renders in dark-mode (light) colors on top of the app's forced-light surfaces, so text appears white on a light background. (Raw `Palette.chalk` usages, by contrast, are confined to the dark gameplay/metronome contexts and are not the leak — except where Metronome will now flip; see below.)
2. **Metronome inconsistency.** `MetronomeView` is a fixed `.surface(.ink)` dark "stage" while every other page is light, which reads as inconsistent.

## Architecture

The mechanism is **colorScheme-driven**:

- A single source of truth — `@AppStorage("appearanceMode")` holding an `AppearanceMode` — is read **only at the app root**, which applies `.preferredColorScheme(mode.preferredColorScheme)`.
- `.preferredColorScheme` does two things at once: it sets SwiftUI's `@Environment(\.colorScheme)` for the entire view tree, **and** it makes all system chrome (tab bar, segmented pickers, nav bars, status bar) match the chosen scheme.
- Every follow-mode screen applies a new **`.appSurface()`** modifier that reads `@Environment(\.colorScheme)` and applies `.surface(colorScheme == .dark ? .ink : .paper)`. No screen reads `AppearanceMode` directly; they all key off `colorScheme`, so they stay consistent with system controls in all three modes (in "System" mode, `preferredColorScheme` is `nil`, so `colorScheme` reflects the OS and screens follow it).
- The immersive gameplay play view and Session Results keep `.surface(.ink)` (fixed dark) and additionally pin `.colorScheme(.dark)` on their subtree so their local system chrome stays dark-appropriate even when the app is in Light mode.

This is preferred over (a) reading `AppearanceMode` in every screen (duplicated env reads; "System" resolution easy to get wrong; still needs `preferredColorScheme` for chrome) and (b) injecting a root-resolved world via environment (fights the existing `.surface()` pattern; the root cannot see the effective scheme for "System" before `preferredColorScheme` resolves).

## Components

### `AppearanceMode` — new, `Virgo/design/AppearanceMode.swift`
```swift
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
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
- `String`-backed so it works directly with `@AppStorage`. An unrecognized stored value falls back to `.system` (`@AppStorage` returns the default when the stored string doesn't decode to a case).

### `SurfaceWorld.forColorScheme(_:)` + `.appSurface()` — extend `Virgo/design/Theme.swift`
```swift
extension SurfaceWorld {
    /// Maps the effective SwiftUI color scheme to a world. Dark → ink, otherwise paper.
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
    /// mode (via the effective color scheme). Use on screens that should flip
    /// with Light/Dark; fixed-world screens keep `.surface(.ink)`.
    func appSurface() -> some View { modifier(AppSurfaceModifier()) }
}
```
- `SurfaceWorld.forColorScheme(_:)` is the pure, unit-tested decision; `.appSurface()` is the thin SwiftUI wrapper (verified by build, not unit test).

### App root — modify `Virgo/VirgoApp.swift`
- Add `@AppStorage(AppearanceMode.storageKey) private var appearanceMode: AppearanceMode = .system`.
- Apply `.preferredColorScheme(appearanceMode.preferredColorScheme)` to `rootView` (so it covers the splash, the tab shell, and all tabs).

### `AppearanceSettingsView` — new, `Virgo/views/AppearanceSettingsView.swift`
- `@AppStorage(AppearanceMode.storageKey) private var appearanceMode: AppearanceMode = .system`.
- A segmented `Picker` over `AppearanceMode.allCases` (System / Light / Dark) bound to `appearanceMode`, styled like the existing sub-tab picker (`SegmentedPickerStyle`, `.tint(Palette.vermillion)`), inside a `LedgerRow`, with a short explanatory caption.
- Wrapped in `.appSurface()` and given `.navigationTitle("Appearance")`.

### `SettingsView` — modify `Virgo/views/SettingsView.swift`
- Replace the disabled "Appearance" `settingsRowDisabled(...)` (lines 77–81) with an active `NavigationLink(destination: AppearanceSettingsView())` wrapping the existing `settingsRow(icon: "paintbrush.fill", title: "Appearance", subtitle: "Light, dark, or follow system")`.

## Scope of file changes

**Swap `.surface(.paper)` → `.appSurface()`** (page screens that should flip):
`MainMenuView`, `SongsTabView`, `LibraryView`, `SettingsView`, `InputSettingsView`, `AudioSettingsView`, `DrumNotationSettingsView`, `ProfileView`, `ChartScoresView`, `SongScoresView`, `views/subviews/DifficultyPickerSheet`.

**Swap `.surface(.ink)` → `.appSurface()`** and re-theme off raw `Palette` (Metronome joins the mode):
`MetronomeView`, `components/MetronomeComponent`, `components/MetronomeSettingsComponent`, and the Metronome-tab placeholder in `ContentView.swift` (lines ~195–200, `Palette.stage` + `Palette.chalk`).

**Raw `Palette` → theme-role mapping** for the re-themed Metronome surfaces:

| Raw token | Theme role |
|-----------|-----------|
| `Palette.stage` | `theme.background` |
| `Palette.stageRaised` | `theme.raised` |
| `Palette.chalk` | `theme.primary` |
| `Palette.chalkMuted` | `theme.secondary` |
| `Palette.gridline` | `theme.rule` |
| `Palette.vermillion` | `theme.accent` |

Components that gain themed colors must read `@Environment(\.theme) private var theme` if they don't already.

**Stay fixed dark (unchanged surfaces), plus pin `.colorScheme(.dark)` on the subtree:**
the gameplay play view (`GameplayView` / its sheet-music + chrome subviews) and `views/subviews/SessionResultsView`. Their raw `Palette.chalk`/notation colors are intentionally left as-is.

**Root:** `VirgoApp` (`preferredColorScheme`).
**Settings:** `SettingsView` (activate row) + new `AppearanceSettingsView`.

## Data flow

User selects a mode in `AppearanceSettingsView` → `@AppStorage("appearanceMode")` persists it → `VirgoApp.rootView` reads it and applies `.preferredColorScheme` → that drives `@Environment(\.colorScheme)` for the whole tree **and** aligns system chrome → each `.appSurface()` screen resolves its world from `colorScheme`. Gameplay/Session Results ignore the mode and stay ink + `.colorScheme(.dark)`.

## Error handling

- Unknown/corrupt stored `appearanceMode` string → `@AppStorage` returns the `.system` default. No crash, no migration needed (new key; absence = `.system`).
- No new runtime failure surfaces; this is presentation-only.

## Testing

- **Unit (Swift Testing, `VirgoTests`):**
  - `AppearanceModeTests`: `.system.preferredColorScheme == nil`, `.light.preferredColorScheme == .light`, `.dark.preferredColorScheme == .dark`; `AppearanceMode(rawValue: "bogus") == nil` (documents the fallback contract).
  - `SurfaceWorldColorSchemeTests`: `SurfaceWorld.forColorScheme(.dark) == .ink`, `SurfaceWorld.forColorScheme(.light) == .paper`.
- **Build:** macOS + iPad Pro 11" (M5) simulator.
- **Visual (manual):** run the iPad sim in Light and Dark; screenshot Songs (the Downloaded/Server segmented picker) and Metronome in both, confirming no white-on-light/dark-on-dark and that Metronome matches the pages. Color contrast is not practical to assert in XCUITest.
- **Regression:** existing UI tests must stay green; `AppearanceSettingsView` adds a navigable row but does not change existing identifiers. Add an accessibility identifier `appearanceModePicker` for future automation.

## Global constraints (inherited by the plan)

- iPad-only for the iOS family (`TARGETED_DEVICE_FAMILY = 2`); macOS 14+ and iPadOS. No iPhone assumptions.
- Unit tests use **Swift Testing** only (`import Testing`, `#expect`, `@Suite`) in `VirgoTests`; never XCTest there.
- **Never** edit `Virgo.xcodeproj/project.pbxproj`; Xcode 16 synchronized groups pick up new files.
- New UI reads `@Environment(\.theme)` / `.appSurface()` and uses design tokens only — no raw `Color.white/.black/.gray`. World-invariant accent stays vermillion (`theme.accent`).
- Preserve existing accessibility identifiers; add only the new `appearanceModePicker`.
- Build/lint/test are authoritative; ignore stale SourceKit "cannot find type" diagnostics (same-module index artifact on this branch).
- Verification runs sequentially; never share `-derivedDataPath` across concurrent `xcodebuild`. Tests run with `-parallel-testing-enabled NO`. (Local `xcodebuild build`/UI runs may need `CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` due to a known keychain/codesign issue on this machine.)
- Commit trailers on every commit:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_013d9nW77M3PamgkL7GnWCyd
  ```

## Out of scope (YAGNI)

- No custom color/theme editor or palette customization.
- No per-screen appearance overrides.
- No scheduled/automatic sunrise–sunset switching.
- No re-theming of the immersive gameplay play surface or Session Results (they stay fixed dark by decision).
- No change to gameplay, metronome timing, scoring, or server logic — presentation only.
