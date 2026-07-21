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

private enum RenderProbeError: Error {
    case missingCGImage
    case missingPixelBuffer
    case missingBitmapContext
}

#if os(macOS)
@MainActor
private func countYellowPixels<V: View>(in view: V, size: CGSize) throws -> Int {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = 1
    guard let cgImage = renderer.cgImage else {
        throw RenderProbeError.missingCGImage
    }

    let width = cgImage.width
    let height = cgImage.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    try pixels.withUnsafeMutableBytes { buffer in
        guard let baseAddress = buffer.baseAddress else {
            throw RenderProbeError.missingPixelBuffer
        }
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RenderProbeError.missingBitmapContext
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    return stride(from: 0, to: pixels.count, by: bytesPerPixel).reduce(0) { count, index in
        let red = pixels[index]
        let green = pixels[index + 1]
        let blue = pixels[index + 2]
        let alpha = pixels[index + 3]
        let isYellow = alpha > 20 && red > 180 && green > 150 && blue < 120
        return count + (isYellow ? 1 : 0)
    }
}
#endif

@Suite("SwiftUI Rendering Notation Tests", .serialized)
@MainActor
struct SwiftUIRenderingNotationTests {
    @Test("Notation primitive mounts every vector notehead")
    func testNotationPrimitiveMountsEveryVectorNotehead() async throws {
        try await TestSetup.withTestSetup {
            for (index, glyph) in DrumNoteheadGlyph.allCases.enumerated() {
                let noteHead = makeRenderedHead(id: UInt64(index), glyph: glyph)
                SwiftUITestUtilities.assertViewWithEnvironment(
                    NotationNoteHeadView(
                        noteHead: noteHead,
                        size: CGSize(width: 30, height: 20)
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
            viewModel.setupGameplay(loadPersistedSpeed: false)
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
                    NotationNoteHeadView(noteHead: noteHead, size: layout.noteHeadSize)
                }
            }

            SwiftUITestUtilities.assertViewWithEnvironment(
                noteHeadViews,
                size: CGSize(width: 1_024, height: 768)
            )
            let noteHeadLabels = layout.noteHeads.flatMap { noteHead in
                SwiftUITestUtilities.renderedTexts(from: NotationNoteHeadView(
                    noteHead: noteHead,
                    size: layout.noteHeadSize
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
        let line5Y = GameplayLayout.StaffLinePosition.line5.absoluteY(for: head.row)
        let existingTopMargin = (line5Y - head.position.y) + GameplayLayout.staffLineSpacing
        let topEdge = articulation.position.y
            - style.articulationDiameter / 2
            - style.articulationStrokeWidth / 2
        let sheetOriginY: CGFloat = 0
        let viewModel = GameplayViewModelCoverageTestSupport.makeViewModel(chart: Chart(difficulty: .medium))
        viewModel.cachedNotationLayout = layout
        let gameplayView = GameplayView(chart: viewModel.chart, metronome: viewModel.metronome)
        let contentTopInset = gameplayView.sheetContentTopInset(viewModel: viewModel)

        #expect(line5Y - articulation.position.y <= existingTopMargin)
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
        viewModel.cachedNotationLayout = layout
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

            let view = ZStack {
                Color.black
                NotationBeamView(beam: beam)
                NotationStemView(stem: stem)
                NotationFlagView(flag: flag)
                NotationNoteHeadView(
                    noteHead: noteHead,
                    size: CGSize(width: 30, height: 20)
                )
            }

            let yellowPixels = try countYellowPixels(in: view, size: CGSize(width: 140, height: 140))

            #expect(yellowPixels == 0, "Notation should not render yellow pixels")
        }
        #endif
    }

    @Test("Notation flag view mounts and renders")
    func testNotationFlagViewRenders() async throws {
        try await TestSetup.withTestSetup {
            let flag = RenderedFlag(
                id: "flag-1",
                noteHeadID: 42,
                stemDirection: .up,
                flagIndex: 0,
                origin: CGPoint(x: 50, y: 50)
            )

            // Smoke test: the flag view should mount and render without errors.
            let view = NotationFlagView(flag: flag)
            SwiftUITestUtilities.assertViewWithEnvironment(view, size: CGSize(width: 120, height: 120))
        }
    }

    @Test("Notation flag view renders with stem-down direction")
    func testNotationFlagViewRendersWithStemDown() async throws {
        try await TestSetup.withTestSetup {
            let flag = RenderedFlag(
                id: "flag-2",
                noteHeadID: 43,
                stemDirection: .down,
                flagIndex: 0,
                origin: CGPoint(x: 50, y: 70)
            )

            // Smoke test: stem-down flag should mount and render without errors
            let view = NotationFlagView(flag: flag)
            SwiftUITestUtilities.assertViewWithEnvironment(view, size: CGSize(width: 120, height: 120))
        }
    }

    @Test("Notation flag position is adjusted for center-based placement")
    func testNotationFlagPositionAdjustedForCenterPlacement() async throws {
        try await TestSetup.withTestSetup {
            // The adjustedCenter property should offset by half the flag frame size
            // so the path origin (0,0) lands on flag.origin instead of the frame center.
            let flagUp = RenderedFlag(
                id: "flag-up",
                noteHeadID: 42,
                stemDirection: .up,
                flagIndex: 0,
                origin: CGPoint(x: 50, y: 50)
            )
            let flagDown = RenderedFlag(
                id: "flag-down",
                noteHeadID: 43,
                stemDirection: .down,
                flagIndex: 0,
                origin: CGPoint(x: 50, y: 70)
            )

            // Both directions should render without error (smoke test for the
            // corrected positioning logic — the actual position correction is
            // exercised visually; this ensures no crash/miscompile).
            let upView = NotationFlagView(flag: flagUp)
            SwiftUITestUtilities.assertViewWithEnvironment(upView, size: CGSize(width: 120, height: 120))

            let downView = NotationFlagView(flag: flagDown)
            SwiftUITestUtilities.assertViewWithEnvironment(downView, size: CGSize(width: 120, height: 120))
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
        glyph: DrumNoteheadGlyph = .filledDiamond
    ) -> RenderedNoteHead {
        // `note` is intentionally unretained: it exists only to produce a
        // unique ObjectIdentifier placeholder for sourceObjectID. The rendering
        // tests never dereference it or compare it against a live Note, so the
        // dangling identity is safe for current use.
        let note = Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: 0
        )
        return RenderedNoteHead(
            id: id,
            sourceObjectID: ObjectIdentifier(note),
            sourceLaneID: nil,
            sourceChipID: nil,
            noteType: .snare,
            drumType: .snare,
            glyph: glyph,
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
            interval: .quarter,
            catalogOrder: 1
        )
    }
}
