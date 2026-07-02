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
