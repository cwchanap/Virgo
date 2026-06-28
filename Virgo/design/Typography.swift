// Virgo/design/Typography.swift
import SwiftUI

/// PostScript (or family) names for the three bundled typefaces.
/// These must match exactly what CoreText resolves after `AppFonts.registerAll()`.
enum AppFontFamily {
    static let serif = "Fraunces-Regular"
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
