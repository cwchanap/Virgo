//
//  GameplayViewModelFullSpeedScoringTests.swift
//  VirgoTests
//
//  Verifies that completed runs are recorded and that only full-speed runs
//  set the all-time best.
//

import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("GameplayViewModel Full-Speed Scoring", .serialized)
@MainActor
struct GameplayViewModelFullSpeedScoringTests {

    private func makeChartInContext() throws -> Chart {
        let context = TestContainer.shared.context
        let song = Song(title: "S", artist: "A", bpm: 120, duration: "1:00", genre: "Rock")
        context.insert(song)
        let chart = Chart(difficulty: .medium, song: song)
        for i in 0..<4 {
            chart.notes.append(Note(
                interval: .quarter,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: Double(i) * 0.1
            ))
        }
        context.insert(chart)
        try context.save()
        return chart
    }

    @Test("Full-speed completion records an attempt and sets best")
    func testFullSpeedCompletionSetsBest() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeChartInContext()
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            let vm = GameplayViewModel(
                chart: chart,
                metronome: MetronomeEngine(audioDriver: RecordingAudioDriver()),
                practiceSettings: GameplayViewModelCoverageTestSupport.makeSettings(),
                scorePersistence: service
            )
            await vm.loadChartData()
            vm.setupGameplay(loadPersistedSpeed: false)
            vm.sessionAtFullSpeed = true
            for _ in 0..<4 { vm.scoreEngine.processHit(accuracy: .perfect, timingError: 0) }

            vm.handlePlaybackCompletion()

            #expect(vm.sessionIsNewRecord == true)
            #expect(service.bestScore(for: chart) > 0)
            #expect(chart.scoreRecords.count == 1)
        }
    }

    @Test("Slowed completion records history but does not set best")
    func testSlowedCompletionDoesNotSetBest() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeChartInContext()
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            let vm = GameplayViewModel(
                chart: chart,
                metronome: MetronomeEngine(audioDriver: RecordingAudioDriver()),
                practiceSettings: GameplayViewModelCoverageTestSupport.makeSettings(),
                scorePersistence: service
            )
            await vm.loadChartData()
            vm.setupGameplay(loadPersistedSpeed: false)
            vm.sessionAtFullSpeed = false
            for _ in 0..<4 { vm.scoreEngine.processHit(accuracy: .perfect, timingError: 0) }

            vm.handlePlaybackCompletion()

            #expect(vm.sessionIsNewRecord == false)
            #expect(service.bestScore(for: chart) == 0)
            #expect(chart.scoreRecords.count == 1)
        }
    }
}
