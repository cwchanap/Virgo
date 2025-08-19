//
//  BeamGroupingLogicTests.swift
//  VirgoTests
//
//  Created by Claude Code on 19/8/2025.
//

import Testing
import Foundation
@testable import Virgo

@Suite("Beam Grouping Logic Tests")
struct BeamGroupingLogicTests {
    
    @Test("Beam grouping helper creates no groups for empty input")
    func testEmptyInput() {
        let beats: [DrumBeat] = []
        let beamGroups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        
        #expect(beamGroups.isEmpty)
    }
    
    @Test("Beam grouping helper ignores non-beamable notes")
    func testNonBeamableNotes() {
        let beats = [
            DrumBeat(id: 1, drums: [.kick], timePosition: 0.0, interval: .quarter),
            DrumBeat(id: 2, drums: [.snare], timePosition: 0.5, interval: .half),
            DrumBeat(id: 3, drums: [.hiHat], timePosition: 1.0, interval: .full)
        ]
        
        let beamGroups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        #expect(beamGroups.isEmpty)
    }
    
    @Test("Beam grouping helper creates group for consecutive eighth notes")
    func testConsecutiveEighthNotes() {
        let beats = [
            DrumBeat(id: 1, drums: [.kick], timePosition: 0.0, interval: .eighth),
            DrumBeat(id: 2, drums: [.snare], timePosition: 0.125, interval: .eighth),
            DrumBeat(id: 3, drums: [.hiHat], timePosition: 0.25, interval: .eighth)
        ]
        
        let beamGroups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        #expect(beamGroups.count == 1)
        #expect(beamGroups.first != nil)
        #expect(beamGroups.first!.beats.count == 3)
        #expect(beamGroups.first!.id.hasPrefix("beam_1_"))
    }
    
    @Test("Beam grouping helper creates group for consecutive sixteenth notes")
    func testConsecutiveSixteenthNotes() {
        let beats = [
            DrumBeat(id: 10, drums: [.kick], timePosition: 0.0, interval: .sixteenth),
            DrumBeat(id: 11, drums: [.snare], timePosition: 0.0625, interval: .sixteenth),
            DrumBeat(id: 12, drums: [.hiHat], timePosition: 0.125, interval: .sixteenth),
            DrumBeat(id: 13, drums: [.crash], timePosition: 0.1875, interval: .sixteenth)
        ]
        
        let beamGroups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        #expect(beamGroups.count == 1)
        #expect(beamGroups.first != nil)
        #expect(beamGroups.first!.beats.count == 4)
        #expect(beamGroups.first!.id.hasPrefix("beam_10_"))
    }
    
    @Test("Beam grouping helper creates separate groups for non-consecutive notes")
    func testNonConsecutiveNotes() {
        let beats = [
            DrumBeat(id: 1, drums: [.kick], timePosition: 0.0, interval: .eighth),
            DrumBeat(id: 2, drums: [.snare], timePosition: 0.125, interval: .eighth),
            DrumBeat(id: 3, drums: [.hiHat], timePosition: 1.0, interval: .eighth), // Gap
            DrumBeat(id: 4, drums: [.crash], timePosition: 1.125, interval: .eighth)
        ]
        
        let beamGroups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        #expect(beamGroups.count == 2)
        #expect(beamGroups[0].beats.count == 2)
        #expect(beamGroups[1].beats.count == 2)
    }
    
    @Test("Beam grouping helper requires minimum two notes for grouping")
    func testMinimumGroupSize() {
        let beats = [
            DrumBeat(id: 1, drums: [.kick], timePosition: 0.0, interval: .eighth),
            DrumBeat(id: 2, drums: [.snare], timePosition: 1.0, interval: .quarter), // Breaks group
            DrumBeat(id: 3, drums: [.hiHat], timePosition: 2.0, interval: .eighth)  // Single note
        ]
        
        let beamGroups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        #expect(beamGroups.isEmpty) // No groups with 2+ consecutive beamable notes
    }
    
    @Test("Beam grouping helper handles mixed intervals correctly")
    func testMixedIntervals() {
        let beats = [
            DrumBeat(id: 1, drums: [.kick], timePosition: 0.0, interval: .eighth),
            DrumBeat(id: 2, drums: [.snare], timePosition: 0.125, interval: .sixteenth),
            DrumBeat(id: 3, drums: [.hiHat], timePosition: 0.1875, interval: .eighth),
            DrumBeat(id: 4, drums: [.crash], timePosition: 0.3125, interval: .thirtysecond)
        ]
        
        let beamGroups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        #expect(beamGroups.count == 1)
        #expect(beamGroups.first != nil)
        #expect(beamGroups.first!.beats.count == 4)
    }
    
    @Test("Beam grouping helper respects measure boundaries")
    func testMeasureBoundaries() {
        let beats = [
            DrumBeat(id: 1, drums: [.kick], timePosition: 0.75, interval: .eighth),    // End of measure 0
            DrumBeat(id: 2, drums: [.snare], timePosition: 1.0, interval: .eighth),   // Start of measure 1
            DrumBeat(id: 3, drums: [.hiHat], timePosition: 1.125, interval: .eighth)  // Measure 1
        ]
        
        let beamGroups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        #expect(beamGroups.count == 1)
        #expect(beamGroups.first != nil)
        #expect(beamGroups.first!.beats.count == 2) // Only beats 2 and 3 should be grouped
    }
    
    @Test("Beam grouping helper creates unique IDs for multiple groups")
    func testUniqueBeamIDs() {
        let beats = [
            DrumBeat(id: 100, drums: [.kick], timePosition: 0.0, interval: .eighth),
            DrumBeat(id: 101, drums: [.snare], timePosition: 0.125, interval: .eighth),
            DrumBeat(id: 200, drums: [.hiHat], timePosition: 2.0, interval: .eighth),
            DrumBeat(id: 201, drums: [.crash], timePosition: 2.125, interval: .eighth)
        ]
        
        let beamGroups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        #expect(beamGroups.count == 2)
        
        let firstGroupID = beamGroups[0].id
        let secondGroupID = beamGroups[1].id
        
        #expect(firstGroupID != secondGroupID)
        #expect(firstGroupID.hasPrefix("beam_100_"))
        #expect(secondGroupID.hasPrefix("beam_200_"))
    }
    
    @Test("Beam grouping helper handles large time gaps correctly")
    func testLargeTimeGaps() {
        let beats = [
            DrumBeat(id: 1, drums: [.kick], timePosition: 0.0, interval: .eighth),
            DrumBeat(id: 2, drums: [.snare], timePosition: 0.125, interval: .eighth),
            DrumBeat(id: 3, drums: [.hiHat], timePosition: 10.0, interval: .eighth), // Large gap
            DrumBeat(id: 4, drums: [.crash], timePosition: 10.125, interval: .eighth)
        ]
        
        let beamGroups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        #expect(beamGroups.count == 2)
        
        // Verify the groups are separate
        let firstGroup = beamGroups.first { $0.id.contains("1") }
        let secondGroup = beamGroups.first { $0.id.contains("3") }
        
        #expect(firstGroup != nil)
        #expect(firstGroup?.beats.count == 2)
        #expect(secondGroup != nil)
        #expect(secondGroup?.beats.count == 2)
    }
    
    @Test("Beam grouping helper handles thirty-second notes")
    func testThirtySecondNotes() {
        let beats = [
            DrumBeat(id: 1, drums: [.kick], timePosition: 0.0, interval: .thirtysecond),
            DrumBeat(id: 2, drums: [.snare], timePosition: 0.03125, interval: .thirtysecond),
            DrumBeat(id: 3, drums: [.hiHat], timePosition: 0.0625, interval: .thirtysecond)
        ]
        
        let beamGroups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        #expect(beamGroups.count == 1)
        #expect(beamGroups.first != nil)
        #expect(beamGroups.first!.beats.count == 3)
    }
    
    @Test("Beam grouping helper preserves beat order in groups")
    func testBeatOrderPreservation() {
        let beats = [
            DrumBeat(id: 5, drums: [.kick], timePosition: 0.0, interval: .eighth),
            DrumBeat(id: 3, drums: [.snare], timePosition: 0.125, interval: .eighth),
            DrumBeat(id: 7, drums: [.hiHat], timePosition: 0.25, interval: .eighth)
        ]
        
        let beamGroups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        #expect(beamGroups.count == 1)
        
        let group = beamGroups.first!
        #expect(group.beats[0].id == 5)
        #expect(group.beats[1].id == 3)
        #expect(group.beats[2].id == 7)
    }
}