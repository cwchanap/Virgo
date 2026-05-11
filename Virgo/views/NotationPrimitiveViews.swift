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
        .fill(.foreground)
        .frame(width: GameplayLayout.flagWidth, height: GameplayLayout.flagHeight)
        .rotationEffect(stemDirection == .down ? .degrees(180) : .zero)
    }
}

struct NotationNoteHeadView: View {
    let noteHead: RenderedNoteHead
    let isActive: Bool

    var body: some View {
        Text(noteHead.drumType.symbol)
            .font(.system(size: GameplayLayout.drumSymbolFontSize, weight: .bold))
            .foregroundColor(isActive ? .yellow : .white)
            .frame(width: GameplayLayout.beatColumnWidth, height: GameplayLayout.drumSymbolFontSize)
            .position(noteHead.position)
    }
}

struct NotationStemView: View {
    let stem: RenderedStem
    let isActive: Bool

    var body: some View {
        Path { path in
            path.move(to: stem.start)
            path.addLine(to: stem.end)
        }
        .stroke(isActive ? Color.yellow : Color.white, lineWidth: GameplayLayout.stemWidth)
    }
}

struct NotationBeamView: View {
    let beam: RenderedBeam
    let isActive: Bool

    var body: some View {
        Path { path in
            path.move(to: beam.start)
            path.addLine(to: beam.end)
        }
        .stroke(isActive ? Color.yellow : Color.white, lineWidth: beam.thickness)
    }
}

struct NotationLedgerLineView: View {
    let ledgerLine: RenderedLedgerLine

    var body: some View {
        Path { path in
            path.move(to: ledgerLine.start)
            path.addLine(to: ledgerLine.end)
        }
        .stroke(Color.white, lineWidth: GameplayLayout.barLineWidth)
    }
}

struct NotationFlagView: View {
    let flag: RenderedFlag
    let isActive: Bool

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
            .foregroundColor(isActive ? .yellow : .white)
            .position(adjustedCenter)
    }
}

struct NotationMeasureBarView: View {
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
                    .foregroundColor(.white)
                Rectangle()
                    .frame(width: GameplayLayout.doubleBarLineWidths.thick, height: GameplayLayout.staffHeight)
                    .foregroundColor(.white)
            }
            .position(x: measureBar.x - totalWidth / 2, y: centerY)
        } else {
            Rectangle()
                .frame(width: GameplayLayout.barLineWidth, height: GameplayLayout.staffHeight)
                .foregroundColor(.white.opacity(0.8))
                .position(x: measureBar.x, y: centerY)
        }
    }
}
