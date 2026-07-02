//
//  DifficultyPickerSheet.swift
//  Virgo
//
//  Sheet for picking a difficulty (chart) for a downloaded song in the grid
//  layout. Reuses DifficultyExpansionView. Charts load asynchronously to avoid
//  synchronous SwiftData faulting.
//

import SwiftUI
import SwiftData

struct DifficultyPickerSheet: View {
    let song: Song
    let onChartSelect: (Chart) -> Void
    let onDismiss: () -> Void

    @Environment(\.theme) private var theme
    @State private var charts: [Chart] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            ScrollView {
                DifficultyExpansionView(charts: displayCharts) { chart in
                    onDismiss()
                    onChartSelect(chart)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .appSurface()
        .loadSongRelationships(for: song) { data in
            charts = data.charts
        }
    }

    private var displayCharts: [Chart] {
        // `charts` is populated from `SongRelationshipData.charts`, which the
        // loader already filters through `isModelAvailable` — no re-filter here.
        charts
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(song.title)
                    .font(AppType.title)
                    .foregroundColor(theme.primary)
                    .lineLimit(1)
                Text("Choose difficulty")
                    .font(.plexMono(12))
                    .foregroundColor(theme.secondary)
            }
            Spacer()
            Button("Done", action: onDismiss)
                .buttonStyle(GhostButtonStyle())
                .accessibilityIdentifier("difficultyPickerDoneButton")
        }
    }
}
