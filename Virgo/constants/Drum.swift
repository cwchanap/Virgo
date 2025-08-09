//
//  Drum.swift
//  Virgo
//
//  Created by Chan Wai Chan on 11/7/2025.
//

import Foundation
import SwiftUI

enum Difficulty: String, Codable, CaseIterable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
    case expert = "Expert"

    var color: Color {
        switch self {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        case .expert: return .purple
        }
    }

    var defaultLevel: Int {
        switch self {
        case .easy: return 30
        case .medium: return 50
        case .hard: return 70
        case .expert: return 90
        }
    }

    var sortOrder: Int {
        switch self {
        case .easy: return 0
        case .medium: return 1
        case .hard: return 2
        case .expert: return 3
        }
    }
}

enum TimeSignature: String, Codable, CaseIterable {
    case fourFour = "4/4"
    case threeFour = "3/4"
    case twoFour = "2/4"
    case sixEight = "6/8"
    case fiveFour = "5/4"
    case sevenEight = "7/8"
    case nineEight = "9/8"
    case twelveEight = "12/8"

    var beatsPerMeasure: Int {
        switch self {
        case .fourFour: return 4
        case .threeFour: return 3
        case .twoFour: return 2
        case .sixEight: return 6
        case .fiveFour: return 5
        case .sevenEight: return 7
        case .nineEight: return 9
        case .twelveEight: return 12
        }
    }

    var noteValue: Int {
        switch self {
        case .fourFour, .threeFour, .twoFour, .fiveFour: return 4
        case .sixEight, .sevenEight, .nineEight, .twelveEight: return 8
        }
    }

    var displayName: String {
        return self.rawValue
    }
}

enum NoteInterval: String, Codable, CaseIterable {
    case full = "Full"
    case half = "Half"
    case quarter = "Quarter"
    case eighth = "Eighth"
    case sixteenth = "Sixteenth"
    case thirtysecond = "Thirty Second"
    case sixtyfourth = "Sixty Fourth"

    var needsStem: Bool {
        switch self {
        case .full, .half:
            return false
        case .quarter, .eighth, .sixteenth, .thirtysecond, .sixtyfourth:
            return true
        }
    }

    var needsFlag: Bool {
        switch self {
        case .full, .half, .quarter:
            return false
        case .eighth, .sixteenth, .thirtysecond, .sixtyfourth:
            return true
        }
    }

    var flagCount: Int {
        switch self {
        case .full, .half, .quarter:
            return 0
        case .eighth:
            return 1
        case .sixteenth:
            return 2
        case .thirtysecond:
            return 3
        case .sixtyfourth:
            return 4
        }
    }
}

enum NoteType: String, Codable, CaseIterable {
    case bass = "Bass"
    case snare = "Snare"
    case highTom = "High Tom"
    case midTom = "Mid Tom"
    case lowTom = "Low Tom"
    case hiHat = "Hi-Hat"
    case hiHatPedal = "Hi-Hat Pedal"
    case openHiHat = "Open Hi-Hat"
    case crash = "Crash"
    case ride = "Ride"
    case china = "China"
    case splash = "Splash"
    case cowbell = "Cowbell"
}

enum DrumType {
    case kick, snare, hiHat, hiHatPedal, crash, ride, tom1, tom2, tom3, cowbell

    var description: String {
        switch self {
        case .kick: return "kick"
        case .snare: return "snare"
        case .hiHat: return "hiHat"
        case .hiHatPedal: return "hiHatPedal"
        case .crash: return "crash"
        case .ride: return "ride"
        case .tom1: return "tom1"
        case .tom2: return "tom2"
        case .tom3: return "tom3"
        case .cowbell: return "cowbell"
        }
    }

    var symbol: String {
        switch self {
        case .kick: return "●"
        case .snare: return "◆"
        case .hiHat: return "×"
        case .hiHatPedal: return "×"
        case .crash: return "◉"
        case .ride: return "○"
        case .tom1: return "◐"
        case .tom2: return "◑"
        case .tom3: return "◒"
        case .cowbell: return "◇"
        }
    }

    static func from(noteType: NoteType) -> DrumType? {
        return noteTypeToDrumTypeMap[noteType]
    }
    
    private static let noteTypeToDrumTypeMap: [NoteType: DrumType] = [
        .bass: .kick,
        .snare: .snare,
        .hiHat: .hiHat,
        .hiHatPedal: .hiHatPedal,
        .openHiHat: .hiHat,
        .crash: .crash,
        .ride: .ride,
        .highTom: .tom1,
        .midTom: .tom2,
        .lowTom: .tom3,
        .china: .crash,
        .splash: .crash,
        .cowbell: .cowbell
    ]
}

// MARK: - Beam Grouping Constants
struct BeamGroupingConstants {
    static let maxConsecutiveInterval: Double = 0.3
}
