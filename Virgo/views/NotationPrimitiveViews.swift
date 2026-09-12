//
//  NotationPrimitiveViews.swift
//  Virgo
//
//  Created by Codex on 1/5/2026.
//

import SwiftUI
import DrumNotation

// Note: these views previously carried an `isActive` parameter intended for
// beat-boundary highlighting. Highlighting was removed because re-evaluating
// the notation subviews on every beat forced expensive sheet re-layouts during
// playback; the quantized vermillion playhead now provides position feedback
// without churning the layout tree. The parameter has been deleted so the
// rendering contract (always chalk) is explicit.

struct NotationNoteHeadView: View, Equatable {
    let noteHead: RenderedNoteHead
    let style: NotationLayoutStyle

    var body: some View {
        PercussionNoteheadView(
            style: VirgoNotationAdapter.noteheadStyle(for: noteHead.noteType),
            duration: VirgoNotationAdapter.duration(for: noteHead.interval),
            staffSpace: style.staffLineSpacing,
            color: Palette.chalk
        )
        .position(noteHead.position)
        .accessibilityLabel(noteHead.accessibilityLabel)
    }
}

struct NotationRestView: View, Equatable {
    let rest: RenderedRest
    let style: NotationLayoutStyle

    var body: some View {
        if let duration = VirgoNotationAdapter.restDuration(rest.duration) {
            NotationRestGlyphView(
                duration: duration,
                staffSpace: style.staffLineSpacing,
                color: Palette.chalk
            )
            .position(rest.position)
            .accessibilityLabel(rest.accessibilityLabel)
        }
    }
}

struct NotationStopNoteView: View, Equatable {
    let stopNote: RenderedStopNote
    let style: NotationLayoutStyle

    var body: some View {
        let halfSize = style.stopMarkSize / 2
        Path { path in
            path.move(to: CGPoint(x: stopNote.position.x - halfSize, y: stopNote.position.y))
            path.addLine(to: CGPoint(x: stopNote.position.x + halfSize, y: stopNote.position.y))
            path.move(to: CGPoint(x: stopNote.position.x, y: stopNote.position.y - halfSize))
            path.addLine(to: CGPoint(x: stopNote.position.x, y: stopNote.position.y + halfSize))
        }
        .stroke(Palette.chalk, lineWidth: style.stopMarkStrokeWidth)
        .accessibilityLabel(stopNote.accessibilityLabel)
    }
}

struct NotationArticulationView: View, Equatable {
    let articulation: RenderedArticulation
    let style: NotationLayoutStyle

    var body: some View {
        PercussionArticulationView(
            articulation: VirgoNotationAdapter.articulation(for: articulation.kind),
            staffSpace: style.staffLineSpacing,
            color: Palette.chalk
        )
        .position(articulation.position)
        .accessibilityHidden(true)
    }
}

struct NotationStemView: View, Equatable {
    let stem: RenderedStem

    var body: some View {
        Path { path in
            path.move(to: stem.start)
            path.addLine(to: stem.end)
        }
        .stroke(Palette.chalk, lineWidth: GameplayLayout.stemWidth)
    }
}

struct NotationBeamView: View, Equatable {
    let beam: RenderedBeam

    var body: some View {
        Path { path in
            path.move(to: beam.start)
            path.addLine(to: beam.end)
        }
        .stroke(Palette.chalk, lineWidth: beam.thickness)
    }
}

struct NotationLedgerLineView: View, Equatable {
    let ledgerLine: RenderedLedgerLine

    var body: some View {
        Path { path in
            path.move(to: ledgerLine.start)
            path.addLine(to: ledgerLine.end)
        }
        .stroke(Palette.chalk, lineWidth: GameplayLayout.barLineWidth)
    }
}

struct NotationFlagView: View, Equatable {
    let command: FlagPaintCommand

    var body: some View {
        NotationFlagGlyphView(
            duration: command.duration,
            direction: command.direction,
            staffSpace: command.staffSpace,
            color: Palette.chalk
        )
        .position(command.center)
    }
}

struct NotationMeasureBarView: View, Equatable {
    let measureBar: RenderedMeasureBar

    var body: some View {
        let centerY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measureBar.row)

        if measureBar.isFinal {
            // Compute total double-bar width: thin bar + spacing + thick bar.
            let totalWidth = GameplayLayout.doubleBarLineWidths.thin
                + GameplayLayout.doubleBarLineSpacing
                + GameplayLayout.doubleBarLineWidths.thick
            // Position HStack so its trailing edge (thick bar) aligns at measureBar.x.
            HStack(spacing: GameplayLayout.doubleBarLineSpacing) {
                Rectangle()
                    .frame(width: GameplayLayout.doubleBarLineWidths.thin, height: GameplayLayout.staffHeight)
                    .foregroundColor(Palette.chalk)
                Rectangle()
                    .frame(width: GameplayLayout.doubleBarLineWidths.thick, height: GameplayLayout.staffHeight)
                    .foregroundColor(Palette.chalk)
            }
            .position(x: measureBar.x - totalWidth / 2, y: centerY)
        } else {
            Rectangle()
                .frame(width: GameplayLayout.barLineWidth, height: GameplayLayout.staffHeight)
                .foregroundColor(Palette.chalk.opacity(0.8))
                .position(x: measureBar.x, y: centerY)
        }
    }
}

struct NotationRhythmDotView: View, Equatable {
    let dot: RenderedRhythmDot
    let style: NotationLayoutStyle

    var body: some View {
        Circle()
            .fill(Palette.chalk)
            .frame(width: style.rhythmDotRadius * 2, height: style.rhythmDotRadius * 2)
            .position(dot.position)
            .accessibilityLabel(dot.accessibilityLabel)
    }
}

private struct TupletThreeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.14))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.52, y: rect.midY),
            control1: CGPoint(x: rect.maxX, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.midY * 0.8)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.12),
            control1: CGPoint(x: rect.maxX, y: rect.midY),
            control2: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        return path
    }
}

struct NotationTupletView: View, Equatable {
    let tuplet: RenderedTuplet
    let style: NotationLayoutStyle

    var body: some View {
        ZStack {
            if tuplet.isBracketVisible, tuplet.bracketPoints.count == 6 {
                Path { path in
                    path.move(to: tuplet.bracketPoints[0])
                    path.addLine(to: tuplet.bracketPoints[1])
                    path.addLine(to: tuplet.bracketPoints[2])
                    path.move(to: tuplet.bracketPoints[3])
                    path.addLine(to: tuplet.bracketPoints[4])
                    path.addLine(to: tuplet.bracketPoints[5])
                }
                .stroke(Palette.chalk, lineWidth: style.tupletLineWidth)
            }

            TupletThreeShape()
                .stroke(
                    Palette.chalk,
                    style: StrokeStyle(lineWidth: style.tupletLineWidth, lineCap: .round, lineJoin: .round)
                )
                .frame(width: style.tupletLabelSize.width, height: style.tupletLabelSize.height)
                .position(tuplet.labelPosition)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tuplet.accessibilityLabel)
    }
}

struct NotationFeelMarkView: View, Equatable {
    let feelMark: RenderedFeelMark
    let style: NotationLayoutStyle

    var body: some View {
        Text(feelMark.feel.rawValue.capitalized)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.chalk)
            .frame(width: feelMark.size.width, height: feelMark.size.height)
            .position(feelMark.position)
            .accessibilityLabel(feelMark.accessibilityLabel)
    }
}

struct NotationRhythmWarningView: View, Equatable {
    let warning: RenderedRhythmWarning
    let style: NotationLayoutStyle

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
