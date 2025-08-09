//
//  GameplayView+InputManagerDelegate.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import Foundation

// MARK: - InputHandler Class

class GameplayInputHandler: InputManagerDelegate {
    func inputManager(_ manager: InputManager, didReceiveHit hit: InputHit) {
        let logMessage = "Input hit received: \(hit.drumType.description) at \(hit.timestamp)"
        Logger.userAction(logMessage)
    }
    
    func inputManager(_ manager: InputManager, didMatchNote result: NoteMatchResult) {
        let accuracyText = switch result.timingAccuracy {
        case .perfect: "PERFECT"
        case .great: "GREAT" 
        case .good: "GOOD"
        case .miss: "MISS"
        }
        
        if result.matchedNote != nil {
            let logMessage = "Note matched: \(result.hitInput.drumType.description) - \(accuracyText) " + 
            "(\(result.timingError.formatted(.number.precision(.fractionLength(0))))ms) " + 
            "at measure \(result.measureNumber)"
            Logger.userAction(logMessage)
        } else {
            let logMessage = "No note match: \(result.hitInput.drumType.description) - " + 
            "\(accuracyText) at measure \(result.measureNumber)"
            Logger.userAction(logMessage)
        }
        
        // TODO: Add visual feedback for note hits
        // TODO: Add scoring system
        // TODO: Add combo tracking
    }
}
