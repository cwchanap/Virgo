//
//  GameplaySheetMusicRowAnchorTests.swift
//  VirgoTests
//
//  Scroll-anchor contract tests for the mounted sheet: every `row_i`
//  anchor must sit at-or-above its own row's topmost ink so
//  `scrollTo("row_i", anchor: .top)` never clips overhanging notation.
//

import Testing
import Foundation
import SwiftUI
import DrumNotation
@testable import Virgo

@MainActor
@Suite("Gameplay sheet music row anchors", .serialized)
struct GameplaySheetMusicRowAnchorTests {

    /// Verifies that `rowAnchorColumn` renders — and that the row_0 scroll
    /// anchor sits at-or-above the sheet's topmost painted ink — when the
    /// installed engraving carries extended above-staff positions
    /// (.aboveLine9). An anchor top below the ink's top edge would let
    /// `scrollTo("row_0", anchor: .top)` clip the head/stem/ledger ink that
    /// pushed the engraving above the sheet origin — the clipping the
    /// dynamic top-padding computation was introduced to prevent.
    @Test("rowAnchorColumn accommodates note heads at aboveLine9 without clipping")
    func rowAnchorColumnWithHighNotePositionsRenders() async throws {
        try await TestSetup.withTestSetup {
            let support = NotationSnapshotTestSupport()
            let (engraved, presentation) = try support.requireReady(support.prepare(
                notes: [Note(interval: .quarter, noteType: .openHiHat, measureNumber: 1, measureOffset: 0)],
                notePositionOverrides: [.hiHat: .aboveLine9]
            ))
            let vm = GameplayViewModelCoverageTestSupport.makeViewModel(
                chart: Chart(difficulty: .medium)
            )
            defer { vm.cleanup() }
            vm.installPreparedNotation(.ready(engraved, presentation))

            let gameplayView = GameplayView(chart: vm.chart, metronome: vm.metronome)
            let tops = gameplayView.staticNotationInput(viewModel: vm).rowAnchorTops
            let rowZeroTop = try #require(tops.first)

            #expect(
                rowZeroTop <= engraved.paintedBounds.minY,
                "row_0's anchor top must not sit below the sheet's topmost ink — scrollTo(.top) would clip it"
            )

            let anchorColumn = gameplayView.rowAnchorColumn(viewModel: vm)
            SwiftUITestUtilities.assertViewWithEnvironment(
                anchorColumn,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    /// Regression for the per-row anchor contract (HPA-583 review): a
    /// single shared `firstRowTop` cannot protect above-band ink past row
    /// 0 — a later row's `.aboveLine9` overhang resolves to a negative
    /// shared offset that a `max(0, …)` clamp discards, landing that row's
    /// anchor on its band top and clipping the overhang. Every `row_i`
    /// anchor must sit at-or-above its own row's topmost ink instead.
    @Test("rowAnchors protect above-band ink on later rows")
    func rowAnchorsProtectLaterRowOverhang() async throws {
        try await TestSetup.withTestSetup {
            let support = NotationSnapshotTestSupport()
            // One high note on the last measure of a multi-row sheet: the
            // 900pt row width packs only a few 4/4 measures per row, so the
            // note lands on a later row while earlier rows carry furniture.
            let (engraved, presentation) = try support.requireReady(support.prepare(
                notes: [Note(interval: .quarter, noteType: .openHiHat, measureNumber: 9, measureOffset: 0)],
                minimumMeasureCount: 9,
                notePositionOverrides: [.hiHat: .aboveLine9]
            ))
            try #require(engraved.rows.count > 1, "fixture must engrave multiple rows")
            let highHead = try #require(
                engraved.noteHeads.first { $0.rowIndex > 0 },
                "the high note must land on a later row"
            )

            let vm = GameplayViewModelCoverageTestSupport.makeViewModel(
                chart: Chart(difficulty: .medium)
            )
            defer { vm.cleanup() }
            vm.installPreparedNotation(.ready(engraved, presentation))

            let view = GameplayView(chart: vm.chart, metronome: vm.metronome)
            let tops = view.staticNotationInput(viewModel: vm).rowAnchorTops
            try #require(tops.count == engraved.rows.count)

            for (top, row) in zip(tops, engraved.rows) {
                let bandTop = max(0, row.staffCenterY - engraved.style.rowHeight / 2)
                #expect(
                    top >= 0 && top <= bandTop
                        && top <= rowInkTop(engraved, rowIndex: row.index),
                    "row_\(row.index) anchor must sit at-or-above its band top and topmost ink"
                )
            }

            let highBandTop = try #require(
                engraved.rows.first { $0.index == highHead.rowIndex }
            ).staffCenterY - engraved.style.rowHeight / 2
            #expect(
                tops[highHead.rowIndex] < highBandTop,
                "the high-note row's anchor must move off the band top — the overhang needs the offset"
            )
            // Non-vacuity: the required shared offset (inkTop − row·pitch)
            // is negative here — the old `max(0, …)` clamp discarded it.
            let pitch = engraved.style.rowHeight + engraved.style.rowVerticalSpacing
            try #require(
                rowInkTop(engraved, rowIndex: highHead.rowIndex)
                    - CGFloat(highHead.rowIndex) * pitch < 0,
                "fixture must put the later-row overhang below the shared-bound floor"
            )

            SwiftUITestUtilities.assertViewWithEnvironment(
                view.rowAnchorColumn(viewModel: vm),
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    /// Independent per-row topmost-ink bound for the anchor contract,
    /// computed over the package's exact per-primitive painted bounds —
    /// the same data production reads, so a family production forgets
    /// cannot hide behind weaker bounds here.
    private func rowInkTop(_ engraving: EngravedNotation, rowIndex: Int) -> CGFloat {
        var bounded: [(Int, CGFloat)] = engraving.rows.map { ($0.index, $0.paintedBounds.minY) }
        bounded += engraving.noteHeads.map { ($0.rowIndex, $0.paintedBounds.minY) }
        bounded += engraving.rests.map { ($0.rowIndex, $0.paintedBounds.minY) }
        bounded += engraving.ledgerLines.map { ($0.rowIndex, $0.paintedBounds.minY) }
        bounded += engraving.rhythmDots.map { ($0.rowIndex, $0.paintedBounds.minY) }
        bounded += engraving.controls.map { ($0.rowIndex, $0.paintedBounds.minY) }
        bounded += engraving.tuplets.map { ($0.rowIndex, $0.paintedBounds.minY) }
        let noteRow = Dictionary(
            engraving.noteHeads.map { ($0.noteID, $0.rowIndex) },
            uniquingKeysWith: { existing, _ in existing }
        )
        var joined: [(Int, CGFloat)] = engraving.stems.compactMap { stem in
            stem.noteIDs.lazy.compactMap { noteRow[$0] }.first
                .map { ($0, stem.paintedBounds.minY) }
        }
        joined += engraving.beams.compactMap { beam in
            beam.noteIDs.lazy.compactMap { noteRow[$0] }.first
                .map { ($0, beam.paintedBounds.minY) }
        }
        joined += engraving.flags.compactMap { flag in
            noteRow[flag.noteID].map { ($0, flag.paintedBounds.minY) }
        }
        joined += engraving.articulations.compactMap { articulation in
            noteRow[articulation.noteID].map { ($0, articulation.paintedBounds.minY) }
        }
        var top = CGFloat.infinity
        for (row, minY) in bounded + joined where row == rowIndex {
            top = min(top, minY)
        }
        return top
    }

    /// Each row keeps its own anchor top even when tops decrease: a later
    /// row's ink can reach above an earlier row's anchor, and clamping to
    /// the previous top would land that row's anchor below its own ink —
    /// `scrollTo("row_i", anchor: .top)` would clip it. The anchor column
    /// positions each target independently precisely so this case is
    /// expressible (HPA-583 review).
    @Test("anchorTops keep a later row's own top when tops decrease")
    func anchorTopsPreserveDecreasingRowTop() async throws {
        try await TestSetup.withTestSetup {
            let support = NotationSnapshotTestSupport()
            let (engraved, _) = try support.requireReady(support.prepare(
                notes: [Note(interval: .quarter, noteType: .openHiHat, measureNumber: 9, measureOffset: 0)],
                minimumMeasureCount: 9
            ))
            try #require(engraved.rows.count > 1, "fixture must engrave multiple rows")

            let lastRow = engraved.rows.count - 1
            let head = try #require(engraved.noteHeads.first)
            let skyHigh = EngravedNoteHead(
                noteID: head.noteID,
                measureIndex: head.measureIndex,
                rowIndex: lastRow,
                staffStep: head.staffStep,
                voice: head.voice,
                stemDirection: head.stemDirection,
                noteheadStyle: head.noteheadStyle,
                duration: head.duration,
                position: head.position,
                paintedBounds: CGRect(x: head.paintedBounds.minX, y: 0, width: 1, height: 1)
            )
            let mutated = engraved.replacing(noteHeads: [skyHigh])

            let tops = GameplayRowAnchorGeometry.anchorTops(for: mutated)
            #expect(tops.count == engraved.rows.count)
            #expect(
                tops[lastRow] <= rowInkTop(mutated, rowIndex: lastRow),
                "row_\(lastRow)'s anchor must sit at-or-above its own topmost ink (minY 0)"
            )
            // Non-vacuity: the fixture must actually produce a decreasing
            // pair — the case a monotone clamp would rewrite into a
            // clipping anchor.
            #expect(
                tops[lastRow] < tops[lastRow - 1],
                "fixture must put the last row's ink top above the previous row's anchor"
            )
        }
    }

    /// Verifies that a chart with crash notes (default position .aboveLine5) produces
    /// a layout where the crash note head sits above the staff, and the anchor column
    /// still renders successfully.
    ///
    /// Note: a true .aboveLine9 override goes through `NotationSnapshotTestSupport`
    /// + `installPreparedNotation` (see the test above); this one covers the
    /// default .aboveLine5 crash position through the view-model preparation path.
    @Test("rowAnchorColumn with above-staff crash notes renders correctly")
    func rowAnchorColumnWithAboveStaffCrashNotesRenders() async throws {
        try await TestSetup.withTestSetup {
            // Create a chart with crash notes (mapped to .aboveLine5 by default).
            let chart = GameplayViewModelCoverageTestSupport.makeChart(
                noteCount: 2,
                interval: .quarter,
                measureOffset: 0.25
            )
            // Change the first note to crash so it uses an above-staff position.
            chart.notes[0].noteType = .crash

            let vm = GameplayViewModelCoverageTestSupport.makeViewModel(chart: chart)
            defer { vm.cleanup() }
            await vm.loadChartData()
            await vm.setupGameplay()

            // Verify the crash note head is above the highest staff line
            // (line5 = the top staff line, pitch-ascending last entry).
            // In screen coordinates, above-line5 means a smaller Y value.
            let engraved = try #require(vm.cachedEngravedNotation)
            let crashEventID = try #require(
                vm.cachedRhythmRuntime.noteByEventID.first { $0.value.noteType == .crash }?.key,
                "Runtime should carry a crash note"
            )
            let crashHead = try #require(
                engraved.noteHeads.first { $0.noteID == crashEventID.rawValue },
                "Engraving should contain a crash note head"
            )
            let row = try #require(engraved.rows.first { $0.index == crashHead.rowIndex })
            let line5Y = try #require(row.staffLineYs.last)
            #expect(crashHead.position.y < line5Y,
                    "Crash note head should be above line5 (default .aboveLine5 position)")

            let gameplayView = GameplayView(chart: vm.chart, metronome: vm.metronome)

            let anchorColumn = gameplayView.rowAnchorColumn(viewModel: vm)
            SwiftUITestUtilities.assertViewWithEnvironment(
                anchorColumn,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    /// Verifies that the populated sheet music view (which includes rowAnchorColumn)
    /// still renders correctly after the rowAnchorColumn signature change.
    @Test("Full sheet music view renders with updated rowAnchorColumn")
    func sheetMusicViewRendersWithUpdatedRowAnchorColumn() async throws {
        try await TestSetup.withTestSetup {
            let vm = await GameplayViewModelCoverageTestSupport.makePreparedViewModel()
            defer { vm.cleanup() }

            let view = GameplayView(chart: vm.chart, metronome: vm.metronome, initialViewModel: vm)
                .environmentObject(vm.practiceSettings)

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }
}

private extension EngravedNotation {
    /// A copy of this immutable engraving with the note-head array swapped
    /// — mirrors `DrumTabRenderProbeTests`' one-layer differential.
    func replacing(noteHeads: [EngravedNoteHead]) -> EngravedNotation {
        EngravedNotation(
            formatted: formatted,
            style: style,
            rows: rows,
            measures: measures,
            noteHeads: noteHeads,
            rests: rests,
            stems: stems,
            beams: beams,
            flags: flags,
            ledgerLines: ledgerLines,
            rhythmDots: rhythmDots,
            articulations: articulations,
            controls: controls,
            tuplets: tuplets,
            measureBars: measureBars,
            paintedBounds: paintedBounds,
            contentWidth: contentWidth,
            contentHeight: contentHeight
        )
    }
}
