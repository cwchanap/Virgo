//
//  BeamGroupingLogic.swift
//  Virgo
//
//  Created by Chan Wai Chan on 12/7/2025.
//

import Foundation

// MARK: - Beam Grouping Helper
struct BeamGroupingHelper {
    static func calculateBeamGroups(from beats: [DrumBeat]) -> [BeamGroup] {
        var beamGroups: [BeamGroup] = []
        var currentGroup: [DrumBeat] = []
        
        for beat in beats {
            // Only group eighth notes and shorter that need flags
            if beat.interval.needsFlag {
                // Check if this beat is consecutive to the previous one
                if let lastBeat = currentGroup.last {
                    let timeDifference = abs(beat.timePosition - lastBeat.timePosition)
                    let measureNumber = Int(beat.timePosition)
                    let lastMeasureNumber = Int(lastBeat.timePosition)
                    
                    // Group notes if they're in the same measure and consecutive (within 0.3 time units)
                    if measureNumber == lastMeasureNumber && timeDifference <= 0.3 {
                        currentGroup.append(beat)
                    } else {
                        // Finish current group if it has 2+ notes
                        if currentGroup.count >= 2 {
                            beamGroups.append(BeamGroup(
                                id: "beam_\(currentGroup.first?.id ?? 0)",
                                beats: currentGroup
                            ))
                        }
                        currentGroup = [beat]
                    }
                } else {
                    currentGroup = [beat]
                }
            } else {
                // Finish current group for non-beamable notes
                if currentGroup.count >= 2 {
                    beamGroups.append(BeamGroup(
                        id: "beam_\(currentGroup.first?.id ?? 0)",
                        beats: currentGroup
                    ))
                }
                currentGroup = []
            }
        }
        
        // Don't forget the last group
        if currentGroup.count >= 2 {
            beamGroups.append(BeamGroup(
                id: "beam_\(currentGroup.first?.id ?? 0)",
                beats: currentGroup
            ))
        }
        
        return beamGroups
    }
}