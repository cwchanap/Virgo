
//
//  DrumType+Extensions.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import Foundation

extension DrumType: CaseIterable {
    public static var allCases: [DrumType] = [
        .kick, .snare, .hiHat, .hiHatPedal, .crash, .ride, 
        .tom1, .tom2, .tom3, .cowbell
    ]
    
    var displayName: String {
        switch self {
        case .kick: return "Kick Drum"
        case .snare: return "Snare"
        case .hiHat: return "Hi-Hat"
        case .hiHatPedal: return "Hi-Hat Pedal"
        case .crash: return "Crash"
        case .ride: return "Ride"
        case .tom1: return "High Tom"
        case .tom2: return "Mid Tom"
        case .tom3: return "Low Tom"
        case .cowbell: return "Cowbell"
        }
    }
    
    var sortOrder: Int {
        switch self {
        case .kick: return 0
        case .snare: return 1
        case .hiHat: return 2
        case .hiHatPedal: return 3
        case .tom1: return 4
        case .tom2: return 5
        case .tom3: return 6
        case .crash: return 7
        case .ride: return 8
        case .cowbell: return 9
        }
    }
}
