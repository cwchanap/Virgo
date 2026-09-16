//
//  GameplayNotationAnnotationViews.swift
//  Virgo
//
//  Created by Codex on 1/5/2026.
//

import SwiftUI
import DrumNotation

/// The app-owned annotation layer painted above `DrumNotationView` (HPA-166
/// Task 7): the localized feel label and per-measure rhythm warnings. Mark
/// positions are already in final sheet coordinates, so the overlay mounts at
/// the same topLeading origin as the package view and applies no translation.
struct GameplayNotationAnnotationOverlay: View, Equatable {
    let annotations: GameplayNotationAnnotations

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(annotations.feelMarks) { mark in
                GameplayFeelMarkView(feelMark: mark)
            }
            ForEach(annotations.rhythmWarnings) { warning in
                GameplayRhythmWarningView(warning: warning)
            }
        }
    }
}

struct GameplayFeelMarkView: View, Equatable {
    let feelMark: GameplayFeelMark

    var body: some View {
        Text(feelMark.feel.rawValue.capitalized)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.chalk)
            .frame(width: feelMark.size.width, height: feelMark.size.height)
            .position(feelMark.position)
            .accessibilityLabel(feelMark.accessibilityLabel)
    }
}

struct GameplayRhythmWarningView: View, Equatable {
    let warning: GameplayRhythmWarning

    var body: some View {
        Text(warning.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.vermillion)
            .lineLimit(1)
            .frame(width: warning.size.width, height: warning.size.height, alignment: .leading)
            .position(warning.position)
            .accessibilityLabel(warning.accessibilityLabel)
    }
}
