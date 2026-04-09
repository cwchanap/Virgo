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

    static func makeHighScoreService() -> HighScoreService {
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        return HighScoreService(userDefaults: userDefaults)
    }

    static func makeMetronome(driver: RecordingAudioDriver? = nil) -> MetronomeEngine {
        MetronomeEngine(audioDriver: driver ?? RecordingAudioDriver())
    }

    static func makeChart(noteCount: Int = 4, interval: NoteInterval = .quarter, measureOffset stride: Double = 0.1) -> Chart {
        let chart = Chart(difficulty: .medium)
        for i in 0..<noteCount {
            let note = Note(
                interval: interval,
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
        settings: PracticeSettingsService? = nil,
        highScoreService: HighScoreService? = nil
    ) -> GameplayViewModel {
        let resolvedChart = chart ?? makeChart(noteCount: noteCount)
        let metronome = makeMetronome()
        let resolvedSettings = settings ?? makeSettings()
        let resolvedHighScoreService = highScoreService ?? makeHighScoreService()
        return GameplayViewModel(
            chart: resolvedChart,
            metronome: metronome,
            practiceSettings: resolvedSettings,
            highScoreService: resolvedHighScoreService
        )
    }

    /// Builds a fully-prepared view model suitable for deterministic render-path tests.
    ///
    /// Creates an eighth-note chart (measureOffset stride 0.25), then drives the
    /// normal view-model lifecycle (`loadChartData` → `setupGameplay`) so that all
    /// pre-computed layout caches are populated.  Pass `staticStaffLinesPresent: false`
    /// to cover the dynamic staff-lines fallback branch.
    static func makePreparedViewModel(staticStaffLinesPresent: Bool = true) async -> GameplayViewModel {
        let chart = makeChart(noteCount: 4, interval: .eighth, measureOffset: 0.25)
        let vm = GameplayViewModel(
            chart: chart,
            metronome: makeMetronome(),
            practiceSettings: makeSettings(),
            highScoreService: makeHighScoreService()
        )
        await vm.loadChartData()
        vm.setupGameplay()
        if !staticStaffLinesPresent {
            vm.staticStaffLinesView = nil
        }
        return vm
    }
}
