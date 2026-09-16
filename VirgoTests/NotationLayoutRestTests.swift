import Testing
import DrumNotation
@testable import Virgo

/// Voice/rest integration through the measured preparation route
/// (HPA-164 Task 6; package engraving since HPA-166 Task 7). Rest synthesis
/// itself lives at import time (`NotationRhythmAnalyzer` +
/// `NotationRestTopologyBuilder`); these tests supply explicit snapshot
/// rests and pin how the package engraver places them. Every engraved rest
/// is printed by construction — hidden candidates feed spacing/tuplets but
/// never enter `ResolvedNotationInput.rests`.
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

    /// The onset tick of an engraved rest: its formatted-column membership
    /// (engraved primitives carry final geometry, not source ticks).
    private func localTick(of rest: EngravedRest, in engraved: EngravedNotation) -> Int? {
        engraved.formatted.measures
            .first { $0.index == rest.measureIndex }?
            .columns
            .first { $0.rests.contains { $0.restID == rest.restID } }?
            .localTick
    }

    @Test("printed full-measure rest centers in the content span once width is known")
    func printedFullMeasureRestCentersInMeasure() throws {
        let engraved = try support.requireEngraved(support.prepare(
            rests: [rest(tick: 0, durationTicks: 960, voice: .upper, interval: .full)]
        ))
        let measure = try #require(engraved.measures.first)
        let printed = try #require(engraved.rests.first)

        #expect(printed.isFullMeasure)
        #expect(printed.measureIndex == measure.index)
        // The formatter centers the full-measure rest in the measure's
        // content span (between the leading/trailing insets).
        let formatting = engraved.style.formatting
        #expect(
            printed.position.x
                == measure.xOffset
                    + (formatting.leadingMeasureInset + measure.width
                        - formatting.trailingMeasureInset) / 2
        )
    }

    @Test("printed voice rests use distinct style-owned baselines")
    func printedRestsUseVoiceBaselines() throws {
        let engraved = try support.requireEngraved(support.prepare(
            rests: [
                rest(tick: 0, durationTicks: 480, voice: .upper, interval: .half),
                rest(tick: 0, durationTicks: 480, voice: .lower, interval: .half)
            ]
        ))
        let upper = try #require(engraved.rests.first { $0.voice == .upper })
        let lower = try #require(engraved.rests.first { $0.voice == .lower })
        let staffCenterY = engraved.rows[upper.rowIndex].staffCenterY

        #expect(upper.position.y == staffCenterY + engraved.style.upperVoiceRestOffset)
        #expect(lower.position.y == staffCenterY + engraved.style.lowerVoiceRestOffset)
        #expect(upper.position.y != lower.position.y)
    }

    @Test("same-tick full-measure and interval rests keep distinct package X")
    func mixedFullMeasureAndIntervalRestsKeepDistinctX() throws {
        let engraved = try support.requireEngraved(support.prepare(
            rests: [
                rest(tick: 0, durationTicks: 960, voice: .upper, interval: .full),
                rest(tick: 0, durationTicks: 480, voice: .lower, interval: .half)
            ]
        ))
        let measure = try #require(engraved.measures.first)
        let full = try #require(engraved.rests.first { $0.isFullMeasure })
        let half = try #require(engraved.rests.first { !$0.isFullMeasure })
        let columnX = try #require(
            engraved.formatted.measures
                .first { $0.index == 0 }?
                .columns
                .first { $0.localTick == 0 }?
                .logicalColumnX
        )

        // The full-measure rest centers in the content span while the
        // interval rest keeps its rhythmic placement at the column anchor.
        let formatting = engraved.style.formatting
        #expect(
            full.position.x
                == measure.xOffset
                    + (formatting.leadingMeasureInset + measure.width
                        - formatting.trailingMeasureInset) / 2
        )
        #expect(half.position.x == columnX)
        #expect(full.position.x != half.position.x)
    }

    @Test("interval rests anchor to their formatted column")
    func intervalRestAnchorsToFormattedColumn() throws {
        let engraved = try support.requireEngraved(support.prepare(
            rests: [rest(tick: 480, durationTicks: 480, voice: .upper, interval: .half)]
        ))
        let column = try #require(
            engraved.formatted.measures
                .first { $0.index == 0 }?
                .columns
                .first { $0.localTick == 480 }
        )
        let rest = try #require(engraved.rests.first)

        #expect(rest.position.x == column.logicalColumnX)
        #expect(localTick(of: rest, in: engraved) == 480)
        #expect(rest.duration == .half)
        #expect(!rest.isFullMeasure)
        #expect(rest.measureIndex == 0)
    }

    @Test("hidden rests stay in the layout without becoming printed content")
    func hiddenRestsRemainNonPrinted() throws {
        let prepared = support.prepare(
            rests: [
                rest(tick: 0, durationTicks: 960, voice: .lower,
                     interval: .full, visibility: .hiddenDuplicate)
            ]
        )

        // Hidden candidates feed spacing/tuplets but never resolve into
        // `ResolvedNotationInput.rests`, so the engraving is empty and the
        // sheet falls back to `.unavailable` — the non-printing outcome the
        // legacy `hasRenderableContent == false` pinned.
        guard case .unavailable = prepared else {
            Issue.record("Expected .unavailable for a hidden-only rest sheet, got \(prepared)")
            return
        }
    }

    @Test("shuffled rest input preserves rendered rest order and semantic IDs")
    func shuffledRestsPreserveOrderingAndIDs() throws {
        let rests = [
            rest(tick: 0, durationTicks: 240, voice: .upper, interval: .quarter),
            rest(tick: 240, durationTicks: 120, voice: .lower, interval: .eighth),
            rest(tick: 720, durationTicks: 240, voice: .upper, interval: .quarter)
        ]
        let ordered = try support.requireEngraved(support.prepare(rests: rests)).rests
        let shuffled = try support.requireEngraved(
            support.prepare(rests: [rests[2], rests[0], rests[1]])
        ).rests

        #expect(!ordered.isEmpty)
        #expect(shuffled == ordered)
        #expect(shuffled.map(\.restID) == ordered.map(\.restID))
    }
}
