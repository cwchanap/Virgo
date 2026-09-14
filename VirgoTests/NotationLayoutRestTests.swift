import Testing
@testable import Virgo

/// Voice/rest integration through the measured preparation route
/// (HPA-164 Task 6). Rest synthesis itself lives at import time
/// (`NotationRhythmAnalyzer` + `NotationRestTopologyBuilder`); these tests
/// supply explicit snapshot rests and pin how the engine places them.
@Suite("Notation Layout Rest Tests")
struct NotationLayoutRestTests {
    private let support = NotationSnapshotTestSupport()

    private func rest(
        tick: Int,
        durationTicks: Int,
        voice: NotationVoice,
        interval: NoteInterval,
        visibility: NotationRestVisibility = .printed
    ) -> RhythmLayoutRest {
        RhythmLayoutRest(
            position: RhythmEventPosition(
                measureIndex: 0,
                localTick: tick,
                absoluteTick: tick
            ),
            durationTicks: durationTicks,
            voice: voice,
            rhythm: NotationRhythm(baseInterval: interval),
            visibility: visibility,
            tupletID: nil
        )
    }

    @Test("printed full-measure rest centers in the content span once width is known")
    func printedFullMeasureRestCentersInMeasure() throws {
        let prepared = support.prepare(
            rests: [rest(tick: 0, durationTicks: 960, voice: .upper, interval: .full)]
        )
        let measure = try #require(prepared.layout.measures.first)
        let printed = try #require(prepared.layout.rests.first { $0.isPrinted })

        #expect(printed.duration == .fullMeasure)
        #expect(printed.timeColumn.tickWithinMeasure == 0)
        #expect(printed.timeColumn.absoluteLayoutTick == 0)
        // The formatter centers the full-measure rest in the measure's
        // content span (between the leading/trailing insets).
        let inset = GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing
        #expect(printed.position.x == measure.xOffset + inset + (measure.width - inset) / 2)
    }

    @Test("printed voice rests use distinct style-owned baselines")
    func printedRestsUseVoiceBaselines() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let prepared = support.prepare(
            rests: [
                rest(tick: 0, durationTicks: 480, voice: .upper, interval: .half),
                rest(tick: 0, durationTicks: 480, voice: .lower, interval: .half)
            ],
            style: style
        )
        let upper = try #require(prepared.layout.rests.first { $0.voice == .upper && $0.isPrinted })
        let lower = try #require(prepared.layout.rests.first { $0.voice == .lower && $0.isPrinted })
        let staffLine3Y = GameplayLayout.StaffLinePosition.line3.absoluteY(for: 0)

        #expect(upper.position.y == staffLine3Y + style.upperVoiceRestOffset)
        #expect(lower.position.y == staffLine3Y + style.lowerVoiceRestOffset)
        #expect(upper.position.y != lower.position.y)
    }

    @Test("interval rests anchor to their formatted column")
    func intervalRestAnchorsToFormattedColumn() throws {
        let prepared = support.prepare(
            rests: [rest(tick: 480, durationTicks: 480, voice: .upper, interval: .half)]
        )
        let columnX = try #require(
            prepared.formatted.measures
                .first { $0.index == 0 }?
                .columns
                .first { $0.localTick == 480 }?
                .logicalColumnX
        )
        let rest = try #require(prepared.layout.rests.first { $0.isPrinted })

        #expect(rest.position.x == columnX)
        #expect(rest.rhythmPosition == RhythmEventPosition(
            measureIndex: 0,
            localTick: 480,
            absoluteTick: 480
        ))
        #expect(rest.rhythm == NotationRhythm(baseInterval: .half))
        #expect(rest.tupletID == nil)
    }

    @Test("hidden rests stay in the layout without becoming printed content")
    func hiddenRestsRemainNonPrinted() throws {
        let prepared = support.prepare(
            rests: [rest(tick: 0, durationTicks: 960, voice: .lower, interval: .full, visibility: .hiddenDuplicate)]
        )
        let hidden = try #require(prepared.layout.rests.first { $0.visibility == .hiddenDuplicate })

        #expect(!hidden.isPrinted)
        #expect(prepared.layout.rests.contains(hidden))
        #expect(prepared.layout.rests.filter(\.isPrinted).isEmpty)
        #expect(!prepared.layout.hasRenderableContent)
    }

    @Test("shuffled rest input preserves rendered rest order and semantic IDs")
    func shuffledRestsPreserveOrderingAndIDs() {
        let rests = [
            rest(tick: 0, durationTicks: 240, voice: .upper, interval: .quarter),
            rest(tick: 240, durationTicks: 120, voice: .lower, interval: .eighth),
            rest(tick: 720, durationTicks: 240, voice: .upper, interval: .quarter)
        ]
        let ordered = support.prepare(rests: rests).layout.rests
        let shuffled = support.prepare(rests: [rests[2], rests[0], rests[1]]).layout.rests

        #expect(!ordered.isEmpty)
        #expect(shuffled == ordered)
        #expect(shuffled.map(\.id) == ordered.map(\.id))
    }
}
