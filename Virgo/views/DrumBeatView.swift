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

// MARK: - Drum Beat View
struct DrumBeatView: View {
    let beat: DrumBeat
    let isActive: Bool
    let row: Int
    let isBeamed: Bool
    
    // Calculate stem connection info for multiple simultaneous notes
    private var stemInfo: StemConnectionInfo {
        guard beat.interval.needsStem && beat.drums.count > 1 else {
            return StemConnectionInfo(hasConnectedStem: false, stemTop: 0, stemBottom: 0, mainStemX: 7)
        }
        
        let noteOffsets = beat.drums.map { $0.notePosition.yOffset }
        let topOffset = noteOffsets.min() ?? 0 // Highest note (smallest y offset)
        let bottomOffset = noteOffsets.max() ?? 0 // Lowest note (largest y offset)
        
        // Only connect stems if notes span multiple staff positions
        let shouldConnect = abs(topOffset - bottomOffset) > GameplayLayout.staffLineSpacing
        
        if shouldConnect {
            // Extend stem upward from the topmost note only (standard music notation)
            let stemExtension: CGFloat = 35
            return StemConnectionInfo(
                hasConnectedStem: true,
                stemTop: topOffset - stemExtension,
                stemBottom: bottomOffset, // Don't extend beyond the bottommost note
                mainStemX: 7
            )
        } else {
            return StemConnectionInfo(hasConnectedStem: false, stemTop: 0, stemBottom: 0, mainStemX: 7)
        }
    }
    
    var body: some View {
        ZStack {
            // Beat column background
            Rectangle()
                .frame(width: 30, height: GameplayLayout.staffHeight)
                .foregroundColor(isActive ? Color.purple.opacity(0.3) : Color.clear)
                .cornerRadius(4)
            
            // Connected stem for multiple notes (if applicable)
            if stemInfo.hasConnectedStem && beat.interval.needsStem {
                let stemTop: CGFloat = isBeamed ? -60 : stemInfo.stemTop  // End at beam if beamed
                let stemBottom = stemInfo.stemBottom
                let stemHeight = stemBottom - stemTop
                let stemCenterY = (stemTop + stemBottom) / 2
                
                Rectangle()
                    .frame(width: 2, height: stemHeight)
                    .foregroundColor(isActive ? .yellow : .white)
                    .offset(x: stemInfo.mainStemX, y: stemCenterY)
            }
            
            // Flags on the main stem (for connected stems, only if not beamed)
            if stemInfo.hasConnectedStem && beat.interval.needsFlag && !isBeamed {
                ForEach(0..<beat.interval.flagCount, id: \.self) { flagIndex in
                    FlagView(flagIndex: flagIndex)
                        .foregroundColor(isActive ? .yellow : .white)
                        .offset(x: stemInfo.mainStemX + 2, y: stemInfo.stemTop - CGFloat(flagIndex * 8))
                }
            }
            
            // Drum symbols with individual stems (for single notes or connection to main stem)
            ForEach(beat.drums, id: \.self) { drum in
                ZStack {
                    let drumYOffset = drum.notePosition.yOffset
                    
                    // Individual stem for single notes or short connection to main stem
                    if beat.interval.needsStem {
                        if !stemInfo.hasConnectedStem {
                            if isBeamed {
                                // Beamed stem - calculate height to reach beam position
                                let beamY: CGFloat = -60 // Base beam position relative to center staff line
                                let stemHeight = abs(drumYOffset - beamY)
                                let stemCenterY = (drumYOffset + beamY) / 2
                                
                                Rectangle()
                                    .frame(width: 2, height: stemHeight)
                                    .foregroundColor(isActive ? .yellow : .white)
                                    .offset(x: 7, y: stemCenterY)
                            } else {
                                // Individual stem for single note (not beamed)
                                Rectangle()
                                    .frame(width: 2, height: 75)
                                    .foregroundColor(isActive ? .yellow : .white)
                                    .offset(x: 7, y: drumYOffset - 37.5)
                            }
                        } else {
                            // Short connector to main stem (only if note is not at the extreme ends)
                            let isTopNote = drumYOffset == beat.drums.map { $0.notePosition.yOffset }.min()
                            let isBottomNote = drumYOffset == beat.drums.map { $0.notePosition.yOffset }.max()
                            
                            if !isTopNote && !isBottomNote {
                                // Short horizontal connector to main stem
                                Rectangle()
                                    .frame(width: 5, height: 2)
                                    .foregroundColor(isActive ? .yellow : .white)
                                    .offset(x: 4.5, y: drumYOffset)
                            }
                        }
                    }
                    
                    // Flags for individual notes (only if not using connected stem and not beamed)
                    if !stemInfo.hasConnectedStem && beat.interval.needsFlag && !isBeamed {
                        ForEach(0..<beat.interval.flagCount, id: \.self) { flagIndex in
                            FlagView(flagIndex: flagIndex)
                                .foregroundColor(isActive ? .yellow : .white)
                                .offset(x: 9, y: drumYOffset - 67.5 - CGFloat(flagIndex * 8))
                        }
                    }
                    
                    // Drum symbol
                    Text(drum.symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(isActive ? .yellow : .white)
                        .offset(x: 0, y: drumYOffset)
                }
            }
        }
        .frame(width: 30, height: GameplayLayout.staffHeight)
    }
}

// MARK: - Flag View
struct FlagView: View {
    let flagIndex: Int
    
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addCurve(to: CGPoint(x: 8, y: 4),
                         control1: CGPoint(x: 4, y: -2),
                         control2: CGPoint(x: 6, y: 2))
            path.addCurve(to: CGPoint(x: 0, y: 8),
                         control1: CGPoint(x: 6, y: 6),
                         control2: CGPoint(x: 4, y: 10))
            path.closeSubpath()
        }
        .fill(Color.white)
        .frame(width: 8, height: 8)
    }
}
