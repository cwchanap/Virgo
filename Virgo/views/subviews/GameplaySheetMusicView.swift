//
//  GameplaySheetMusicView.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import SwiftUI

extension GameplayView {
    @ViewBuilder
    func sheetMusicView(geometry: GeometryProxy) -> some View {
        if let viewModel = viewModel {
            let usesNotationLayout = usesNotationLayout(viewModel: viewModel)
            let measurePositions = sheetMeasurePositions(viewModel: viewModel)
            let contentWidth = sheetContentWidth(viewModel: viewModel)
            let contentHeight = sheetContentHeight(viewModel: viewModel)
            let rowCount = sheetRowCount(measurePositions: measurePositions)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        // Use cached static staff lines view - created only once
                        if usesNotationLayout {
                            if let cachedNotationView = viewModel.notationStaffLinesView {
                                cachedNotationView
                            } else {
                                staffLinesView(measurePositions: measurePositions, width: contentWidth)
                            }
                        } else if let staticView = viewModel.staticStaffLinesView {
                            staticView
                        } else {
                            // Fallback: render dynamic staff lines when static view is not available
                            staffLinesView(measurePositions: measurePositions, width: contentWidth)
                        }

                        // Dynamic content
                        ZStack(alignment: .topLeading) {
                            barLinesView(measurePositions: measurePositions, viewModel: viewModel)

                            clefsAndTimeSignaturesView(measurePositions: measurePositions, viewModel: viewModel)

                            drumNotationView(viewModel: viewModel)

                            timeBasedBeatProgressionBars(viewModel: viewModel)
                        }

                        // Invisible per-row anchor column. Each anchor occupies the
                        // exact vertical span of its row in the layout coordinate
                        // system, so ScrollViewReader.scrollTo("row_n", anchor: .top)
                        // resolves to the correct y. Kept off-screen horizontally
                        // (width 1) and outside the visible content area.
                        rowAnchorColumn(rowCount: rowCount)
                    }
                    .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
                }
                .background(Color.gray.opacity(0.1))
                .onChange(of: viewModel.currentRow) { _, newRow in
                    guard viewModel.isPlaying else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo("row_\(newRow)", anchor: .top)
                    }
                }
            }
        } else {
            Color.black
                .overlay(Text("Loading...").foregroundColor(.white))
        }
    }

    /// Renders an invisible column of row anchors stacked vertically using `.frame`
    /// so each anchor has a real, distinct y position. ScrollViewReader uses these
    /// to scroll the active row to the top.
    @ViewBuilder
    func rowAnchorColumn(rowCount: Int) -> some View {
        let firstRowTop = max(0, GameplayLayout.StaffLinePosition.line5.absoluteY(for: 0)
            - GameplayLayout.staffLineSpacing)
        let rowSpan = GameplayLayout.rowHeight + GameplayLayout.rowVerticalSpacing
        VStack(alignment: .leading, spacing: 0) {
            // Pad above the first row so row_0 anchors at the actual top of staff 0.
            Color.clear.frame(width: 1, height: firstRowTop)
            ForEach(0..<max(rowCount, 1), id: \.self) { row in
                Color.clear
                    .frame(width: 1, height: rowSpan)
                    .id("row_\(row)")
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    func sheetRowCount(measurePositions: [GameplayLayout.MeasurePosition]) -> Int {
        (measurePositions.map { $0.row }.max() ?? 0) + 1
    }

    func staffLinesView(
        measurePositions: [GameplayLayout.MeasurePosition],
        width: CGFloat = GameplayLayout.maxRowWidth
    ) -> some View {
        let rows = Set(measurePositions.map { $0.row })

        return ZStack {
            ForEach(Array(rows), id: \.self) { row in
                ZStack {
                    ForEach(0..<GameplayLayout.staffLineCount, id: \.self) { lineIndex in
                        Rectangle()
                            .frame(width: width, height: 1) // Full width to cover clef area
                            .foregroundColor(.gray.opacity(0.5))
                            .position(
                                x: width / 2, // Center in full width
                                y: GameplayLayout.StaffLinePosition(rawValue: lineIndex)?.absoluteY(for: row) ?? 0
                            )
                    }
                }
            }
        }
    }

    func clefsAndTimeSignaturesView(
        measurePositions: [GameplayLayout.MeasurePosition],
        viewModel: GameplayViewModel
    ) -> some View {
        let rows = Set(measurePositions.map { $0.row })

        return ZStack {
            ForEach(Array(rows), id: \.self) { row in
                Group {
                    // Drum Clef - position at center of staff (line 3)
                    DrumClefSymbol()
                        .frame(width: GameplayLayout.clefWidth, height: GameplayLayout.staffHeight)
                        .foregroundColor(.white)
                        .position(
                            x: GameplayLayout.clefX,
                            y: GameplayLayout.StaffLinePosition.line3.absoluteY(for: row)
                        )

                    // Time Signature - position at center of staff (line 3)
                    TimeSignatureSymbol(timeSignature: viewModel.track?.timeSignature ?? TimeSignature.fourFour)
                        .frame(width: GameplayLayout.timeSignatureWidth, height: GameplayLayout.staffHeight)
                        .foregroundColor(.white)
                        .position(
                            x: GameplayLayout.timeSignatureX,
                            y: GameplayLayout.StaffLinePosition.line3.absoluteY(for: row)
                        )
                }
            }
        }
    }

    func barLinesView(measurePositions: [GameplayLayout.MeasurePosition], viewModel: GameplayViewModel) -> some View {
        let notationMeasureBars = viewModel.cachedNotationLayout.measureBars
        let usesNotationLayout = usesNotationLayout(viewModel: viewModel)

        return ZStack {
            if usesNotationLayout {
                ForEach(notationMeasureBars) { measureBar in
                    NotationMeasureBarView(measureBar: measureBar)
                }
            } else {
                // Regular bar lines
                ForEach(measurePositions, id: \.measureIndex) { position in
                    // Use the same Y positioning as staff lines - center of the staff for this row
                    let centerY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: position.row)

                    Rectangle()
                        .frame(width: GameplayLayout.barLineWidth, height: GameplayLayout.staffHeight)
                        .foregroundColor(.white.opacity(0.8))
                        .position(
                            x: position.xOffset,
                            y: centerY
                        )
                }

                // Double bar line at the very end
                if let lastPosition = measurePositions.last {
                    let measureWidth = GameplayLayout.measureWidth(
                        for: viewModel.track?.timeSignature ?? TimeSignature.fourFour
                    )
                    let endX = lastPosition.xOffset + measureWidth
                    let centerY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: lastPosition.row)

                    HStack(spacing: GameplayLayout.doubleBarLineSpacing) {
                        Rectangle()
                            .frame(width: GameplayLayout.doubleBarLineWidths.thin, height: GameplayLayout.staffHeight)
                            .foregroundColor(.white)
                        Rectangle()
                            .frame(width: GameplayLayout.doubleBarLineWidths.thick, height: GameplayLayout.staffHeight)
                            .foregroundColor(.white)
                    }
                    .position(
                        x: endX,
                        y: centerY
                    )
                }
            }
        }
    }

    func drumNotationView(viewModel: GameplayViewModel) -> some View {
        let notationLayout = viewModel.cachedNotationLayout
        let activeNotationNoteHeadIDs = viewModel.activeNotationNoteHeadIDs

        return ZStack {
            ForEach(notationLayout.ledgerLines) { ledgerLine in
                NotationLedgerLineView(ledgerLine: ledgerLine)
            }

            ForEach(notationLayout.beams) { beam in
                let isActive = beam.noteHeadIDs.contains { activeNotationNoteHeadIDs.contains($0) }
                NotationBeamView(beam: beam, isActive: isActive)
            }

            ForEach(notationLayout.flags) { flag in
                NotationFlagView(
                    flag: flag,
                    isActive: activeNotationNoteHeadIDs.contains(flag.noteHeadID)
                )
            }

            ForEach(notationLayout.stems) { stem in
                let isActive = stem.noteHeadIDs.contains { activeNotationNoteHeadIDs.contains($0) }
                NotationStemView(stem: stem, isActive: isActive)
            }

            ForEach(notationLayout.noteHeads) { noteHead in
                NotationNoteHeadView(
                    noteHead: noteHead,
                    isActive: activeNotationNoteHeadIDs.contains(noteHead.id)
                )
            }
        }
    }

    func timeBasedBeatProgressionBars(viewModel: GameplayViewModel) -> some View {
        Group {
            if let position = viewModel.purpleBarPosition {
                Rectangle()
                    .frame(width: GameplayLayout.beatColumnWidth, height: GameplayLayout.staffHeight)
                    .foregroundColor(Color.purple.opacity(GameplayLayout.activeOpacity))
                    .cornerRadius(GameplayLayout.beatColumnCornerRadius)
                    .position(x: position.x, y: position.y)
            }
        }
    }

    func usesNotationLayout(viewModel: GameplayViewModel) -> Bool {
        !viewModel.cachedNotationLayout.noteHeads.isEmpty
    }

    func sheetMeasurePositions(viewModel: GameplayViewModel) -> [GameplayLayout.MeasurePosition] {
        guard usesNotationLayout(viewModel: viewModel) else {
            return viewModel.cachedMeasurePositions
        }

        return measurePositions(from: viewModel.cachedNotationLayout)
    }

    func sheetContentHeight(viewModel: GameplayViewModel) -> CGFloat {
        guard usesNotationLayout(viewModel: viewModel) else {
            return GameplayLayout.totalHeight(for: viewModel.cachedMeasurePositions)
        }

        return viewModel.cachedNotationLayout.totalHeight
    }

    func sheetContentWidth(viewModel: GameplayViewModel) -> CGFloat {
        guard usesNotationLayout(viewModel: viewModel) else {
            return GameplayLayout.maxRowWidth
        }

        return notationContentWidth(for: viewModel.cachedNotationLayout)
    }

    func measurePositions(from notationLayout: NotationLayout) -> [GameplayLayout.MeasurePosition] {
        notationLayout.measures.map { measure in
            GameplayLayout.MeasurePosition(
                row: measure.row,
                xOffset: measure.xOffset,
                measureIndex: measure.measureIndex
            )
        }
    }

    func notationContentWidth(for notationLayout: NotationLayout) -> CGFloat {
        notationLayout.contentWidth
    }
}
