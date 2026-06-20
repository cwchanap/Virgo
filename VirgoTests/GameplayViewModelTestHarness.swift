//
//  GameplayViewModelTestHarness.swift
//  VirgoTests
//
//  Shared builders extracted from GameplayViewModelTests for the themed suites.
//

import Testing
import Foundation
import AVFoundation
import Observation
import SwiftUI
@testable import Virgo

@MainActor
enum GameplayViewModelTestHarness {

    static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    static func makeSilentWAVData(durationSeconds: Double = 2.0) -> Data {
        let sampleRate: UInt32 = 44_100
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let sampleCount = UInt32(max(1.0, durationSeconds * Double(sampleRate)))

        let blockAlign = channels * bitsPerSample / 8
        let byteRate = sampleRate * UInt32(blockAlign)
        let dataSize = sampleCount * UInt32(blockAlign)
        let chunkSize: UInt32 = 36 + dataSize

        var wavData = Data()
        wavData.append("RIFF".data(using: .ascii)!)
        appendLittleEndian(chunkSize, to: &wavData)
        wavData.append("WAVE".data(using: .ascii)!)
        wavData.append("fmt ".data(using: .ascii)!)
        appendLittleEndian(UInt32(16), to: &wavData)
        appendLittleEndian(UInt16(1), to: &wavData)
        appendLittleEndian(channels, to: &wavData)
        appendLittleEndian(sampleRate, to: &wavData)
        appendLittleEndian(byteRate, to: &wavData)
        appendLittleEndian(blockAlign, to: &wavData)
        appendLittleEndian(bitsPerSample, to: &wavData)
        wavData.append("data".data(using: .ascii)!)
        appendLittleEndian(dataSize, to: &wavData)
        wavData.append(Data(repeating: 0, count: Int(dataSize)))
        return wavData
    }

    static func makeSilentAudioPlayer(durationSeconds: Double = 5.0) throws -> AVAudioPlayer {
        try AVAudioPlayer(data: makeSilentWAVData(durationSeconds: durationSeconds))
    }

    static func createTestPracticeSettings() -> PracticeSettingsService {
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        return PracticeSettingsService(userDefaults: userDefaults)
    }

    /// Creates a test Chart with sample notes
    static func createTestChart(
        noteCount: Int = 4,
        measuresCount: Int = 1
    ) -> Chart {
        let chart = Chart(difficulty: .medium)

        // Add sample notes across measures
        for i in 0..<noteCount {
            let measureNumber = (i / 4) + 1
            let measureOffset = Double(i % 4) * 0.25
            let note = Note(
                interval: .quarter,
                noteType: i % 2 == 0 ? .bass : .snare,
                measureNumber: measureNumber,
                measureOffset: measureOffset
            )
            chart.notes.append(note)
        }

        return chart
    }

    /// Creates a test MetronomeEngine
    static func createTestMetronome() -> MetronomeEngine {
        return MetronomeEngine()
    }
}

@MainActor
extension GameplayViewModel {
    convenience init(chart: Chart, metronome: MetronomeEngine) {
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)
        self.init(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
    }
}

/// Metronome spy capturing `startAtTime` calls for scheduled-playback assertions.
@MainActor
final class ScheduledMetronomeSpy: MetronomeEngine {
    struct StartAtTimeCall {
        let bpm: Double
        let timeSignature: TimeSignature
        let startTime: TimeInterval
        let totalBeatsElapsed: Double
    }

    private(set) var startAtTimeCalls: [StartAtTimeCall] = []

    override func startAtTime(
        bpm: Double,
        timeSignature: TimeSignature,
        startTime: TimeInterval,
        totalBeatsElapsed: Double = 0
    ) {
        startAtTimeCalls.append(
            StartAtTimeCall(
                bpm: bpm,
                timeSignature: timeSignature,
                startTime: startTime,
                totalBeatsElapsed: totalBeatsElapsed
            )
        )
    }

    override func stop() {}

    override func getCurrentPlaybackTime() -> TimeInterval? {
        nil
    }
}
