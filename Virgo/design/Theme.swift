import SwiftUI

enum SurfaceWorld {
    case paper
    case ink
}

/// The active color world resolved into semantic roles. Injected via
/// `@Environment(\.theme)` so shared components adapt to paper vs. ink.
///
/// World-resolution convention:
/// - Paper-world screens and ALL world-shared components (button styles, etc.)
///   read `@Environment(\.theme)` so they adapt to whichever surface hosts them.
/// - Fixed-world Ink screens (gameplay, session results) reference
///   `Palette.*` directly: their world never flips, and the notation primitives
///   render in tight ForEach/Path loops where avoiding an environment lookup
///   matters for performance. Those screens still apply `.surface(.ink)` at the
///   root so any shared component they host resolves the ink theme correctly.
///   (Metronome now follows global appearance via `.appSurface()`.)
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

private struct AppThemeRootModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.theme, VirgoTheme.resolve(.forColorScheme(colorScheme)))
    }
}

extension View {
    /// Injects the global `VirgoTheme` resolved from the effective color scheme
    /// so that a screen's OWN body-level `@Environment(\.theme)` reads match the
    /// active Light/Dark mode. `.appSurface()` injects the theme only into its
    /// descendants, so a view that both applies `.appSurface()` and reads
    /// `theme` at its own level would otherwise see the ambient default
    /// (`.paper`) and render dark-on-dark in Dark mode. Apply ONCE at the app
    /// root, inside `.preferredColorScheme`. Fixed-world screens (gameplay,
    /// session results) use raw `Palette`, so this never affects them.
    func appThemeRoot() -> some View {
        modifier(AppThemeRootModifier())
    }
}
