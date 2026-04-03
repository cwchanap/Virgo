//
//  GameplayViewModelCoverageTestSupport.swift
//  VirgoTests
//

import Foundation
@testable import Virgo

@MainActor
enum GameplayViewModelCoverageTestSupport {
    static func makeSettings() -> PracticeSettingsService {
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        return PracticeSettingsService(userDefaults: userDefaults)
    }

    static func makeMetronome(driver: RecordingAudioDriver? = nil) -> MetronomeEngine {
        MetronomeEngine(audioDriver: driver ?? RecordingAudioDriver())
    }

    static func makeChart(noteCount: Int = 4, measureOffset stride: Double = 0.1) -> Chart {
        let chart = Chart(difficulty: .medium)
        for i in 0..<noteCount {
            let note = Note(
                interval: .quarter,
                noteType: i.isMultiple(of: 2) ? .bass : .snare,
                measureNumber: 1,
                measureOffset: Double(i) * stride
            )
            chart.notes.append(note)
        }
        return chart
    }

    static func makeViewModel(
        chart: Chart? = nil,
        noteCount: Int = 4,
        settings: PracticeSettingsService? = nil
    ) -> GameplayViewModel {
        let resolvedChart = chart ?? makeChart(noteCount: noteCount)
        let metronome = makeMetronome()
        let resolvedSettings = settings ?? makeSettings()
        return GameplayViewModel(
            chart: resolvedChart,
            metronome: metronome,
            practiceSettings: resolvedSettings
        )
    }
}
