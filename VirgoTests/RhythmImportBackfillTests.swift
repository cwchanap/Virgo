//
//  RhythmImportBackfillTests.swift
//  VirgoTests
//

import Foundation
import SwiftData
import Testing
@testable import Virgo

@Suite("Rhythm Import and Backfill", .serialized)
@MainActor
struct RhythmImportBackfillTests {
    @Test("failed local import rolls back the inserted graph before a later save")
    func failedLocalImportRollsBackInsertedGraph() throws {
        let testContainer = TestContainer.isolatedContainer()
        let context = testContainer.context
        let folder = try makeFixtureFolder(includeSecondChart: false)

        #expect(throws: TestFailure.saveFailed) {
            try LocalDTXFixtureImporter.importSongResult(
                from: folder,
                into: context,
                save: { _ in throw TestFailure.saveFailed }
            )
        }

        #expect(!context.hasChanges)
        context.insert(Song(
            title: "Unrelated", artist: "Tester", bpm: 120, duration: "1:00", genre: "Manual"
        ))
        try context.save()

        let reopened = ModelContext(testContainer.container)
        let songs = try reopened.fetch(FetchDescriptor<Song>())
        #expect(songs.map(\.title) == ["Unrelated"])
        #expect(try reopened.fetch(FetchDescriptor<Chart>()).isEmpty)
        #expect(try reopened.fetch(FetchDescriptor<Note>()).isEmpty)
        #expect(try reopened.fetch(FetchDescriptor<ChartControlEvent>()).isEmpty)
    }

    @Test("valid DTX projection carries exact metadata and canonical note/control timing")
    func validProjectionCarriesCanonicalTiming() throws {
        let chartData = try DTXFileParser.parseChartMetadata(from: """
        #TITLE: Variable Meter
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 55
        #VIRGO_TIME_SIGNATURE: 6/8
        #VIRGO_CONTROL: 1
        #00102: 0.5
        #00001: 0001
        #00012: 01000000
        #00122: 00160000
        #00113: 00000100
        """)

        let projection = try chartData.persistenceProjection()

        #expect(projection.timeSignature == .sixEight)
        #expect(projection.chartMetadata.timeSignature == .sixEight)
        #expect(projection.chartMetadata.timingStatus == .valid)
        let expectedAnchor = try RhythmSourceAnchor(
            measureIndex: 0,
            gridPosition: 1,
            gridSize: 2
        )
        #expect(projection.chartMetadata.bgmStartAnchor == expectedAnchor)
        #expect(projection.warning == nil)

        #expect(projection.notes.count == 2)
        #expect(projection.notes[0].normalizedMeasureIndex == 0)
        #expect(projection.notes[0].normalizedAbsoluteTick == 0)
        #expect(projection.notes[0].normalizedTickWithinMeasure == 0)
        #expect(projection.notes[0].normalizedTicksPerMeasure == 12)
        // The only later playable onset is in the lower voice, so it cannot
        // provide duration evidence for this terminal upper-voice note.
        #expect(projection.notes[0].visualDurationCandidate == nil)
        #expect(projection.notes[1].normalizedMeasureIndex == 1)
        #expect(projection.notes[1].normalizedAbsoluteTick == 16)
        #expect(projection.notes[1].normalizedTickWithinMeasure == 4)
        #expect(projection.notes[1].normalizedTicksPerMeasure == 8)
        #expect(projection.notes[1].visualDurationCandidate == nil)

        #expect(projection.controls.count == 1)
        #expect(projection.controls[0].normalizedMeasureIndex == 1)
        #expect(projection.controls[0].normalizedAbsoluteTick == 14)
        #expect(projection.controls[0].normalizedTickWithinMeasure == 2)
        #expect(projection.controls[0].normalizedTicksPerMeasure == 8)
    }

    @Test("timing-fatal DTX projection retains identity and clears canonical timing")
    func fatalProjectionRetainsIdentityWithoutCanonicalTiming() throws {
        let chartData = try DTXFileParser.parseChartMetadata(from: """
        #TITLE: Fatal Timing
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 55
        #VIRGO_CONTROL: 1
        #00102: 0
        #00112: 0100
        #00122: 0016
        """)

        let projection = try chartData.persistenceProjection()

        #expect(projection.chartMetadata.timingStatus == .fatal)
        #expect(projection.warning != nil)
        #expect(projection.notes.count == 1)
        #expect(projection.notes[0].sourceLaneID == "12")
        #expect(projection.notes[0].sourceNoteID == "01")
        #expect(projection.notes[0].sourceGridPosition == 0)
        #expect(projection.notes[0].sourceGridSize == 2)
        #expect(projection.notes[0].interval == .quarter)
        #expect(projection.notes[0].visualDurationCandidate == nil)
        #expect(projection.notes[0].normalizedMeasureIndex == nil)
        #expect(projection.notes[0].normalizedAbsoluteTick == nil)
        #expect(projection.notes[0].normalizedTickWithinMeasure == nil)
        #expect(projection.notes[0].normalizedTicksPerMeasure == nil)

        #expect(projection.controls.count == 1)
        #expect(projection.controls[0].sourceLaneID == "22")
        #expect(projection.controls[0].sourceNoteID == "16")
        #expect(projection.controls[0].normalizedMeasureIndex == nil)
        #expect(projection.controls[0].normalizedAbsoluteTick == nil)
        #expect(projection.controls[0].normalizedTickWithinMeasure == nil)
        #expect(projection.controls[0].normalizedTicksPerMeasure == nil)
    }

    @Test("cross-voice onset cannot invent a terminal upper-voice duration")
    func crossVoiceOnsetStaysIndeterminateThroughBackfillAndLayout() async throws {
        let folder = try makeVoiceScopedDurationFixtureFolder()
        let chartURL = folder.appendingPathComponent("first.dtx")
        let chartData = try DTXFileParser.parseChartMetadata(from: chartURL)
        let projection = try chartData.persistenceProjection()

        #expect(projection.notes.map(\.sourceLaneID) == ["12", "11", "13"])
        #expect(projection.notes.map(\.normalizedAbsoluteTick) == [0, 0, 1])
        #expect(projection.notes.map(\.notationVoiceCandidate) == [.upper, .upper, .lower])
        #expect(projection.notes.map(\.visualDurationCandidate) == [nil, nil, nil])

        let testContainer = TestContainer.isolatedContainer()
        let context = testContainer.context
        let song = Song(
            title: "Voice-scoped durations",
            artist: "Tester",
            bpm: 120,
            duration: "0:01",
            genre: "DTX Import",
            isServerImported: true,
            serverSongId: folder.lastPathComponent
        )
        let chart = Chart(difficulty: .easy, level: 40, song: song)
        chart.notes = projection.notes.map { values in
            let note = values.makeNote(for: chart)
            note.normalizedMeasureIndex = nil
            note.normalizedAbsoluteTick = nil
            note.normalizedTickWithinMeasure = nil
            note.normalizedTicksPerMeasure = nil
            note.notationVoiceCandidate = nil
            note.visualDurationCandidate = nil
            return note
        }
        song.charts = [chart]
        context.insert(song)
        try context.save()

        let (defaults, _) = TestUserDefaults.makeIsolated(
            suiteName: "RhythmBackfill.voice-scoped.\(UUID().uuidString)"
        )
        try LocalDTXFixtureImporter.backfillRhythmTiming(
            for: song,
            from: folder,
            in: context,
            versionStore: RhythmBackfillVersionStore(userDefaults: defaults)
        )

        #expect(Set(chart.safeNotes.compactMap(\.sourceLaneID)) == Set(["12", "11", "13"]))
        #expect(chart.safeNotes.allSatisfy { $0.visualDurationCandidate == nil })

        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        let snapshot = try #require(viewModel.cachedRhythmRuntime.layoutSnapshot)
        let upperNotes = snapshot.notes.filter { $0.sourceLaneID == "12" || $0.sourceLaneID == "11" }

        #expect(upperNotes.count == 2)
        #expect(upperNotes.allSatisfy {
            $0.rhythm.support == .indeterminate(.indeterminateTerminalDuration)
        })
        guard case let .unsupported(warningCodes) = snapshot.measures.first?.engravingSupport else {
            Issue.record("Expected the terminal upper voice to mark its measure unsupported")
            return
        }
        #expect(warningCodes.contains(.indeterminateTerminalDuration))

        viewModel.setupGameplay(loadPersistedSpeed: false)
        let upperHeadIDs = Set(viewModel.cachedNotationLayout.noteHeads.compactMap { head in
            upperNotes.contains { $0.eventID == head.eventID } ? head.id : nil
        })
        #expect(!upperHeadIDs.isEmpty)
        #expect(viewModel.cachedNotationLayout.stems.allSatisfy {
            upperHeadIDs.isDisjoint(with: $0.noteHeadIDs)
        })
        #expect(viewModel.cachedNotationLayout.beams.allSatisfy {
            upperHeadIDs.isDisjoint(with: $0.noteHeadIDs)
        })
        #expect(viewModel.cachedNotationLayout.flags.allSatisfy { !upperHeadIDs.contains($0.noteHeadID) })
        #expect(viewModel.cachedNotationLayout.rhythmDots.allSatisfy { dot in
            guard case let .event(eventID) = dot.source else { return true }
            return !upperNotes.contains { $0.eventID == eventID }
        })
        #expect(viewModel.cachedNotationLayout.tuplets.allSatisfy { tuplet in
            Set(tuplet.memberEventIDs).isDisjoint(with: upperNotes.map(\.eventID))
        })
        viewModel.cleanup()
    }

    @Test("backfill updates only source-backed nil payloads, saves once, and skips a completed version")
    func backfillIsSelectiveTransactionalAndIdempotent() throws {
        let context = TestContainer.isolatedContainer().context
        let folder = try makeFixtureFolder(includeSecondChart: true)
        let song = Song(
            title: "Legacy", artist: "Tester", bpm: 120, duration: "1:00",
            genre: "DTX Import", isServerImported: true, serverSongId: folder.lastPathComponent
        )
        let legacyChart = sourceBackedChart(difficulty: .easy, level: 40, song: song)
        let manualChart = Chart(
            difficulty: .easy,
            level: 40,
            notes: [Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)],
            song: song
        )
        let corruptChart = sourceBackedChart(difficulty: .medium, level: 50, song: song)
        corruptChart.rhythmMetadataData = Data("corrupt".utf8)
        song.charts = [manualChart, corruptChart, legacyChart]
        context.insert(song)
        try context.save()

        let (defaults, _) = TestUserDefaults.makeIsolated(
            suiteName: "RhythmBackfill.selective.\(UUID().uuidString)"
        )
        let store = RhythmBackfillVersionStore(userDefaults: defaults)
        var parseCount = 0
        var saveCount = 0

        try LocalDTXFixtureImporter.backfillRhythmTiming(
            for: song,
            from: folder,
            in: context,
            versionStore: store,
            parseChart: { url in
                parseCount += 1
                return try DTXFileParser.parseChartMetadata(from: url)
            },
            save: { modelContext in
                saveCount += 1
                try modelContext.save()
            }
        )

        #expect(parseCount == 1)
        #expect(saveCount == 1)
        #expect(store.completedVersion() == RhythmBackfillVersionStore.currentVersion)
        #expect(legacyChart.rhythmMetadataData != nil)
        #expect(legacyChart.notes.first?.normalizedMeasureIndex == 0)
        #expect(legacyChart.notes.first?.normalizedAbsoluteTick == 0)
        #expect(legacyChart.notes.first?.normalizedTickWithinMeasure == 0)
        #expect(legacyChart.notes.first?.normalizedTicksPerMeasure == 4)
        #expect(legacyChart.controlEvents.first?.normalizedAbsoluteTick == 1)
        #expect(manualChart.rhythmMetadataData == nil)
        #expect(corruptChart.rhythmMetadataData == Data("corrupt".utf8))

        try LocalDTXFixtureImporter.backfillRhythmTiming(
            for: song,
            from: folder,
            in: context,
            versionStore: store,
            parseChart: { _ in
                Issue.record("Completed backfill must not reparse DTX")
                throw TestFailure.unexpectedParse
            },
            save: { _ in
                Issue.record("Completed backfill must not save")
                throw TestFailure.unexpectedSave
            }
        )
        #expect(parseCount == 1)
        #expect(saveCount == 1)
    }

    @Test("backfill applies one equivalent projection to every duplicate source-backed chart")
    func backfillUpdatesAllEquivalentDuplicateCharts() throws {
        let context = TestContainer.isolatedContainer().context
        let folder = try makeFixtureFolder(includeSecondChart: false)
        let song = Song(
            title: "Duplicates", artist: "Tester", bpm: 120, duration: "1:00",
            genre: "DTX Import", isServerImported: true, serverSongId: folder.lastPathComponent
        )
        let first = sourceBackedChart(difficulty: .easy, level: 40, song: song)
        let second = sourceBackedChart(difficulty: .easy, level: 40, song: song)
        let manual = Chart(
            difficulty: .easy,
            level: 40,
            notes: [Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)],
            song: song
        )
        song.charts = [second, manual, first]
        context.insert(song)
        try context.save()

        let (defaults, _) = TestUserDefaults.makeIsolated(
            suiteName: "RhythmBackfill.duplicates.\(UUID().uuidString)"
        )
        let store = RhythmBackfillVersionStore(userDefaults: defaults)

        try LocalDTXFixtureImporter.backfillRhythmTiming(
            for: song,
            from: folder,
            in: context,
            versionStore: store
        )

        #expect(first.rhythmMetadataData != nil)
        #expect(second.rhythmMetadataData != nil)
        #expect(first.notes.first?.normalizedAbsoluteTick == 0)
        #expect(second.notes.first?.normalizedAbsoluteTick == 0)
        #expect(first.controlEvents.first?.normalizedAbsoluteTick == 1)
        #expect(second.controlEvents.first?.normalizedAbsoluteTick == 1)
        #expect(manual.rhythmMetadataData == nil)
        #expect(store.completedVersion() == RhythmBackfillVersionStore.currentVersion)
    }

    @Test("unmatched eligible source chart aborts without marking completion")
    func unmatchedEligibleChartDoesNotCompleteBackfill() throws {
        let context = TestContainer.isolatedContainer().context
        let folder = try makeFixtureFolder(includeSecondChart: false)
        let song = Song(
            title: "Unmatched", artist: "Tester", bpm: 120, duration: "1:00",
            genre: "DTX Import", isServerImported: true, serverSongId: folder.lastPathComponent
        )
        let unmatched = sourceBackedChart(difficulty: .easy, level: 40, song: song)
        unmatched.notes.first?.sourceNoteID = "FF"
        let manual = Chart(
            difficulty: .easy,
            level: 40,
            notes: [Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)],
            song: song
        )
        song.charts = [manual, unmatched]
        context.insert(song)
        try context.save()

        let (defaults, _) = TestUserDefaults.makeIsolated(
            suiteName: "RhythmBackfill.unmatched.\(UUID().uuidString)"
        )
        let store = RhythmBackfillVersionStore(userDefaults: defaults)

        do {
            try LocalDTXFixtureImporter.backfillRhythmTiming(
                for: song,
                from: folder,
                in: context,
                versionStore: store
            )
            Issue.record("Expected an unmatched eligible chart to abort the pass")
        } catch {
            #expect(error.localizedDescription.contains("No deterministic rhythm backfill source"))
        }

        #expect(store.completedVersion() == 0)
        #expect(unmatched.rhythmMetadataData == nil)
        #expect(unmatched.notes.first?.normalizedAbsoluteTick == nil)
        #expect(manual.rhythmMetadataData == nil)
        #expect(!context.hasChanges)
    }

    @Test("ambiguous eligible source chart aborts without choosing SET order")
    func ambiguousEligibleChartDoesNotCompleteBackfill() throws {
        let context = TestContainer.isolatedContainer().context
        let folder = try makeAmbiguousFixtureFolder()
        let song = Song(
            title: "Ambiguous", artist: "Tester", bpm: 120, duration: "1:00",
            genre: "DTX Import", isServerImported: true, serverSongId: folder.lastPathComponent
        )
        let ambiguous = sourceBackedChart(difficulty: .easy, level: 40, song: song)
        ambiguous.controlEvents = []
        song.charts = [ambiguous]
        context.insert(song)
        try context.save()

        let (defaults, _) = TestUserDefaults.makeIsolated(
            suiteName: "RhythmBackfill.ambiguous.\(UUID().uuidString)"
        )
        let store = RhythmBackfillVersionStore(userDefaults: defaults)

        do {
            try LocalDTXFixtureImporter.backfillRhythmTiming(
                for: song,
                from: folder,
                in: context,
                versionStore: store
            )
            Issue.record("Expected ambiguous source projections to abort the pass")
        } catch {
            #expect(error.localizedDescription.contains("Multiple rhythm backfill sources"))
        }

        #expect(store.completedVersion() == 0)
        #expect(ambiguous.rhythmMetadataData == nil)
        #expect(ambiguous.notes.first?.normalizedAbsoluteTick == nil)
        #expect(!context.hasChanges)
    }

    @Test("failed whole-pass save leaves version unset and retries next launch")
    func failedSaveRetries() throws {
        let testContainer = TestContainer.isolatedContainer()
        let context = testContainer.context
        let folder = try makeFixtureFolder(includeSecondChart: false)
        let song = Song(
            title: "Retry", artist: "Tester", bpm: 120, duration: "1:00",
            genre: "DTX Import", isServerImported: true, serverSongId: folder.lastPathComponent
        )
        let legacyChart = sourceBackedChart(difficulty: .easy, level: 40, song: song)
        song.charts = [legacyChart]
        context.insert(song)
        try context.save()

        let (defaults, _) = TestUserDefaults.makeIsolated(
            suiteName: "RhythmBackfill.retry.\(UUID().uuidString)"
        )
        let store = RhythmBackfillVersionStore(userDefaults: defaults)
        var parseCount = 0

        #expect(throws: TestFailure.saveFailed) {
            try LocalDTXFixtureImporter.backfillRhythmTiming(
                for: song,
                from: folder,
                in: context,
                versionStore: store,
                parseChart: { url in
                    parseCount += 1
                    return try DTXFileParser.parseChartMetadata(from: url)
                },
                save: { _ in throw TestFailure.saveFailed }
            )
        }
        #expect(store.completedVersion() == 0)

        let retryContext = ModelContext(testContainer.container)
        let retrySong = try #require(try retryContext.fetch(FetchDescriptor<Song>()).first)
        try LocalDTXFixtureImporter.backfillRhythmTiming(
            for: retrySong,
            from: folder,
            in: retryContext,
            versionStore: store,
            parseChart: { url in
                parseCount += 1
                return try DTXFileParser.parseChartMetadata(from: url)
            },
            save: { try $0.save() }
        )
        #expect(parseCount == 2)
        #expect(store.completedVersion() == RhythmBackfillVersionStore.currentVersion)
    }

    private enum TestFailure: Error, Equatable {
        case saveFailed
        case unexpectedParse
        case unexpectedSave
    }

    private func sourceBackedChart(difficulty: Difficulty, level: Int, song: Song) -> Chart {
        let chart = Chart(difficulty: difficulty, level: level, song: song)
        chart.notes = [Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: 0,
            chart: chart,
            originKind: .dtx,
            sourceLaneID: "12",
            sourceNoteID: "01",
            sourceGridPosition: 0,
            sourceGridSize: 4
        )]
        chart.controlEvents = [ChartControlEvent(
            kind: .choke,
            measureNumber: 1,
            measureOffset: 0.25,
            chart: chart,
            originKind: .dtx,
            sourceLaneID: "22",
            sourceNoteID: "16",
            sourceGridPosition: 1,
            sourceGridSize: 4,
            targetLaneID: "16"
        )]
        return chart
    }

    private func makeFixtureFolder(includeSecondChart: Bool) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-rhythm-backfill-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let secondReference = includeSecondChart
            ? "\n#L2LABEL: ADVANCED\n#L2FILE: second.dtx"
            : ""
        try """
        #TITLE: Backfill
        #L1LABEL: BASIC
        #L1FILE: first.dtx\(secondReference)
        """.write(to: folder.appendingPathComponent("SET.def"), atomically: true, encoding: .utf8)
        try """
        #TITLE: Backfill
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 40
        #VIRGO_CONTROL: 1
        #00012: 01000000
        #00022: 00160000
        """.write(to: folder.appendingPathComponent("first.dtx"), atomically: true, encoding: .utf8)
        if includeSecondChart {
            try """
            #TITLE: Backfill
            #ARTIST: Tester
            #BPM: 120
            #DLEVEL: 50
            #00012: 01000000
            """.write(to: folder.appendingPathComponent("second.dtx"), atomically: true, encoding: .utf8)
        }
        return folder
    }

    private func makeVoiceScopedDurationFixtureFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-rhythm-voice-duration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try """
        #TITLE: Voice-scoped durations
        #L1LABEL: BASIC
        #L1FILE: first.dtx
        """.write(to: folder.appendingPathComponent("SET.def"), atomically: true, encoding: .utf8)
        try """
        #TITLE: Voice-scoped durations
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 40
        #00012: 0100000000000000
        #00011: 0200000000000000
        #00013: 0003000000000000
        """.write(to: folder.appendingPathComponent("first.dtx"), atomically: true, encoding: .utf8)
        return folder
    }

    private func makeAmbiguousFixtureFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-rhythm-ambiguous-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try """
        #TITLE: Ambiguous
        #L1LABEL: BASIC
        #L1FILE: first.dtx
        #L2LABEL: BASIC
        #L2FILE: second.dtx
        """.write(to: folder.appendingPathComponent("SET.def"), atomically: true, encoding: .utf8)
        try """
        #TITLE: Ambiguous
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 40
        #VIRGO_CONTROL: 1
        #00012: 01000000
        #00022: 00160000
        """.write(to: folder.appendingPathComponent("first.dtx"), atomically: true, encoding: .utf8)
        try """
        #TITLE: Ambiguous
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 40
        #VIRGO_TIME_SIGNATURE: 6/8
        #VIRGO_CONTROL: 1
        #00012: 01000000
        #00022: 00170000
        """.write(to: folder.appendingPathComponent("second.dtx"), atomically: true, encoding: .utf8)
        return folder
    }
}
