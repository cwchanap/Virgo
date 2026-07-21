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
        if let viewModel, viewModel.hasFatalRhythmTiming {
            rhythmFatalSheet(message: viewModel.rhythmFatalMessage)
        } else if let viewModel = viewModel, viewModel.isGameplayPrepared {
            let measurePositions = sheetMeasurePositions(viewModel: viewModel)
            let contentWidth = sheetContentWidth(viewModel: viewModel)
            let contentTopInset = sheetContentTopInset(viewModel: viewModel)
            let contentHeight = sheetContentHeight(viewModel: viewModel, contentTopInset: contentTopInset)
            let rowCount = sheetRowCount(measurePositions: measurePositions)

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        staticSheetMusicContent(
                            measurePositions: measurePositions,
                            contentWidth: contentWidth,
                            contentTopInset: contentTopInset,
                            rowCount: rowCount,
                            viewModel: viewModel
                        )
                        GameplayPlayheadBarView(viewModel: viewModel)
                            .offset(y: contentTopInset)
                    }
                    .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
                }
                .background(Palette.stage)
                .onChange(of: viewModel.currentRow) { _, newRow in
                    guard shouldAutoScrollSheet(
                        viewModel: viewModel,
                        isPlaying: viewModel.isPlaying
                    ) else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo("row_\(newRow)", anchor: .top)
                    }
                }
                .onChange(of: viewModel.isPlaying) { _, nowPlaying in
                    guard shouldAutoScrollSheet(
                        viewModel: viewModel,
                        isPlaying: nowPlaying
                    ) else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo("row_\(viewModel.currentRow)", anchor: .top)
                    }
                }
                .onAppear { viewModel.updateRowWidth(geometry.size.width) }
                .onChange(of: geometry.size.width) { _, newWidth in
                    viewModel.updateRowWidth(newWidth)
                }
            }
        } else {
            Palette.stage
                .overlay(Text("Loading...").foregroundColor(Palette.chalk))
        }
    }

    func rhythmFatalSheet(message: String) -> some View {
        Palette.stage
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(Palette.vermillion)
                    Text("Practice unavailable")
                        .font(.headline)
                        .foregroundColor(Palette.chalk)
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(Palette.chalkMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .padding(24)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("rhythmFatalPracticeMessage")
            }
    }

    func shouldAutoScrollSheet(viewModel: GameplayViewModel, isPlaying: Bool) -> Bool {
        isPlaying && (
            viewModel.cachedNotationLayout.hasPlayableContent
                || !viewModel.cachedNotationLayout.hasRenderableContent
        )
    }

    func staticSheetMusicContent(
        measurePositions: [GameplayLayout.MeasurePosition],
        contentWidth: CGFloat,
        contentTopInset: CGFloat,
        rowCount: Int,
        viewModel: GameplayViewModel
    ) -> some View {
        let usesNotationLayout = usesNotationLayout(viewModel: viewModel)
        return ZStack(alignment: .topLeading) {
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

                ZStack(alignment: .topLeading) {
                    barLinesView(measurePositions: measurePositions, viewModel: viewModel)
                    clefsAndTimeSignaturesView(measurePositions: measurePositions, viewModel: viewModel)
                    drumNotationView(viewModel: viewModel)
                }
            }
            .offset(y: contentTopInset)

            // Invisible per-row anchor column. Each anchor occupies the exact
            // vertical span of its row so ScrollViewReader resolves row anchors.
            // Offset by the same top inset as the notation content so anchors
            // align with their rendered rows when overlays extend above the staff.
            rowAnchorColumn(rowCount: rowCount, viewModel: viewModel)
                .offset(y: contentTopInset)
        }
    }

    /// Renders an invisible column of row anchors stacked vertically using `.frame`
    /// so each anchor has a real, distinct y position. ScrollViewReader uses these
    /// to scroll the active row to the top.
    @ViewBuilder
    func rowAnchorColumn(rowCount: Int, viewModel: GameplayViewModel) -> some View {
        // Compute the padding above line5 for row 0 from the actual note heads so
        // that custom positions (e.g. .aboveLine9) remain fully visible after
        // scrollTo(_, anchor: .top). Falls back to 3 staff-line spacings when no
        // notation layout is available.
        let topPaddingAboveLine5 = spacingAboveLine5(for: viewModel)
        let firstRowTop = max(0, GameplayLayout.StaffLinePosition.line5.absoluteY(for: 0)
            - topPaddingAboveLine5)
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

    /// Returns the number of staff-line spacings above line5 needed to
    /// accommodate the highest note head in the notation layout, with a
    /// small margin. Falls back to 3 spacings when no notation layout is present.
    private func spacingAboveLine5(for viewModel: GameplayViewModel) -> CGFloat {
        let notationLayout = viewModel.cachedNotationLayout
        let defaultSpacings: CGFloat = 3
        guard !notationLayout.noteHeads.isEmpty else { return defaultSpacings * GameplayLayout.staffLineSpacing }

        // line5's y for a given row is the reference point. Find the note head
        // that sits highest (minimum y) relative to its row's line5.
        let minRelativeOffset = notationLayout.noteHeads.compactMap { noteHead -> CGFloat? in
            let line5Y = GameplayLayout.StaffLinePosition.line5.absoluteY(for: noteHead.row)
            return line5Y - noteHead.position.y
        }.max() ?? 0

        // Add 1 extra spacing as margin for ledger lines and note head height.
        let needed = max(CGFloat(defaultSpacings) * GameplayLayout.staffLineSpacing,
                         minRelativeOffset + GameplayLayout.staffLineSpacing)
        return needed
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
                            // chalkMuted.opacity(0.5), not Palette.gridline — gridline (#2A2419) is near-invisible on stage (#15120D).
                            .foregroundColor(Palette.chalkMuted.opacity(0.5))
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
                        .foregroundColor(Palette.chalk)
                        .position(
                            x: GameplayLayout.clefX,
                            y: GameplayLayout.StaffLinePosition.line3.absoluteY(for: row)
                        )

                    // Time Signature - position at center of staff (line 3)
                    TimeSignatureSymbol(timeSignature: viewModel.track?.timeSignature ?? TimeSignature.fourFour)
                        .frame(width: GameplayLayout.timeSignatureWidth, height: GameplayLayout.staffHeight)
                        .foregroundColor(Palette.chalk)
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
                        .equatable()
                }
            } else {
                // Regular bar lines
                ForEach(measurePositions, id: \.measureIndex) { position in
                    // Use the same Y positioning as staff lines - center of the staff for this row
                    let centerY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: position.row)

                    Rectangle()
                        .frame(width: GameplayLayout.barLineWidth, height: GameplayLayout.staffHeight)
                        .foregroundColor(Palette.chalk.opacity(0.8))
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
                            .foregroundColor(Palette.chalk)
                        Rectangle()
                            .frame(width: GameplayLayout.doubleBarLineWidths.thick, height: GameplayLayout.staffHeight)
                            .foregroundColor(Palette.chalk)
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
        let printedRests = printedNotationRests(viewModel: viewModel)
        let style = NotationLayoutStyle.gameplayDefault

        return ZStack {
            ForEach(notationLayout.ledgerLines) { ledgerLine in
                NotationLedgerLineView(ledgerLine: ledgerLine)
                    .equatable()
            }

            ForEach(printedRests) { rest in
                NotationRestView(rest: rest, style: style)
                    .equatable()
            }

            ForEach(notationLayout.beams) { beam in
                NotationBeamView(beam: beam)
                    .equatable()
            }

            ForEach(notationLayout.flags) { flag in
                NotationFlagView(flag: flag)
                    .equatable()
            }

            ForEach(notationLayout.stems) { stem in
                NotationStemView(stem: stem)
                    .equatable()
            }

            ForEach(notationLayout.noteHeads) { noteHead in
                NotationNoteHeadView(noteHead: noteHead, size: notationLayout.noteHeadSize)
                    .equatable()
            }

            ForEach(notationLayout.rhythmDots) { dot in
                NotationRhythmDotView(dot: dot, style: style)
                    .equatable()
            }

            ForEach(notationLayout.articulations) { articulation in
                NotationArticulationView(articulation: articulation, style: style)
                    .equatable()
            }

            ForEach(notationLayout.stopNotes) { stopNote in
                NotationStopNoteView(stopNote: stopNote, style: style)
                    .equatable()
            }

            ForEach(notationLayout.tuplets) { tuplet in
                NotationTupletView(tuplet: tuplet, style: style)
                    .equatable()
            }

            ForEach(notationLayout.feelMarks) { feelMark in
                NotationFeelMarkView(feelMark: feelMark, style: style)
                    .equatable()
            }

            ForEach(notationLayout.rhythmWarnings) { warning in
                NotationRhythmWarningView(warning: warning, style: style)
                    .equatable()
            }
        }
    }

    func printedNotationRests(viewModel: GameplayViewModel) -> [RenderedRest] {
        viewModel.cachedNotationLayout.rests.filter(\.isPrinted)
    }

    func usesNotationLayout(viewModel: GameplayViewModel) -> Bool {
        viewModel.cachedNotationLayout.hasRenderableContent
    }

    func sheetMeasurePositions(viewModel: GameplayViewModel) -> [GameplayLayout.MeasurePosition] {
        guard usesNotationLayout(viewModel: viewModel) else {
            return viewModel.cachedMeasurePositions
        }

        return measurePositions(from: viewModel.cachedNotationLayout)
    }

    func sheetContentHeight(viewModel: GameplayViewModel, contentTopInset: CGFloat? = nil) -> CGFloat {
        guard usesNotationLayout(viewModel: viewModel) else {
            return GameplayLayout.totalHeight(for: viewModel.cachedMeasurePositions)
        }

        let inset = contentTopInset ?? sheetContentTopInset(viewModel: viewModel)
        return viewModel.cachedNotationLayout.totalHeight + inset
    }

    func sheetContentTopInset(viewModel: GameplayViewModel) -> CGFloat {
        guard usesNotationLayout(viewModel: viewModel) else { return 0 }
        return viewModel.cachedNotationLayout.topContentInset(style: .gameplayDefault)
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

private struct GameplayPlayheadBarView: View {
    let viewModel: GameplayViewModel

    var body: some View {
        Group {
            if let position = viewModel.purpleBarPosition {
                Rectangle()
                    .frame(width: GameplayLayout.beatColumnWidth, height: GameplayLayout.staffHeight)
                    .foregroundColor(Palette.vermillion.opacity(GameplayLayout.activeOpacity))
                    .cornerRadius(GameplayLayout.beatColumnCornerRadius)
                    .position(x: position.x, y: position.y)
            }
        }
    }
}
