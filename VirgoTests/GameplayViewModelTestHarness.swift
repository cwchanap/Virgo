//
//  GameplayViewModelTestHarness.swift
//  VirgoTests
//
//  Shared builders extracted from GameplayViewModelTests for the themed suites.
//

import Testing
import Foundation
import AVFoundation
import Combine
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

    /// Creates a test Chart with sample notes.
    /// Notes are placed 4-per-measure (the historical layout), but the span is
    /// extended to at least `measuresCount` measures. This makes the previously
    /// ignored `measuresCount` parameter actually affect the generated chart
    /// (it widens the measure span when larger than the natural note-driven
    /// spread) without changing the default behavior existing tests rely on.
    static func createTestChart(
        noteCount: Int = 4,
        measuresCount: Int = 1
    ) -> Chart {
        let chart = Chart(difficulty: .medium)

        // Natural spread is ceil(noteCount/4) measures at 4 notes per measure.
        // Respect an explicit measuresCount by widening the span when requested.
        let naturalMeasures = max(1, (noteCount + 3) / 4)
        let effectiveMeasures = max(naturalMeasures, max(1, measuresCount))
        let notesPerMeasure = max(1, (noteCount + effectiveMeasures - 1) / effectiveMeasures)

        var noteIndex = 0
        for measure in 1...effectiveMeasures {
            let baseMeasureNumber = measure
            for beat in 0..<notesPerMeasure {
                guard noteIndex < noteCount else { break }
                let measureOffset = Double(beat) * 0.25
                let note = Note(
                    interval: .quarter,
                    noteType: noteIndex % 2 == 0 ? .bass : .snare,
                    measureNumber: baseMeasureNumber,
                    measureOffset: measureOffset
                )
                chart.notes.append(note)
                noteIndex += 1
            }
        }

        return chart
    }

    /// Creates a test MetronomeEngine
    static func createTestMetronome() -> MetronomeEngine {
        return MetronomeEngine()
    }

    /// A `GameplayCompletionScheduler` that fires the completion action on the
    /// next main-actor run-loop tick instead of waiting the real late-tolerance
    /// grace window. The grace-period delay is a production constant
    /// (`TimingAccuracy.good.toleranceMs`) that should not be re-measured by
    /// wall-clock in unit tests; this scheduler keeps completion-path tests
    /// deterministic under CI main-actor contention while still preserving the
    /// schedule-then-defer-then-fire semantics (the action never runs
    /// synchronously inside `updateContinuousVisuals`).
    static func immediateCompletionScheduler() -> GameplayCompletionScheduler {
        { _, action in
            let task = Task { @MainActor in action() }
            return AnyCancellable { task.cancel() }
        }
    }
}

@MainActor
extension GameplayViewModel {
    convenience init(chart: Chart, metronome: MetronomeEngine) {
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)
        self.init(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
    }

    convenience init(
        chart: Chart,
        metronome: MetronomeEngine,
        completionScheduler: @escaping GameplayCompletionScheduler
    ) {
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)
        self.init(
            chart: chart,
            metronome: metronome,
            practiceSettings: practiceSettings,
            scorePersistence: ScorePersistenceService.makeInMemory(),
            completionScheduler: completionScheduler
        )
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
