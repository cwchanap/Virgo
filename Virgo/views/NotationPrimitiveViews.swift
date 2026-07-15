//
//  NotationPrimitiveViews.swift
//  Virgo
//
//  Created by Codex on 1/5/2026.
//

import SwiftUI

struct FlagView: View {
    let flagIndex: Int
    var stemDirection: StemDirection = .up

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addCurve(to: CGPoint(x: GameplayLayout.flagCurveMidPointX, y: GameplayLayout.flagCurveMidPointY),
                          control1: CGPoint(x: GameplayLayout.flagCurveControl1X, y: GameplayLayout.flagCurveControl1Y),
                          control2: CGPoint(x: GameplayLayout.flagCurveControl2X, y: GameplayLayout.flagCurveControl2Y))
            path.addCurve(to: CGPoint(x: 0, y: GameplayLayout.flagHeight),
                          control1: CGPoint(x: GameplayLayout.flagCurveEndControl1X, y: GameplayLayout.flagCurveEndControl1Y),
                          control2: CGPoint(x: GameplayLayout.flagCurveEndControl2X, y: GameplayLayout.flagCurveEndControl2Y))
            path.closeSubpath()
        }
        .fill(Palette.chalk)
        .frame(width: GameplayLayout.flagWidth, height: GameplayLayout.flagHeight)
        .rotationEffect(stemDirection == .down ? .degrees(180) : .zero)
    }
}

// Note: these views previously carried an `isActive` parameter intended for
// beat-boundary highlighting. Highlighting was removed because re-evaluating
// the notation subviews on every beat forced expensive sheet re-layouts during
// playback; the quantized vermillion playhead now provides position feedback
// without churning the layout tree. The parameter has been deleted so the
// rendering contract (always chalk) is explicit.

private struct DrumNoteheadShape: Shape {
    let glyph: DrumNoteheadGlyph

    func path(in rect: CGRect) -> Path {
        Path(glyph.makePath(in: rect))
    }
}

struct NotationNoteHeadView: View, Equatable {
    let noteHead: RenderedNoteHead
    let size: CGSize

    var body: some View {
        DrumNoteheadShape(glyph: noteHead.glyph)
            .fill(
                Palette.chalk,
                style: FillStyle(eoFill: noteHead.glyph.usesEvenOddFill)
            )
            .frame(
                width: size.width,
                height: size.height
            )
            .position(noteHead.position)
            .accessibilityLabel(noteHead.accessibilityLabel)
    }
}

struct NotationRestView: View, Equatable {
    let rest: RenderedRest
    let style: NotationLayoutStyle

    var body: some View {
        ZStack {
            switch rest.duration {
            case .fullMeasure, .half:
                Rectangle()
                    .fill(Palette.chalk)
                    .frame(
                        width: style.fullMeasureRestWidth,
                        height: style.fullMeasureRestHeight
                    )
                    .position(rest.position)
            case .quarter:
                quarterRestPath
                    .stroke(
                        Palette.chalk,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
            case .eighth, .sixteenth, .thirtySecond, .sixtyFourth:
                hookedRestPath
                    .stroke(
                        Palette.chalk,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
            case .indeterminate:
                EmptyView()
            }
        }
        .accessibilityLabel(rest.accessibilityLabel)
    }

    private var quarterRestPath: Path {
        let halfWidth = style.restSymbolWidth / 2
        let halfHeight = style.restSymbolHeight / 2
        var path = Path()
        path.move(to: CGPoint(x: rest.position.x + halfWidth * 0.45, y: rest.position.y - halfHeight))
        path.addLine(to: CGPoint(x: rest.position.x - halfWidth * 0.35, y: rest.position.y - halfHeight * 0.2))
        path.addLine(to: CGPoint(x: rest.position.x + halfWidth * 0.25, y: rest.position.y + halfHeight * 0.15))
        path.addLine(to: CGPoint(x: rest.position.x - halfWidth * 0.4, y: rest.position.y + halfHeight * 0.55))
        path.addLine(to: CGPoint(x: rest.position.x + halfWidth * 0.35, y: rest.position.y + halfHeight))
        return path
    }

    private var hookedRestPath: Path {
        let halfHeight = style.restSymbolHeight / 2
        let stemX = rest.position.x - style.restSymbolWidth * 0.2
        let stemTop = rest.position.y - halfHeight
        let hookSpacing = style.restSymbolHeight / 5
        var path = Path()
        path.move(to: CGPoint(x: stemX, y: stemTop))
        path.addLine(to: CGPoint(x: stemX, y: rest.position.y + halfHeight))
        for index in 0..<hookCount {
            let hookY = stemTop + CGFloat(index) * hookSpacing
            path.move(to: CGPoint(x: stemX, y: hookY))
            path.addCurve(
                to: CGPoint(x: stemX + style.restSymbolWidth * 0.7, y: hookY + hookSpacing * 0.8),
                control1: CGPoint(x: stemX + style.restSymbolWidth * 0.35, y: hookY),
                control2: CGPoint(x: stemX + style.restSymbolWidth * 0.7, y: hookY + hookSpacing * 0.3)
            )
        }
        return path
    }

    private var hookCount: Int {
        switch rest.duration {
        case .eighth: return 1
        case .sixteenth: return 2
        case .thirtySecond: return 3
        case .sixtyFourth: return 4
        case .fullMeasure, .half, .quarter, .indeterminate: return 0
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
        Circle()
            .stroke(Palette.chalk, lineWidth: style.articulationStrokeWidth)
            .frame(width: style.articulationDiameter, height: style.articulationDiameter)
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
    let flag: RenderedFlag

    /// Computes the corrected center so the flag path origin (0,0) lands on the
    /// stem-tip attachment point stored in `flag.origin`.
    /// `.position()` centres the flagWidth × flagHeight frame, so we shift by
    /// half the frame to align the top-left corner with the stem tip.
    /// For stem-down the view is rotated 180°, which mirrors the attachment to
    /// the opposite corner, so the correction direction flips.
    private var adjustedCenter: CGPoint {
        let halfW = GameplayLayout.flagWidth / 2
        let halfH = GameplayLayout.flagHeight / 2
        switch flag.stemDirection {
        case .up:
            return CGPoint(x: flag.origin.x + halfW, y: flag.origin.y + halfH)
        case .down:
            return CGPoint(x: flag.origin.x - halfW, y: flag.origin.y - halfH)
        }
    }

    var body: some View {
        FlagView(flagIndex: flag.flagIndex, stemDirection: flag.stemDirection)
            .foregroundColor(Palette.chalk)
            .position(adjustedCenter)
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
