import Testing
import Foundation
@testable import Virgo

@Suite("Rhythm layout snapshot builder", .serialized)
@MainActor
struct RhythmLayoutSnapshotBuilderTests {
    @Test("builder produces a snapshot from a resolved chart rhythm")
    func buildsSnapshotFromResolvedRhythm() throws {
        let dtx = """
        #TITLE: Builder
        #ARTIST: Virgo Fixtures
        #BPM: 120
        #DLEVEL: 50
        #00113: 01010101
        """
        let chartData = try DTXFileParser.parseChartMetadata(from: dtx)
        let projection = try chartData.persistenceProjection()
        let container = TestContainer.ephemeralContainer()
        let context = container.context
        let song = Song(
            title: chartData.title,
            artist: chartData.artist,
            bpm: chartData.bpm,
            duration: "0:04",
            genre: "DTX"
        )
        let chart = Chart(
            difficulty: .medium,
            timeSignature: projection.timeSignature,
            song: song
        )
        try chart.setRhythmMetadata(projection.chartMetadata)
        chart.notes = projection.notes.map { $0.makeNote(for: chart) }
        chart.controlEvents = projection.controls.map { $0.makeControl(for: chart) }
        song.charts = [chart]
        context.insert(song)
        try context.save()

        let resolved = RhythmTimelineResolver().resolve(chart: chart)
        #expect(resolved.availability == .valid)
        let timeline = try #require(resolved.timeline)

        let snapshot = try RhythmLayoutSnapshotBuilder().build(
            resolvedRhythm: resolved,
            timeline: timeline,
            feel: .straight
        )

        #expect(snapshot.ticksPerWholeNote == timeline.ticksPerWholeNote)
        #expect(snapshot.notes.count == 4)
        #expect(snapshot.feel == .straight)
        #expect(snapshot.measures.count == timeline.measures.count)
    }

    @Test("terminal lower voice warning remains engraving-permitting in the snapshot")
    func terminalLowerVoiceWarningRemainsPermittingInSnapshot() throws {
        let dtx = """
        #TITLE: Voice-scoped warning
        #ARTIST: Virgo Fixtures
        #BPM: 120
        #DLEVEL: 50
        #00012: 0100000000000000
        #00011: 0200000000000000
        #00013: 0003000000000000
        """
        let chartData = try DTXFileParser.parseChartMetadata(from: dtx)
        let projection = try chartData.persistenceProjection()
        let container = TestContainer.ephemeralContainer()
        let context = container.context
        let song = Song(
            title: chartData.title,
            artist: chartData.artist,
            bpm: chartData.bpm,
            duration: "0:04",
            genre: "DTX"
        )
        let chart = Chart(
            difficulty: .medium,
            timeSignature: projection.timeSignature,
            song: song
        )
        try chart.setRhythmMetadata(projection.chartMetadata)
        chart.notes = projection.notes.map { $0.makeNote(for: chart) }
        song.charts = [chart]
        context.insert(song)
        try context.save()

        let resolved = RhythmTimelineResolver().resolve(chart: chart)
        let timeline = try #require(resolved.timeline)
        let snapshot = try RhythmLayoutSnapshotBuilder().build(
            resolvedRhythm: resolved,
            timeline: timeline,
            feel: .straight
        )

        #expect(snapshot.measures.first?.engravingSupport == .warning([.indeterminateTerminalDuration]))
        let upperNotes = snapshot.notes.filter { $0.sourceLaneID == "12" || $0.sourceLaneID == "11" }
        let lowerNote = try #require(snapshot.notes.first { $0.sourceLaneID == "13" })
        #expect(upperNotes.count == 2)
        #expect(upperNotes.allSatisfy {
            $0.rhythm == NotationRhythm(baseInterval: .full)
        })
        #expect(lowerNote.rhythm.support == .indeterminate(.indeterminateTerminalDuration))
    }
}
