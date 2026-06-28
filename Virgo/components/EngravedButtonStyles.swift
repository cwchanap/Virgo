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
