//
//  DTXControlImportIntegrationTests.swift
//  VirgoTests
//

import Testing
import Foundation
@testable import Virgo

/// End-to-end test: DTX string → parse → ChartControlEvent → layout engine →
/// rendered stop mark. Covers acceptance criterion 2 ("render") through the real
/// parser and layout engine, not just the data pipeline.
@Suite("DTX Control Import Integration")
struct DTXControlImportIntegrationTests {
    private let support = NotationLayoutTestSupport()

    @Test("parsed choke control renders as a stop mark through the layout engine")
    func parsedControlRendersAsStopMark() throws {
        let dtx = """
        #TITLE: Integration
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00012: 01000000
        #00022: 16000000
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)
        let controls = data.toControlEvents(for: chart)

        #expect(controls.count == 1)

        // Convert to NotationControlEvent (the immutable snapshot the layout engine consumes)
        let notationControls = controls.map { NotationControlEvent($0) }

        // Include a playable note so the tab grid has content to project onto
        let result = support.layout(
            notes: [support.fallbackGridNote()],
            controls: notationControls
        )

        #expect(result.stopNotes.count == 1)
        let stopNote = try #require(result.stopNotes.first)
        #expect(stopNote.kind == .choke)
        #expect(stopNote.targetLaneID == "16")
        #expect(stopNote.targetDisplayName == "Crash")
    }

    @Test("parsed incommensurate control preserves measure but omits mark")
    func parsedIncommensurateControlPreservesMeasure() throws {
        let dtx = """
        #TITLE: Incommensurate
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00012: 01000000
        #00221: 01000000000000
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)
        let controls = data.toControlEvents(for: chart)
        #expect(controls.count == 1)
        let notationControls = controls.map { NotationControlEvent($0) }

        let result = support.layout(
            notes: [support.fallbackGridNote()],
            controls: notationControls
        )

        // The control is at measure index 2 → total measures >= 3
        #expect(result.measures.count >= 3)
        // 1/7 does not project onto a 960-tick grid → no rendered mark
        #expect(result.stopNotes.isEmpty)
    }
}
