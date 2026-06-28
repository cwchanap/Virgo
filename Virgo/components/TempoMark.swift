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
