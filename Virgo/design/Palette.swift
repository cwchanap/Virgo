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
