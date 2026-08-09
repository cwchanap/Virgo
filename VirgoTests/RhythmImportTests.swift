//
//  RhythmImportTests.swift
//  VirgoTests
//

import Foundation
import SwiftData
import Testing
@testable import Virgo

@Suite("Rhythm Import", .serialized)
@MainActor
struct RhythmImportTests {
    @Test("failed local import rolls back the inserted graph before a later save")
    func failedLocalImportRollsBackInsertedGraph() throws {
        let testContainer = TestContainer.isolatedContainer()
        let context = testContainer.context
        let folder = try makeVoiceScopedDurationFixtureFolder()

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

    @Test("cross-voice onset does not shorten an exact terminal upper-voice duration")
    func crossVoiceOnsetDoesNotShortenTerminalUpperVoiceDuration() async throws {
        let folder = try makeVoiceScopedDurationFixtureFolder()
        let testContainer = TestContainer.isolatedContainer()
        let context = testContainer.context
        let song = try LocalDTXFixtureImporter.importSong(from: folder, into: context)
        let chart = try #require(song.charts.first)

        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        let snapshot = try #require(viewModel.cachedRhythmRuntime.layoutSnapshot)
        let upperNotes = snapshot.notes.filter { $0.sourceLaneID == "12" || $0.sourceLaneID == "11" }

        #expect(upperNotes.count == 2)
        let measureDuration = try #require(snapshot.measures.first?.durationTicks)
        #expect(upperNotes.allSatisfy { $0.durationTicks == measureDuration })
        #expect(upperNotes.allSatisfy { $0.rhythm.baseInterval == .full })
        #expect(upperNotes.allSatisfy { $0.rhythm.support == .supported })
        guard case let .warning(warningCodes) = snapshot.measures.first?.engravingSupport else {
            Issue.record("Expected the unresolved lower voice to mark its measure warning-only")
            return
        }
        #expect(warningCodes.contains(.indeterminateTerminalDuration))

        viewModel.setupGameplay(loadPersistedSpeed: false)
        let expectedUpperEventIDs = Set(upperNotes.map(\.eventID))
        let upperHeads = viewModel.cachedNotationLayout.noteHeads.filter {
            guard let eventID = $0.eventID else { return false }
            return expectedUpperEventIDs.contains(eventID)
        }
        #expect(Set(upperHeads.compactMap { $0.eventID }) == expectedUpperEventIDs)
        #expect(upperHeads.count == expectedUpperEventIDs.count)
        let upperHeadIDs = Set(upperHeads.map(\.id))
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
        #expect(viewModel.cachedNotationLayout.rhythmWarnings.count == 1)
        #expect(viewModel.cachedNotationLayout.rhythmWarnings.first?.codes == [.indeterminateTerminalDuration])
        #expect(viewModel.cachedNotationLayout.tuplets.allSatisfy { tuplet in
            Set(tuplet.memberEventIDs).isDisjoint(with: upperNotes.map(\.eventID))
        })
        viewModel.cleanup()
    }

    private enum TestFailure: Error, Equatable {
        case saveFailed
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
}
