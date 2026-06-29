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
/// - Fixed-world Ink screens (gameplay, metronome, session results) reference
///   `Palette.*` directly: their world never flips, and the notation primitives
///   render in tight ForEach/Path loops where avoiding an environment lookup
///   matters for performance. Those screens still apply `.surface(.ink)` at the
///   root so any shared component they host resolves the ink theme correctly.
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
