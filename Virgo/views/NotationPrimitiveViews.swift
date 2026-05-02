//
//  NotationPrimitiveViews.swift
//  Virgo
//
//  Created by Codex on 1/5/2026.
//

import SwiftUI

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

    var body: some View {
        FlagView(flagIndex: flag.flagIndex, stemDirection: flag.stemDirection)
            .foregroundColor(isActive ? .yellow : .white)
            .position(flag.origin)
    }
}

struct NotationMeasureBarView: View {
    let measureBar: RenderedMeasureBar

    var body: some View {
        let centerY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measureBar.row)

        if measureBar.isFinal {
            HStack(spacing: GameplayLayout.doubleBarLineSpacing) {
                Rectangle()
                    .frame(width: GameplayLayout.doubleBarLineWidths.thin, height: GameplayLayout.staffHeight)
                    .foregroundColor(.white)
                Rectangle()
                    .frame(width: GameplayLayout.doubleBarLineWidths.thick, height: GameplayLayout.staffHeight)
                    .foregroundColor(.white)
            }
            .position(x: measureBar.x, y: centerY)
        } else {
            Rectangle()
                .frame(width: GameplayLayout.barLineWidth, height: GameplayLayout.staffHeight)
                .foregroundColor(.white.opacity(0.8))
                .position(x: measureBar.x, y: centerY)
        }
    }
}
