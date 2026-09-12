//
//  SwiftUIRenderingNotationTests.swift
//  VirgoTests
//
//  Notation-primitive rendering coverage split from SwiftUIRenderingCoverageTests
//  to keep both files under SwiftLint's 600-line file-length warn limit.
//

import Testing
import SwiftUI
import Foundation
import SwiftData
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
    @Test("Notation primitive mounts every package notehead style carrier")
    func testNotationPrimitiveMountsEveryVectorNotehead() async throws {
        try await TestSetup.withTestSetup {
            // One representative per package PercussionNoteheadStyle:
            // snare (.normal), hiHat (.x), cowbell (.diamond).
            for (index, noteType) in [NoteType.snare, .hiHat, .cowbell].enumerated() {
                let noteHead = makeRenderedHead(id: UInt64(index), noteType: noteType)
                SwiftUITestUtilities.assertViewWithEnvironment(
                    NotationNoteHeadView(
                        noteHead: noteHead,
                        style: .gameplayDefault
                    ),
                    size: CGSize(width: 120, height: 120)
                )
            }
        }
    }

    @Test("Notation rest primitives mount every printed duration with semantic labels")
    func testNotationRestPrimitivesMountEveryPrintedDuration() async throws {
        try await TestSetup.withTestSetup {
            for (index, duration) in NotationRestDuration.allCases.filter({ $0 != .indeterminate }).enumerated() {
                let rest = makeRenderedRest(
                    id: "rest-\(index)",
                    duration: duration,
                    visibility: .printed
                )
                let view = NotationRestView(rest: rest, style: .gameplayDefault)
                SwiftUITestUtilities.assertViewWithEnvironment(
                    view,
                    size: CGSize(width: 120, height: 120)
                )
                #expect(SwiftUITestUtilities.renderedTexts(from: view.body).contains(rest.accessibilityLabel))
            }
        }
    }

    @Test("Notation sheet filters hidden rests before constructing rest views")
    func testNotationSheetFiltersHiddenRestsBeforeConstruction() async throws {
        try await TestSetup.withTestSetup {
            let viewModel = GameplayViewModelCoverageTestSupport.makeViewModel(
                chart: Chart(difficulty: .medium),
                noteCount: 0
            )
            await viewModel.loadChartData()
            await viewModel.setupGameplay(loadPersistedSpeed: false)
            guard let printed = viewModel.cachedNotationLayout.rests.first(where: \.isPrinted),
                  let hidden = viewModel.cachedNotationLayout.rests.first(where: { !$0.isPrinted }) else {
                Issue.record("Expected one printed and one hidden full-measure rest")
                return
            }
            let gameplayView = GameplayView(chart: viewModel.chart, metronome: viewModel.metronome)

            SwiftUITestUtilities.assertViewWithEnvironment(
                gameplayView.drumNotationView(viewModel: viewModel),
                size: CGSize(width: 1_024, height: 768)
            )
            #expect(gameplayView.printedNotationRests(viewModel: viewModel) == [printed])
            #expect(!gameplayView.printedNotationRests(viewModel: viewModel).contains(hidden))
        }
    }

    @Test("Notation stop primitives mount every semantic control kind")
    func testNotationStopPrimitivesMountEveryControlKind() async throws {
        try await TestSetup.withTestSetup {
            for (index, kind) in NotationControlEventKind.allCases.enumerated() {
                let stop = makeRenderedStop(id: "stop-\(index)", kind: kind)
                let view = NotationStopNoteView(stopNote: stop, style: .gameplayDefault)
                SwiftUITestUtilities.assertViewWithEnvironment(
                    view,
                    size: CGSize(width: 120, height: 120)
                )
                #expect(SwiftUITestUtilities.renderedTexts(from: view.body).contains(stop.accessibilityLabel))
            }
        }
    }

    @Test("Hi-hat noteheads own distinct labels while the open circle is hidden")
    func testHiHatAccessibilityOwnership() async throws {
        try await TestSetup.withTestSetup {
            let layout = NotationLayoutEngine().layout(input: NotationLayoutInput(
                notes: [
                    Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0),
                    Note(interval: .quarter, noteType: .openHiHat, measureNumber: 1, measureOffset: 0.25),
                    Note(interval: .quarter, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0.5)
                ],
                timeSignature: .fourFour
            ))
            guard let openCircle = layout.articulations.first else {
                Issue.record("Expected an open hi-hat articulation")
                return
            }
            let noteHeadViews = ZStack {
                ForEach(layout.noteHeads) { noteHead in
                    NotationNoteHeadView(noteHead: noteHead, style: .gameplayDefault)
                }
            }

            SwiftUITestUtilities.assertViewWithEnvironment(
                noteHeadViews,
                size: CGSize(width: 1_024, height: 768)
            )
            let noteHeadLabels = layout.noteHeads.flatMap { noteHead in
                SwiftUITestUtilities.renderedTexts(from: NotationNoteHeadView(
                    noteHead: noteHead,
                    style: .gameplayDefault
                ).body)
            }
            #expect(Set(noteHeadLabels).isSuperset(of: ["Closed hi-hat", "Open hi-hat", "Pedal hi-hat"]))
            let articulationView = NotationArticulationView(
                articulation: openCircle,
                style: .gameplayDefault
            )
            SwiftUITestUtilities.assertViewWithEnvironment(
                articulationView,
                size: CGSize(width: 120, height: 120)
            )
            #expect(accessibilityVisibilityRawValues(in: articulationView.body).contains(4))
        }
    }

    @Test("highest open hi-hat articulation bounds stay inside the sheet origin")
    func testHighestOpenHiHatArticulationStaysInsideTopMargin() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let layout = NotationLayoutEngine().layout(input: NotationLayoutInput(
            notes: [Note(
                interval: .quarter,
                noteType: .openHiHat,
                measureNumber: 1,
                measureOffset: 0
            )],
            timeSignature: .fourFour,
            style: style,
            notePositionOverrides: [.hiHat: .aboveLine9]
        ))
        let head = try #require(layout.noteHeads.first)
        let articulation = try #require(layout.articulations.first)
        // Bravura pictOpen needs articulationVerticalOffset 24 > one staff space,
        // so the old "center within head elevation + staff space" margin no longer
        // holds by design; pin the clearance the offset exists for instead (>= 2pt
        // between pictOpen ink and the X-head ink) and keep sheet containment via
        // the real painted bounds.
        #expect(
            head.paintedBounds(style: style).minY
                - articulation.paintedBounds(style: style).maxY >= 2
        )
        let topEdge = articulation.paintedBounds(style: style).minY
        let sheetOriginY: CGFloat = 0
        let viewModel = GameplayViewModelCoverageTestSupport.makeViewModel(chart: Chart(difficulty: .medium))
        viewModel.installNotationLayout(layout)
        let gameplayView = GameplayView(chart: viewModel.chart, metronome: viewModel.metronome)
        let contentTopInset = gameplayView.sheetContentTopInset(viewModel: viewModel)

        #expect(topEdge + contentTopInset >= sheetOriginY)
        #expect(gameplayView.sheetContentHeight(viewModel: viewModel) == layout.totalHeight + contentTopInset)
    }

    @Test("highest control-only stop mark painted bounds stay inside the sheet origin")
    func testHighestControlOnlyStopMarkStaysInsideSheetOrigin() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let event = NotationControlEvent(ChartControlEvent(
            kind: .stop,
            measureNumber: 1,
            measureOffset: 0,
            targetLaneID: "1A"
        ))
        let layout = NotationLayoutEngine().layout(input: NotationLayoutInput(
            notes: [],
            controlEvents: [event],
            timeSignature: .fourFour,
            style: style,
            notePositionOverrides: [.crash: .aboveLine9]
        ))
        let stop = try #require(layout.stopNotes.first)
        let paintedTopEdge = stop.position.y - style.stopMarkSize / 2 - style.stopMarkStrokeWidth / 2
        let viewModel = GameplayViewModelCoverageTestSupport.makeViewModel(chart: Chart(difficulty: .medium))
        viewModel.installNotationLayout(layout)
        let gameplayView = GameplayView(chart: viewModel.chart, metronome: viewModel.metronome)
        let contentTopInset = gameplayView.sheetContentTopInset(viewModel: viewModel)

        #expect(!layout.hasPlayableContent)
        #expect(layout.hasRenderableContent)
        #expect(paintedTopEdge + contentTopInset >= 0)
        #expect(gameplayView.sheetContentHeight(viewModel: viewModel) == layout.totalHeight + contentTopInset)
    }

    @Test("Notation primitives never render yellow highlighting")
    func testNotationPrimitivesDoNotRenderYellowHighlighting() async throws {
        #if os(macOS)
        try await TestSetup.withTestSetup {
            let noteHead = makeRenderedHead()
            let stem = RenderedStem(
                id: "stem-1",
                noteHeadIDs: [42],
                direction: .up,
                start: CGPoint(x: 66, y: 25),
                end: CGPoint(x: 66, y: 80)
            )
            let beam = RenderedBeam(
                id: "beam-1",
                noteHeadIDs: [42],
                direction: .up,
                level: 0,
                kind: .forwardHook,
                start: CGPoint(x: 35, y: 25),
                end: CGPoint(x: 95, y: 25),
                thickness: 4
            )
            let flag = RenderedFlag(
                id: "flag-1",
                noteHeadID: 42,
                stemDirection: .up,
                flagIndex: 0,
                origin: CGPoint(x: 66, y: 25)
            )
            let flagCommands = VirgoNotationAdapter.flagPaintCommands(
                flags: [flag],
                heads: [],
                style: .gameplayDefault
            )

            let view = ZStack {
                Color.black
                NotationBeamView(beam: beam)
                NotationStemView(stem: stem)
                ForEach(flagCommands) { NotationFlagView(command: $0) }
                NotationNoteHeadView(noteHead: noteHead, style: .gameplayDefault)
            }

            let yellowPixels = try countYellowPixels(in: view, size: CGSize(width: 140, height: 140))

            #expect(yellowPixels == 0, "Notation should not render yellow pixels")
        }
        #endif
    }

    @Test("Notation flag view mounts up and down flag commands")
    func testNotationFlagViewMountsCommands() async throws {
        try await TestSetup.withTestSetup {
            for direction in [StemDirection.up, .down] {
                let flag = RenderedFlag(
                    id: "flag-\(direction == .up ? "up" : "down")",
                    noteHeadID: 42,
                    stemDirection: direction,
                    flagIndex: 0,
                    origin: CGPoint(x: 50, y: 50)
                )
                let command = try #require(
                    VirgoNotationAdapter.flagPaintCommands(
                        flags: [flag],
                        heads: [],
                        style: .gameplayDefault
                    ).first
                )

                // Smoke test: the flag view should mount and render without errors.
                let view = NotationFlagView(command: command)
                SwiftUITestUtilities.assertViewWithEnvironment(view, size: CGSize(width: 120, height: 120))
            }
        }
    }

    @Test("Notation stem view mounts and renders")
    func testNotationStemViewRenders() async throws {
        try await TestSetup.withTestSetup {
            let stem = RenderedStem(
                id: "stem-1",
                noteHeadIDs: [42],
                direction: .up,
                start: CGPoint(x: 50, y: 20),
                end: CGPoint(x: 50, y: 80)
            )

            let view = NotationStemView(stem: stem)
            SwiftUITestUtilities.assertViewWithEnvironment(view, size: CGSize(width: 120, height: 120))
        }
    }

    @Test("Notation beam view mounts and renders")
    func testNotationBeamViewRenders() async throws {
        try await TestSetup.withTestSetup {
            let beam = RenderedBeam(
                id: "beam-1",
                noteHeadIDs: [42, 43],
                direction: .up,
                level: 0,
                kind: .full,
                start: CGPoint(x: 20, y: 30),
                end: CGPoint(x: 80, y: 30),
                thickness: 3.0
            )

            let view = NotationBeamView(beam: beam)
            SwiftUITestUtilities.assertViewWithEnvironment(view, size: CGSize(width: 120, height: 120))
        }
    }

    #if os(macOS)
    // MARK: - Bravura ink gates

    // Real-pixel gates: each production wrapper is rasterized in isolation and
    // its actual ink is checked against the same translated `paintedBounds`
    // production layout computes -- at least one alpha > 20 pixel inside, none
    // outside the bounds expanded by 1pt for antialias tolerance. This is not
    // a same-helper check: a wrapper that paints nothing, paints offset, or
    // paints oversized fails here even though view and metrics agree on data.

    @Test("whole normal notehead paints ink inside its painted bounds")
    func wholeNoteheadInkInsideBounds() async throws {
        try await TestSetup.withTestSetup {
            let style = NotationLayoutStyle.gameplayDefault
            let head = makeRenderedHead(id: 1, noteType: .snare, interval: .full)
            try assertWrapperInk(
                view: NotationNoteHeadView(noteHead: head, style: style),
                bounds: head.paintedBounds(style: style),
                label: "whole normal notehead"
            )
        }
    }

    @Test("quarter normal X and diamond noteheads paint ink inside painted bounds", arguments: [
        NoteType.snare, .hiHat, .cowbell
    ])
    func quarterNoteheadInkInsideBounds(_ noteType: NoteType) async throws {
        try await TestSetup.withTestSetup {
            let style = NotationLayoutStyle.gameplayDefault
            let head = makeRenderedHead(id: 2, noteType: noteType, interval: .quarter)
            try assertWrapperInk(
                view: NotationNoteHeadView(noteHead: head, style: style),
                bounds: head.paintedBounds(style: style),
                label: "quarter \(noteType.rawValue) notehead"
            )
        }
    }

    @Test("whole and quarter rests paint ink inside painted bounds", arguments: [
        NotationRestDuration.fullMeasure, .quarter
    ])
    func restInkInsideBounds(_ duration: NotationRestDuration) async throws {
        try await TestSetup.withTestSetup {
            let style = NotationLayoutStyle.gameplayDefault
            let rest = makeRenderedRest(
                id: "ink-rest-\(duration)",
                duration: duration,
                visibility: .printed
            )
            try assertWrapperInk(
                view: NotationRestView(rest: rest, style: style),
                bounds: rest.paintedBounds(style: style),
                label: "\(duration) rest"
            )
        }
    }

    @Test("isolated sixty-fourth flag command paints ink inside painted bounds")
    func sixtyFourthFlagCommandInkInsideBounds() async throws {
        try await TestSetup.withTestSetup {
            let style = NotationLayoutStyle.gameplayDefault
            let head = makeRenderedHead(id: 3, noteType: .snare, interval: .sixtyfourth)
            let origin = CGPoint(x: 100, y: 60)
            let flags = (0..<head.interval.flagCount).map { index in
                RenderedFlag(
                    id: "flag-64-\(index)",
                    noteHeadID: head.id,
                    stemDirection: .up,
                    flagIndex: index,
                    origin: origin
                )
            }
            let commands = VirgoNotationAdapter.flagPaintCommands(
                flags: flags,
                heads: [head],
                style: style
            )
            #expect(commands.count == 1, "a full uncovered set collapses to one canonical command")
            let command = try #require(commands.first)
            #expect(command.duration == .sixtyFourth)
            try assertWrapperInk(
                view: NotationFlagView(command: command),
                bounds: command.paintedBounds,
                label: "isolated 64th flag command"
            )
        }
    }

    @Test("open hi-hat articulation paints ink inside painted bounds")
    func openHiHatArticulationInkInsideBounds() async throws {
        try await TestSetup.withTestSetup {
            let style = NotationLayoutStyle.gameplayDefault
            let articulation = RenderedArticulation(
                id: "art-open",
                kind: .openHiHat,
                sourceNoteHeadID: 42,
                row: 0,
                position: CGPoint(x: 100, y: 100)
            )
            try assertWrapperInk(
                view: NotationArticulationView(articulation: articulation, style: style),
                bounds: articulation.paintedBounds(style: style),
                label: "open hi-hat articulation"
            )
        }
    }

    /// One representative visual preview for human inspection (see PR notes):
    /// whole + quarter normal heads, X + diamond heads, whole + quarter + 16th
    /// rests, isolated 8th + 64th flags, one partially beamed uncovered hook,
    /// and an open hi-hat articulation, mounted in production z-order. The
    /// absolute PNG path is printed so the exact generated file can be opened.
    @Test("Bravura preview row rasterizes to a non-empty PNG")
    func bravuraPreviewRowWritesPNG() async throws {
        try await TestSetup.withTestSetup {
            let style = NotationLayoutStyle.gameplayDefault
            let layout = makeBravuraPreviewRow(style: style)
            let yOffset = layout.topContentInset(style: style)
            let size = CGSize(width: layout.contentWidth, height: layout.totalHeight + yOffset)
            let view = makePreviewOverlay(layout: layout, style: style)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("hpa-163-bravura-preview.png")
            try writeRasterPNG(view, size: size, url: url)
            let data = try Data(contentsOf: url)
            #expect(!data.isEmpty, "preview PNG at \(url.path) is empty")
            print("[hpa-163] Bravura preview PNG written to: \(url.path)")
        }
    }
    #endif

    @Test("rhythm dot tuplet feel and warning views mount with semantic labels")
    func testRhythmPrimitiveViewsRender() async throws {
        try await TestSetup.withTestSetup {
            let style = NotationLayoutStyle.gameplayDefault
            let dot = RenderedRhythmDot(
                source: .event(RhythmEventID(rawValue: 1)),
                position: CGPoint(x: 30, y: 30),
                rowIndex: 0
            )
            let tuplet = RenderedTuplet(
                id: RhythmTupletID(
                    measureIndex: 0,
                    voice: .upper,
                    beatGroupIndex: 0,
                    startTick: 0,
                    durationTicks: 240,
                    stableMemberEventID: RhythmEventID(rawValue: 1)
                ),
                voice: .upper,
                ratio: TupletRatio(actual: 3, normal: 2),
                memberEventIDs: [RhythmEventID(rawValue: 1)],
                bracketPoints: [
                    CGPoint(x: 20, y: 50), CGPoint(x: 20, y: 40), CGPoint(x: 45, y: 40),
                    CGPoint(x: 55, y: 40), CGPoint(x: 80, y: 40), CGPoint(x: 80, y: 50)
                ],
                isBracketVisible: true,
                labelPosition: CGPoint(x: 50, y: 40),
                rowIndex: 0
            )
            let feel = RenderedFeelMark(
                feel: .swing,
                position: CGPoint(x: 50, y: 20),
                rowIndex: 0,
                style: style
            )
            let warning = RenderedRhythmWarning.measure(
                measureIndex: 0,
                kind: .unsupported,
                codes: [.ambiguousBeatGrouping],
                position: CGPoint(x: 80, y: 20),
                style: style
            )

            let views = ZStack {
                NotationRhythmDotView(dot: dot, style: style)
                NotationTupletView(tuplet: tuplet, style: style)
                NotationFeelMarkView(feelMark: feel, style: style)
                NotationRhythmWarningView(warning: warning, style: style)
            }
            SwiftUITestUtilities.assertViewWithEnvironment(views, size: CGSize(width: 180, height: 120))
            #expect(SwiftUITestUtilities.renderedTexts(
                from: NotationTupletView(tuplet: tuplet, style: style).body
            ).contains(tuplet.accessibilityLabel))
            #expect(SwiftUITestUtilities.renderedTexts(
                from: NotationFeelMarkView(feelMark: feel, style: style).body
            ).contains(feel.accessibilityLabel))
            #expect(SwiftUITestUtilities.renderedTexts(
                from: NotationRhythmWarningView(warning: warning, style: style).body
            ).contains(warning.accessibilityLabel))
        }
    }
}

private extension SwiftUIRenderingNotationTests {
    #if os(macOS)
    // MARK: - Bravura ink gate helpers

    /// Renders the production wrapper on a clear canvas (scale 1: 1pt = 1px)
    /// and asserts real ink against `bounds`: at least one alpha > 20 pixel
    /// inside, none outside the bounds expanded by 1pt for antialias tolerance.
    @MainActor
    private func assertWrapperInk<V: View>(
        view: V,
        bounds: CGRect,
        label: String,
        canvas: CGSize = CGSize(width: 200, height: 200)
    ) throws {
        guard !bounds.isNull else {
            Issue.record("\(label): painted bounds are null")
            return
        }
        let raster = try rasterizeView(ZStack { Color.clear; view }, size: canvas)
        #expect(
            inkCount(in: raster, rect: bounds) > 0,
            "\(label): no ink (alpha > 20) inside painted bounds \(bounds)"
        )
        let expanded = bounds.insetBy(dx: -1, dy: -1)
        let outside = totalInk(in: raster) - inkCount(in: raster, rect: expanded)
        #expect(
            outside == 0,
            "\(label): \(outside) ink pixels outside expanded painted bounds \(expanded)"
        )
    }

    private func inkCount(in raster: RasterBitmap, rect: CGRect) -> Int {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(raster.width - 1, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(raster.height - 1, Int(rect.maxY.rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return 0 }
        var count = 0
        for y in minY...maxY {
            for x in minX...maxX where raster.pixel(at: y * raster.width + x).alpha > 20 {
                count += 1
            }
        }
        return count
    }

    private func totalInk(in raster: RasterBitmap) -> Int {
        raster.count { $0.alpha > 20 }
    }

    // MARK: - Bravura preview row fixture

    /// The preview row mounted in production z-order (same layers, same order,
    /// as `GameplaySheetMusicView.GameplayDrumNotationView`), shifted by the
    /// sheet's content inset.
    @MainActor
    private func makePreviewOverlay(
        layout: NotationLayout,
        style: NotationLayoutStyle
    ) -> some View {
        let flagCommands = VirgoNotationAdapter.flagPaintCommands(
            flags: layout.flags,
            heads: layout.noteHeads,
            style: style
        )
        let yOffset = layout.topContentInset(style: style)
        return ZStack {
            Color.clear
            ForEach(layout.rests) { NotationRestView(rest: $0, style: style) }
            ForEach(layout.beams) { NotationBeamView(beam: $0) }
            ForEach(flagCommands) { NotationFlagView(command: $0) }
            ForEach(layout.stems) { NotationStemView(stem: $0) }
            ForEach(layout.noteHeads) { NotationNoteHeadView(noteHead: $0, style: style) }
            ForEach(layout.articulations) { NotationArticulationView(articulation: $0, style: style) }
        }
        .offset(y: yOffset)
    }

    /// Hand-assembled single-row fixture spanning every representative Bravura
    /// primitive. Geometry comes from the same package metrics production uses
    /// (via the adapter); mounting follows production z-order.
    private func makeBravuraPreviewRow(style: NotationLayoutStyle) -> NotationLayout {
        var layout = makePreviewRowBase(style: style)
        let xHead = layout.noteHeads.first { $0.noteType == .hiHat }
        if let xHead {
            layout.articulations = [
                RenderedArticulation(
                    id: "preview-open",
                    kind: .openHiHat,
                    sourceNoteHeadID: xHead.id,
                    row: 0,
                    position: CGPoint(
                        x: xHead.position.x,
                        y: xHead.position.y - style.articulationVerticalOffset
                    )
                )
            ]
        }
        layout.paintedBounds = layout.calculatePaintedBounds(style: style)
        layout.totalHeight = max(GameplayLayout.rowHeight, layout.paintedBounds.maxY)
        return layout
    }

    /// Heads, stems, rests, the beamed pair, and the flags of the preview row.
    private func makePreviewRowBase(style: NotationLayoutStyle) -> NotationLayout {
        var layout = NotationLayout.empty
        let whole = makePreviewHead(1, .snare, .full, x: 90, y: 40)
        let quarter = makePreviewHead(2, .snare, .quarter, x: 170, y: 40)
        let xHead = makePreviewHead(3, .hiHat, .quarter, x: 250, y: 12)
        let diamond = makePreviewHead(4, .cowbell, .quarter, x: 330, y: 12)
        let eighth = makePreviewHead(5, .snare, .eighth, x: 610, y: 40)
        let sixtyFourth = makePreviewHead(6, .snare, .sixtyfourth, x: 690, y: 40)
        let beamedA = makePreviewHead(7, .snare, .sixteenth, x: 770, y: 40)
        let beamedB = makePreviewHead(8, .snare, .sixteenth, x: 830, y: 40)

        let eighthStem = makePreviewStem(
            "preview-stem-8", for: eighth,
            length: VirgoNotationAdapter.minimumUnbeamedStemLength(heads: [eighth], style: style),
            style: style
        )
        let sixtyFourthStem = makePreviewStem(
            "preview-stem-64", for: sixtyFourth,
            length: VirgoNotationAdapter.minimumUnbeamedStemLength(heads: [sixtyFourth], style: style),
            style: style
        )
        let beamedAStem = makePreviewStem("preview-stem-a", for: beamedA, length: style.stemLength, style: style)
        let beamedBStem = makePreviewStem("preview-stem-b", for: beamedB, length: style.stemLength, style: style)

        layout.noteHeads = [whole, quarter, xHead, diamond, eighth, sixtyFourth, beamedA, beamedB]
        layout.rests = [
            makePreviewRest("preview-rest-whole", .fullMeasure, x: 410, y: 20),
            makePreviewRest("preview-rest-quarter", .quarter, x: 470, y: 40),
            makePreviewRest("preview-rest-16th", .sixteenth, x: 530, y: 40)
        ]
        layout.stems = [eighthStem.stem, sixtyFourthStem.stem, beamedAStem.stem, beamedBStem.stem]
        layout.beams = [RenderedBeam(
            id: "preview-beam",
            noteHeadIDs: [beamedA.id, beamedB.id],
            direction: .up,
            level: 0,
            kind: .full,
            start: beamedAStem.tip,
            end: beamedBStem.tip,
            thickness: style.beamThickness
        )]
        layout.flags = makePreviewFlags(for: eighth, tip: eighthStem.tip)
            + makePreviewFlags(for: sixtyFourth, tip: sixtyFourthStem.tip)
            + [
                // Partially beamed pair: the primary beam covers level 0 of the
                // second head; its uncovered secondary level stays a flag.
                RenderedFlag(
                    id: "preview-flag-hook", noteHeadID: beamedB.id,
                    stemDirection: .up, flagIndex: 1, origin: beamedBStem.tip
                )
            ]
        return layout
    }

    /// Full uncovered flag set for one unbeamed head (the canonical-collapse case).
    private func makePreviewFlags(for head: RenderedNoteHead, tip: CGPoint) -> [RenderedFlag] {
        (0..<head.interval.flagCount).map { index in
            RenderedFlag(
                id: "preview-flag-\(head.id)-\(index)",
                noteHeadID: head.id,
                stemDirection: .up,
                flagIndex: index,
                origin: tip
            )
        }
    }

    private func makePreviewHead(
        _ id: UInt64,
        _ noteType: NoteType,
        _ interval: NoteInterval,
        x: CGFloat,
        y: CGFloat
    ) -> RenderedNoteHead {
        RenderedNoteHead(
            id: id,
            sourceLaneID: nil,
            sourceChipID: nil,
            noteType: noteType,
            drumType: DrumType.from(noteType: noteType) ?? .snare,
            variant: .standard,
            voice: .upper,
            stemDirection: .up,
            timeColumn: NotationTimeColumn(measureIndex: 0, tickWithinMeasure: 0, absoluteLayoutTick: 0),
            timePosition: 0,
            row: 0,
            position: CGPoint(x: x, y: y),
            staffStep: 0,
            interval: interval,
            catalogOrder: Int(id)
        )
    }

    private func makePreviewStem(
        _ id: String,
        for head: RenderedNoteHead,
        length: CGFloat,
        style: NotationLayoutStyle
    ) -> (stem: RenderedStem, tip: CGPoint) {
        let anchor = VirgoNotationAdapter.noteheadMetrics(for: head, style: style).stemAnchorOffset
        let start = CGPoint(x: head.position.x + anchor.x, y: head.position.y + anchor.y)
        let tip = CGPoint(x: start.x, y: start.y - length)
        let stem = RenderedStem(id: id, noteHeadIDs: [head.id], direction: .up, start: start, end: tip)
        return (stem, tip)
    }

    private func makePreviewRest(
        _ id: String,
        _ duration: NotationRestDuration,
        x: CGFloat,
        y: CGFloat
    ) -> RenderedRest {
        RenderedRest(
            id: id,
            timeColumn: NotationTimeColumn(measureIndex: 0, tickWithinMeasure: 0, absoluteLayoutTick: 0),
            measureIndex: 0,
            row: 0,
            voice: .upper,
            durationTicks: 960,
            duration: duration,
            visibility: .printed,
            position: CGPoint(x: x, y: y)
        )
    }
    #endif

    func makeRenderedRest(
        id: String,
        duration: NotationRestDuration,
        visibility: NotationRestVisibility
    ) -> RenderedRest {
        RenderedRest(
            id: id,
            timeColumn: NotationTimeColumn(
                measureIndex: 0,
                tickWithinMeasure: 0,
                absoluteLayoutTick: 0
            ),
            measureIndex: 0,
            row: 0,
            voice: .upper,
            durationTicks: 960,
            duration: duration,
            visibility: visibility,
            position: CGPoint(x: 60, y: 60)
        )
    }

    func makeRenderedStop(id: String, kind: NotationControlEventKind) -> RenderedStopNote {
        RenderedStopNote(
            id: id,
            kind: kind,
            sourceLaneID: "55",
            sourceNoteID: "0A",
            targetLaneID: "1A",
            targetDisplayName: "Crash",
            timeColumn: NotationTimeColumn(
                measureIndex: 0,
                tickWithinMeasure: 0,
                absoluteLayoutTick: 0
            ),
            row: 0,
            position: CGPoint(x: 60, y: 60)
        )
    }

    func accessibilityVisibilityRawValues(
        in value: Any,
        path: [String] = [],
        depth: Int = 0
    ) -> [UInt32] {
        guard depth < 16 else { return [] }
        let mirror = Mirror(reflecting: value)
        var values: [UInt32] = []
        for child in mirror.children {
            let label = child.label ?? ""
            let childPath = path + [label]
            if label == "rawValue",
               childPath.contains("visibility"),
               let rawValue = child.value as? UInt32 {
                values.append(rawValue)
            }
            values.append(contentsOf: accessibilityVisibilityRawValues(
                in: child.value,
                path: childPath,
                depth: depth + 1
            ))
        }
        return values
    }

    func makeRenderedHead(
        id: UInt64 = 42,
        noteType: NoteType = .snare,
        interval: NoteInterval = .quarter
    ) -> RenderedNoteHead {
        return RenderedNoteHead(
            id: id,
            sourceLaneID: nil,
            sourceChipID: nil,
            noteType: noteType,
            drumType: DrumType.from(noteType: noteType) ?? .snare,
            variant: .standard,
            voice: .upper,
            stemDirection: .up,
            timeColumn: NotationTimeColumn(
                measureIndex: 0,
                tickWithinMeasure: 0,
                absoluteLayoutTick: 0
            ),
            timePosition: 0,
            row: 0,
            position: CGPoint(x: 60, y: 60),
            staffStep: -4,
            interval: interval,
            catalogOrder: 1
        )
    }
}
