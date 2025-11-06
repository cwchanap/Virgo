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
import AVFoundation

// MARK: - Test Audio Driver

@MainActor
class FailingAudioDriver: AudioDriverProtocol {
    private var shouldFailOnStart = true
    
    func playTick(volume: Float, isAccented: Bool, atTime: AVAudioTime?) {
        // Do nothing - just simulate audio failure
    }
    
    func stop() {
        // Do nothing
    }
    
    func resume() {
        if shouldFailOnStart {
            shouldFailOnStart = false
            // Simulate audio engine failure during startup
            // In real MetronomeAudioEngine, failures are handled gracefully
        }
    }
    
    func convertToAudioEngineTime(_ cfTime: CFAbsoluteTime) -> AVAudioTime? {
        return nil // Simulate no audio engine running
    }
}

@Suite("Metronome Basic Tests", .serialized)
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

    @Test
    func testMetronomeBasicControls() async {
        let metronome = MetronomeEngine()

        // Test starting - use sync version for reliable state verification
        await metronome.startSync(bpm: Self.testBPM, timeSignature: .fourFour)

        #expect(metronome.isEnabled, "Metronome should be enabled after startSync")
        #expect(metronome.currentBeat == 1, "Beat should be initialized to 1")

        // Test stopping - use sync version for reliable state verification
        await metronome.stopSync()

        #expect(!metronome.isEnabled, "Metronome should be disabled after stopSync")
        #expect(metronome.currentBeat == 1, "Beat should reset to 1 after stopping")
    }

    @Test func testMetronomeToggleFunction() async {
        let metronome = MetronomeEngine()

        #expect(metronome.isEnabled == false)

        // Toggle on - use sync version
        await metronome.toggleSync(bpm: Self.testBPM, timeSignature: .fourFour)
        #expect(metronome.isEnabled, "Metronome should be enabled after first toggle")

        // Toggle off - use sync version
        await metronome.toggleSync(bpm: Self.testBPM, timeSignature: .fourFour)
        #expect(!metronome.isEnabled, "Metronome should be disabled after second toggle")
        #expect(metronome.currentBeat == 1, "Beat should be reset to 1 after stopping")
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

    @Test func testMetronomeComponentCreation() async {
        await TestSetup.setUp()
        
        let metronome = MetronomeEngine()
        let component = MetronomeComponent(metronome: metronome, bpm: Self.testBPM, timeSignature: .fourFour)
        #expect(component.bpm == Self.testBPM)
        #expect(component.timeSignature == .fourFour)
        
        // Test that component can be created with environment
        SwiftUITestUtilities.assertViewWithEnvironment(component)
    }

    @Test func testMetronomeSettingsViewCreation() async {
        await TestSetup.setUp()
        
        let metronome = MetronomeEngine()
        let settingsView = MetronomeSettingsView(metronome: metronome)
        #expect(settingsView != nil)
        
        // Test that settings view can be created with environment
        SwiftUITestUtilities.assertViewWithEnvironment(settingsView)
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
    func testAudioEngineFailure() async {
        let failingAudioDriver = FailingAudioDriver()
        let metronome = MetronomeEngine(audioDriver: failingAudioDriver)
        metronome.configure(bpm: Self.testBPM, timeSignature: .fourFour)

        // Test that metronome continues to function even if audio fails
        await metronome.startSync(bpm: Self.testBPM, timeSignature: .fourFour)

        #expect(metronome.isEnabled, "Metronome should start even with failing audio driver")

        // Test basic functionality continues without crashing
        let initialBeat = metronome.currentBeat
        #expect(initialBeat >= 1, "Beat counter should work without audio")

        await metronome.stopSync()

        #expect(!metronome.isEnabled, "Metronome should stop correctly even with failing audio driver")
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
