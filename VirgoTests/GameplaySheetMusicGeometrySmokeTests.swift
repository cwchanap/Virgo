//
//  GameplaySheetMusicGeometrySmokeTests.swift
//  VirgoTests
//
//  HPA-166 Task 9 review fix — mounted geometry-to-raster region gates
//  and the hosted accessibility hierarchy.
//

import Testing
import SwiftUI
import Foundation
import DrumNotation
@testable import Virgo

#if os(macOS)
import AppKit

/// The hosted sheet's viewport — the size the production `ScrollView`
/// clips to in every scenario below.
let mountedViewport = CGSize(width: 1_024, height: 768)

/// Region-scoped differential: counts pixels inside `rect` (clamped to the
/// bitmap) whose channels differ between two rasters. `changedPixelCount`
/// proves a family paints *somewhere*; this pins the ink to the region the
/// engraving says it must occupy.
func changedPixels(
    in rect: CGRect,
    between lhs: RasterBitmap,
    and rhs: RasterBitmap
) -> Int {
    guard lhs.width == rhs.width, lhs.height == rhs.height else { return .max }
    let minX = max(0, Int(rect.minX.rounded(.down)))
    let maxX = min(lhs.width, Int(rect.maxX.rounded(.up)))
    let minY = max(0, Int(rect.minY.rounded(.down)))
    let maxY = min(lhs.height, Int(rect.maxY.rounded(.up)))
    guard minX < maxX, minY < maxY else { return 0 }
    var count = 0
    for y in minY..<maxY {
        for x in minX..<maxX {
            let index = y * lhs.width + x
            let first = lhs.pixel(at: index)
            let second = rhs.pixel(at: index)
            if first.red != second.red || first.green != second.green
                || first.blue != second.blue || first.alpha != second.alpha {
                count += 1
            }
        }
    }
    return count
}

/// Everything one mounted scenario needs: the view model that owns the
/// installed engraving, the production `GameplayView` mounting it, and the
/// prepared state both came from.
struct MountedSheet {
    let viewModel: GameplayViewModel
    let gameplayView: GameplayView
    let engraving: EngravedNotation
    let presentation: GameplayNotationPresentation
}

/// The stroke rect one beam segment paints: its segment bounds padded by
/// half the stroke thickness plus a 1pt rasterization pad.
private func beamInkRect(for beam: EngravedBeam) -> CGRect {
    CGRect(
        x: min(beam.start.x, beam.end.x) - 1,
        y: min(beam.start.y, beam.end.y) - beam.thickness / 2 - 1,
        width: abs(beam.end.x - beam.start.x) + 2,
        height: abs(beam.end.y - beam.start.y) + beam.thickness + 2
    )
}

/// The mirror-image rect on the wrong side of the hook's stem axis —
/// where the ink would land if the hook's direction were reversed.
private func hookMirrorRect(for beam: EngravedBeam) -> CGRect {
    let length = abs(beam.end.x - beam.start.x)
    let minX = beam.end.x > beam.start.x
        ? beam.start.x - length - 2
        : beam.start.x + 2
    return CGRect(
        x: minX,
        y: beam.start.y - beam.thickness / 2 - 1,
        width: length,
        height: beam.thickness + 2
    )
}

/// The pure-stem band of one engraved stem: stem-width around the segment
/// with both ends inset past the head anchor and the beam/flag tip, so
/// only stem ink lands inside.
private func stemInkRect(_ stem: EngravedStem) -> CGRect {
    CGRect(
        x: min(stem.start.x, stem.end.x) - 2,
        y: min(stem.start.y, stem.end.y) + 3,
        width: abs(stem.end.x - stem.start.x) + 4,
        height: max(1, abs(stem.end.y - stem.start.y) - 6)
    )
}

/// Mounted geometry-region and accessibility gates over the same
/// production hierarchy the primitive-family smoke uses — `ScrollView` →
/// `GameplayStaticNotationView` → `GameplayStaticNotationLayers` →
/// `DrumNotationView`. Where `GameplaySheetMusicSmokeTests` asks "does the
/// family paint at all", this suite asks "does it paint where the
/// engraving says, and does the VoiceOver map reach the mounted tree".
@Suite("Gameplay sheet music geometry smoke", .serialized)
@MainActor
struct GameplaySheetMusicGeometrySmokeTests {
    /// Runs a real-DTX fixture through the full production path — DTX
    /// parse → persistence projection → rhythm resolve → snapshot →
    /// `GameplayNotationPreparer` → `installPreparedNotation` — at the
    /// viewport width the hosted sheet's `onAppear` will report, so the
    /// first raster cannot trigger a re-engrave mid-differential.
    func mountFixture(_ fixture: DrumTabFixture) async throws -> MountedSheet {
        let rendered = try DrumTabFixtureHarness.render(fixture)
        let viewModel = GameplayViewModel(
            chart: rendered.chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.updateRowWidth(mountedViewport.width)
        let engraving = try #require(viewModel.cachedEngravedNotation)
        let presentation = viewModel.notationPresentation
            ?? GameplayNotationPresentation(annotations: .empty, accessibilityLabels: [:])
        return MountedSheet(
            viewModel: viewModel,
            gameplayView: GameplayView(
                chart: viewModel.chart,
                metronome: viewModel.metronome,
                initialViewModel: viewModel
            ),
            engraving: engraving,
            presentation: presentation
        )
    }

    /// Rasterizes the mounted production sheet — the same
    /// `sheetMusicView(geometry:)` call `GameplayView.body` makes, hosted
    /// in a real `NSHostingView` so the `ScrollView` document paints.
    func rasterize(_ sheet: MountedSheet) throws -> RasterBitmap {
        try rasterize(sheet, scrollY: 0)
    }

    /// Same hosted rasterization after scrolling the sheet's `NSScrollView`
    /// `scrollY` document points down.
    func rasterize(_ sheet: MountedSheet, scrollY: CGFloat) throws -> RasterBitmap {
        try rasterizeHostedView(
            GeometryReader { proxy in
                sheet.gameplayView.sheetMusicView(geometry: proxy)
            },
            size: mountedViewport,
            scrollY: scrollY
        )
    }

    /// Reinstalls the same prepared state with one primitive family
    /// swapped out — the region differential's "off"/sabotaged state.
    func reinstall(
        _ sheet: MountedSheet,
        engraving: EngravedNotation,
        presentation: GameplayNotationPresentation? = nil
    ) {
        sheet.viewModel.installPreparedNotation(.ready(
            engraving,
            presentation ?? sheet.presentation
        ))
    }

    /// Region gate for hook direction: each engraved hook must change
    /// pixels inside its own stroke rect when beams are stripped, and the
    /// mirror rect on the wrong side of the stem axis must stay untouched.
    /// A reversed hook empties the expected rect and fills the mirror —
    /// both assertions fail — so direction is pinned, not just presence.
    @Test("sheetMusicView paints hooks in their engraved direction")
    func mountedSheetPaintsHookRegions() async throws {
        try await TestSetup.withTestSetup {
            let sheet = try await mountFixture(DrumTabFixtureCatalog.tripletHooksAndStop)
            defer { sheet.viewModel.cleanup() }

            let forward = sheet.engraving.beams.filter { $0.kind == .forwardHook }
            let backward = sheet.engraving.beams.filter { $0.kind == .backwardHook }
            try #require(!forward.isEmpty, "fixture must engrave a forward hook")
            try #require(!backward.isEmpty, "fixture must engrave a backward hook")
            for hook in forward { #expect(hook.end.x > hook.start.x) }
            for hook in backward { #expect(hook.end.x < hook.start.x) }

            let headful = try rasterize(sheet)
            reinstall(sheet, engraving: sheet.engraving.swapping(beams: []))
            let beardless = try rasterize(sheet)

            for hook in forward + backward {
                assertHookDirection(hook, headful: headful, beardless: beardless)
            }
        }
    }

    /// One hook's two-sided ink check: its engraved stroke rect must hold
    /// hook ink, and the mirror rect — where a reversed hook's segment
    /// would land — must hold less than a quarter of it. Stroke caps and
    /// antialiasing bleed a pixel or two across the axis, so the mirror
    /// gate is relative rather than absolute zero.
    private func assertHookDirection(
        _ hook: EngravedBeam,
        headful: RasterBitmap,
        beardless: RasterBitmap
    ) {
        let expectedInk = changedPixels(
            in: beamInkRect(for: hook),
            between: headful, and: beardless
        )
        #expect(
            expectedInk > 0,
            "hook at \(hook.start) painted no ink inside its engraved rect"
        )
        let mirrorInk = changedPixels(
            in: hookMirrorRect(for: hook),
            between: headful, and: beardless
        )
        #expect(
            mirrorInk * 4 <= expectedInk,
            """
            hook at \(hook.start): \(mirrorInk) mirror-side pixels vs \
            \(expectedInk) expected — hook painted on the wrong side?
            """
        )
    }

    /// Head/stem attachment: the head-side anchor of every representative
    /// stem sits inside (±2pt) a served head's painted bounds, and each
    /// stem's interior band must lose ink when stems are stripped — and
    /// again when stems are shifted off their engraved segments. A stem
    /// painted detached leaves the expected rect empty in either
    /// differential, so the region gate fails for detachment, not only
    /// for removal.
    @Test("sheetMusicView attaches stems to their heads' bounds")
    func mountedSheetAttachesStemsToHeads() async throws {
        try await TestSetup.withTestSetup {
            let sheet = try await mountFixture(DrumTabFixtureCatalog.tripletHooksAndStop)
            defer { sheet.viewModel.cleanup() }
            let viewportRect = CGRect(origin: .zero, size: mountedViewport)

            // Representative attached stems whose pure-stem band is fully
            // inside the hosted viewport.
            let stems = sheet.engraving.stems.filter {
                viewportRect.contains(stemInkRect($0))
            }
            try #require(stems.count >= 3, "fixture must mount several visible stems")
            try assertStemAnchors(stems, in: sheet.engraving)

            let headful = try rasterize(sheet)
            reinstall(sheet, engraving: sheet.engraving.swapping(stems: []))
            let stemless = try rasterize(sheet)
            assertStemInk(stems, headful: headful, stripped: stemless, when: "removed")

            // Detachment sabotage: stems painted 3000pt off their engraved
            // segments must empty the same rects — the gate fails whether
            // stems are absent or merely painted detached.
            let shifted = sheet.engraving.stems.map { stem in
                EngravedStem(
                    noteIDs: stem.noteIDs,
                    direction: stem.direction,
                    start: CGPoint(x: stem.start.x + 3_000, y: stem.start.y),
                    end: CGPoint(x: stem.end.x + 3_000, y: stem.end.y)
                )
            }
            reinstall(sheet, engraving: sheet.engraving.swapping(stems: shifted))
            let detached = try rasterize(sheet)
            assertStemInk(stems, headful: headful, stripped: detached, when: "shifted off")
        }
    }

    /// Geometry half of attachment: every stem's head-side anchor sits in
    /// a served member head's painted bounds (a chord stem anchors on one
    /// member — the union is the contract).
    private func assertStemAnchors(_ stems: [EngravedStem], in engraving: EngravedNotation) throws {
        let headsByID = Dictionary(
            uniqueKeysWithValues: engraving.noteHeads.map { ($0.noteID, $0) }
        )
        for stem in stems {
            let memberHeads = stem.noteIDs.compactMap { headsByID[$0] }
            try #require(!memberHeads.isEmpty)
            #expect(
                memberHeads.contains {
                    $0.paintedBounds.insetBy(dx: -2, dy: -2).contains(stem.start)
                },
                "stem for \(stem.noteIDs) anchors at \(stem.start), outside every member head"
            )
        }
    }

    /// Raster half of attachment: every stem's interior band must hold
    /// stem ink — comparing the intact raster against the variant where
    /// stems are `when`-sabotaged.
    private func assertStemInk(
        _ stems: [EngravedStem],
        headful: RasterBitmap,
        stripped: RasterBitmap,
        when sabotage: String
    ) {
        for stem in stems {
            #expect(
                changedPixels(
                    in: stemInkRect(stem),
                    between: headful, and: stripped
                ) > 0,
                "no stem ink inside the engraved stem rect \(stem.start)→\(stem.end) after stems \(sabotage)"
            )
        }
    }

    /// Tuplet mount gate: the resolved triplet's numeral must paint inside
    /// its reserved label rect — stripping tuplets must change that rect.
    @Test("sheetMusicView paints the triplet numeral at its engraved position")
    func mountedSheetPaintsTupletLabel() async throws {
        try await TestSetup.withTestSetup {
            let sheet = try await mountFixture(DrumTabFixtureCatalog.tripletHooksAndStop)
            defer { sheet.viewModel.cleanup() }

            let tuplet = try #require(
                sheet.engraving.tuplets.first { $0.memberNoteIDs.count == 3 },
                "the supported triplet must engrave a tuplet primitive"
            )
            #expect(tuplet.ratio.actual == 3 && tuplet.ratio.normal == 2)

            let size = sheet.engraving.style.tupletLabelSize
            let labelRect = CGRect(
                x: tuplet.labelPosition.x - size.width / 2 - 1,
                y: tuplet.labelPosition.y - size.height / 2 - 1,
                width: size.width + 2,
                height: size.height + 2
            )

            let headful = try rasterize(sheet)
            reinstall(sheet, engraving: sheet.engraving.swapping(tuplets: []))
            let tupletless = try rasterize(sheet)

            #expect(
                changedPixels(in: labelRect, between: headful, and: tupletless) > 0,
                "no tuplet ink inside the engraved label rect at \(tuplet.labelPosition)"
            )
        }
    }

    /// Viewport-edge clipping: `multiRowStableWidths` engraves ~2700pt of
    /// content into a 768pt ScrollView viewport. The production sheet is
    /// hosted at its fixed viewport size inside an oversized rasterized
    /// ancestor carrying `sheetClipMargin` of capture space on every side —
    /// if the sheet's ScrollView ever fails to clip, the overflow ink
    /// lands in the margin bands instead of falling off the raster's edge,
    /// so the differential can actually see it. A second leg hosts the
    /// same production hierarchy with the scroll viewport grown to the
    /// full content height: the identical off-viewport heads must then
    /// produce differential ink outside the 768pt band — the unclipped
    /// control proving the clipped leg's zero is not vacuous.
    @Test("sheetMusicView clips engraved content at the viewport edge")
    func mountedSheetClipsAtViewportEdge() async throws {
        try await TestSetup.withTestSetup {
            let sheet = try await mountFixture(DrumTabFixtureCatalog.multiRowStableWidths)
            defer { sheet.viewModel.cleanup() }
            let viewportRect = CGRect(origin: .zero, size: mountedViewport)
            let engraving = sheet.engraving

            try #require(
                engraving.contentHeight > mountedViewport.height,
                "fixture must overflow the viewport vertically for the clipping gate"
            )
            let offscreen = engraving.noteHeads.filter {
                !viewportRect.intersects($0.paintedBounds)
            }
            let visible = engraving.noteHeads.filter {
                viewportRect.contains($0.paintedBounds)
            }
            try #require(!offscreen.isEmpty && !visible.isEmpty)

            let clipped = try rasterizeInAncestor(sheet, sheetSize: mountedViewport)
            try await assertClipHolds(
                sheet: sheet, reference: clipped, offscreenCount: offscreen.count
            )
            try await assertUnclippedControl(sheet: sheet, offscreenCount: offscreen.count)
            try await assertVisibleHeadChangesRaster(
                sheet: sheet, clipped: clipped, visible: visible
            )
        }
    }

    /// Edge-straddling head: the production sheet is hosted in the
    /// oversized ancestor with its ScrollView scrolled `crossingScrollY`
    /// document points down, so the row-2 heads at sheet-y ~770–790
    /// straddle the 768pt clip edge by ~10pt on each side — the boundary
    /// cuts real glyphs mid-stroke. ONE qualifying head then drives all
    /// three legs: removing it must move ink inside the clipped viewport,
    /// leave its own deep-outside mask (painted bounds below the clip edge
    /// plus the `clipEdgeBleed` AA band) strict zero in the clipped
    /// capture, and move ink inside that same document-space mask in the
    /// full-height control — margin- and scroll-translated per capture.
    /// Geometry depth alone cannot stand in for that pixel evidence.
    @Test("sheetMusicView clips a head straddling the viewport edge")
    func mountedSheetClipsEdgeCrossingHead() async throws {
        try await TestSetup.withTestSetup {
            let sheet = try await mountFixture(DrumTabFixtureCatalog.multiRowStableWidths)
            defer { sheet.viewModel.cleanup() }
            let engraving = sheet.engraving

            try #require(
                engraving.contentHeight > mountedViewport.height,
                "fixture must overflow the viewport vertically for the crossing gate"
            )
            // Viewport coordinates: sheet bounds shifted down by the scroll
            // offset. The head must straddle the edge deeply enough that
            // its outside part reaches past the clip-edge AA bleed band.
            let crossing = engraving.noteHeads.filter {
                $0.paintedBounds.minY - crossingScrollY < mountedViewport.height
                    && $0.paintedBounds.maxY - crossingScrollY > mountedViewport.height
            }
            try #require(
                !crossing.isEmpty,
                "no head straddles the 768pt edge at scroll \(crossingScrollY)"
            )
            try #require(
                crossing.allSatisfy {
                    mountedViewport.height - ($0.paintedBounds.minY - crossingScrollY) >= 6
                        && $0.paintedBounds.maxY - crossingScrollY
                            - (mountedViewport.height + clipEdgeBleed) >= 2
                },
                "crossing heads must straddle ≥6pt inside and ≥\(clipEdgeBleed + 2)pt outside"
            )
            // The same primitive must drive every leg: pick the qualifying
            // head reaching deepest below the edge so its deep-outside
            // mask carries the most ink.
            let head = try #require(
                crossing.max { $0.paintedBounds.maxY < $1.paintedBounds.maxY },
                "no qualifying boundary-crossing head"
            )

            let clipped = try rasterizeInAncestor(
                sheet, sheetSize: mountedViewport, scrollY: crossingScrollY
            )
            try await assertCrossingHeadClipsAtEdge(
                sheet: sheet, clipped: clipped, head: head
            )
        }
    }

    /// Hosted accessibility hierarchy: representative note, control, rest,
    /// and tuplet VoiceOver labels must appear in the mounted tree's
    /// accessibility elements — not merely in the presentation's backing
    /// map. Installing the same engraving with an empty label map must
    /// empty the tree: a label that survives proves a second label path,
    /// and a label absent in the first place means the mount dropped the
    /// map at the `DrumNotationView` seam.
    @Test("sheetMusicView exposes semantic labels in the hosted hierarchy")
    func hostedSheetExposesNotationLabels() async throws {
        try await TestSetup.withTestSetup {
            let sheet = try await mountFixture(DrumTabFixtureCatalog.tripletHooksAndStop)
            defer { sheet.viewModel.cleanup() }

            // Pinned against `GameplayNotationPreparation`'s copy: lane-12
            // snare and lane-11 closed hi-hat notes, the measure-0 stop on
            // the snare, the empty lower voice's full-measure rest, and
            // the supported 3:2 triplet.
            let expected = [
                "Snare",
                "Closed hi-hat",
                "Stop Snare",
                "Lower voice full-measure rest",
                "Upper voice tuplet, 3 in the time of 2"
            ]

            let labeledDump = hostedAccessibilityLabels(of: sheet, viewport: mountedViewport)
            for label in expected {
                #expect(
                    labeledDump.labels.contains(label),
                    """
                    hosted accessibility tree lacks "\(label)" — visited nodes: \
                    \(labeledDump.nodeKinds.prefix(24))
                    """
                )
            }

            reinstall(
                sheet,
                engraving: sheet.engraving,
                presentation: GameplayNotationPresentation(
                    annotations: .empty,
                    accessibilityLabels: [:]
                )
            )
            let unlabeled = hostedAccessibilityLabels(of: sheet, viewport: mountedViewport)
            for label in expected {
                #expect(
                    !unlabeled.labels.contains(label),
                    "\"\(label)\" survived an empty label map — the mount isn't reading it"
                )
            }
        }
    }
}

// MARK: - Rhythm-dot VoiceOver

extension GameplaySheetMusicGeometrySmokeTests {
    /// Hosted rhythm-dot VoiceOver: a prepare-produced dotted engraving,
    /// installed through the production `installPreparedNotation` seam, must
    /// surface one "Rhythm dot" element per painted dot in the mounted
    /// tree — and the view must hide dots whose label is absent (the
    /// negative leg keeps every other label to prove the reinstall took).
    @Test("sheetMusicView exposes rhythm dot labels in the hosted hierarchy")
    func hostedSheetExposesRhythmDotLabels() async throws {
        try await TestSetup.withTestSetup {
            let sheet = try await mountFixture(DrumTabFixtureCatalog.tripletHooksAndStop)
            defer { sheet.viewModel.cleanup() }

            let support = NotationSnapshotTestSupport()
            let (dottedEngraving, dottedPresentation) = try support.requireReady(
                support.prepare(rests: [
                    RhythmLayoutRest(
                        position: RhythmEventPosition(measureIndex: 0, localTick: 0, absoluteTick: 0),
                        durationTicks: 360,
                        voice: .upper,
                        rhythm: NotationRhythm(baseInterval: .quarter, dotCount: 2),
                        visibility: .printed,
                        tupletID: nil
                    )
                ])
            )
            try #require(!dottedEngraving.rhythmDots.isEmpty, "dotted state must paint rhythm dots")

            reinstall(sheet, engraving: dottedEngraving, presentation: dottedPresentation)
            let labeled = hostedAccessibilityLabels(of: sheet, viewport: mountedViewport)
            #expect(
                labeled.labels.filter { $0 == "Rhythm dot" }.count >= dottedEngraving.rhythmDots.count,
                """
                hosted tree lacks per-dot \"Rhythm dot\" labels — visited nodes: \
                \(labeled.nodeKinds.prefix(24))
                """
            )

            let strippedLabels = dottedPresentation.accessibilityLabels.filter { key, _ in
                if case .rhythmDot = key { return false }
                return true
            }
            reinstall(sheet, engraving: dottedEngraving, presentation: GameplayNotationPresentation(
                annotations: dottedPresentation.annotations,
                accessibilityLabels: strippedLabels
            ))
            let unlabeled = hostedAccessibilityLabels(of: sheet, viewport: mountedViewport)
            #expect(
                !unlabeled.labels.contains("Rhythm dot"),
                "\"Rhythm dot\" survived without a dot label — the mount isn't reading the map"
            )
            #expect(
                unlabeled.labels.contains("Upper voice quarter rest"),
                "non-dot labels vanished with the strip — the reinstall did not take"
            )
        }
    }
}

extension EngravedNotation {
    /// A copy with selected primitive arrays swapped — the region
    /// differential's "off"/sabotaged states. Only the listed families are
    /// touched; every other primitive keeps its engraved identity.
    func swapping(
        noteHeads: [EngravedNoteHead]? = nil,
        stems: [EngravedStem]? = nil,
        beams: [EngravedBeam]? = nil,
        tuplets: [EngravedTuplet]? = nil
    ) -> EngravedNotation {
        EngravedNotation(
            formatted: formatted,
            style: style,
            rows: rows,
            measures: measures,
            noteHeads: noteHeads ?? self.noteHeads,
            rests: rests,
            stems: stems ?? self.stems,
            beams: beams ?? self.beams,
            flags: flags,
            ledgerLines: ledgerLines,
            rhythmDots: rhythmDots,
            articulations: articulations,
            controls: controls,
            tuplets: tuplets ?? self.tuplets,
            measureBars: measureBars,
            paintedBounds: paintedBounds,
            contentWidth: contentWidth,
            contentHeight: contentHeight
        )
    }
}
#endif
