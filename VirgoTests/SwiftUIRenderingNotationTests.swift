//
//  SwiftUIRenderingNotationTests.swift
//  VirgoTests
//
//  App-side notation rendering coverage after the HPA-166 Task 7 cutover.
//  The package owns every notation primitive now — `DrumNotationViewTests`
//  gates their ink — so this suite keeps only the seams the app still owns:
//  mounting `DrumNotationView` on an installed engraving, the app-owned
//  annotation views, VoiceOver label ownership, and normalized sheet-origin
//  containment. The deleted legacy wrappers (`Notation*View` over
//  `Rendered*` primitives) carried their own mounting/ink gates; those went
//  with the wrappers.
//

import Testing
import SwiftUI
import Foundation
import DrumNotation
#if os(macOS)
import AppKit
#endif
@testable import Virgo

#if os(macOS)
/// Rasterization itself lives in `RenderRasterProbe.swift`, shared with
/// `DrumTabRenderProbeTests`; only the colour predicate is local to this suite.
@MainActor
private func countYellowPixels<V: View>(in view: V, size: CGSize) throws -> Int {
    try rasterizeView(view, size: size).count { pixel in
        pixel.alpha > 20 && pixel.red > 180 && pixel.green > 150 && pixel.blue < 120
    }
}
#endif

@Suite("SwiftUI Rendering Notation Tests", .serialized)
@MainActor
struct SwiftUIRenderingNotationTests {
    private let support = NotationSnapshotTestSupport()

    @Test("Production sheet mounts the package renderer over the installed engraving")
    func testDrumNotationViewMountsInstalledEngraving() async throws {
        try await TestSetup.withTestSetup {
            let (engraved, presentation) = try support.requireReady(support.prepare(notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
                Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.5)
            ]))
            let viewModel = GameplayViewModelCoverageTestSupport.makeViewModel(
                chart: Chart(difficulty: .medium)
            )
            viewModel.installPreparedNotation(.ready(engraved, presentation))
            let gameplayView = GameplayView(chart: viewModel.chart, metronome: viewModel.metronome)

            SwiftUITestUtilities.assertViewWithEnvironment(
                gameplayView.drumNotationView(viewModel: viewModel),
                size: CGSize(width: 1_024, height: 768)
            )
            // Every engraved rest is printed by construction: hidden
            // candidates never enter `ResolvedNotationInput`.
            #expect(gameplayView.printedNotationRests(viewModel: viewModel) == engraved.rests)
        }
    }

    @Test("hidden rest candidates never reach the engraving")
    func testHiddenRestsNeverReachEngraving() throws {
        // One printed rest plus one hidden spacing rest at later ticks of the
        // same measure: only the printed one may appear in `engraved.rests`.
        let rests = [
            RhythmLayoutRest(
                position: RhythmEventPosition(measureIndex: 0, localTick: 480, absoluteTick: 480),
                durationTicks: 240,
                voice: .lower,
                rhythm: NotationRhythm(baseInterval: .quarter),
                visibility: .printed,
                tupletID: nil
            ),
            RhythmLayoutRest(
                position: RhythmEventPosition(measureIndex: 0, localTick: 720, absoluteTick: 720),
                durationTicks: 240,
                voice: .lower,
                rhythm: NotationRhythm(baseInterval: .quarter),
                visibility: .hiddenSpacing,
                tupletID: nil
            )
        ]
        let engraved = try support.requireEngraved(support.prepare(
            notes: [Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)],
            rests: rests
        ))

        #expect(engraved.rests.count == 1)
    }

    @Test("Hi-hat noteheads own distinct labels while the open circle is hidden")
    func testHiHatAccessibilityOwnership() async throws {
        try await TestSetup.withTestSetup {
            let (engraved, presentation) = try support.requireReady(support.prepare(notes: [
                Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0),
                Note(interval: .quarter, noteType: .openHiHat, measureNumber: 1, measureOffset: 0.25),
                Note(interval: .quarter, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0.5)
            ]))

            // The open circle is a decorative articulation mark on the open
            // hi-hat head — the head owns the label, the mark stays hidden.
            #expect(engraved.articulations.map(\.kind) == [.open])
            let noteLabels = Set(engraved.noteHeads.compactMap {
                presentation.accessibilityLabels[.note($0.noteID)]
            })
            #expect(noteLabels == ["Closed hi-hat", "Open hi-hat", "Pedal hi-hat"])
            // No semantic ID exists for articulations, so the open circle
            // cannot acquire a separate VoiceOver label.
            #expect(presentation.accessibilityLabels.keys.allSatisfy { key in
                if case .note = key { return true }
                return false
            })

            SwiftUITestUtilities.assertViewWithEnvironment(
                DrumNotationView(
                    layout: engraved,
                    appearance: GameplayView.notationAppearance,
                    accessibilityLabels: presentation.accessibilityLabels
                ),
                size: CGSize(width: 1_024, height: 400)
            )
        }
    }

    @Test("highest open hi-hat articulation bounds stay inside the sheet origin")
    func testHighestOpenHiHatArticulationStaysInsideTopMargin() async throws {
        try await TestSetup.withTestSetup {
            let (engraved, presentation) = try support.requireReady(support.prepare(
                notes: [Note(
                    interval: .quarter,
                    noteType: .openHiHat,
                    measureNumber: 1,
                    measureOffset: 0
                )],
                notePositionOverrides: [.hiHat: .aboveLine9]
            ))
            let head = try #require(engraved.noteHeads.first)
            let articulation = try #require(engraved.articulations.first)
            let metrics = PercussionGlyphMetrics.articulation(
                articulation.kind,
                staffSpace: engraved.style.formatting.staffSpace
            )
            // The view frames the glyph to its painted bounds centered on
            // `position`; the engraver unions the same rect.
            let artBounds = metrics.paintedBounds.offsetBy(
                dx: articulation.position.x - metrics.paintedBounds.midX,
                dy: articulation.position.y - metrics.paintedBounds.midY
            )

            // Bravura pictOpen needs articulationVerticalOffset 24 > one staff
            // space; pin the clearance the offset exists for (>= 2pt between
            // pictOpen ink and the X-head ink). Sheet containment is now the
            // engraver's normalization guarantee — the painted union's minY
            // is clamped at the sheet origin, and the articulation's ink is
            // part of that union.
            #expect(head.paintedBounds.minY - artBounds.maxY >= 2)
            #expect(artBounds.minY >= 0)
            #expect(engraved.paintedBounds.minY >= 0)

            let viewModel = GameplayViewModelCoverageTestSupport.makeViewModel(
                chart: Chart(difficulty: .medium)
            )
            viewModel.installPreparedNotation(.ready(engraved, presentation))
            let gameplayView = GameplayView(chart: viewModel.chart, metronome: viewModel.metronome)

            #expect(gameplayView.sheetContentHeight(viewModel: viewModel) == engraved.contentHeight)
        }
    }

    @Test("highest control-only stop mark painted bounds stay inside the sheet origin")
    func testHighestControlOnlyStopMarkStaysInsideSheetOrigin() async throws {
        try await TestSetup.withTestSetup {
            let event = NotationControlEvent(ChartControlEvent(
                kind: .stop,
                measureNumber: 1,
                measureOffset: 0,
                targetLaneID: "1A"
            ))
            let (engraved, presentation) = try support.requireReady(support.prepare(
                notes: [],
                controls: [event],
                notePositionOverrides: [.crash: .aboveLine9]
            ))
            let control = try #require(engraved.controls.first)
            // The cross mark's ink: the mark square plus its stroke width —
            // the same extent the engraver unions into `paintedBounds`.
            let markExtent = engraved.style.stopMarkSize + engraved.style.stopMarkStrokeWidth
            let paintedTopEdge = control.position.y - markExtent / 2
            let viewModel = GameplayViewModelCoverageTestSupport.makeViewModel(
                chart: Chart(difficulty: .medium)
            )
            viewModel.installPreparedNotation(.ready(engraved, presentation))
            let gameplayView = GameplayView(chart: viewModel.chart, metronome: viewModel.metronome)

            #expect(!viewModel.cachedNotationHasPlayableContent)
            #expect(viewModel.cachedNotationHasRenderableContent)
            #expect(paintedTopEdge >= 0)
            #expect(gameplayView.sheetContentHeight(viewModel: viewModel) == engraved.contentHeight)
        }
    }

    @Test("Mounted package notation never renders yellow highlighting")
    func testNotationPrimitivesDoNotRenderYellowHighlighting() async throws {
        #if os(macOS)
        try await TestSetup.withTestSetup {
            let (engraved, presentation) = try support.requireReady(support.prepare(notes: [
                Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
                Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 16.0),
                Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 2.0 / 16.0),
                Note(interval: .sixtyfourth, noteType: .cowbell, measureNumber: 1, measureOffset: 4.0 / 16.0)
            ]))
            let viewModel = GameplayViewModelCoverageTestSupport.makeViewModel(
                chart: Chart(difficulty: .medium)
            )
            viewModel.installPreparedNotation(.ready(engraved, presentation))
            let gameplayView = GameplayView(chart: viewModel.chart, metronome: viewModel.metronome)

            let yellowPixels = try countYellowPixels(
                in: ZStack {
                    Color.black
                    gameplayView.drumNotationView(viewModel: viewModel)
                },
                size: CGSize(width: 1_024, height: 400)
            )

            #expect(yellowPixels == 0, "Notation should not render yellow pixels")
        }
        #endif
    }

    @Test("Feel and warning annotation views mount with semantic labels")
    func testAnnotationViewsRender() async throws {
        try await TestSetup.withTestSetup {
            let feel = GameplayFeelMark(
                feel: .swing,
                position: CGPoint(x: 50, y: 20),
                rowIndex: 0,
                size: CGSize(width: 60, height: 16)
            )
            let warning = GameplayRhythmWarning.measure(
                measureIndex: 0,
                kind: .warning,
                codes: [.ambiguousBeatGrouping],
                position: CGPoint(x: 80, y: 20),
                rowIndex: 0,
                size: CGSize(width: 120, height: 16)
            )
            let overlay = GameplayNotationAnnotationOverlay(
                annotations: GameplayNotationAnnotations(feelMarks: [feel], rhythmWarnings: [warning])
            )

            SwiftUITestUtilities.assertViewWithEnvironment(overlay, size: CGSize(width: 240, height: 120))
            #expect(SwiftUITestUtilities.renderedTexts(
                from: GameplayFeelMarkView(feelMark: feel).body
            ).contains(feel.accessibilityLabel))
            #expect(SwiftUITestUtilities.renderedTexts(
                from: GameplayRhythmWarningView(warning: warning).body
            ).contains(warning.accessibilityLabel))
        }
    }
}
