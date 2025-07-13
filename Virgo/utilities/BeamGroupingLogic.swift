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
        var groupIndex = 0 // Track unique group index
        
        // Helper function to create unique beam ID
        func createBeamGroup(from group: [DrumBeat]) -> BeamGroup {
            // Validate that group is not empty and increment index
            guard !group.isEmpty else {
                groupIndex += 1
                return BeamGroup(id: "beam_empty_\(groupIndex)", beats: [])
            }
            
            let firstBeatID = group.first!.id // Safe unwrap since we checked !group.isEmpty
            groupIndex += 1
            return BeamGroup(id: "beam_\(firstBeatID)_\(groupIndex)", beats: group)
        }
        
        for beat in beats {
            // Only group eighth notes and shorter that need flags
            if beat.interval.needsFlag {
                // Check if this beat is consecutive to the previous one
                if let lastBeat = currentGroup.last {
                    let timeDifference = abs(beat.timePosition - lastBeat.timePosition)
                    let measureNumber = Int(beat.timePosition)
                    let lastMeasureNumber = Int(lastBeat.timePosition)
                    
                    // Group notes if they're in the same measure and consecutive (within threshold time units)
                    if measureNumber == lastMeasureNumber && timeDifference <= BeamGroupingConstants.maxConsecutiveInterval {
                        currentGroup.append(beat)
                    } else {
                        // Finish current group if it has 2+ notes
                        if currentGroup.count >= 2 {
                            beamGroups.append(createBeamGroup(from: currentGroup))
                        }
                        currentGroup = [beat]
                    }
                } else {
                    currentGroup = [beat]
                }
            } else {
                // Finish current group for non-beamable notes
                if currentGroup.count >= 2 {
                    beamGroups.append(createBeamGroup(from: currentGroup))
                }
                currentGroup = []
            }
        }
        
        // Don't forget the last group
        if currentGroup.count >= 2 {
            beamGroups.append(createBeamGroup(from: currentGroup))
        }
        
        return beamGroups
    }
}

// MARK: - Testing and Validation
/*
 The fix ensures unique beam IDs by:
 
 1. Using a group index that increments for each beam group created
 2. Combining the first beat ID with the group index: "beam_{firstBeatID}_{groupIndex}"
 3. Safely unwrapping group.first after validating !group.isEmpty
 4. Handling edge case of empty groups with "beam_empty_{groupIndex}"
 
 Example IDs generated:
 - "beam_1000_1" (first group, starts with beat ID 1000)
 - "beam_1250_2" (second group, starts with beat ID 1250)  
 - "beam_2000_3" (third group, starts with beat ID 2000)
 
 This eliminates the risk of collision from the previous "beam_0" fallback
 and ensures each beam group has a unique identifier.
 */
