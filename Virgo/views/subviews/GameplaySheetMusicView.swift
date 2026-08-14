//
//  GameplaySheetMusicView.swift
//  Virgo
//

import SwiftUI

/// Immutable values needed to render the complete static notation sheet.
///
/// The generation is the identity of this projection. The layout and legacy
/// positions are copy-on-write values, so capturing them here is O(1); the
/// array scans needed by the sheet tree happen inside `GameplayStaticNotationView`.
struct GameplayStaticNotationInput: Equatable {
    let layout: NotationLayout
    let legacyMeasurePositions: [GameplayLayout.MeasurePosition]
    let legacyContentHeight: CGFloat
    let timeSignature: TimeSignature
    let hasPlayableContent: Bool
    let hasRenderableContent: Bool
    let generation: UInt64

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.generation == rhs.generation
    }

    var usesNotationLayout: Bool { hasRenderableContent }

    var measurePositions: [GameplayLayout.MeasurePosition] {
        guard usesNotationLayout else { return legacyMeasurePositions }
        return layout.measures.map { measure in
            GameplayLayout.MeasurePosition(
                row: measure.row,
                xOffset: measure.xOffset,
                measureIndex: measure.measureIndex
            )
        }
    }

    var rowCount: Int {
        (measurePositions.map { $0.row }.max() ?? 0) + 1
    }

    var contentWidth: CGFloat {
        usesNotationLayout ? layout.contentWidth : GameplayLayout.maxRowWidth
    }

    var contentTopInset: CGFloat {
        usesNotationLayout ? layout.topContentInset(style: .gameplayDefault) : 0
    }

    var contentHeight: CGFloat {
        usesNotationLayout ? layout.totalHeight + contentTopInset : legacyContentHeight
    }
}

extension GameplayView {
    @ViewBuilder
    func sheetMusicView(geometry: GeometryProxy) -> some View {
        if let viewModel, viewModel.hasFatalRhythmTiming {
            rhythmFatalSheet(message: viewModel.rhythmFatalMessage)
        } else if let viewModel = viewModel, viewModel.isGameplayPrepared {
            let staticInput = staticNotationInput(viewModel: viewModel)
            let contentWidth = staticInput.contentWidth
            let contentTopInset = staticInput.contentTopInset
            let contentHeight = staticInput.contentHeight

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        GameplayStaticNotationView(input: staticInput)
                            .equatable()
                        GameplayPlayheadBarView(position: viewModel.purpleBarPosition)
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

    func staticNotationInput(viewModel: GameplayViewModel) -> GameplayStaticNotationInput {
        GameplayStaticNotationInput(
            layout: viewModel.cachedNotationLayout,
            legacyMeasurePositions: viewModel.cachedMeasurePositions,
            legacyContentHeight: viewModel.cachedLegacyContentHeight,
            timeSignature: viewModel.track?.timeSignature ?? .fourFour,
            hasPlayableContent: viewModel.cachedNotationHasPlayableContent,
            hasRenderableContent: viewModel.cachedNotationHasRenderableContent,
            generation: viewModel.notationLayoutGeneration
        )
    }

    func rhythmFatalSheet(message: String, onDismiss: (() -> Void)? = nil) -> some View {
        Palette.stage
            .overlay {
                VStack(spacing: 12) {
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
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("rhythmFatalPracticeMessage")

                    if let onDismiss {
                        Button("Back", action: onDismiss)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("rhythmFatalBackButton")
                            .accessibilityHint("Return to the song library")
                    }
                }
                .padding(24)
                .accessibilityElement(children: .contain)
            }
    }

    func shouldAutoScrollSheet(viewModel: GameplayViewModel, isPlaying: Bool) -> Bool {
        isPlaying && (
            viewModel.cachedNotationHasPlayableContent
                || !viewModel.cachedNotationHasRenderableContent
        )
    }

    // These value-based wrappers remain useful to the raster and layout tests.
    // The mounted gameplay sheet uses `GameplayStaticNotationView` above, so
    // none of these wrappers are evaluated by the playback-observed container.
    func staticSheetMusicContent(
        measurePositions: [GameplayLayout.MeasurePosition],
        contentWidth: CGFloat,
        contentTopInset: CGFloat,
        rowCount: Int,
        viewModel: GameplayViewModel
    ) -> some View {
        GameplayStaticNotationLayers(
            input: staticNotationInput(viewModel: viewModel),
            measurePositions: measurePositions,
            contentWidth: contentWidth,
            contentTopInset: contentTopInset,
            rowCount: rowCount
        )
    }

    /// Compatibility wrapper for direct notation mounting probes.
    func drumNotationView(viewModel: GameplayViewModel) -> some View {
        GameplayDrumNotationView(
            layout: viewModel.cachedNotationLayout
        )
    }

    /// Compatibility wrapper used by the row-anchor rendering probes.
    @ViewBuilder
    func rowAnchorColumn(rowCount: Int, viewModel: GameplayViewModel) -> some View {
        GameplayRowAnchorColumn(layout: viewModel.cachedNotationLayout, rowCount: rowCount)
    }

    func staffLinesView(
        measurePositions: [GameplayLayout.MeasurePosition],
        width: CGFloat = GameplayLayout.maxRowWidth
    ) -> some View {
        StaffLinesBackgroundView(measurePositions: measurePositions, width: width)
    }

    func clefsAndTimeSignaturesView(
        measurePositions: [GameplayLayout.MeasurePosition],
        viewModel: GameplayViewModel
    ) -> some View {
        GameplayClefsAndTimeSignaturesView(
            measurePositions: measurePositions,
            timeSignature: viewModel.track?.timeSignature ?? .fourFour
        )
    }

    func barLinesView(
        measurePositions: [GameplayLayout.MeasurePosition],
        viewModel: GameplayViewModel
    ) -> some View {
        GameplayBarLinesView(
            measurePositions: measurePositions,
            layout: viewModel.cachedNotationLayout,
            timeSignature: viewModel.track?.timeSignature ?? .fourFour,
            hasRenderableContent: viewModel.cachedNotationHasRenderableContent
        )
    }

    func printedNotationRests(viewModel: GameplayViewModel) -> [RenderedRest] {
        viewModel.cachedNotationLayout.rests.filter(\.isPrinted)
    }

    func usesNotationLayout(viewModel: GameplayViewModel) -> Bool {
        viewModel.cachedNotationHasRenderableContent
    }

    func sheetMeasurePositions(viewModel: GameplayViewModel) -> [GameplayLayout.MeasurePosition] {
        staticNotationInput(viewModel: viewModel).measurePositions
    }

    func sheetContentHeight(viewModel: GameplayViewModel, contentTopInset: CGFloat? = nil) -> CGFloat {
        let input = staticNotationInput(viewModel: viewModel)
        guard let contentTopInset else { return input.contentHeight }
        return input.usesNotationLayout ? input.layout.totalHeight + contentTopInset : input.legacyContentHeight
    }

    func sheetContentTopInset(viewModel: GameplayViewModel) -> CGFloat {
        staticNotationInput(viewModel: viewModel).contentTopInset
    }

    func sheetContentWidth(viewModel: GameplayViewModel) -> CGFloat {
        staticNotationInput(viewModel: viewModel).contentWidth
    }

    func sheetRowCount(measurePositions: [GameplayLayout.MeasurePosition]) -> Int {
        (measurePositions.map { $0.row }.max() ?? 0) + 1
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

private struct GameplayStaticNotationView: View, Equatable {
    let input: GameplayStaticNotationInput

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.input.generation == rhs.input.generation
    }

    var body: some View {
        let measurePositions = input.measurePositions
        return GameplayStaticNotationLayers(
            input: input,
            measurePositions: measurePositions,
            contentWidth: input.contentWidth,
            contentTopInset: input.contentTopInset,
            rowCount: input.rowCount
        )
    }
}

private struct GameplayStaticNotationLayers: View {
    let input: GameplayStaticNotationInput
    let measurePositions: [GameplayLayout.MeasurePosition]
    let contentWidth: CGFloat
    let contentTopInset: CGFloat
    let rowCount: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                StaffLinesBackgroundView(measurePositions: measurePositions, width: contentWidth)
                ZStack(alignment: .topLeading) {
                    GameplayBarLinesView(
                        measurePositions: measurePositions,
                        layout: input.layout,
                        timeSignature: input.timeSignature,
                        hasRenderableContent: input.hasRenderableContent
                    )
                    GameplayClefsAndTimeSignaturesView(
                        measurePositions: measurePositions,
                        timeSignature: input.timeSignature
                    )
                    GameplayDrumNotationView(
                        layout: input.layout
                    )
                }
            }
            .offset(y: contentTopInset)

            GameplayRowAnchorColumn(layout: input.layout, rowCount: rowCount)
                .offset(y: contentTopInset)
        }
    }
}

private struct GameplayBarLinesView: View {
    let measurePositions: [GameplayLayout.MeasurePosition]
    let layout: NotationLayout
    let timeSignature: TimeSignature
    let hasRenderableContent: Bool

    var body: some View {
        ZStack {
            if hasRenderableContent {
                ForEach(layout.measureBars) { measureBar in
                    NotationMeasureBarView(measureBar: measureBar)
                        .equatable()
                }
            } else {
                ForEach(measurePositions, id: \.measureIndex) { position in
                    let centerY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: position.row)
                    Rectangle()
                        .frame(width: GameplayLayout.barLineWidth, height: GameplayLayout.staffHeight)
                        .foregroundColor(Palette.chalk.opacity(0.8))
                        .position(x: position.xOffset, y: centerY)
                }

                if let lastPosition = measurePositions.last {
                    let measureWidth = GameplayLayout.measureWidth(for: timeSignature)
                    let endX = lastPosition.xOffset + measureWidth
                    let centerY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: lastPosition.row)
                    HStack(spacing: GameplayLayout.doubleBarLineSpacing) {
                        Rectangle()
                            .frame(
                                width: GameplayLayout.doubleBarLineWidths.thin,
                                height: GameplayLayout.staffHeight
                            )
                            .foregroundColor(Palette.chalk)
                        Rectangle()
                            .frame(
                                width: GameplayLayout.doubleBarLineWidths.thick,
                                height: GameplayLayout.staffHeight
                            )
                            .foregroundColor(Palette.chalk)
                    }
                    .position(x: endX, y: centerY)
                }
            }
        }
    }
}

private struct GameplayClefsAndTimeSignaturesView: View {
    let measurePositions: [GameplayLayout.MeasurePosition]
    let timeSignature: TimeSignature

    var body: some View {
        let rows = Set(measurePositions.map { $0.row })
        return ZStack {
            ForEach(Array(rows), id: \.self) { row in
                Group {
                    DrumClefSymbol()
                        .frame(width: GameplayLayout.clefWidth, height: GameplayLayout.staffHeight)
                        .foregroundColor(Palette.chalk)
                        .position(
                            x: GameplayLayout.clefX,
                            y: GameplayLayout.StaffLinePosition.line3.absoluteY(for: row)
                        )

                    TimeSignatureSymbol(timeSignature: timeSignature)
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
}

private struct GameplayDrumNotationView: View {
    let layout: NotationLayout

    var body: some View {
        let printedRests = layout.rests.filter(\.isPrinted)
        let style = NotationLayoutStyle.gameplayDefault

        return ZStack {
            ForEach(layout.ledgerLines) { ledgerLine in
                NotationLedgerLineView(ledgerLine: ledgerLine)
                    .equatable()
            }

            ForEach(printedRests) { rest in
                NotationRestView(rest: rest, style: style)
                    .equatable()
            }

            ForEach(layout.beams) { beam in
                NotationBeamView(beam: beam)
                    .equatable()
            }

            ForEach(layout.flags) { flag in
                NotationFlagView(flag: flag)
                    .equatable()
            }

            ForEach(layout.stems) { stem in
                NotationStemView(stem: stem)
                    .equatable()
            }

            ForEach(layout.noteHeads) { noteHead in
                NotationNoteHeadView(noteHead: noteHead, size: layout.noteHeadSize)
                    .equatable()
            }

            ForEach(layout.rhythmDots) { dot in
                NotationRhythmDotView(dot: dot, style: style)
                    .equatable()
            }

            ForEach(layout.articulations) { articulation in
                NotationArticulationView(articulation: articulation, style: style)
                    .equatable()
            }

            ForEach(layout.stopNotes) { stopNote in
                NotationStopNoteView(stopNote: stopNote, style: style)
                    .equatable()
            }

            ForEach(layout.tuplets) { tuplet in
                NotationTupletView(tuplet: tuplet, style: style)
                    .equatable()
            }

            ForEach(layout.feelMarks) { feelMark in
                NotationFeelMarkView(feelMark: feelMark, style: style)
                    .equatable()
            }

            ForEach(layout.rhythmWarnings) { warning in
                NotationRhythmWarningView(warning: warning, style: style)
                    .equatable()
            }
        }
    }
}

private struct GameplayRowAnchorColumn: View {
    let layout: NotationLayout
    let rowCount: Int

    var body: some View {
        let defaultSpacings: CGFloat = 3
        let topPaddingAboveLine5: CGFloat
        if layout.noteHeads.isEmpty {
            topPaddingAboveLine5 = defaultSpacings * GameplayLayout.staffLineSpacing
        } else {
            let minRelativeOffset = layout.noteHeads.compactMap { noteHead -> CGFloat? in
                let line5Y = GameplayLayout.StaffLinePosition.line5.absoluteY(for: noteHead.row)
                return line5Y - noteHead.position.y
            }.max() ?? 0
            topPaddingAboveLine5 = max(
                defaultSpacings * GameplayLayout.staffLineSpacing,
                minRelativeOffset + GameplayLayout.staffLineSpacing
            )
        }

        let firstRowTop = max(
            0,
            GameplayLayout.StaffLinePosition.line5.absoluteY(for: 0) - topPaddingAboveLine5
        )
        let rowSpan = GameplayLayout.rowHeight + GameplayLayout.rowVerticalSpacing
        return VStack(alignment: .leading, spacing: 0) {
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
}

private struct GameplayPlayheadBarView: View {
    let position: (x: Double, y: Double)?

    var body: some View {
        Group {
            if let position {
                Rectangle()
                    .frame(width: GameplayLayout.beatColumnWidth, height: GameplayLayout.staffHeight)
                    .foregroundColor(Palette.vermillion.opacity(GameplayLayout.activeOpacity))
                    .cornerRadius(GameplayLayout.beatColumnCornerRadius)
                    .position(x: position.x, y: position.y)
            }
        }
    }
}
