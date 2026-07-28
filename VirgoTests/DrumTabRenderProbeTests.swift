import Testing
import SwiftUI
import Foundation
import CoreGraphics
@testable import Virgo

#if os(macOS)
/// Differential ink-rendering probe: renders the same notation primitives that
/// `GameplaySheetMusicView.drumNotationView` mounts, once with `noteHeads` and once without,
/// and asserts that mounting note heads actually paints pixels -- inside each head's own
/// painted bounds, not just somewhere on the canvas.
///
/// Every other test in this effort (`DrumTabGoldenTests`, `DrumTabRegressionInvariantTests`)
/// asserts on layout *data* -- positions, ticks, bounds structs -- and a layout value is
/// perfectly consistent whether or not anything ever draws it. This is the one test that
/// rasterizes through `ImageRenderer` and checks that ink landed where the layout said it
/// would.
///
/// Know its boundary. This suite does not drive a real `GameplayViewModel` through
/// `drumNotationView`. That is possible --
/// `SwiftUIRenderingNotationTests.testNotationSheetFiltersHiddenRestsBeforeConstruction` calls
/// `gameplayView.drumNotationView(viewModel:)` directly via
/// `GameplayViewModelCoverageTestSupport.makeViewModel` -- but it pulls in the view model's
/// async lifecycle and its own row-width/style resolution, which these fixture-driven probes
/// are built to hold fixed. Instead this suite re-declares a deliberately head-layer-scoped
/// subset of the same primitives in the same z-order (see `notationOverlay`): it mounts
/// `ledgerLines`, `rests`, `beams`, `flags`, `stems`, then stops at `noteHeads`, omitting the
/// six layers `drumNotationView` mounts afterwards (`rhythmDots`, `articulations`,
/// `stopNotes`, `tuplets`, `feelMarks`, `rhythmWarnings`). That is intentional, not an
/// oversight: all six draw *over* note heads, so including them could only mask head ink and
/// weaken the differential. It does mean this mirror diverges from `drumNotationView` from
/// day one, not as some hypothetical future risk -- and nothing enforces that the two
/// z-orders stay in step going forward.
///
/// What `notationOverlay` gates is `NotationNoteHeadView` *itself* -- an empty body, a zero
/// frame, a transparent fill, a broken `DrumNoteheadShape` path, a dropped `.position` --
/// against real pixels. Head *placement* is a separate claim this probe does not make: the
/// sample rect is computed from `noteHead.position` via `RenderedNoteHead.paintedBounds`
/// (`NotationRhythmRendering.swift:178-180`), and the glyph is drawn at that same position, so
/// a wrong position moves rect and glyph together and this probe stays green. Placement is
/// gated by the goldens (`DrumTabGoldenTests`), not here. Nor does anything gate production's
/// mounting of the head layer: deleting the `noteHeads` `ForEach` from `drumNotationView`
/// leaves this probe green, because the probe builds its own ZStack.
///
/// Fault-injected once, on the per-head gate: displacing every note head by `.offset(x: 40)`
/// in `NotationPrimitiveViews.swift` turned the per-head deltas red -- and only at the edge
/// heads, because a uniform shift lands head *N*'s glyph inside head *N+1*'s rect at these
/// fixtures' spacing. The total-ink guard was not separately injected; it is false by
/// construction when the head layer paints nothing, since the two renders are then
/// byte-identical.
@Suite("Drum tab render probe", .serialized)
@MainActor
struct DrumTabRenderProbeTests {
    private enum ProbeError: Error {
        case missingCGImage
        case missingPixelBuffer
        case missingBitmapContext
    }

    /// Per-pixel alpha map of a rendered bitmap. A struct rather than a tuple so SwiftLint's
    /// large-tuple rule doesn't flag the 3-member (pixels, width, height) grouping.
    private struct InkMap {
        let pixels: [Bool]
        let width: Int
        let height: Int
    }

    // MARK: - Overlay under test

    /// Mounts the first six notation primitive layers, in the same z-order as
    /// `GameplaySheetMusicView.drumNotationView`: `ledgerLines`, printed `rests`, `beams`,
    /// `flags`, `stems`, then `noteHeads` -- deliberately stopping there (see the type doc for
    /// why). `drumNotationView` takes a `GameplayViewModel`, and this suite does not drive one
    /// (see the type doc); this rebuilds the same primitive z-order from a `NotationLayout`
    /// instead, on a transparent background so no staff/sheet chrome can mask a missing head.
    private func notationOverlay(
        _ layout: NotationLayout,
        style: NotationLayoutStyle
    ) -> some View {
        ZStack {
            ForEach(layout.ledgerLines) { NotationLedgerLineView(ledgerLine: $0) }
            ForEach(layout.rests.filter(\.isPrinted)) { NotationRestView(rest: $0, style: style) }
            ForEach(layout.beams) { NotationBeamView(beam: $0) }
            ForEach(layout.flags) { NotationFlagView(flag: $0) }
            ForEach(layout.stems) { NotationStemView(stem: $0) }
            ForEach(layout.noteHeads) {
                NotationNoteHeadView(noteHead: $0, size: layout.noteHeadSize)
            }
        }
    }

    // MARK: - Pixel sampling

    /// Renders `view` into an offscreen bitmap of `size` and returns a per-pixel alpha map.
    /// Ink is alpha > 20 so the probe is colour-agnostic (survives theme/palette changes).
    private func inkMap<V: View>(of view: V, size: CGSize) throws -> InkMap {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { throw ProbeError.missingCGImage }

        let width = cgImage.width, height = cgImage.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        try bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { throw ProbeError.missingPixelBuffer }
            guard let context = CGContext(
                data: base, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw ProbeError.missingBitmapContext }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var pixels = [Bool](repeating: false, count: width * height)
        for index in 0..<(width * height) {
            pixels[index] = bytes[index * 4 + 3] > 20
        }
        return InkMap(pixels: pixels, width: width, height: height)
    }

    private func totalInk(_ map: InkMap) -> Int {
        map.pixels.filter { $0 }.count
    }

    private func inkCount(in map: InkMap, rect: CGRect) -> Int {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(map.width - 1, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(map.height - 1, Int(rect.maxY.rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return 0 }

        var count = 0
        for y in minY...maxY {
            for x in minX...maxX where map.pixels[y * map.width + x] {
                count += 1
            }
        }
        return count
    }

    // MARK: - Sanity: does ImageRenderer paint anything at all in this host?

    /// Verifies `ImageRenderer` produces real, non-transparent pixels in this test host before
    /// trusting it to gate note-head rendering below. A `nil` `cgImage` already fails
    /// `noteHeadsArePainted` loudly via `ProbeError.missingCGImage`; what that test cannot
    /// distinguish on its own is a *non-nil but all-transparent* bitmap, which would also make
    /// its differential comparison fail (0 vs 0 ink) -- correctly, but without pointing at the
    /// renderer as the cause. This test isolates that failure mode directly.
    @Test("ImageRenderer paints a plain filled rectangle")
    func imageRendererPaintsSolidInk() throws {
        let size = CGSize(width: 40, height: 40)
        // Black (0,0,0,255) rather than white: white's RGB channels are all 255, so this would
        // still pass even if the renderer wrote the wrong byte index for alpha. Black pins the
        // alpha channel as the only non-zero byte, at zero extra cost.
        let map = try inkMap(of: Rectangle().fill(Color.black), size: size)
        #expect(totalInk(map) > 0, "ImageRenderer produced an all-transparent bitmap for a filled rectangle")
    }

    // MARK: - The probe

    @Test("note heads are actually painted", arguments: [
        DrumTabFixtureCatalog.sixteenthRun,
        DrumTabFixtureCatalog.multiRowStableWidths,
        DrumTabFixtureCatalog.sameTimeTrio,
        DrumTabFixtureCatalog.stopChokeDamp
    ])
    func noteHeadsArePainted(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let layout = result.layout

        // drumNotationView resolves gameplayDefault internally, but DrumTabFixtureHarness
        // renders with a locked style so goldens stay stable. Confirm the two agree on note
        // head size before trusting sample rects computed against `viewStyle` to land on
        // `result.style`'s rendered geometry -- if they ever diverge, fail loudly here instead
        // of silently sampling the wrong pixels below. This is a drift tripwire, not an active
        // check today: `DrumTabFixtureHarness.lockedStyle` is
        // `gameplayDefault.with(rowWidth: maxRowWidth)`, and `.with(rowWidth:)` copies
        // note-head size verbatim from `gameplayDefault`, so as currently wired this
        // `#expect` cannot fail.
        let viewStyle = NotationLayoutStyle.gameplayDefault
        #expect(
            viewStyle.noteHeadWidth == result.style.noteHeadWidth
                && viewStyle.noteHeadHeight == result.style.noteHeadHeight,
            "view style and harness style disagree on note head size"
        )

        #expect(!layout.noteHeads.isEmpty, "\(fixture.name) must have note heads for this probe to be non-vacuous")

        // Primitive coordinates are staff-relative; GameplaySheetMusicView applies this inset
        // as an `.offset(y:)` on the ancestor ZStack that hosts `drumNotationView` (see
        // `staticSheetMusicContent`). The render below applies that same shift so the sampled
        // rects -- computed from the same un-shifted `paintedBounds` -- land on the painted
        // glyphs instead of drifting off them.
        let yOffset = layout.topContentInset(style: viewStyle)
        // `layout.contentWidth`, not `result.style.rowWidth`: production sizes the sheet with
        // the same `max(maxRowWidth, paintedBounds.maxX + uniformSpacing)` formula
        // (`NotationLayout.swift:307-310`), so a future fixture wider than the fixed row width
        // cannot get clipped out of this canvas.
        let size = CGSize(width: layout.contentWidth, height: max(layout.totalHeight + yOffset, 1))

        var stripped = layout
        stripped.noteHeads = []

        let withHeads = try inkMap(of: notationOverlay(layout, style: viewStyle).offset(y: yOffset), size: size)
        let withoutHeads = try inkMap(of: notationOverlay(stripped, style: viewStyle).offset(y: yOffset), size: size)

        let totalWith = totalInk(withHeads)
        let totalWithout = totalInk(withoutHeads)

        // Checked first so a completely unmounted head layer fails once, clearly, rather than
        // as N confusing per-head failures below.
        #expect(totalWith > totalWithout, "mounting note heads added no ink (\(totalWith) vs \(totalWithout))")

        // Per-head delta inside the head's own 2-D bounds. A full-height column band would
        // also catch stems and beams sharing that x band -- that's why this is differential
        // and rect-scoped rather than a coarse column check that would stay green after
        // deleting every NotationNoteHeadView.
        for head in layout.noteHeads {
            let rect = head.paintedBounds(style: viewStyle).offsetBy(dx: 0, dy: yOffset)
            // RenderedNoteHead.paintedBounds has no `.null` return path (unlike RenderedRest's),
            // so this should never fire; assert it instead of silently skipping so a future
            // change that introduces one is caught rather than swallowed.
            #expect(!rect.isNull, "head \(head.id) has a null painted bounds rect")
            guard !rect.isNull else { continue }
            let delta = inkCount(in: withHeads, rect: rect) - inkCount(in: withoutHeads, rect: rect)
            #expect(delta > 0, "head \(head.id) contributed no ink in \(rect)")
        }
    }
}
#endif
