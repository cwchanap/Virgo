import SwiftUI

/// The "♩ = N" tempo-mark motif used as a recurring header device.
///
/// Accepts a `Double` so fractional tempos from imported DTX metadata are not
/// truncated. Integer BPM renders without decimals; fractional BPM mirrors the
/// `%.2f` formatting used by the song row layouts.
struct TempoMark: View {
    let bpm: Double
    @Environment(\.theme) private var theme

    private var bpmText: String {
        bpm.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", bpm)
            : String(format: "%.2f", bpm)
    }

    var body: some View {
        Text("♩ = \(bpmText)")
            .font(.plexMono(14))
            .foregroundColor(theme.secondary)
            .accessibilityLabel("Tempo \(bpmText) beats per minute")
    }
}
