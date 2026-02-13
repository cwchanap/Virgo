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
            let totalHeight = GameplayLayout.totalHeight(for: viewModel.cachedMeasurePositions)

            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Use cached static staff lines view - created only once
                    if let staticView = viewModel.staticStaffLinesView {
                        staticView
                    }

                    // Dynamic content
                    ZStack(alignment: .topLeading) {
                        barLinesView(measurePositions: viewModel.cachedMeasurePositions, viewModel: viewModel)

                        clefsAndTimeSignaturesView(measurePositions: viewModel.cachedMeasurePositions, viewModel: viewModel)

                        drumNotationView(measurePositions: viewModel.cachedMeasurePositions, viewModel: viewModel)

                        timeBasedBeatProgressionBars(measurePositions: viewModel.cachedMeasurePositions, viewModel: viewModel)
                    }
                }
                .frame(width: GameplayLayout.maxRowWidth, height: totalHeight)
            }
            .background(Color.gray.opacity(0.1))
        } else {
            Color.black
                .overlay(Text("Loading...").foregroundColor(.white))
        }
    }

    func staffLinesView(measurePositions: [GameplayLayout.MeasurePosition]) -> some View {
        let rows = Set(measurePositions.map { $0.row })

        return ZStack {
            ForEach(Array(rows), id: \.self) { row in
                ZStack {
                    ForEach(0..<GameplayLayout.staffLineCount, id: \.self) { lineIndex in
                        Rectangle()
                            .frame(width: GameplayLayout.maxRowWidth, height: 1) // Full width to cover clef area
                            .foregroundColor(.gray.opacity(0.5))
                            .position(
                                x: GameplayLayout.maxRowWidth / 2, // Center in full width
                                y: GameplayLayout.StaffLinePosition(rawValue: lineIndex)?.absoluteY(for: row) ?? 0
                            )
                    }
                }
                .id("row_\(row)") // Add scroll anchor for each row
            }
        }
    }

    func clefsAndTimeSignaturesView(measurePositions: [GameplayLayout.MeasurePosition], viewModel: GameplayViewModel) -> some View {
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
        ZStack {
            // Regular bar lines
            ForEach(measurePositions, id: \.measureIndex) { position in
                // Use the same Y positioning as staff lines - center of the staff for this row
                let centerY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: position.row) // Middle staff line

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
                let measureWidth = GameplayLayout.measureWidth(for: viewModel.track?.timeSignature ?? TimeSignature.fourFour)
                let endX = lastPosition.xOffset + measureWidth
                let centerY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: lastPosition.row) // Middle staff line

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

    func drumNotationView(measurePositions: [GameplayLayout.MeasurePosition], viewModel: GameplayViewModel) -> some View {
        return ZStack {
            // Render beams first (behind notes)
            ForEach(viewModel.cachedBeamGroups, id: \.id) { beamGroup in
                BeamGroupView(
                    beamGroup: beamGroup,
                    measurePositions: measurePositions,
                    timeSignature: viewModel.track?.timeSignature ?? TimeSignature.fourFour,
                    isActive: false // Keep disabled for performance
                )
            }

            // Then render individual notes
            ForEach(viewModel.cachedDrumBeats, id: \.id) { beat in

                // PERFORMANCE FIX: Use pre-cached active beat ID instead of calculating for every beat
                let isCurrentlyActive = viewModel.activeBeatId == beat.id

                // PERFORMANCE FIX: Use pre-cached positions to avoid expensive per-frame calculations
                if let cachedPosition = viewModel.cachedBeatPositions[beat.id] {
                    // Use cached lookup map for O(1) beam group check
                    let isBeamed = viewModel.beatToBeamGroupMap[beat.id] != nil
                    let measureIndex = MeasureUtils.measureIndex(from: beat.timePosition)
                    let row = viewModel.measurePositionMap[measureIndex]?.row ?? 0

                    DrumBeatView(
                        beat: beat,
                        isActive: isCurrentlyActive,
                        row: row,
                        isBeamed: isBeamed
                    )
                    .position(
                        x: cachedPosition.x,
                        y: cachedPosition.y
                    )
                }
            }
        }
    }

    func timeBasedBeatProgressionBars(measurePositions: [GameplayLayout.MeasurePosition], viewModel: GameplayViewModel) -> some View {
        Group {
            // PERFORMANCE FIX: Use pre-cached purple bar position instead of expensive calculation
            if let position = viewModel.purpleBarPosition {
                Rectangle()
                    .frame(width: GameplayLayout.beatColumnWidth, height: GameplayLayout.staffHeight)
                    .foregroundColor(Color.purple.opacity(GameplayLayout.activeOpacity))
                    .cornerRadius(GameplayLayout.beatColumnCornerRadius)
                    .position(x: position.x, y: position.y)
            }
        }
    }
}
