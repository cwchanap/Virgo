//
//  GameplayViewTests.swift
//  VirgoTests
//
//  Created by Chan Wai Chan on 30/6/2025.
//

import Testing
import Foundation
@testable import Virgo

struct GameplayViewTests {
    
    @Test func testDrumBeatCreation() async throws {
        let beat = DrumBeat(id: 0, drums: [.kick, .hiHat], timePosition: 0.0, interval: .quarter)
        
        #expect(beat.id == 0)
        #expect(beat.drums.count == 2)
        #expect(beat.drums.contains(.kick))
        #expect(beat.drums.contains(.hiHat))
        #expect(beat.timePosition == 0.0)
    }
    
    @Test func testDrumBeatWithSingleDrum() async throws {
        let beat = DrumBeat(id: 1, drums: [.snare], timePosition: 0.5, interval: .quarter)
        
        #expect(beat.id == 1)
        #expect(beat.drums.count == 1)
        #expect(beat.drums.first == .snare)
        #expect(beat.timePosition == 0.5)
    }
    
    @Test func testDrumBeatWithMultipleDrums() async throws {
        let beat = DrumBeat(id: 2, drums: [.kick, .snare, .hiHat, .crash], timePosition: 1.0, interval: .quarter)
        
        #expect(beat.id == 2)
        #expect(beat.drums.count == 4)
        #expect(beat.drums.contains(.kick))
        #expect(beat.drums.contains(.snare))
        #expect(beat.drums.contains(.hiHat))
        #expect(beat.drums.contains(.crash))
        #expect(beat.timePosition == 1.0)
    }
    
    @Test func testDrumTypeSymbols() async throws {
        #expect(DrumType.kick.symbol == "●")
        #expect(DrumType.snare.symbol == "◆")
        #expect(DrumType.hiHat.symbol == "×")
        #expect(DrumType.crash.symbol == "◉")
        #expect(DrumType.ride.symbol == "○")
        #expect(DrumType.tom1.symbol == "◐")
        #expect(DrumType.tom2.symbol == "◑")
        #expect(DrumType.tom3.symbol == "◒")
        #expect(DrumType.cowbell.symbol == "◇")
    }
    
    @Test func testDrumTypePositions() async throws {
        let row = 0 // Use row 0 for testing
        
        #expect(DrumType.crash.yPosition(for: row) == 90)   // aboveLine5
        #expect(DrumType.hiHat.yPosition(for: row) == 110)  // line5
        #expect(DrumType.cowbell.yPosition(for: row) == 130)  // line4
        #expect(DrumType.tom1.yPosition(for: row) == 140)   // spaceBetween3And4
        #expect(DrumType.snare.yPosition(for: row) == 150)  // line3
        #expect(DrumType.tom2.yPosition(for: row) == 160)   // spaceBetween2And3
        #expect(DrumType.tom3.yPosition(for: row) == 170)   // line2
        #expect(DrumType.kick.yPosition(for: row) == 210)   // belowLine1
        #expect(DrumType.ride.yPosition(for: row) == 120)   // spaceBetween4And5
        
        // Test that positions are correctly ordered (top to bottom)
        let orderedTypes: [DrumType] = [.crash, .hiHat, .ride, .cowbell, .tom1, .snare, .tom2, .tom3, .kick]
        let positions = orderedTypes.map { $0.yPosition(for: row) }
        let sortedPositions = positions.sorted()
        #expect(positions == sortedPositions)
    }
    
    @Test func testDrumTypeUniqueness() async throws {
        let row = 0 // Use row 0 for testing
        let allDrumTypes: [DrumType] = [.kick, .snare, .hiHat, .crash, .ride, .tom1, .tom2, .tom3, .cowbell]
        let symbols = allDrumTypes.map { $0.symbol }
        let positions = allDrumTypes.map { $0.yPosition(for: row) }
        
        // All symbols should be unique
        #expect(Set(symbols).count == symbols.count)
        
        // All positions should be unique
        #expect(Set(positions).count == positions.count)
    }
    
    @Test func testDrumTypePositionSpacing() async throws {
        let row = 0 // Use row 0 for testing
        let allDrumTypes: [DrumType] = [.crash, .hiHat, .ride, .cowbell, .tom1, .snare, .tom2, .tom3, .kick]
        let positions = allDrumTypes.map { $0.yPosition(for: row) }
        
        // Check that positions are properly ordered (smaller Y = higher on screen)
        for i in 1..<positions.count {
            #expect(positions[i] >= positions[i-1]) // Y increases as we go down
        }
    }
    
    @Test func testMockDrumPattern() async throws {
        let mockPattern = [
            DrumBeat(id: 0, drums: [.kick, .hiHat], timePosition: 0.0, interval: .quarter),
            DrumBeat(id: 1, drums: [.hiHat], timePosition: 0.25, interval: .quarter),
            DrumBeat(id: 2, drums: [.snare, .hiHat], timePosition: 0.5, interval: .quarter),
            DrumBeat(id: 3, drums: [.hiHat], timePosition: 0.75, interval: .quarter)
        ]
        
        #expect(mockPattern.count == 4)
        #expect(mockPattern[0].drums.contains(.kick))
        #expect(mockPattern[2].drums.contains(.snare))
        
        // Test that all beats except one contain hi-hat (common in drum patterns)
        let hiHatBeats = mockPattern.filter { $0.drums.contains(.hiHat) }
        #expect(hiHatBeats.count >= 3) // Most beats should have hi-hat
        
        // Test time progression
        for i in 1..<mockPattern.count {
            #expect(mockPattern[i].timePosition > mockPattern[i-1].timePosition)
        }
    }
    
    @Test func testDrumPatternTiming() async throws {
        let pattern = [
            DrumBeat(id: 0, drums: [.kick], timePosition: 0.0, interval: .quarter),
            DrumBeat(id: 1, drums: [.snare], timePosition: 0.5, interval: .quarter),
            DrumBeat(id: 2, drums: [.kick], timePosition: 1.0, interval: .quarter),
            DrumBeat(id: 3, drums: [.snare], timePosition: 1.5, interval: .quarter)
        ]
        
        // Test basic timing intervals
        #expect(pattern[1].timePosition - pattern[0].timePosition == 0.5)
        #expect(pattern[2].timePosition - pattern[1].timePosition == 0.5)
        #expect(pattern[3].timePosition - pattern[2].timePosition == 0.5)
        
        // Test total pattern duration
        let totalDuration = pattern.last!.timePosition - pattern.first!.timePosition
        #expect(totalDuration == 1.5)
    }
    
    @Test func testComplexDrumPattern() async throws {
        let complexPattern = [
            DrumBeat(id: 0, drums: [.kick, .hiHat], timePosition: 0.0, interval: .quarter),
            DrumBeat(id: 1, drums: [.hiHat], timePosition: 0.25, interval: .quarter),
            DrumBeat(id: 2, drums: [.snare, .hiHat], timePosition: 0.5, interval: .quarter),
            DrumBeat(id: 3, drums: [.hiHat], timePosition: 0.75, interval: .quarter),
            DrumBeat(id: 4, drums: [.kick, .hiHat], timePosition: 1.0, interval: .quarter),
            DrumBeat(id: 5, drums: [.hiHat], timePosition: 1.25, interval: .quarter),
            DrumBeat(id: 6, drums: [.snare, .hiHat], timePosition: 1.5, interval: .quarter),
            DrumBeat(id: 7, drums: [.hiHat, .crash], timePosition: 1.75, interval: .quarter)
        ]
        
        #expect(complexPattern.count == 8)
        
        // Test kick drum pattern (should be on beats 0 and 4)
        let kickBeats = complexPattern.filter { $0.drums.contains(.kick) }
        #expect(kickBeats.count == 2)
        #expect(kickBeats[0].id == 0)
        #expect(kickBeats[1].id == 4)
        
        // Test snare drum pattern (should be on beats 2 and 6)
        let snareBeats = complexPattern.filter { $0.drums.contains(.snare) }
        #expect(snareBeats.count == 2)
        #expect(snareBeats[0].id == 2)
        #expect(snareBeats[1].id == 6)
        
        // Test crash appears only once (at the end)
        let crashBeats = complexPattern.filter { $0.drums.contains(.crash) }
        #expect(crashBeats.count == 1)
        #expect(crashBeats[0].id == 7)
    }
    
    @Test func testEmptyDrumBeat() async throws {
        let emptyBeat = DrumBeat(id: 99, drums: [], timePosition: 2.0, interval: .quarter)
        
        #expect(emptyBeat.id == 99)
        #expect(emptyBeat.drums.isEmpty)
        #expect(emptyBeat.timePosition == 2.0)
    }
    
    @Test func testDrumTypeEnumCaseCount() async throws {
        let allDrumTypes: [DrumType] = [.kick, .snare, .hiHat, .crash, .ride, .tom1, .tom2, .tom3, .cowbell]
        
        // Ensure we have exactly 9 drum types
        #expect(allDrumTypes.count == 9)
        
        // Ensure each type appears only once
        let uniqueTypes = Set(allDrumTypes.map { $0.symbol })
        #expect(uniqueTypes.count == 9)
    }
    
    @Test func testCowbellDrumType() async throws {
        // Test that cowbell is properly configured
        #expect(DrumType.cowbell.symbol == "◇")
        #expect(DrumType.cowbell.yPosition(for: 0) == 130) // line4
        
        // Test that cowbell maps correctly from NoteType
        #expect(DrumType.from(noteType: .cowbell) == .cowbell)
    }
}
