//
//  GameplayLayout+NotePosition.swift
//  Virgo
//
//  Extracted from DrumNotationSettingsView to keep that file under SwiftLint's
//  600-line file-length warn threshold. These display/persistence helpers on
//  GameplayLayout.NotePosition are independent of the settings view's state.
//

import SwiftUI

extension GameplayLayout.NotePosition {
    var displayName: String {
        switch self {
        // Extended positions above staff
        case .aboveLine9: return "Above Line 9"
        case .aboveLine8: return "Above Line 8"
        case .aboveLine7: return "Above Line 7"
        case .aboveLine6: return "Above Line 6"
        case .aboveLine5: return "Above Line 5"

        // Main staff positions
        case .line5: return "Line 5 (Top)"
        case .spaceBetween4And5: return "Space 4-5"
        case .line4: return "Line 4"
        case .spaceBetween3And4: return "Space 3-4"
        case .line3: return "Line 3 (Middle)"
        case .spaceBetween2And3: return "Space 2-3"
        case .line2: return "Line 2"
        case .spaceBetween1And2: return "Space 1-2"
        case .line1: return "Line 1 (Bottom)"

        // Extended positions below staff
        case .spaceBetweenLine1AndBelow: return "Below Space"
        case .belowLine1: return "Below Line 1"
        case .belowLine2: return "Below Line 2"
        case .belowLine3: return "Below Line 3"
        case .belowLine4: return "Below Line 4"
        case .belowLine5: return "Below Line 5"
        case .belowLine6: return "Below Line 6"
        }
    }

    var rawValue: String {
        switch self {
        // Extended positions above staff
        case .aboveLine9: return "aboveLine9"
        case .aboveLine8: return "aboveLine8"
        case .aboveLine7: return "aboveLine7"
        case .aboveLine6: return "aboveLine6"
        case .aboveLine5: return "aboveLine5"

        // Main staff positions
        case .line5: return "line5"
        case .spaceBetween4And5: return "spaceBetween4And5"
        case .line4: return "line4"
        case .spaceBetween3And4: return "spaceBetween3And4"
        case .line3: return "line3"
        case .spaceBetween2And3: return "spaceBetween2And3"
        case .line2: return "line2"
        case .spaceBetween1And2: return "spaceBetween1And2"
        case .line1: return "line1"

        // Extended positions below staff
        case .spaceBetweenLine1AndBelow: return "spaceBetweenLine1AndBelow"
        case .belowLine1: return "belowLine1"
        case .belowLine2: return "belowLine2"
        case .belowLine3: return "belowLine3"
        case .belowLine4: return "belowLine4"
        case .belowLine5: return "belowLine5"
        case .belowLine6: return "belowLine6"
        }
    }

    var previewOffset: CGFloat {
        switch self {
        // Extended positions above staff
        case .aboveLine9: return -72
        case .aboveLine8: return -64
        case .aboveLine7: return -56
        case .aboveLine6: return -48
        case .aboveLine5: return -40

        // Main staff positions
        case .line5: return -32
        case .spaceBetween4And5: return -28
        case .line4: return -24
        case .spaceBetween3And4: return -20
        case .line3: return -16
        case .spaceBetween2And3: return -12
        case .line2: return -8
        case .spaceBetween1And2: return -4
        case .line1: return 0

        // Extended positions below staff
        case .spaceBetweenLine1AndBelow: return 4
        case .belowLine1: return 8
        case .belowLine2: return 16
        case .belowLine3: return 24
        case .belowLine4: return 32
        case .belowLine5: return 40
        case .belowLine6: return 48
        }
    }
}
