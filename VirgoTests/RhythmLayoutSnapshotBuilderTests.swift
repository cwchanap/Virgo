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
        let container = TestContainer.isolatedContainer()
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
}
