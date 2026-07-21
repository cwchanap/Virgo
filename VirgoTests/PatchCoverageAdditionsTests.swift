//
//  PatchCoverageAdditionsTests.swift
//  VirgoTests
//
//  Targeted coverage for lines added in the gameplay-timing-navigation-and-coverage
//  patch that were not exercised by the existing suite.
//

import Testing
import Foundation
import AVFoundation
import SwiftUI
import SwiftData
@testable import Virgo

// MARK: - GameplayViewModel patch coverage

@Suite("GameplayViewModel Patch Coverage", .serialized)
@MainActor
struct GameplayViewModelPatchCoverageTests {

    @Test("startPlayback is rejected when gameplay is not prepared")
    func testStartPlaybackRejectedWhenNotPrepared() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        defer { vm.cleanup() }

        // Data is loaded but setupGameplay() has not run, so isGameplayPrepared is false.
        #expect(vm.isDataLoaded)
        #expect(!vm.isGameplayPrepared)

        vm.startPlayback()

        #expect(!vm.isPlaying, "Playback must not start before gameplay is prepared")
    }

    @Test("updatePlaybackProgress throttles rapid ticks and publishes on completion")
    func testPlaybackProgressThrottling() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay()
        defer { vm.cleanup() }

        vm.isPlaying = true
        vm.updateContinuousVisualsForTesting(elapsedTime: 0.0)
        let firstProgress = vm.playbackProgress
        #expect(firstProgress == 0.0)

        // A tiny elapsed delta within the publish interval must be throttled.
        vm.updateContinuousVisualsForTesting(elapsedTime: 0.01)
        #expect(vm.playbackProgress == firstProgress, "Sub-threshold tick should not publish progress")

        // A delta beyond the publish interval should update progress.
        vm.updateContinuousVisualsForTesting(elapsedTime: 0.2)
        #expect(vm.playbackProgress > firstProgress, "Larger tick should publish progress")

        // Reaching the end of the track must publish completion even if the delta is small.
        let duration = vm.cachedTrackDuration
        vm.updateContinuousVisualsForTesting(elapsedTime: duration + 1.0)
        #expect(vm.playbackProgress == 1.0, "Completion tick should clamp progress to 1.0")
    }

    @Test("updatePurpleBarPosition follows continuous timeline progress")
    func testPurpleBarPositionMovesAcrossSubBeatTicks() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay()
        defer { vm.cleanup() }

        vm.isPlaying = true
        vm.updatePurpleBarPosition(elapsedTime: 0.05)
        let firstPosition = vm.purpleBarPosition

        vm.updatePurpleBarPosition(elapsedTime: 0.06)
        #expect(!Self.samePosition(vm.purpleBarPosition, firstPosition))
    }

    @Test("calculateBGMOffset uses persisted DTX bgmStartOffsetSeconds scaled by speed")
    func testCalculateBGMOffsetUsesDTXStartOffset() async throws {
        let chart = GameplayViewModelCoverageTestSupport.makeChart(noteCount: 4)
        chart.notes.forEach { $0.originKind = .dtx }
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(chart: chart)
        await vm.loadChartData()
        vm.setupGameplay()
        defer { vm.cleanup() }

        let song = SwiftUICoverageFixtures.makeSong(bgmFilePath: nil, previewFilePath: nil)
        song.bgmStartOffsetSeconds = 2.0
        vm.cachedSong = song

        let offset = vm.calculateBGMOffset()
        #expect(abs(offset - 2.0) < 0.001, "At 1.0x speed the DTX BGM offset should pass through unscaled")

        vm.practiceSettings.setSpeed(0.5)
        let scaledOffset = vm.calculateBGMOffset()
        #expect(abs(scaledOffset - 4.0) < 0.001, "At 0.5x speed the offset should double in timeline seconds")
    }

    @Test("updateRowWidth before gameplay preparation caches width without rebuilding layout")
    func testUpdateRowWidthBeforePreparationCachesOnly() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        defer { vm.cleanup() }

        #expect(!vm.isGameplayPrepared)
        let beforeWidth = vm.cachedLayoutRowWidth

        vm.updateRowWidth(1400)

        #expect(vm.cachedLayoutRowWidth > beforeWidth,
                "Width should be cached even before gameplay is prepared")
    }

    @Test("calculateElapsedTime prefers live BGM playback time when available")
    func testCalculateElapsedTimeUsesBGMPlaybackTime() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay()
        defer { vm.cleanup() }

        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer(durationSeconds: 5)
        _ = player.prepareToPlay()
        player.currentTime = 1.0
        vm.bgmPlayer = player
        vm.isPlaying = true

        let elapsed = vm.calculateElapsedTime()
        #expect(elapsed != nil, "calculateElapsedTime should return a value when BGM is playing")
        if let elapsed {
            #expect(elapsed > 0, "Elapsed time should reflect the BGM player position")
        }
    }

    private static func makeSilentPlayer() -> AVAudioPlayer? {
        let wav = SilentWAVFactory.makeMonoPCM()
        return try? AVAudioPlayer(data: wav)
    }

    private static func samePosition(
        _ lhs: (x: Double, y: Double)?,
        _ rhs: (x: Double, y: Double)?
    ) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case let (.some(l), .some(r)):
            return abs(l.x - r.x) < 0.0001 && abs(l.y - r.y) < 0.0001
        default: return false
        }
    }
}

// MARK: - MetronomeTimingEngine static helper coverage

@Suite("MetronomeTimingEngine Static Helpers")
struct MetronomeTimingEngineStaticHelperTests {

    @Test("beatInMeasure wraps within the time signature")
    func testBeatInMeasureWraps() {
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: 1, timeSignature: .fourFour) == 1)
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: 4, timeSignature: .fourFour) == 4)
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: 5, timeSignature: .fourFour) == 1)
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: 1, timeSignature: .threeFour) == 1)
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: 4, timeSignature: .threeFour) == 1)
    }

    @Test("beatInMeasure clamps non-positive beat numbers")
    func testBeatInMeasureClampsNonPositive() {
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: 0, timeSignature: .fourFour) == 1)
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: -3, timeSignature: .fourFour) == 1)
    }

    @Test("completedBeatCount floors finite beats and guards non-finite input")
    func testCompletedBeatCount() {
        #expect(MetronomeTimingEngine.completedBeatCount(forTotalBeatsElapsed: 0.0) == 0)
        #expect(MetronomeTimingEngine.completedBeatCount(forTotalBeatsElapsed: 3.9) == 3)
        #expect(MetronomeTimingEngine.completedBeatCount(forTotalBeatsElapsed: -5.0) == 0)
        #expect(MetronomeTimingEngine.completedBeatCount(forTotalBeatsElapsed: .infinity) == 0)
        #expect(MetronomeTimingEngine.completedBeatCount(forTotalBeatsElapsed: .nan) == 0)
    }

    @Test("firstFiredBeatNumber returns the next beat boundary")
    func testFirstFiredBeatNumber() {
        #expect(MetronomeTimingEngine.firstFiredBeatNumber(afterTotalBeatsElapsed: 0.0) == 1)
        #expect(MetronomeTimingEngine.firstFiredBeatNumber(afterTotalBeatsElapsed: 3.0) == 4)
        #expect(MetronomeTimingEngine.firstFiredBeatNumber(afterTotalBeatsElapsed: 3.2) == 5)
        #expect(MetronomeTimingEngine.firstFiredBeatNumber(afterTotalBeatsElapsed: -1.0) == 1)
        #expect(MetronomeTimingEngine.firstFiredBeatNumber(afterTotalBeatsElapsed: .infinity) == 1)
    }

    @Test("audioTime returns nil for a stale beat time that clamps to mach zero")
    func testAudioTimeNilForStaleBeat() {
        let audioTime = MetronomeTimingEngine.audioTime(forIdealBeatTime: 999.0)
        #expect(audioTime == nil, "A beat time before the reference should not produce a valid audio time")
    }

    @Test("audioTime returns a valid time for a future beat")
    func testAudioTimeValidForFutureBeat() {
        let futureTime = CFAbsoluteTimeGetCurrent() + 1.0
        let audioTime = MetronomeTimingEngine.audioTime(forIdealBeatTime: futureTime)
        #expect(audioTime != nil)
        #expect(audioTime?.isHostTimeValid == true)
    }
}

// MARK: - LocalDTXFixtureImporter error-path coverage

@Suite("LocalDTXFixtureImporter Error Paths", .serialized)
@MainActor
struct LocalDTXFixtureImporterErrorPathTests {

    @Test("importSong throws missingSETFile when the folder has no SET.def")
    func testThrowsMissingSETFile() throws {
        let store = try makeStore()
        let tempDir = makeTempDirectory()

        #expect(throws: LocalDTXFixtureImportError.self) {
            try LocalDTXFixtureImporter.importSong(from: tempDir, into: store.context)
        }
    }

    @Test("importSong throws unreadableSETFile when SET.def cannot be decoded")
    func testThrowsUnreadableSETFile() throws {
        let store = try makeStore()
        let tempDir = makeTempDirectory()

        // 0xFE 0xFF is a UTF-16 BOM but the following bytes are not valid UTF-16,
        // Shift-JIS, or UTF-8, so every decoding fallback fails.
        let garbage = Data([0xFE, 0xFF, 0x00, 0x01, 0x80, 0x81])
        try garbage.write(to: tempDir.appendingPathComponent("SET.def"))

        #expect(throws: LocalDTXFixtureImportError.self) {
            try LocalDTXFixtureImporter.importSong(from: tempDir, into: store.context)
        }
    }

    @Test("importSong throws noPlayableCharts when referenced chart files are missing")
    func testThrowsNoPlayableCharts() throws {
        let store = try makeStore()
        let tempDir = makeTempDirectory()

        let setDef = """
        #TITLE: No Charts
        #L1LABEL: BASIC
        #L1FILE: missing.dtx
        """
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf8)

        #expect(throws: LocalDTXFixtureImportError.self) {
            try LocalDTXFixtureImporter.importSong(from: tempDir, into: store.context)
        }
    }

    @Test("importBundledSoukyuuIfAvailable returns nil when the bundle has no SET.def")
    func testReturnsNilWhenBundleLacksSETDef() throws {
        let store = try makeStore()
        // The unit-test bundle does not bundle a SET.def resource.
        let result = try LocalDTXFixtureImporter.importBundledSoukyuuIfAvailable(
            into: store.context,
            bundle: Bundle(for: DTXFixtureTestBundleAnchor.self)
        )
        #expect(result == nil)
    }

    @Test("importSong imports a UTF-8 SET.def with a single chart and no audio assets")
    func testImportsUTF8FixtureWithoutAudio() throws {
        let store = try makeStore()
        let tempDir = makeTempDirectory()

        let setDef = """
        #TITLE: UTF8 Fixture
        #L1LABEL: BASIC
        #L1FILE: chart.dtx
        """
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf8)

        let chartContent = "#TITLE: UTF8 Fixture\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 50\n#03113: 01000000"
        try chartContent.write(
            to: tempDir.appendingPathComponent("chart.dtx"),
            atomically: true,
            encoding: .utf8
        )

        let song = try LocalDTXFixtureImporter.importSong(from: tempDir, into: store.context)

        #expect(song.title == "UTF8 Fixture")
        #expect(song.charts.count == 1)
        #expect(song.charts.first?.difficulty == .easy)
        #expect(song.bgmFilePath == nil, "No bgm.m4a present -> path should be nil")
        #expect(song.previewFilePath == nil, "No preview.mp3 present -> path should be nil")
    }

    @Test("re-importing an existing fixture without audio changes performs no-op refresh")
    func testReimportWithoutAudioChangeIsNoOp() throws {
        let store = try makeStore()
        let tempDir = makeTempDirectory()

        let setDef = """
        #TITLE: Noop Fixture
        #L1LABEL: BASIC
        #L1FILE: chart.dtx
        """
        try setDef.write(to: tempDir.appendingPathComponent("SET.def"), atomically: true, encoding: .utf8)
        let chartContent = "#TITLE: Noop Fixture\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 50\n#03113: 01000000"
        try chartContent.write(
            to: tempDir.appendingPathComponent("chart.dtx"),
            atomically: true,
            encoding: .utf8
        )

        let first = try LocalDTXFixtureImporter.importSong(from: tempDir, into: store.context)
        let firstBGM = first.bgmFilePath
        let second = try LocalDTXFixtureImporter.importSong(from: tempDir, into: store.context)

        #expect(second === first, "Re-import should return the existing song")
        #expect(second.bgmFilePath == firstBGM)
        let songs = try store.context.fetch(FetchDescriptor<Song>())
        #expect(songs.count == 1)
    }

    private struct TestStore {
        let container: ModelContainer
        let context: ModelContext
    }

    private func makeStore() throws -> TestStore {
        let schema = Schema([
            Song.self, Chart.self, Note.self, ChartControlEvent.self,
            ServerSong.self, ServerChart.self, ScoreRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // Container must be retained for the lifetime of the context; ModelContext
        // does not strongly retain its ModelContainer, and using a context whose
        // backing container has been deallocated crashes under `xcodebuild test`.
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return TestStore(container: container, context: container.mainContext)
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-dtx-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

// MARK: - SwiftUI render coverage for patched views

@Suite("Patch Render Coverage", .serialized)
@MainActor
struct PatchRenderCoverageTests {

    @Test("ChartSelectionCard renders the difficulty play button content")
    func testChartSelectionCardRenders() async throws {
        try await TestSetup.withTestSetup {
            let chart = SwiftUICoverageFixtures.makeChart(difficulty: .hard, level: 70)
            chart.bestScore = 12_500
            let card = ChartSelectionCard(chart: chart, onSelect: {})

            SwiftUITestUtilities.assertView(
                card,
                containsStrings: ["Level 70", "HARD"],
                size: CGSize(width: 360, height: 120)
            )
        }
    }

    @Test("MainMenuView renders the start menu without entering ContentView")
    func testMainMenuViewRendersStartMenu() async throws {
        try await TestSetup.withTestSetup {
            let menu = MainMenuView()

            SwiftUITestUtilities.assertView(
                menu,
                containsStrings: ["VIRGO", "START"],
                size: CGSize(width: 1024, height: 768)
            )
        }
    }

    @Test("GameplayView renders the purple bar overlay when a position is set")
    func testGameplayViewRendersPurpleBarOverlay() async throws {
        try await TestSetup.withTestSetup {
            let vm = await GameplayViewModelCoverageTestSupport.makePreparedViewModel()
            defer { vm.cleanup() }
            vm.isPlaying = true
            vm.updatePurpleBarPosition(elapsedTime: 0.01)
            #expect(vm.purpleBarPosition != nil, "Fixture must produce a purple bar position")

            let view = GameplayView(chart: vm.chart, metronome: vm.metronome, initialViewModel: vm)
                .environmentObject(vm.practiceSettings)

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    @Test("GameplayView prepares gameplay via the .task lifecycle when no viewModel is injected")
    func testGameplayViewPrepareGameplayViaTaskLifecycle() async throws {
        try await TestSetup.withTestSetup {
            let chart = GameplayViewModelCoverageTestSupport.makeChart(noteCount: 4)
            let metronome = GameplayViewModelCoverageTestSupport.makeMetronome()
            let settings = GameplayViewModelCoverageTestSupport.makeSettings()

            let view = GameplayView(chart: chart, metronome: metronome)
                .environmentObject(settings)

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
            // Allow the .task-driven async preparation to complete.
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
    }

    @Test("ContentView mounts and runs the startup onAppear with the tab shell")
    func testContentViewMountsAndRunsStartupOnAppear() async throws {
        try await TestSetup.withTestSetup {
            let metronome = MetronomeEngine(audioDriver: RecordingAudioDriver())
            let container = TestContainer.shared.container

            let view = ContentView()
                .environmentObject(metronome)
                .modelContainer(container)

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 800)
            )
            // Let the synchronous onAppear body and queued startup tasks settle.
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }
}

// MARK: - Silent WAV fixture

/// Anchor class used to resolve the unit-test bundle (which has no SET.def resource).
private final class DTXFixtureTestBundleAnchor {}

private enum SilentWAVFactory {
    /// Builds a minimal valid mono 16-bit PCM WAV (44-byte header + 4 silent samples)
    /// suitable for initializing an `AVAudioPlayer` in unit tests.
    static func makeMonoPCM() -> Data {
        let sampleRate: UInt32 = 44_100
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        // 1 second of silence so currentTime can be set to a positive value.
        let dataBytes: UInt32 = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(uint32(36 + dataBytes))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(uint32(16))
        data.append(uint16(1))
        data.append(uint16(channels))
        data.append(uint32(sampleRate))
        data.append(uint32(byteRate))
        data.append(uint16(blockAlign))
        data.append(uint16(bitsPerSample))
        data.append("data".data(using: .ascii)!)
        data.append(uint32(dataBytes))
        data.append(contentsOf: [UInt8](repeating: 0, count: Int(dataBytes)))
        return data
    }

    private static func uint32(_ value: UInt32) -> Data {
        Data([value, value >> 8, value >> 16, value >> 24].map { UInt8($0 & 0xFF) })
    }

    private static func uint16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }
}
