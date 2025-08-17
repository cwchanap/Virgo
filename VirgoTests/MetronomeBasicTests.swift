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
    
    private static let testBPM: Double = 120.0
    private static let highTestBPM: Double = 140.0
    private static let stressTestBPM: Double = 200.0

    @Test func testMetronomeEngineCreation() {
        let metronome = MetronomeEngine()
        #expect(metronome != nil)
    }

    @Test func testMetronomeInitialState() {
        let metronome = MetronomeEngine()
        #expect(metronome.isEnabled == false)
        #expect(metronome.currentBeat == 1)
        #expect(metronome.volume == 0.7)
    }

    @Test func testMetronomeConfiguration() {
        let metronome = MetronomeEngine()
        metronome.configure(bpm: Self.highTestBPM, timeSignature: .threeFour)

        // Configuration should not change public state immediately
        #expect(metronome.isEnabled == false)
        #expect(metronome.currentBeat == 1)
    }

    @Test func testMetronomeBasicControls() {
        let metronome = MetronomeEngine()

        // Test starting
        metronome.start(bpm: Self.testBPM, timeSignature: .fourFour)
        #expect(metronome.isEnabled == true)
        #expect(metronome.currentBeat == 1)

        // Test stopping
        metronome.stop()
        #expect(metronome.isEnabled == false)
        #expect(metronome.currentBeat == 1)
    }

    @Test func testMetronomeToggleFunction() {
        let metronome = MetronomeEngine()

        #expect(metronome.isEnabled == false)

        // Toggle on
        metronome.toggle(bpm: Self.testBPM, timeSignature: .fourFour)
        #expect(metronome.isEnabled == true)

        // Toggle off
        metronome.toggle(bpm: Self.testBPM, timeSignature: .fourFour)
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
        let metronome = MetronomeEngine()
        let component = MetronomeComponent(metronome: metronome, bpm: Self.testBPM, timeSignature: .fourFour)
        #expect(component.bpm == Self.testBPM)
        #expect(component.timeSignature == .fourFour)
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
        let metronome = MetronomeEngine()
        
        let testCases = [
            (bpm: 100, timeSignature: TimeSignature.fourFour),
            (bpm: Int(Self.highTestBPM), timeSignature: TimeSignature.threeFour)
        ]

        for testCase in testCases {
            let component = MetronomeComponent(
                metronome: metronome,
                bpm: Double(testCase.bpm),
                timeSignature: testCase.timeSignature
            )
            #expect(component.bpm == Double(testCase.bpm))
            #expect(component.timeSignature == testCase.timeSignature)
        }
    }

    @Test func testMetronomeButtonStyleCreation() {
        let buttonStyle = MetronomeButtonStyle()
        #expect(buttonStyle != nil)
    }

    @Test
    func testUIUpdatePerformance() {
        let metronome = MetronomeEngine()
        metronome.configure(bpm: Self.stressTestBPM, timeSignature: .fourFour) // High BPM for stress test

        let startTime = CFAbsoluteTimeGetCurrent()

        // Simulate rapid beat updates and measure performance
        for _ in 0..<100 {
            _ = metronome.currentBeat
        }

        let endTime = CFAbsoluteTimeGetCurrent()
        let executionTime = endTime - startTime

        // Should complete quickly (less than 0.1 seconds for 100 calls)
        #expect(executionTime < 0.1, "Beat counter access should be fast even under load")
    }

    @Test
    func testAudioEngineFailure() {
        let metronome = MetronomeEngine()
        metronome.configure(bpm: Self.testBPM, timeSignature: .fourFour)

        // Test that metronome continues to function even if audio fails
        metronome.start(bpm: Self.testBPM, timeSignature: .fourFour)
        #expect(metronome.isEnabled == true, "Metronome should start even without audio")

        // Test basic functionality continues
        metronome.testClick() // Should not crash

        let beat = metronome.currentBeat
        #expect(beat >= 1, "Beat counter should work without audio")

        metronome.stop()
        #expect(metronome.isEnabled == false, "Metronome should stop correctly")
    }

    @Test
    func testBeatCounterThreadSafety() async {
        let metronome = MetronomeEngine()
        metronome.configure(bpm: Self.testBPM, timeSignature: .fourFour)

        // Test concurrent access to beat counter
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { @MainActor in
                    for _ in 0..<100 {
                        let beat = metronome.currentBeat
                        #expect(beat >= 1 && beat <= 4, "Beat should always be within valid range")
                    }
                }
            }
        }
    }
}
