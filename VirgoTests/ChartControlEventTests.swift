import SwiftData
import Testing
@testable import Virgo

@Suite("Chart Control Event Tests", .serialized)
@MainActor
struct ChartControlEventTests {
    @Test("control kinds preserve stable raw values")
    func kindRawValuesAreStable() {
        #expect(NotationControlEventKind.stop.rawValue == "stop")
        #expect(NotationControlEventKind.choke.rawValue == "choke")
        #expect(NotationControlEventKind.damp.rawValue == "damp")
        #expect(NotationControlEventKind.allCases == [.stop, .choke, .damp])
    }

    @Test("control defaults to manual origin and snapshots all semantic fields")
    func defaultsAndSnapshot() {
        let event = ChartControlEvent(
            kind: .choke,
            measureNumber: 2,
            measureOffset: 0.25,
            sourceLaneID: "55",
            sourceNoteID: "0A",
            sourceGridPosition: 1,
            sourceGridSize: 4,
            normalizedMeasureIndex: 1,
            normalizedAbsoluteTick: 5,
            normalizedTickWithinMeasure: 1,
            normalizedTicksPerMeasure: 4,
            targetLaneID: "1A"
        )

        let snapshot = NotationControlEvent(event)

        #expect(event.originKind == .manual)
        #expect(snapshot.kind == .choke)
        #expect(snapshot.measureNumber == 2)
        #expect(snapshot.measureOffset == 0.25)
        #expect(snapshot.sourceLaneID == "55")
        #expect(snapshot.sourceNoteID == "0A")
        #expect(snapshot.normalizedAbsoluteTick == 5)
        #expect(snapshot.targetLaneID == "1A")
    }

    @Test("control persists and Chart deletion cascades")
    func persistenceAndCascade() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let chart = Chart(difficulty: .medium)
            let event = ChartControlEvent(
                kind: .stop,
                measureNumber: 1,
                measureOffset: 0.5,
                chart: chart,
                targetLaneID: "18"
            )
            chart.controlEvents = [event]
            context.insert(chart)
            try context.save()

            #expect(try context.fetch(FetchDescriptor<ChartControlEvent>()).count == 1)

            context.delete(chart)
            try context.save()

            #expect(try context.fetch(FetchDescriptor<ChartControlEvent>()).isEmpty)
        }
    }

    @Test("fixture copy preserves controls separately from notes")
    func fixtureCopyPreservesControls() throws {
        let template = Song(title: "T", artist: "A", bpm: 120, duration: "1:00", genre: "Test")
        let chart = Chart(difficulty: .hard, song: template)
        chart.notes = [Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0)]
        chart.controlEvents = [
            ChartControlEvent(kind: .choke, measureNumber: 1, measureOffset: 0.25, targetLaneID: "1A")
        ]
        template.charts = [chart]

        let copy = Song.fixtureCopy(from: template)
        let copiedChart = try #require(copy.charts.first)
        let copiedControl = try #require(copiedChart.controlEvents.first)

        #expect(copiedChart.notes.count == 1)
        #expect(copiedChart.controlEvents.count == 1)
        #expect(copiedControl !== chart.controlEvents[0])
        #expect(copiedControl.chart === copiedChart)
        #expect(copiedControl.kind == .choke)
        #expect(copiedControl.targetLaneID == "1A")
    }
}
