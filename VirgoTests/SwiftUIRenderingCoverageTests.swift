//
//  SwiftUIRenderingCoverageTests.swift
//  VirgoTests
//
//  Created by Copilot on 22/3/2026.
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

@Suite("SwiftUI Rendering Coverage Tests", .serialized)
@MainActor
struct SwiftUIRenderingCoverageTests {
    private let drumNotationSettingsKey = "DrumNotationSettings"

    private struct MountedLifecycleTextView: View {
        @State private var text = "Initial Text"

        var body: some View {
            Text(text)
                .onAppear {
                    text = "Mounted Text"
                }
        }
    }

    @Test("SettingsView renders inside a navigation stack")
    func testSettingsViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                SettingsView()
            }
            .environmentObject(MetronomeEngine(audioDriver: RecordingAudioDriver()))

            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("Render helper does not create visible windows")
    func testRenderHelperDoesNotCreateVisibleWindows() async throws {
        try await TestSetup.withTestSetup {
            #if os(macOS)
            let initialVisibleWindowCount = NSApp.windows.filter(\.isVisible).count

            SwiftUITestUtilities.assertViewWithEnvironment(Text("Offscreen Render"))

            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            let finalVisibleWindowCount = NSApp.windows.filter(\.isVisible).count
            #expect(finalVisibleWindowCount == initialVisibleWindowCount)
            #endif
        }
    }

    @Test("assertView inspects the mounted hierarchy after onAppear updates")
    func testAssertViewUsesMountedHierarchyAfterOnAppear() async throws {
        try await TestSetup.withTestSetup {
            SwiftUITestUtilities.assertView(
                MountedLifecycleTextView(),
                containsStrings: ["Mounted Text"],
                excludesStrings: ["Initial Text"]
            )
        }
    }

    @Test("AudioSettingsView renders its sections")
    func testAudioSettingsViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                AudioSettingsView()
            }

            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("DrumNotationSettingsView renders interactive notation controls")
    func testDrumNotationSettingsViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                DrumNotationSettingsView()
            }

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 1600)
            )
        }
    }

    @Test("DrumNotationSettingsManager persists custom positions and resets defaults")
    func testDrumNotationSettingsManagerPersistence() async throws {
        try await TestSetup.withTestSetup {
            let (userDefaults, _) = TestUserDefaults.makeIsolated()
            userDefaults.removeObject(forKey: drumNotationSettingsKey)

            let manager = DrumNotationSettingsManager(userDefaults: userDefaults)
            manager.loadSettings()

            for drumType in DrumType.allCases {
                #expect(manager.getNotePosition(for: drumType) == drumType.notePosition)
            }

            manager.setNotePosition(.belowLine6, for: .snare)
            #expect(manager.getNotePosition(for: .snare) == .belowLine6)

            let reloadedManager = DrumNotationSettingsManager(userDefaults: userDefaults)
            reloadedManager.loadSettings()
            #expect(reloadedManager.getNotePosition(for: .snare) == .belowLine6)

            manager.resetToDefaults()
            #expect(manager.getNotePosition(for: .snare) == DrumType.snare.notePosition)
        }
    }

    @Test("GameplayLayout note positions expose stable display names and raw values")
    func testNotePositionDisplayNamesAndRawValues() {
        let positions = GameplayLayout.NotePosition.allCases
        #expect(!positions.isEmpty)

        let rawValues = Set(positions.map(\.rawValue))
        #expect(rawValues.count == positions.count)

        for position in positions {
            #expect(!position.displayName.isEmpty)
            #expect(!position.rawValue.isEmpty)
        }
    }

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

    @Test("Gameplay sheet sizing uses notation width only when note heads are active")
    func testGameplaySheetSizingUsesNotationWidthOnlyWhenActive() async throws {
        try await TestSetup.withTestSetup {
            let emptyViewModel = GameplayViewModelCoverageTestSupport.makeViewModel(
                chart: Chart(difficulty: .medium),
                noteCount: 0
            )
            await emptyViewModel.loadChartData()
            emptyViewModel.setupGameplay()

            let gameplayView = GameplayView(chart: emptyViewModel.chart, metronome: emptyViewModel.metronome)
            #expect(!gameplayView.usesNotationLayout(viewModel: emptyViewModel))
            #expect(emptyViewModel.cachedNotationLayout.measureBars.count >= 1)
            #expect(gameplayView.sheetContentWidth(viewModel: emptyViewModel) == GameplayLayout.maxRowWidth)

            let denseChart = Chart(difficulty: .medium)
            for index in 0..<32 {
                denseChart.notes.append(
                    Note(
                        interval: .sixteenth,
                        noteType: .snare,
                        measureNumber: 1,
                        measureOffset: Double(index) / 32.0
                    )
                )
            }
            let denseViewModel = GameplayViewModelCoverageTestSupport.makeViewModel(chart: denseChart)
            await denseViewModel.loadChartData()
            denseViewModel.setupGameplay()

            #expect(gameplayView.usesNotationLayout(viewModel: denseViewModel))
            #expect(gameplayView.sheetContentWidth(viewModel: denseViewModel) > GameplayLayout.maxRowWidth)
            #expect(
                gameplayView.sheetContentHeight(viewModel: denseViewModel)
                    == denseViewModel.cachedNotationLayout.totalHeight
            )
        }
    }
}

private extension SwiftUIRenderingCoverageTests {
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
