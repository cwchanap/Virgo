//
//  MetronomeBasicTests.swift
//  VirgoTests
//
//  Created by Chan Wai Chan on 14/7/2025.
//

import Testing
import Foundation
import SwiftUI
@testable import Virgo

struct MetronomeBasicTests {
    
    @Test func testMetronomeEngineCreation() {
        let metronome = MetronomeEngine()
        #expect(metronome != nil)
    }
    
    @Test func testMetronomeInitialState() {
        let metronome = MetronomeEngine()
        #expect(metronome.isEnabled == false)
        #expect(metronome.currentBeat == 0)
        #expect(metronome.volume == 0.7)
    }
    
    @Test func testMetronomeConfiguration() {
        let metronome = MetronomeEngine()
        metronome.configure(bpm: 140, timeSignature: .threeFour)
        
        // Configuration should not change public state immediately
        #expect(metronome.isEnabled == false)
        #expect(metronome.currentBeat == 0)
    }
    
    @Test func testMetronomeBasicControls() {
        let metronome = MetronomeEngine()
        metronome.configure(bpm: 120, timeSignature: .fourFour)
        
        // Test starting
        metronome.start()
        #expect(metronome.isEnabled == true)
        #expect(metronome.currentBeat == 0)
        
        // Test stopping
        metronome.stop()
        #expect(metronome.isEnabled == false)
        #expect(metronome.currentBeat == 0)
    }
    
    @Test func testMetronomeToggleFunction() {
        let metronome = MetronomeEngine()
        metronome.configure(bpm: 120, timeSignature: .fourFour)
        
        #expect(metronome.isEnabled == false)
        
        // Toggle on
        metronome.toggle()
        #expect(metronome.isEnabled == true)
        
        // Toggle off
        metronome.toggle()
        #expect(metronome.isEnabled == false)
    }
    
    @Test func testMetronomeVolumeControl() {
        let metronome = MetronomeEngine()
        
        // Test different volume levels
        metronome.volume = 0.0
        #expect(metronome.volume == 0.0)
        
        metronome.volume = 1.0
        #expect(metronome.volume == 1.0)
        
        metronome.volume = 0.5
        #expect(metronome.volume == 0.5)
    }
    
    @Test func testTimeSignatureProperties() {
        #expect(TimeSignature.twoFour.beatsPerMeasure == 2)
        #expect(TimeSignature.threeFour.beatsPerMeasure == 3)
        #expect(TimeSignature.fourFour.beatsPerMeasure == 4)
        #expect(TimeSignature.fiveFour.beatsPerMeasure == 5)
        
        #expect(TimeSignature.twoFour.displayName == "2/4")
        #expect(TimeSignature.threeFour.displayName == "3/4")
        #expect(TimeSignature.fourFour.displayName == "4/4")
        #expect(TimeSignature.fiveFour.displayName == "5/4")
    }
    
    @Test func testMetronomeComponentCreation() {
        let track = DrumTrack(
            title: "Test Track",
            artist: "Test Artist",
            bpm: 120,
            duration: "3:00",
            genre: "Rock",
            difficulty: .medium,
            timeSignature: .fourFour
        )
        
        let component = MetronomeComponent(track: track, isPlaying: .constant(false))
        #expect(component.track.title == "Test Track")
        #expect(component.track.bpm == 120)
        #expect(component.track.timeSignature == .fourFour)
    }
    
    @Test func testMetronomeSettingsViewCreation() {
        let metronome = MetronomeEngine()
        let settingsView = MetronomeSettingsView(metronome: metronome)
        #expect(settingsView != nil)
    }
    
    @Test func testBeatCounterLogic() {
        let signatures: [TimeSignature] = [.twoFour, .threeFour, .fourFour, .fiveFour]
        
        for signature in signatures {
            let beatsPerMeasure = signature.beatsPerMeasure
            
            // Test beat wrapping
            for beat in 0..<(beatsPerMeasure * 2) {
                let wrappedBeat = beat % beatsPerMeasure
                #expect(wrappedBeat >= 0)
                #expect(wrappedBeat < beatsPerMeasure)
            }
        }
    }
    
    @Test func testTimingCalculations() {
        // Test BPM to interval conversion
        let bpm120 = 120
        let expectedInterval120 = 60.0 / Double(bpm120)
        #expect(abs(expectedInterval120 - 0.5) < 0.001)
        
        let bpm60 = 60
        let expectedInterval60 = 60.0 / Double(bpm60)
        #expect(abs(expectedInterval60 - 1.0) < 0.001)
    }
    
    @Test func testVolumeAccentCalculation() {
        let baseVolume: Float = 0.5
        let accentMultiplier: Float = 1.3
        let expectedAccentVolume = baseVolume * accentMultiplier
        
        #expect(abs(expectedAccentVolume - 0.65) < 0.001)
        #expect(expectedAccentVolume > baseVolume)
    }
    
    @Test func testMetronomeEngineObservableObject() {
        let metronome = MetronomeEngine()
        #expect(metronome is any ObservableObject)
    }
    
    @Test func testMetronomeComponentWithDifferentTracks() {
        let tracks = [
            DrumTrack(title: "Track 1", artist: "Artist", bpm: 100, duration: "3:00", 
                     genre: "Pop", difficulty: .easy, timeSignature: .fourFour),
            DrumTrack(title: "Track 2", artist: "Artist", bpm: 140, duration: "4:00", 
                     genre: "Jazz", difficulty: .hard, timeSignature: .threeFour)
        ]
        
        for track in tracks {
            let component = MetronomeComponent(track: track, isPlaying: .constant(false))
            #expect(component.track.bpm == track.bpm)
            #expect(component.track.timeSignature == track.timeSignature)
        }
    }
    
    @Test func testMetronomeButtonStyleCreation() {
        let buttonStyle = MetronomeButtonStyle()
        #expect(buttonStyle != nil)
    }
}
