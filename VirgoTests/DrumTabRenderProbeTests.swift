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
/// Know its boundary. `drumNotationView` takes a `GameplayViewModel`, so this suite cannot
/// call it and instead re-declares the same primitives in the same z-order (see
/// `notationOverlay`). What that gates is `NotationNoteHeadView` *itself* -- an empty body, a
/// zero frame, a transparent fill, a broken `DrumNoteheadShape` path, a dropped `.position` --
/// against real pixels, plus the layout geometry those pixels are sampled at. What it does
/// **not** gate is production's mounting of that view: deleting the `noteHeads` `ForEach` from
/// `drumNotationView` leaves this probe green, because the probe builds its own ZStack. Nor
/// does anything force the two z-orders to stay in step; `notationOverlay` is a hand-kept
/// mirror, and a primitive added to `drumNotationView` will not appear here on its own.
///
/// Fault-injected on both counts before being committed: displacing every note head by
/// `.offset(x: 40)` in `NotationPrimitiveViews.swift` turned the per-head deltas red (total
/// ink is unchanged by a pure translation, so only the rect-scoped comparison catches it),
/// and the total-ink guard fails by construction if the head layer paints nothing at all.
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

    /// Mounts the notation primitives in the same z-order as
    /// `GameplaySheetMusicView.drumNotationView`: `ledgerLines`, printed `rests`, `beams`,
    /// `flags`, `stems`, then `noteHeads`. `drumNotationView` takes a `GameplayViewModel`, so
    /// it cannot be called directly from a fixture-driven test; this rebuilds the same
    /// primitive z-order from a `NotationLayout` instead, on a transparent background so no
    /// staff/sheet chrome can mask a missing head.
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
        let map = try inkMap(of: Rectangle().fill(Color.white), size: size)
        #expect(totalInk(map) > 0, "ImageRenderer produced an all-transparent bitmap for a filled rectangle")
    }

    // MARK: - The probe

    @Test("note heads are actually painted", arguments: [
        DrumTabFixtureCatalog.sixteenthRun,
        DrumTabFixtureCatalog.multiRowStableWidths
    ])
    func noteHeadsArePainted(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let layout = result.layout

        // drumNotationView resolves gameplayDefault internally, but DrumTabFixtureHarness
        // renders with a locked style so goldens stay stable. Confirm the two agree on note
        // head size before trusting sample rects computed against `viewStyle` to land on
        // `result.style`'s rendered geometry -- if they ever diverge, fail loudly here instead
        // of silently sampling the wrong pixels below.
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
        let size = CGSize(width: result.style.rowWidth, height: max(layout.totalHeight + yOffset, 1))

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
            guard !rect.isNull else { continue }
            let delta = inkCount(in: withHeads, rect: rect) - inkCount(in: withoutHeads, rect: rect)
            #expect(delta > 0, "head \(head.id) contributed no ink in \(rect)")
        }
    }
}
#endif
