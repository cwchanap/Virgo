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

    // MARK: - Multi-row Layout Constants
    static let maxRowWidth: CGFloat = 900 // Maximum width per row before wrapping
    static let rowHeight: CGFloat = 200 // Height between rows
    static let rowVerticalSpacing: CGFloat = 40 // Extra space between rows

    // MARK: - Base Y Position (lowest staff line for first row)
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

        func absoluteY(for row: Int) -> CGFloat {
            let rowY = GameplayLayout.baseStaffY + CGFloat(row) *
                (GameplayLayout.rowHeight + GameplayLayout.rowVerticalSpacing)
            return rowY + yOffset
        }
    }

    // MARK: - Note Positions (including spaces between staff lines)
    enum NotePosition: CaseIterable {
        // Extended positions above staff
        case aboveLine9      // Far above staff
        case aboveLine8
        case aboveLine7
        case aboveLine6
        case aboveLine5      // Above highest staff line
        
        // Main staff positions
        case line5           // Highest staff line
        case spaceBetween4And5
        case line4
        case spaceBetween3And4
        case line3           // Middle staff line (snare)
        case spaceBetween2And3
        case line2
        case spaceBetween1And2
        case line1           // Lowest staff line
        
        // Extended positions below staff
        case spaceBetweenLine1AndBelow  // Between line1 and belowLine1
        case belowLine1      // Below lowest staff line
        case belowLine2      // Even further below (for kick drum)
        case belowLine3      // Extended below positions
        case belowLine4
        case belowLine5
        case belowLine6      // Far below staff

        var yOffset: CGFloat {
            switch self {
            // Extended positions above staff
            case .aboveLine9: return -9 * GameplayLayout.staffLineSpacing
            case .aboveLine8: return -8 * GameplayLayout.staffLineSpacing  
            case .aboveLine7: return -7 * GameplayLayout.staffLineSpacing
            case .aboveLine6: return -6 * GameplayLayout.staffLineSpacing
            case .aboveLine5: return -5 * GameplayLayout.staffLineSpacing
            
            // Main staff positions
            case .line5: return -4 * GameplayLayout.staffLineSpacing
            case .spaceBetween4And5: return -3.5 * GameplayLayout.staffLineSpacing
            case .line4: return -3 * GameplayLayout.staffLineSpacing
            case .spaceBetween3And4: return -2.5 * GameplayLayout.staffLineSpacing
            case .line3: return -2 * GameplayLayout.staffLineSpacing
            case .spaceBetween2And3: return -1.5 * GameplayLayout.staffLineSpacing
            case .line2: return -1 * GameplayLayout.staffLineSpacing
            case .spaceBetween1And2: return -0.5 * GameplayLayout.staffLineSpacing
            case .line1: return 0 * GameplayLayout.staffLineSpacing
            
            // Extended positions below staff
            case .spaceBetweenLine1AndBelow: return 0.5 * GameplayLayout.staffLineSpacing
            case .belowLine1: return 1 * GameplayLayout.staffLineSpacing
            case .belowLine2: return 2 * GameplayLayout.staffLineSpacing
            case .belowLine3: return 3 * GameplayLayout.staffLineSpacing
            case .belowLine4: return 4 * GameplayLayout.staffLineSpacing
            case .belowLine5: return 5 * GameplayLayout.staffLineSpacing
            case .belowLine6: return 6 * GameplayLayout.staffLineSpacing
            }
        }

        func absoluteY(for row: Int) -> CGFloat {
            let rowY = GameplayLayout.baseStaffY + CGFloat(row) *
                (GameplayLayout.rowHeight + GameplayLayout.rowVerticalSpacing)
            return rowY + yOffset
        }
    }

    // MARK: - Horizontal Layout
    static let clefWidth: CGFloat = 40
    static let timeSignatureWidth: CGFloat = 30
    static let leftMargin: CGFloat = 100 // clefWidth + timeSignatureWidth + spacing
    static let uniformSpacing: CGFloat = 50 // Unified spacing between all elements (bars, notes)
    static let measureSpacing: CGFloat = 12 // Space between measures

    // MARK: - Bar Line Layout
    static let barLineWidth: CGFloat = 2
    static let doubleBarLineWidths: (thin: CGFloat, thick: CGFloat) = (2, 4)
    static let doubleBarLineSpacing: CGFloat = 3

    // MARK: - DrumBeat Constants
    static let beatColumnWidth: CGFloat = 30
    static let beatColumnCornerRadius: CGFloat = 4
    static let stemWidth: CGFloat = 2
    static let stemHeight: CGFloat = 75
    static let stemExtension: CGFloat = 35
    static let stemXOffset: CGFloat = 7
    static let beamYPosition: CGFloat = -60
    static let connectorWidth: CGFloat = 5
    static let connectorHeight: CGFloat = 2
    static let connectorXOffset: CGFloat = 4.5
    static let flagXOffset: CGFloat = 2
    static let flagVerticalSpacing: CGFloat = 8
    static let individualFlagXOffset: CGFloat = 9
    static let individualFlagYOffset: CGFloat = 67.5
    static let drumSymbolFontSize: CGFloat = 20
    static let activeOpacity: CGFloat = 0.3
    static let beamLevelSpacing: CGFloat = 6

    // MARK: - Flag Drawing Constants
    static let flagWidth: CGFloat = 8
    static let flagHeight: CGFloat = 8
    static let flagCurveControl1X: CGFloat = 4
    static let flagCurveControl1Y: CGFloat = -2
    static let flagCurveControl2X: CGFloat = 6
    static let flagCurveControl2Y: CGFloat = 2
    static let flagCurveMidPointX: CGFloat = 8
    static let flagCurveMidPointY: CGFloat = 4
    static let flagCurveEndControl1X: CGFloat = 6
    static let flagCurveEndControl1Y: CGFloat = 6
    static let flagCurveEndControl2X: CGFloat = 4
    static let flagCurveEndControl2Y: CGFloat = 10

    // MARK: - Component Positions
    static let clefX: CGFloat = 20
    static let timeSignatureX: CGFloat = 55

    // MARK: - Row Calculation
    struct MeasurePosition {
        let row: Int
        let xOffset: CGFloat
        let measureIndex: Int
    }

    static func calculateMeasurePositions(totalMeasures: Int, timeSignature: TimeSignature) -> [MeasurePosition] {
        var positions: [MeasurePosition] = []
        var currentRow = 0
        var currentX: CGFloat = leftMargin
        let measureWidth = self.measureWidth(for: timeSignature)

        for measureIndex in 0..<totalMeasures {
            // Check if this measure would exceed the row width
            let totalWidthNeeded = currentX + measureWidth + (measureIndex == totalMeasures - 1 ? 20 : measureSpacing)

            if totalWidthNeeded > maxRowWidth && measureIndex > 0 {
                // Start new row
                currentRow += 1
                currentX = leftMargin
            }

            positions.append(MeasurePosition(row: currentRow, xOffset: currentX, measureIndex: measureIndex))
            currentX += measureWidth + measureSpacing
        }

        return positions
    }

    static func totalHeight(for positions: [MeasurePosition]) -> CGFloat {
        let maxRow = positions.map { $0.row }.max() ?? 0
        return baseStaffY + CGFloat(maxRow + 1) * (rowHeight + rowVerticalSpacing) + 100
    }

    // MARK: - Calculation Helpers
    static func measureWidth(for timeSignature: TimeSignature) -> CGFloat {
        // Pattern: bar + spacing + note + spacing + note + spacing + ... + spacing
        // Total: barWidth + (beatsPerMeasure + 1) * uniformSpacing
        return barLineWidth + CGFloat(timeSignature.beatsPerMeasure + 1) * uniformSpacing
    }

    static func noteXPosition(
        measurePosition: MeasurePosition, beatIndex: Int, timeSignature: TimeSignature
    ) -> CGFloat {
        // Position: measureStart + barWidth + spacing + beatIndex * (spacing)
        return measurePosition.xOffset + barLineWidth + uniformSpacing + CGFloat(beatIndex) * uniformSpacing
    }

    static func preciseNoteXPosition(
        measurePosition: MeasurePosition, beatPosition: Double, timeSignature: TimeSignature
    ) -> CGFloat {
        // Position: measureStart + barWidth + spacing + beatPosition * (spacing)
        // This allows for fractional beat positions (e.g., 0.5 for eighth notes, 0.25 for sixteenth notes)
        return measurePosition.xOffset + barLineWidth + uniformSpacing + CGFloat(beatPosition) * uniformSpacing
    }

    static func rowWidth(for timeSignature: TimeSignature) -> CGFloat {
        return maxRowWidth
    }

    static func noteXPosition(
        measureIndex: Int, beatIndex: Int, timeSignature: TimeSignature, positions: [MeasurePosition]
    ) -> CGFloat {
        guard let measurePos = positions.first(where: { $0.measureIndex == measureIndex }) else {
            return leftMargin
        }
        return noteXPosition(measurePosition: measurePos, beatIndex: beatIndex, timeSignature: timeSignature)
    }

    static func noteYPosition(row: Int, notePosition: NotePosition) -> CGFloat {
        return notePosition.absoluteY(for: row)
    }
}

// MARK: - Drum Position Mapping
extension DrumType {
    var notePosition: GameplayLayout.NotePosition {
        switch self {
        case .crash: return .aboveLine5
        case .hiHat: return .line5
        case .hiHatPedal: return .belowLine1
        case .tom1: return .spaceBetween3And4
        case .snare: return .line3
        case .tom2: return .spaceBetween2And3
        case .tom3: return .line2
        case .kick: return .belowLine2
        case .ride: return .spaceBetween4And5
        case .cowbell: return .line4
        }
    }

    func yPosition(for row: Int) -> CGFloat {
        return notePosition.absoluteY(for: row)
    }
}
