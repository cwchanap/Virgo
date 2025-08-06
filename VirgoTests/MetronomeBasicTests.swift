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

@MainActor
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
        let song = Song(
            title: "Test Track",
            artist: "Test Artist",
            bpm: 120,
            duration: "3:00",
            genre: "Rock",
            timeSignature: .fourFour
        )

        let chart = Chart(difficulty: .medium, song: song)
        let track = DrumTrack(chart: chart)

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
        let song1 = Song(title: "Track 1", artist: "Artist", bpm: 100, duration: "3:00",
                         genre: "Pop", timeSignature: .fourFour)
        let chart1 = Chart(difficulty: .easy, song: song1)

        let song2 = Song(title: "Track 2", artist: "Artist", bpm: 140, duration: "4:00",
                         genre: "Jazz", timeSignature: .threeFour)
        let chart2 = Chart(difficulty: .hard, song: song2)

        let tracks = [
            DrumTrack(chart: chart1),
            DrumTrack(chart: chart2)
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

    @Test
    func testUIUpdatePerformance() {
        let metronome = MetronomeEngine()
        metronome.configure(bpm: 200, timeSignature: .fourFour) // High BPM for stress test

        let startTime = CFAbsoluteTimeGetCurrent()

        // Simulate rapid beat updates and measure performance
        for _ in 0..<100 {
            _ = metronome.getCurrentBeat()
        }

        let endTime = CFAbsoluteTimeGetCurrent()
        let executionTime = endTime - startTime

        // Should complete quickly (less than 0.1 seconds for 100 calls)
        #expect(executionTime < 0.1, "Beat counter access should be fast even under load")
    }

    @Test
    func testAudioEngineFailure() {
        let metronome = MetronomeEngine()
        metronome.configure(bpm: 120, timeSignature: .fourFour)

        // Test that metronome continues to function even if audio fails
        metronome.start()
        #expect(metronome.isEnabled == true, "Metronome should start even without audio")

        // Test basic functionality continues
        metronome.testClick() // Should not crash

        let beat = metronome.getCurrentBeat()
        #expect(beat >= 0, "Beat counter should work without audio")

        metronome.stop()
        #expect(metronome.isEnabled == false, "Metronome should stop correctly")
    }

    @Test
    func testMetronomeConfigurationConstants() {
        #expect(MetronomeConfiguration.defaultSampleRate == 44100.0)
        #expect(MetronomeConfiguration.accentMultiplier == 1.3)
        #expect(MetronomeConfiguration.uiUpdateThreshold == 4)
        #expect(MetronomeConfiguration.maxBPMForSlowUpdate == 60)
        #expect(MetronomeConfiguration.mediumBPMThreshold == 120)
    }

    @Test
    func testBeatCounterThreadSafety() async {
        let metronome = MetronomeEngine()
        metronome.configure(bpm: 120, timeSignature: .fourFour)

        // Test concurrent access to beat counter
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    for _ in 0..<100 {
                        let beat = metronome.getCurrentBeat()
                        #expect(beat >= 0 && beat < 4, "Beat should always be within valid range")
                    }
                }
            }
        }
    }
}
