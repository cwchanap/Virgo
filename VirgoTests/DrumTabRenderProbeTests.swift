import Testing
import SwiftUI
import Foundation
import CoreGraphics
import DrumNotation
@testable import Virgo

#if os(macOS)
/// Differential ink-rendering probe: rasterizes the package `DrumNotationView`
/// over a fixture's `EngravedNotation`, once with `noteHeads` and once without,
/// and asserts that mounting note heads actually paints pixels -- inside each
/// head's own painted bounds, not just somewhere on the canvas.
///
/// Every other test in this effort (`DrumTabGoldenTests`, `DrumTabRegressionInvariantTests`)
/// asserts on engraving *data* -- positions, ticks, bounds structs -- and an engraving
/// value is perfectly consistent whether or not anything ever draws it. This is the
/// one test that rasterizes through `ImageRenderer` and checks that ink landed where
/// the engraving said it would.
///
/// Know its boundary. This suite proves *package ink contribution inside
/// package geometry*: `PercussionNoteheadView`, the flag glyph painter, and
/// the `DrumNotationView` layer stack itself -- an empty body, a zero frame,
/// a transparent fill, a broken glyph path, a dropped `.position`. Alpha
/// differencing cannot prove z-order: where a swapped layer's ink overlaps
/// the staff-line band, the staff lines' own paint covers those pixels in
/// both legs, so a layer mounted *behind* opaque staff ink would go
/// undetected -- the claim here is ink contribution within package-claimed
/// bounds only. Head *placement* is a separate claim this probe does not make: the
/// sample rect is the head's own `paintedBounds` and the glyph is drawn at that
/// same position, so a wrong position moves rect and glyph together and this
/// probe stays green. Placement is gated by the goldens (`DrumTabGoldenTests`),
/// not here. Nor does anything here prove *production* mounts the package view:
/// `DrumNotationView` over test-produced engravings says nothing about
/// `GameplaySheetMusicView` -- production mounting is the
/// `GameplaySheetMusicMountingTests` claim in a later task, kept deliberately
/// separate.
///
/// The full package view is mounted unmodified for every render: staff lines,
/// clef/meter furniture, ledgers, rests, beams, flags, stems, heads, dots,
/// articulations, controls, tuplets. The differential isolates one layer by
/// swapping exactly one primitive array on a copy of the same immutable
/// engraving (see `EngravedNotation.replacing`), so the only ink that can
/// differ between the compared renders is the layer under test.
///
/// Package coordinates need no offset: `EngravedNotation` is already
/// normalized so `paintedBounds.minY >= 0`, and `DrumNotationView` frames
/// itself to `contentWidth × contentHeight` with no additional translation —
/// the canvas is exactly the sheet.
///
/// Fault-injected once, on the per-head gate (against the app-painter version
/// of this probe): displacing every note head by `.offset(x: 40)` turned the
/// per-head deltas red -- and only at the edge heads, because a uniform shift
/// lands head *N*'s glyph inside head *N+1*'s rect at these fixtures' spacing.
/// That was under the old baseline which stripped ALL heads, so a neighbour's
/// glyph could supply ink for an interior head's rect. The per-head gate
/// renders each head in isolation against the no-heads baseline, so the same
/// shift would turn every head red, not just the edge ones. The total-ink
/// guard was not separately injected; it is false by construction when the
/// head layer paints nothing, since the two renders are then byte-identical.
@Suite("Drum tab render probe", .serialized)
@MainActor
struct DrumTabRenderProbeTests {
    /// Per-pixel alpha map of a rendered bitmap. A struct rather than a tuple so SwiftLint's
    /// large-tuple rule doesn't flag the 3-member (pixels, width, height) grouping.
    private struct InkMap {
        let pixels: [Bool]
        let width: Int
        let height: Int
    }

    // MARK: - View under test

    /// Mounts the complete package sheet over `engraving` — all eleven
    /// layers `DrumNotationView` paints, unmodified. The differential swaps
    /// primitive arrays on the *engraving* rather than rebuilding layers,
    /// so there is no probe-side z-order to drift out of sync with the view.
    ///
    /// `foreground: .black` pins an opaque ink colour: the probe keys on
    /// alpha, and `.primary` is opaque in this host anyway, but an explicit
    /// colour removes the environment from the claim entirely.
    private func notationView(_ engraving: EngravedNotation) -> some View {
        DrumNotationView(
            layout: engraving,
            appearance: DrumNotationAppearance(foreground: .black)
        )
    }

    // MARK: - Pixel sampling

    /// Renders `view` into an offscreen bitmap of `size` and returns a per-pixel alpha map.
    /// Ink is alpha > 20 so the probe is colour-agnostic (survives theme/palette changes).
    ///
    /// Rasterization is `rasterizeView` in `RenderRasterProbe.swift`, shared with
    /// `SwiftUIRenderingNotationTests`; this adds only the boolean ink threshold and the
    /// 2-D indexing the per-head rect sampling below needs.
    private func inkMap<V: View>(of view: V, size: CGSize) throws -> InkMap {
        let raster = try rasterizeView(view, size: size)
        var pixels = [Bool](repeating: false, count: raster.pixelCount)
        for index in 0..<raster.pixelCount {
            pixels[index] = raster.pixel(at: index).alpha > 20
        }
        return InkMap(pixels: pixels, width: raster.width, height: raster.height)
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
    /// `noteHeadsArePainted` loudly via `RenderRasterProbeError.missingCGImage`; what that test cannot
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
        DrumTabFixtureCatalog.stopChokeDamp,
        DrumTabFixtureCatalog.isolatedFlaggedNotes
    ])
    func noteHeadsArePainted(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let engraved = result.engraved

        #expect(!engraved.noteHeads.isEmpty,
                "\(fixture.name) must have note heads for this probe to be non-vacuous")

        // The canvas is the sheet the view declares: the engraving's
        // normalized content size, no additional offset.
        let size = CGSize(
            width: engraved.contentWidth,
            height: max(engraved.contentHeight, 1)
        )

        let withHeads = try inkMap(of: notationView(engraved), size: size)
        let withoutHeads = try inkMap(
            of: notationView(engraved.replacing(noteHeads: [])),
            size: size
        )

        let totalWith = totalInk(withHeads)
        let totalWithout = totalInk(withoutHeads)

        // Checked first so a completely unmounted head layer fails once, clearly, rather than
        // as N confusing per-head failures below.
        #expect(totalWith > totalWithout, "mounting note heads added no ink (\(totalWith) vs \(totalWithout))")

        // Per-head differential inside each head's own 2-D bounds (see
        // `assertEveryHeadPaints` for why it is rect-scoped and isolated).
        try assertEveryHeadPaints(engraved)
    }

    // MARK: - Rasterized checklist shapes (final-review follow-up)

    /// The three measured-geometry checklist shapes the final review verified
    /// only at the layout-data level, now driven through the same differential
    /// ink probe as `noteHeadsArePainted`. Each case reuses the exact fixture
    /// parameters of its data-level suite — no new fixture framework.
    private enum ChecklistShape: String, CaseIterable, Sendable {
        /// `MeasuredGeometryInvariantsTests`' sparse-next-to-dense measure pair.
        case sparseNextToDense
        /// `isolatedFlaggedNotes`' fully-uncovered flags: the lone sixteenth
        /// and lone eighth keep canonical flags, and each flag's reserved
        /// footprint must receive ink. (The three-arm rule's *partial*
        /// `.eighth`-component arm is unreachable end-to-end — the beam
        /// topology's hook segments cover their owner, so a beamed note never
        /// shows a flag — and stays pinned at data level by the package
        /// formatter tests.)
        case uncoveredFlagFootprints
        /// `DisplacedSecondStemAxisTests`' up-stem second (snare + highTom).
        case upDisplacedSecond
        /// `DisplacedSecondStemAxisTests`' down-stem second (hiHatPedal + bass).
        case downDisplacedSecond
    }

    private let checklistSupport = NotationSnapshotTestSupport()

    private func makeChecklistEngraving(for shape: ChecklistShape) throws -> EngravedNotation {
        switch shape {
        case .sparseNextToDense:
            return try checklistSupport.engrave(notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
                Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 0),
                Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 1.0 / 16.0),
                Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 2.0 / 16.0),
                Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 3.0 / 16.0)
            ])
        case .uncoveredFlagFootprints:
            return try DrumTabFixtureHarness
                .render(DrumTabFixtureCatalog.isolatedFlaggedNotes).engraved
        case .upDisplacedSecond:
            return try checklistSupport.engrave(notes: [
                Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
                Note(interval: .eighth, noteType: .highTom, measureNumber: 1, measureOffset: 0),
                Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 8.0),
                Note(interval: .eighth, noteType: .highTom, measureNumber: 1, measureOffset: 1.0 / 8.0)
            ])
        case .downDisplacedSecond:
            return try checklistSupport.engrave(
                notes: [
                    Note(interval: .eighth, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0),
                    Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0),
                    Note(interval: .eighth, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 1.0 / 8.0),
                    Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 1.0 / 8.0)
                ],
                notePositionOverrides: [.kick: .belowLine1, .hiHatPedal: .spaceBetweenLine1AndBelow]
            )
        }
    }

    @Test("checklist shapes paint ink where the layout reserves it", arguments: ChecklistShape.allCases)
    private func checklistShapePaintsInk(_ shape: ChecklistShape) throws {
        let engraved = try makeChecklistEngraving(for: shape)

        switch shape {
        case .sparseNextToDense:
            // Non-vacuous pair: both neighbors carry heads.
            for measure in engraved.measures {
                #expect(
                    engraved.noteHeads.contains { $0.measureIndex == measure.index },
                    "measure \(measure.index) must carry heads for the pair probe"
                )
            }
        case .uncoveredFlagFootprints:
            // The lone sixteenth and lone eighth keep fully-uncovered
            // canonical flags: the flag-ink differential below must find ink
            // in each reserved footprint (.sixteenth / .eighth).
            #expect(!engraved.flags.isEmpty, "fixture must produce visible flags")
        case .upDisplacedSecond, .downDisplacedSecond:
            // Displacement actually happened: one chord head sits off the
            // shared column axis.
            let column = try #require(engraved.formatted.measures.first?.columns.first)
            #expect(
                engraved.noteHeads.contains { $0.position.x != column.logicalColumnX },
                "chord must carry a displaced head off the column axis"
            )
        }

        try assertEveryHeadPaints(engraved)
        try assertFlagInkInReservedFootprint(engraved)
    }

    /// The per-head differential gate shared by `noteHeadsArePainted` and the
    /// checklist-shape probes: each head, rendered in isolation against the
    /// no-heads baseline, must add ink inside its own `EngravedNoteHead
    /// .paintedBounds`.
    ///
    /// A full-height column band would also catch stems and beams sharing
    /// that x band — that's why this is differential and rect-scoped rather
    /// than a coarse column check that would stay green after deleting every
    /// `PercussionNoteheadView`. Rendering only the current head (rather than
    /// all heads minus the current one) makes the delta attributable: a
    /// neighbouring head that also paints inside this rect is absent from
    /// both the single-head render and the no-heads baseline, so it cannot
    /// supply ink for this assertion. (The earlier baseline stripped ALL
    /// heads, so a missing or displaced head could stay green when a
    /// neighbour supplied ink inside its bounds — confirmed by fault
    /// injection; see the type doc comment.)
    private func assertEveryHeadPaints(_ engraved: EngravedNotation) throws {
        let size = CGSize(
            width: engraved.contentWidth,
            height: max(engraved.contentHeight, 1)
        )
        let withoutHeads = try inkMap(
            of: notationView(engraved.replacing(noteHeads: [])),
            size: size
        )
        for head in engraved.noteHeads {
            let rect = head.paintedBounds
            // EngravedNoteHead.paintedBounds has no `.null` return path (it is
            // computed from Bravura metrics at compose time), so this should
            // never fire; assert it instead of silently skipping so a future
            // change that introduces one is caught rather than swallowed.
            #expect(!rect.isNull, "head \(head.noteID) has a null painted bounds rect")
            guard !rect.isNull else { continue }
            let withOnlyHead = try inkMap(
                of: notationView(engraved.replacing(noteHeads: [head])),
                size: size
            )
            let delta = inkCount(in: withOnlyHead, rect: rect) - inkCount(in: withoutHeads, rect: rect)
            #expect(delta > 0, "head \(head.noteID) contributed no ink in \(rect)")
        }
    }

    /// Flag-level differential gate: each engraved flag, rendered as the only
    /// flag against the no-flags baseline, must add ink inside its own
    /// reserved footprint — the Bravura flag bounds the formatter's collision
    /// rule reserved for it (isolated per flag so a beam or neighbour flag
    /// cannot supply the ink).
    private func assertFlagInkInReservedFootprint(_ engraved: EngravedNotation) throws {
        guard !engraved.flags.isEmpty else { return }
        let size = CGSize(
            width: engraved.contentWidth,
            height: max(engraved.contentHeight, 1)
        )
        let staffSpace = engraved.style.formatting.staffSpace
        let withoutFlags = try inkMap(
            of: notationView(engraved.replacing(flags: [])),
            size: size
        )
        for flag in engraved.flags {
            // The footprint the engraver reserved and unioned: the flag
            // glyph's painted bounds with its SMuFL attachment point moved
            // onto `flag.origin` — the same formula `appendFlag` applies.
            let metrics = PercussionGlyphMetrics.flag(
                duration: flag.duration,
                direction: flag.stemDirection,
                staffSpace: staffSpace
            )
            let rect = metrics.paintedBounds.offsetBy(
                dx: flag.origin.x - metrics.attachmentOffset.x,
                dy: flag.origin.y - metrics.attachmentOffset.y
            )
            let withOnlyFlag = try inkMap(
                of: notationView(engraved.replacing(flags: [flag])),
                size: size
            )
            let delta = inkCount(in: withOnlyFlag, rect: rect) - inkCount(in: withoutFlags, rect: rect)
            #expect(
                delta > 0,
                Comment(rawValue: "flag head=\(flag.noteID) index=\(flag.flagIndex) contributed no ink "
                    + "in its reserved footprint \(rect)")
            )
        }
    }
}

private extension EngravedNotation {
    /// A copy of this immutable engraving with selected primitive arrays
    /// swapped — the probe's one-layer-at-a-time differential. All other
    /// arrays (stems, beams, furniture) are shared verbatim, so only the
    /// swapped layer can differ between the compared renders.
    func replacing(
        noteHeads: [EngravedNoteHead]? = nil,
        flags: [EngravedFlag]? = nil
    ) -> EngravedNotation {
        EngravedNotation(
            formatted: formatted,
            style: style,
            rows: rows,
            measures: measures,
            noteHeads: noteHeads ?? self.noteHeads,
            rests: rests,
            stems: stems,
            beams: beams,
            flags: flags ?? self.flags,
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
#endif
