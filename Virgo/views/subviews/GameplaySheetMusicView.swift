//
//  GameplaySheetMusicView.swift
//  Virgo
//
//  HPA-166 Task 7 — production mounts the package renderer: the installed
//  `EngravedNotation` goes straight into `DrumNotationView`, the app-owned
//  feel/warning annotations layer above it, and the playhead + row anchors
//  read package row geometry. The legacy furniture fallback (staff lines,
//  bars, clef/meter) remains only for charts with no timeline notation; a
//  `.failed` preparation surfaces the practice-unavailable sheet instead.
//

import SwiftUI
import DrumNotation

/// Immutable values needed to render the complete static notation sheet.
///
/// The generation is the identity of this projection. The engraving and
/// presentation are copy-on-write values, so capturing them here is O(1).
struct GameplayStaticNotationInput: Equatable {
    let engraving: EngravedNotation?
    let presentation: GameplayNotationPresentation?
    /// Per-row scroll-anchor tops for the installed engraving — derived
    /// once at install; ignored when `usesEngravedNotation` is false.
    let engravedRowAnchorTops: [CGFloat]
    let legacyMeasurePositions: [GameplayLayout.MeasurePosition]
    let legacyContentHeight: CGFloat
    let timeSignature: TimeSignature
    let hasRenderableContent: Bool
    let generation: UInt64

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.generation == rhs.generation
    }

    /// Engraved notation drives the sheet only when an install is present —
    /// `hasRenderableContent` is the install state resolved once per
    /// generation (cleared installations and `.failed` leave it false).
    var usesEngravedNotation: Bool { hasRenderableContent && engraving != nil }

    var measurePositions: [GameplayLayout.MeasurePosition] {
        guard usesEngravedNotation, let engraving else { return legacyMeasurePositions }
        return engraving.measures.map { measure in
            GameplayLayout.MeasurePosition(
                row: measure.rowIndex,
                xOffset: measure.xOffset,
                measureIndex: measure.index
            )
        }
    }

    /// Sheet row count: the engraving's rows when installed, else the legacy
    /// fallback positions' rows.
    var rowCount: Int {
        if usesEngravedNotation, let engraving { return engraving.rows.count }
        return (legacyMeasurePositions.map { $0.row }.max() ?? 0) + 1
    }

    var contentWidth: CGFloat {
        engraving?.contentWidth ?? GameplayLayout.maxRowWidth
    }

    /// Sheet height: the engraving's declared `contentHeight` already covers
    /// its normalized ink and the last row's anchor extent — no app-side
    /// inset applies.
    var contentHeight: CGFloat {
        engraving?.contentHeight ?? legacyContentHeight
    }

    /// The deepest row anchor's top edge in sheet coordinates — the offset
    /// `scrollTo("row_N", anchor: .top)` targets for the final row.
    var lastRowAnchorTop: CGFloat {
        if usesEngravedNotation { return engravedRowAnchorTops.last ?? 0 }
        return rowCount > 0 ? legacyRowAnchorTop(rowCount - 1) : 0
    }

    /// Scroll-canvas height: the sheet content, extended when needed so the
    /// deepest row anchor can still reach the viewport top. The scroll view
    /// clamps the offset at `canvas − viewport`, so the last band top only
    /// arrives when the canvas runs a full viewport height below it —
    /// `contentHeight` alone ends at the anchor block's bottom.
    func scrollContentHeight(viewportHeight: CGFloat) -> CGFloat {
        max(contentHeight, lastRowAnchorTop + max(0, viewportHeight))
    }

    /// Per-row scroll-anchor tops in sheet coordinates: `row_i`'s top edge.
    /// Engraved sheets read the install-derived array — the primitive scan
    /// runs once per install generation, never per playback invalidation —
    /// while the fallback derives each top from the legacy staff formula
    /// (three staff spaces above line 5, one row pitch per row). Every
    /// anchor sits at-or-above its own row's topmost ink — stems, flags,
    /// and above-staff note positions can paint above a row's band top, and
    /// `scrollTo("row_i", anchor: .top)` clips anything that starts above
    /// the anchor (HPA-583).
    var rowAnchorTops: [CGFloat] {
        if usesEngravedNotation { return engravedRowAnchorTops }
        return (0..<rowCount).map(legacyRowAnchorTop)
    }

    /// Legacy fallback: three staff spaces above line 5 of the first row,
    /// one row pitch per row.
    private func legacyRowAnchorTop(_ row: Int) -> CGFloat {
        let first = max(
            0,
            GameplayLayout.StaffLinePosition.line5.absoluteY(for: 0)
                - 3 * GameplayLayout.staffLineSpacing
        )
        let pitch = GameplayLayout.rowHeight + GameplayLayout.rowVerticalSpacing
        return first + CGFloat(row) * pitch
    }
}

extension GameplayView {
    /// The package renderer's appearance for the fixed-ink gameplay world:
    /// chalk ink everywhere, muted chalk at half opacity on the staff-line
    /// tier — the same two ink tiers the legacy sheet painted.
    static var notationAppearance: DrumNotationAppearance {
        DrumNotationAppearance(
            foreground: Palette.chalk,
            staffLines: Palette.chalkMuted.opacity(0.5)
        )
    }

    @ViewBuilder
    func sheetMusicView(geometry: GeometryProxy) -> some View {
        if let viewModel, let message = viewModel.practiceUnavailableMessage {
            rhythmFatalSheet(message: message)
        } else if let viewModel = viewModel, viewModel.isGameplayPrepared {
            let staticInput = staticNotationInput(viewModel: viewModel)

            // The inner reader reports the ScrollView's own viewport size —
            // `geometry` spans the header and controls too — so the scroll
            // canvas extends exactly one real viewport below the last anchor.
            GeometryReader { sheetProxy in
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            GameplayStaticNotationView(input: staticInput)
                                .equatable()
                            GameplayPlayheadBarView(position: viewModel.purpleBarPosition)
                        }
                        .frame(
                            width: staticInput.contentWidth,
                            height: staticInput.scrollContentHeight(
                                viewportHeight: sheetProxy.size.height
                            ),
                            alignment: .topLeading
                        )
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
            }
        } else {
            Palette.stage
                .overlay(Text("Loading...").foregroundColor(Palette.chalk))
        }
    }

    func staticNotationInput(viewModel: GameplayViewModel) -> GameplayStaticNotationInput {
        GameplayStaticNotationInput(
            engraving: viewModel.cachedEngravedNotation,
            presentation: viewModel.notationPresentation,
            engravedRowAnchorTops: viewModel.cachedNotationRowAnchorTops,
            legacyMeasurePositions: viewModel.cachedMeasurePositions,
            legacyContentHeight: viewModel.cachedLegacyContentHeight,
            timeSignature: viewModel.track?.timeSignature ?? .fourFour,
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
    func staticSheetMusicContent(viewModel: GameplayViewModel) -> some View {
        GameplayStaticNotationLayers(input: staticNotationInput(viewModel: viewModel))
    }

    /// Row-anchor column probe over the installed input's package-derived
    /// anchor geometry.
    func rowAnchorColumn(viewModel: GameplayViewModel) -> some View {
        let input = staticNotationInput(viewModel: viewModel)
        return GameplayRowAnchorColumn(rowAnchorTops: input.rowAnchorTops)
    }

    /// The installed engraving's printed rests — every engraved rest is
    /// printed by construction.
    func printedNotationRests(viewModel: GameplayViewModel) -> [EngravedRest] {
        viewModel.cachedEngravedNotation?.rests ?? []
    }

    func usesEngravedNotation(viewModel: GameplayViewModel) -> Bool {
        staticNotationInput(viewModel: viewModel).usesEngravedNotation
    }

    func sheetMeasurePositions(viewModel: GameplayViewModel) -> [GameplayLayout.MeasurePosition] {
        staticNotationInput(viewModel: viewModel).measurePositions
    }

    func sheetContentHeight(viewModel: GameplayViewModel) -> CGFloat {
        staticNotationInput(viewModel: viewModel).contentHeight
    }

    func sheetContentWidth(viewModel: GameplayViewModel) -> CGFloat {
        staticNotationInput(viewModel: viewModel).contentWidth
    }
}

private struct GameplayStaticNotationView: View, Equatable {
    let input: GameplayStaticNotationInput

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.input.generation == rhs.input.generation
    }

    var body: some View {
        GameplayStaticNotationLayers(input: input)
    }
}

private struct GameplayStaticNotationLayers: View {
    let input: GameplayStaticNotationInput

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let engraving = input.engraving, input.usesEngravedNotation {
                // The package view paints every primitive at the engraving's
                // final normalized sheet coordinates — no app translation,
                // no gameplay clock.
                DrumNotationView(
                    layout: engraving,
                    appearance: GameplayView.notationAppearance,
                    accessibilityLabels: input.presentation?.accessibilityLabels ?? [:]
                )
                // App-owned localized annotations layer above the package
                // sheet at the same topLeading origin.
                GameplayNotationAnnotationOverlay(
                    annotations: input.presentation?.annotations ?? .empty
                )
            } else {
                // No engraving is installed — no timeline snapshot, or the
                // last preparation failed — so the legacy furniture
                // fallback (staff lines, bars, clef/meter) is unchanged.
                StaffLinesBackgroundView(
                    measurePositions: input.legacyMeasurePositions,
                    width: input.contentWidth
                )
                GameplayBarLinesView(
                    measurePositions: input.legacyMeasurePositions,
                    timeSignature: input.timeSignature
                )
                GameplayClefsAndTimeSignaturesView(
                    measurePositions: input.legacyMeasurePositions,
                    timeSignature: input.timeSignature
                )
            }

            GameplayRowAnchorColumn(rowAnchorTops: input.rowAnchorTops)
        }
    }
}

/// Legacy-fallback bar lines: one `barLineWidth` bar per measure start plus
/// the thin+thick double bar closing the last measure — the furniture tier
/// used when no engraving is installed.
private struct GameplayBarLinesView: View {
    let measurePositions: [GameplayLayout.MeasurePosition]
    let timeSignature: TimeSignature

    var body: some View {
        ZStack {
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

/// Legacy-fallback clef + meter furniture, drawn per distinct row.
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

/// Invisible `ScrollViewReader` anchors `row_0…row_N`, each at its row's
/// own top edge. Anchor geometry is caller-supplied: install-derived
/// per-row tops for engraved sheets, the legacy staff formula for the
/// fallback sheet.
private struct GameplayRowAnchorColumn: View {
    /// `row_i`'s top edge in sheet coordinates.
    let rowAnchorTops: [CGFloat]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(width: 1, height: heights.first ?? 0)
            ForEach(0..<max(rowAnchorTops.count, 1), id: \.self) { row in
                Color.clear
                    .frame(width: 1, height: extent(at: row))
                    .id("row_\(row)")
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    /// Stacked frame heights from the pure helper: index 0 is the lead
    /// spacer, index i+1 is row i's extent, so each `row_i` frame's top
    /// edge lands exactly on `rowAnchorTops[i]`.
    private var heights: [CGFloat] {
        GameplayRowAnchorGeometry.anchorColumnHeights(for: rowAnchorTops)
    }

    /// `scrollTo(anchor: .top)` reads only the top edge, so the last row
    /// needs just a token extent.
    private func extent(at row: Int) -> CGFloat {
        heights.indices.contains(row + 1) ? heights[row + 1] : 1
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
