//
//  gameplay.swift
//  Virgo
//
//  Created by Chan Wai Chan on 11/7/2025.
//

import SwiftUI

struct GameplayLayout {
    // MARK: - Staff Layout Constants
    static let staffLineSpacing: CGFloat = 20
    static let staffLineCount: Int = 5
    static let staffHeight: CGFloat = CGFloat(staffLineCount - 1) * staffLineSpacing // 80
    
    // MARK: - Base Y Position (lowest staff line)
    static let baseStaffY: CGFloat = 150 + (staffHeight / 2) // 190 (center of staff area)
    
    // MARK: - Staff Line Positions (relative to lowest staff line)
    enum StaffLinePosition: Int, CaseIterable {
        case line1 = 0  // Lowest staff line (bass)
        case line2 = 1
        case line3 = 2  // Middle staff line (snare)
        case line4 = 3
        case line5 = 4  // Highest staff line
        
        var yOffset: CGFloat {
            return -CGFloat(self.rawValue) * GameplayLayout.staffLineSpacing
        }
        
        var absoluteY: CGFloat {
            return GameplayLayout.baseStaffY + yOffset
        }
    }
    
    // MARK: - Note Positions (including spaces between staff lines)
    enum NotePosition: CaseIterable {
        case aboveLine5      // Above highest staff line
        case line5           // Highest staff line
        case spaceBetween4And5
        case line4
        case spaceBetween3And4
        case line3           // Middle staff line (snare)
        case spaceBetween2And3
        case line2
        case spaceBetween1And2
        case line1           // Lowest staff line
        case belowLine1      // Below lowest staff line
        
        var yOffset: CGFloat {
            switch self {
            case .aboveLine5: return -5 * GameplayLayout.staffLineSpacing
            case .line5: return -4 * GameplayLayout.staffLineSpacing
            case .spaceBetween4And5: return -3.5 * GameplayLayout.staffLineSpacing
            case .line4: return -3 * GameplayLayout.staffLineSpacing
            case .spaceBetween3And4: return -2.5 * GameplayLayout.staffLineSpacing
            case .line3: return -2 * GameplayLayout.staffLineSpacing
            case .spaceBetween2And3: return -1.5 * GameplayLayout.staffLineSpacing
            case .line2: return -1 * GameplayLayout.staffLineSpacing
            case .spaceBetween1And2: return -0.5 * GameplayLayout.staffLineSpacing
            case .line1: return 0 * GameplayLayout.staffLineSpacing
            case .belowLine1: return 1 * GameplayLayout.staffLineSpacing
            }
        }
        
        var absoluteY: CGFloat {
            return GameplayLayout.baseStaffY + yOffset
        }
    }
    
    // MARK: - Horizontal Layout
    static let clefWidth: CGFloat = 40
    static let timeSignatureWidth: CGFloat = 30
    static let leftMargin: CGFloat = 100 // clefWidth + timeSignatureWidth + spacing
    static let noteSpacing: CGFloat = 40
    static let measureSpacing: CGFloat = 0 // Space between measures
    
    // MARK: - Bar Line Layout
    static let barLineWidth: CGFloat = 2
    static let doubleBarLineWidths: (thin: CGFloat, thick: CGFloat) = (2, 4)
    static let doubleBarLineSpacing: CGFloat = 3
    
    // MARK: - Component Positions
    static let clefX: CGFloat = 20
    static let timeSignatureX: CGFloat = 55
    
    // MARK: - Calculation Helpers
    static func measureWidth(for timeSignature: TimeSignature) -> CGFloat {
        return CGFloat(timeSignature.beatsPerMeasure) * noteSpacing
    }
    
    static func staffWidth(measuresCount: Int, timeSignature: TimeSignature) -> CGFloat {
        return leftMargin + 
               (CGFloat(measuresCount) * measureWidth(for: timeSignature)) + 
               (CGFloat(max(0, measuresCount - 1)) * measureSpacing) + 
               10 // Space for final double bar line
    }
    
    static func noteXPosition(measureIndex: Int, beatIndex: Int, timeSignature: TimeSignature) -> CGFloat {
        let measureWidth = measureWidth(for: timeSignature)
        let measureX = leftMargin + (CGFloat(measureIndex) * (measureWidth + measureSpacing))
        let beatX = CGFloat(beatIndex) * noteSpacing
        return measureX + beatX
    }
    
    static func barLineXPosition(measureIndex: Int, timeSignature: TimeSignature) -> CGFloat {
        let measureWidth = measureWidth(for: timeSignature)
        return leftMargin + (CGFloat(measureIndex) * (measureWidth + measureSpacing))
    }
}

// MARK: - Drum Position Mapping
extension DrumType {
    var notePosition: GameplayLayout.NotePosition {
        switch self {
        case .crash: return .aboveLine5
        case .hiHat: return .line5
        case .tom1: return .spaceBetween3And4
        case .snare: return .line3
        case .tom2: return .spaceBetween2And3
        case .tom3: return .line2
        case .kick: return .belowLine1
        case .ride: return .spaceBetween4And5
        }
    }
    
    var yPosition: CGFloat {
        return notePosition.absoluteY
    }
}