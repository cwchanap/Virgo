//
//  GameplaySheetMusicView.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import SwiftUI

extension GameplayView {
    func sheetMusicView(geometry: GeometryProxy) -> some View {
        let totalHeight = GameplayLayout.totalHeight(for: cachedMeasurePositions)

        return ScrollView([.horizontal, .vertical], showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                // Use cached static staff lines view - created only once
                if let staticView = staticStaffLinesView {
                    staticView
                }

                // Dynamic content
                ZStack(alignment: .topLeading) {
                    // Bar lines
                    barLinesView(measurePositions: cachedMeasurePositions)

                    // Clefs and time signatures for each row
                    clefsAndTimeSignaturesView(measurePositions: cachedMeasurePositions)

                    // Drum notation
                    drumNotationView(measurePositions: cachedMeasurePositions)

                    // Time-based beat progression bars (purple bars at all quarter note positions)
                    timeBasedBeatProgressionBars(measurePositions: cachedMeasurePositions)
                }
            }
            .frame(width: GameplayLayout.maxRowWidth, height: totalHeight)
        }
        .background(Color.gray.opacity(0.1))
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

    func clefsAndTimeSignaturesView(measurePositions: [GameplayLayout.MeasurePosition]) -> some View {
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
                    TimeSignatureSymbol(timeSignature: track?.timeSignature ?? TimeSignature.fourFour)
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

    func barLinesView(measurePositions: [GameplayLayout.MeasurePosition]) -> some View {
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
                let measureWidth = GameplayLayout.measureWidth(for: track?.timeSignature ?? TimeSignature.fourFour)
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

    func drumNotationView(measurePositions: [GameplayLayout.MeasurePosition]) -> some View {
        return ZStack {
            // Render beams first (behind notes)
            ForEach(cachedBeamGroups, id: \.id) { beamGroup in
                BeamGroupView(
                    beamGroup: beamGroup,
                    measurePositions: measurePositions,
                    timeSignature: track?.timeSignature ?? TimeSignature.fourFour,
                    isActive: false // Keep disabled for performance
                )
            }

            // Then render individual notes
            ForEach(cachedBeatIndices, id: \.self) { index in
                let beat = cachedDrumBeats[index]
                // Find which measure this beat belongs to based on the measure number in the beat
                let measureIndex = MeasureUtils.measureIndex(from: beat.timePosition)

                if let measurePos = measurePositionMap[measureIndex] {
                    // Calculate precise beat position within the measure based on measureOffset
                    let beatOffsetInMeasure = beat.timePosition - Double(measureIndex)
                    let beatPosition = beatOffsetInMeasure * Double(track?.timeSignature.beatsPerMeasure ?? 4)
                    // Use precise beat positioning system
                    let beatX = GameplayLayout.preciseNoteXPosition(measurePosition: measurePos, beatPosition: beatPosition, timeSignature: track?.timeSignature ?? TimeSignature.fourFour)

                    // Use the center of the staff area as the reference point for individual drum positioning
                    let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measurePos.row)

                    // Use cached lookup map for O(1) beam group check
                    let isBeamed = beatToBeamGroupMap[beat.id] != nil

                    // FIXED: Use timer-based values for note highlighting (same as purple bar)
                    // SwiftUI won't update for non-@Published metronome methods, so use our timer values
                    // Use floor to get the current beat index (0,1,2,3 for quarter notes)
                    let displayBeat = Int(floor(currentBeatPosition * Double(track?.timeSignature.beatsPerMeasure ?? 4)))
                    let displayMeasure = currentMeasureIndex

                    // Convert to time position for comparison with beat.timePosition
                    let currentTimePosition = Double(displayMeasure) + (Double(displayBeat) / Double(track?.timeSignature.beatsPerMeasure ?? 4))
                    let timeTolerance = 0.05 // Small tolerance for time-based matching
                    let isCurrentlyActive = isPlaying && abs(beat.timePosition - currentTimePosition) < timeTolerance

                    DrumBeatView(
                        beat: beat,
                        isActive: isCurrentlyActive,
                        row: measurePos.row,
                        isBeamed: isBeamed
                    )
                    .position(
                        x: beatX,
                        y: staffCenterY
                    )
                }
            }
        }
    }

    func timeBasedBeatProgressionBars(measurePositions: [GameplayLayout.MeasurePosition]) -> some View {
        Group {
            if isPlaying, let track = track {
                // Calculate which measure the metronome is currently playing
                // Use timer-based measure calculation but sync beat with metronome
                let displayMeasure = currentMeasureIndex

                // Get measure position from display timing
                let measurePos = measurePositionMap[displayMeasure] ?? measurePositionMap[0]

                if let measurePos = measurePos {
                    // Use timer-based discrete beat positioning for 4 jumps per measure
                    let timerBeatIndex = Int(floor(currentBeatPosition * Double(track.timeSignature.beatsPerMeasure)))
                    let discreteBeatPosition = Double(timerBeatIndex)

                    // Calculate exact X position using metronome beat position
                    let indicatorX = GameplayLayout.preciseNoteXPosition(
                        measurePosition: measurePos,
                        beatPosition: discreteBeatPosition,
                        timeSignature: track.timeSignature
                    )

                    // Position at center of staff
                    let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measurePos.row)

                    Rectangle()
                        .frame(width: GameplayLayout.beatColumnWidth, height: GameplayLayout.staffHeight)
                        .foregroundColor(Color.purple.opacity(GameplayLayout.activeOpacity))
                        .cornerRadius(GameplayLayout.beatColumnCornerRadius)
                        .position(x: indicatorX, y: staffCenterY)
                }
            }
        }
    }
}
