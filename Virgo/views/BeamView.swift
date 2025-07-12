//
//  BeamView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 12/7/2025.
//

import SwiftUI

// MARK: - Beam Group Models
struct BeamGroup: Identifiable {
    let id: String
    let beats: [DrumBeat]
    
    var beamCount: Int {
        return beats.map { $0.interval.flagCount }.max() ?? 1
    }
}

// MARK: - Beam Group View
struct BeamGroupView: View {
    let beamGroup: BeamGroup
    let measurePositions: [GameplayLayout.MeasurePosition]
    let timeSignature: TimeSignature
    let isActive: Bool
    
    var body: some View {
        ZStack {
            ForEach(0..<beamGroup.beamCount, id: \.self) { beamLevel in
                BeamView(
                    beats: beamGroup.beats,
                    beamLevel: beamLevel,
                    measurePositions: measurePositions,
                    timeSignature: timeSignature,
                    isActive: isActive
                )
            }
        }
    }
}

// MARK: - Individual Beam View
struct BeamView: View {
    let beats: [DrumBeat]
    let beamLevel: Int
    let measurePositions: [GameplayLayout.MeasurePosition]
    let timeSignature: TimeSignature
    let isActive: Bool
    
    var body: some View {
        // Filter beats that need this beam level
        let beamedBeats = beats.filter { $0.interval.flagCount > beamLevel }
        
        guard beamedBeats.count >= 2,
              let firstBeat = beamedBeats.first,
              let lastBeat = beamedBeats.last else {
            return AnyView(EmptyView())
        }
        
        // Calculate beam positions
        let firstMeasureIndex = firstBeat.id / 1000
        let lastMeasureIndex = lastBeat.id / 1000
        
        guard let firstMeasurePos = measurePositions.first(where: { $0.measureIndex == firstMeasureIndex }),
              let lastMeasurePos = measurePositions.first(where: { $0.measureIndex == lastMeasureIndex }),
              firstMeasurePos.row == lastMeasurePos.row else {
            return AnyView(EmptyView())
        }
        
        // Calculate X positions
        let firstBeatOffset = firstBeat.timePosition - Double(firstMeasureIndex)
        let lastBeatOffset = lastBeat.timePosition - Double(lastMeasureIndex)
        let firstBeatIndex = Int(firstBeatOffset * Double(timeSignature.beatsPerMeasure))
        let lastBeatIndex = Int(lastBeatOffset * Double(timeSignature.beatsPerMeasure))
        
        let startX = GameplayLayout.noteXPosition(
            measurePosition: firstMeasurePos,
            beatIndex: firstBeatIndex,
            timeSignature: timeSignature
        ) + 7 // Stem offset
        let endX = GameplayLayout.noteXPosition(
            measurePosition: lastMeasurePos,
            beatIndex: lastBeatIndex,
            timeSignature: timeSignature
        ) + 7
        
        // Beam Y position (above the notes, accounting for beam level)
        let baseY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: firstMeasurePos.row) - 60 - CGFloat(beamLevel * 6)
        
        return AnyView(
            Path { path in
                path.move(to: CGPoint(x: startX, y: baseY))
                path.addLine(to: CGPoint(x: endX, y: baseY))
            }
            .stroke(isActive ? Color.yellow : Color.white, lineWidth: 4)
        )
    }
}
