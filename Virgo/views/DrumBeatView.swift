//
//  DrumBeatView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 12/7/2025.
//

import SwiftUI

// MARK: - Supporting Models
struct DrumBeat {
    let id: Int
    let drums: [DrumType]
    let timePosition: Double
    let interval: NoteInterval
}

// MARK: - Stem Connection Info
private struct StemConnectionInfo {
    let hasConnectedStem: Bool
    let stemTop: CGFloat
    let stemBottom: CGFloat
    let mainStemX: CGFloat
}

// MARK: - Stem View Component
private struct StemView: View {
    let stemInfo: StemConnectionInfo
    let beat: DrumBeat
    let isActive: Bool
    let isBeamed: Bool

    var body: some View {
        Group {
            // Connected stem for multiple notes
            if stemInfo.hasConnectedStem && beat.interval.needsStem {
                ConnectedStemView(
                    stemInfo: stemInfo,
                    beat: beat,
                    isActive: isActive,
                    isBeamed: isBeamed
                )
            }

            // Individual stems for each drum
            ForEach(Array(beat.drums.enumerated()), id: \.offset) { _, drum in
                IndividualStemView(
                    drum: drum,
                    stemInfo: stemInfo,
                    beat: beat,
                    isActive: isActive,
                    isBeamed: isBeamed
                )
            }
        }
    }
}

// MARK: - Connected Stem Component
private struct ConnectedStemView: View {
    let stemInfo: StemConnectionInfo
    let beat: DrumBeat
    let isActive: Bool
    let isBeamed: Bool

    var body: some View {
        let stemTop: CGFloat = isBeamed ? GameplayLayout.beamYPosition : stemInfo.stemTop
        let stemBottom = stemInfo.stemBottom
        let stemHeight = stemBottom - stemTop
        let stemCenterY = (stemTop + stemBottom) / 2

        Rectangle()
            .frame(width: GameplayLayout.stemWidth, height: stemHeight)
            .foregroundColor(isActive ? .yellow : .white)
            .offset(x: stemInfo.mainStemX, y: stemCenterY)
    }
}

// MARK: - Individual Stem Component
private struct IndividualStemView: View {
    let drum: DrumType
    let stemInfo: StemConnectionInfo
    let beat: DrumBeat
    let isActive: Bool
    let isBeamed: Bool

    var body: some View {
        let drumYOffset = drum.notePosition.yOffset

        Group {
            if beat.interval.needsStem {
                if !stemInfo.hasConnectedStem {
                    // Individual stem for single note
                    if isBeamed {
                        BeamedStemView(drumYOffset: drumYOffset, isActive: isActive)
                    } else {
                        UnbeamedStemView(drumYOffset: drumYOffset, isActive: isActive)
                    }
                } else {
                    // Short connector to main stem
                    StemConnectorView(drum: drum, beat: beat, isActive: isActive)
                }
            }
        }
    }
}

// MARK: - Beamed Stem Component
private struct BeamedStemView: View {
    let drumYOffset: CGFloat
    let isActive: Bool

    var body: some View {
        let stemHeight = abs(drumYOffset - GameplayLayout.beamYPosition)
        let stemCenterY = (drumYOffset + GameplayLayout.beamYPosition) / 2

        Rectangle()
            .frame(width: GameplayLayout.stemWidth, height: stemHeight)
            .foregroundColor(isActive ? .yellow : .white)
            .offset(x: GameplayLayout.stemXOffset, y: stemCenterY)
    }
}

// MARK: - Unbeamed Stem Component
private struct UnbeamedStemView: View {
    let drumYOffset: CGFloat
    let isActive: Bool

    var body: some View {
        Rectangle()
            .frame(width: GameplayLayout.stemWidth, height: GameplayLayout.stemHeight)
            .foregroundColor(isActive ? .yellow : .white)
            .offset(x: GameplayLayout.stemXOffset, y: drumYOffset - GameplayLayout.stemHeight / 2)
    }
}

// MARK: - Stem Connector Component
private struct StemConnectorView: View {
    let drum: DrumType
    let beat: DrumBeat
    let isActive: Bool

    var body: some View {
        let drumYOffset = drum.notePosition.yOffset
        let noteOffsets = beat.drums.map { $0.notePosition.yOffset }
        let isTopNote = drumYOffset == noteOffsets.min()
        let isBottomNote = drumYOffset == noteOffsets.max()

        if !isTopNote && !isBottomNote {
            Rectangle()
                .frame(width: GameplayLayout.connectorWidth, height: GameplayLayout.connectorHeight)
                .foregroundColor(isActive ? .yellow : .white)
                .offset(x: GameplayLayout.connectorXOffset, y: drumYOffset)
        }
    }
}

// MARK: - Drum Beat View
struct DrumBeatView: View {
    let beat: DrumBeat
    let isActive: Bool
    let row: Int
    let isBeamed: Bool

    // Calculate stem connection info for multiple simultaneous notes
    private var stemInfo: StemConnectionInfo {
        guard beat.interval.needsStem && beat.drums.count > 1 else {
            return StemConnectionInfo(
                hasConnectedStem: false,
                stemTop: 0,
                stemBottom: 0,
                mainStemX: GameplayLayout.stemXOffset
            )
        }

        let noteOffsets = beat.drums.map { $0.notePosition.yOffset }
        let topOffset = noteOffsets.min() ?? 0 // Highest note (smallest y offset)
        let bottomOffset = noteOffsets.max() ?? 0 // Lowest note (largest y offset)

        // Only connect stems if notes span multiple staff positions
        let shouldConnect = abs(topOffset - bottomOffset) > GameplayLayout.staffLineSpacing

        if shouldConnect {
            return StemConnectionInfo(
                hasConnectedStem: true,
                stemTop: topOffset - GameplayLayout.stemExtension,
                stemBottom: bottomOffset, // Don't extend beyond the bottommost note
                mainStemX: GameplayLayout.stemXOffset
            )
        } else {
            return StemConnectionInfo(
                hasConnectedStem: false,
                stemTop: 0,
                stemBottom: 0,
                mainStemX: GameplayLayout.stemXOffset
            )
        }
    }

    var body: some View {
        ZStack {
            // Stem rendering
            StemView(
                stemInfo: stemInfo,
                beat: beat,
                isActive: isActive,
                isBeamed: isBeamed
            )

            // Flags on the main stem (for connected stems, only if not beamed)
            if stemInfo.hasConnectedStem && beat.interval.needsFlag && !isBeamed {
                ForEach(0..<beat.interval.flagCount, id: \.self) { flagIndex in
                    FlagView(flagIndex: flagIndex)
                        .foregroundColor(isActive ? .yellow : .white)
                        .offset(
                            x: stemInfo.mainStemX + GameplayLayout.flagXOffset,
                            y: stemInfo.stemTop - CGFloat(flagIndex) * GameplayLayout.flagVerticalSpacing
                        )
                }
            }

            // Drum symbols with flags for individual notes
            ForEach(Array(beat.drums.enumerated()), id: \.offset) { _, drum in
                DrumSymbolView(
                    drum: drum,
                    stemInfo: stemInfo,
                    beat: beat,
                    isActive: isActive,
                    isBeamed: isBeamed
                )
            }
        }
        .frame(width: GameplayLayout.beatColumnWidth, height: GameplayLayout.staffHeight)
    }
}

// MARK: - Drum Symbol Component
private struct DrumSymbolView: View {
    let drum: DrumType
    let stemInfo: StemConnectionInfo
    let beat: DrumBeat
    let isActive: Bool
    let isBeamed: Bool

    var body: some View {
        let drumYOffset = drum.notePosition.yOffset

        ZStack {
            // Flags for individual notes (only if not using connected stem and not beamed)
            if !stemInfo.hasConnectedStem && beat.interval.needsFlag && !isBeamed {
                ForEach(0..<beat.interval.flagCount, id: \.self) { flagIndex in
                    FlagView(flagIndex: flagIndex)
                        .foregroundColor(isActive ? .yellow : .white)
                        .offset(
                            x: GameplayLayout.individualFlagXOffset,
                            y: drumYOffset - GameplayLayout.individualFlagYOffset -
                                CGFloat(flagIndex) * GameplayLayout.flagVerticalSpacing
                        )
                }
            }

            // Drum symbol
            Text(drum.symbol)
                .font(.system(size: GameplayLayout.drumSymbolFontSize, weight: .bold))
                .foregroundColor(isActive ? .yellow : .white)
                .offset(x: 0, y: drumYOffset)
        }
    }
}

// MARK: - Flag View
struct FlagView: View {
    let flagIndex: Int

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
        .fill(Color.white)
        .frame(width: GameplayLayout.flagWidth, height: GameplayLayout.flagHeight)
    }
}
