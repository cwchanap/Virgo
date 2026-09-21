//
//  GameplaySheetMusicClippingProbe.swift
//  VirgoTests
//
//  HPA-166 Task 9 review fix — oversized-ancestor raster host for the
//  viewport-clipping gate: the production sheet fixed at its scroll
//  viewport size inside a larger unclipped canvas, plus the clipped /
//  unclipped / non-vacuity assert legs.
//

import Testing
import SwiftUI
import Foundation
import DrumNotation
@testable import Virgo

#if os(macOS)
import AppKit

/// Capture margin around the fixed-size sheet inside the oversized
/// ancestor canvas — where overflow ink lands if the sheet's own clip
/// (the production `ScrollView`) ever fails.
let sheetClipMargin: CGFloat = 40

/// The rasterized ancestor canvas: wide/tall enough to hold the full
/// engraved content plus margin on every side, so off-viewport ink has
/// somewhere to appear.
func oversizedClipCanvasSize(contentHeight: CGFloat) -> CGSize {
    CGSize(
        width: mountedViewport.width + sheetClipMargin * 2,
        height: contentHeight + sheetClipMargin * 2
    )
}

/// The sheet's viewport rect inside the oversized ancestor canvas — the
/// sheet is offset by `sheetClipMargin` on both axes.
var ancestorViewportRect: CGRect {
    CGRect(
        origin: CGPoint(x: sheetClipMargin, y: sheetClipMargin),
        size: mountedViewport
    )
}

/// Differential ink outside the sheet's viewport band: the whole-canvas
/// differential minus the viewport-band differential. Zero unless content
/// escaped the sheet's own clip into the captured margin bands.
func ancestorOverflowInk(
    between lhs: RasterBitmap,
    and rhs: RasterBitmap,
    contentHeight: CGFloat
) -> Int {
    changedPixels(
        in: CGRect(
            origin: .zero,
            size: oversizedClipCanvasSize(contentHeight: contentHeight)
        ),
        between: lhs, and: rhs
    ) - changedPixels(in: ancestorViewportRect, between: lhs, and: rhs)
}

/// Document scroll offset used by the boundary-crossing leg: shifts the
/// row-2 heads (~770–790 sheet-y) so the 768pt clip edge cuts them
/// ~10pt deep on both sides.
let crossingScrollY: CGFloat = 12

/// Rasterization bleed width at the clip boundary: the hosted ScrollView's
/// edge antialiases a few points past the clip line, so strict-zero
/// assertions start `clipEdgeBleed` points beyond the edge.
let clipEdgeBleed: CGFloat = 4

/// The deep region below the clip-edge bleed band — the strict-zero mask
/// the clipped legs check and the exact region the unclipped controls
/// must prove real ink can reach. Anything shallower would let bleed-band
/// ink alone satisfy the control.
func deepOutsideClipRect(contentHeight: CGFloat) -> CGRect {
    let canvas = oversizedClipCanvasSize(contentHeight: contentHeight)
    let bleedLine = ancestorViewportRect.maxY + clipEdgeBleed
    return CGRect(
        x: 0, y: bleedLine,
        width: canvas.width, height: canvas.height - bleedLine
    )
}

/// The four canvas regions a correctly clipped sheet must leave untouched:
/// top margin, left/right margins (up to the bleed line), and the deep
/// region below the bleed band.
func outsideClipRects(contentHeight: CGFloat) -> [CGRect] {
    let canvas = oversizedClipCanvasSize(contentHeight: contentHeight)
    let band = ancestorViewportRect
    let bleedLine = band.maxY + clipEdgeBleed
    return [
        CGRect(x: 0, y: 0, width: canvas.width, height: band.minY),
        CGRect(x: 0, y: band.minY, width: band.minX, height: bleedLine - band.minY),
        CGRect(
            x: band.maxX, y: band.minY,
            width: canvas.width - band.maxX, height: bleedLine - band.minY
        ),
        deepOutsideClipRect(contentHeight: contentHeight)
    ]
}

/// The document-space mask where one boundary-crossing head's clipped
/// part lands past the clip edge's AA bleed band: the head's painted
/// bounds below `viewport height + crossingScrollY + clipEdgeBleed`. One
/// mask drives both captures — offset by (`sheetClipMargin`,
/// `sheetClipMargin - crossingScrollY`) it is the clipped raster's
/// strict-zero region; offset by (`sheetClipMargin`, `sheetClipMargin`)
/// it is the same ink the full-height control must show. Keeping the mask
/// in document space is what makes the two captures comparable: the
/// unclipped sheet is not scrolled, so the same head lands `crossingScrollY`
/// points lower there.
func crossingDeepMask(of head: EngravedNoteHead) -> CGRect {
    let deepTop = mountedViewport.height + crossingScrollY + clipEdgeBleed
    return CGRect(
        x: head.paintedBounds.minX,
        y: deepTop,
        width: head.paintedBounds.width,
        height: head.paintedBounds.maxY - deepTop
    )
}

@MainActor
extension GameplaySheetMusicGeometrySmokeTests {
    /// Rasterizes the production sheet fixed at `sheetSize`, inset by
    /// `sheetClipMargin` inside the oversized ancestor canvas. Neither the
    /// ancestor nor the hosting view clips — only the sheet's own
    /// `ScrollView` does — so content escaping the sheet paints into the
    /// captured margin bands where `ancestorOverflowInk` can measure it.
    /// Spacer layout (not `.offset`, which the hosted scroll hierarchy
    /// ignores) positions the sheet at (`sheetClipMargin`,
    /// `sheetClipMargin`). `scrollY` scrolls the sheet's own NSScrollView
    /// down the document before snapshotting.
    func rasterizeInAncestor(
        _ sheet: MountedSheet,
        sheetSize: CGSize,
        scrollY: CGFloat = 0
    ) throws -> RasterBitmap {
        try rasterizeHostedView(
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: sheetClipMargin)
                HStack(alignment: .top, spacing: 0) {
                    Spacer().frame(width: sheetClipMargin)
                    GeometryReader { proxy in
                        sheet.gameplayView.sheetMusicView(geometry: proxy)
                    }
                    .frame(width: sheetSize.width, height: sheetSize.height)
                    Spacer()
                }
                Spacer()
            },
            size: oversizedClipCanvasSize(contentHeight: sheet.engraving.contentHeight),
            scrollY: scrollY
        )
    }

    /// Hosts the production sheet at `mountedViewport` and returns the
    /// scroll offset its `NSScrollView` actually reached for `scrollY` —
    /// the post-clamp readback, not the request.
    func hostedSheetScrollOffset(
        _ sheet: MountedSheet,
        scrollY: CGFloat
    ) -> CGFloat? {
        hostedScrollOffset(
            GeometryReader { proxy in
                sheet.gameplayView.sheetMusicView(geometry: proxy)
            },
            size: mountedViewport,
            scrollY: scrollY
        )
    }

    /// Clipped leg: removing every head the ScrollView clips outside the
    /// viewport must leave the oversized-canvas raster identical — inside
    /// AND outside the sheet's viewport band. Any outside-band change
    /// means clipped content overflowed the sheet into the ancestor.
    func assertClipHolds(
        sheet: MountedSheet,
        reference clipped: RasterBitmap,
        offscreenCount: Int
    ) async throws {
        reinstall(sheet, engraving: sheet.engraving.swapping(
            noteHeads: sheet.engraving.noteHeads.filter {
                CGRect(origin: .zero, size: mountedViewport).intersects($0.paintedBounds)
            }
        ))
        let stripped = try rasterizeInAncestor(sheet, sheetSize: mountedViewport)
        #expect(
            changedPixels(in: ancestorViewportRect, between: clipped, and: stripped) == 0,
            "removing off-viewport heads changed the raster inside the viewport"
        )
        let overflow = ancestorOverflowInk(
            between: clipped, and: stripped, contentHeight: sheet.engraving.contentHeight
        )
        #expect(
            overflow == 0,
            """
            removing \(offscreenCount) off-viewport head(s) changed \(overflow) \
            pixel(s) outside the sheet viewport — clipped content overflowed
            """
        )
        reinstall(sheet, engraving: sheet.engraving)
    }

    /// Unclipped control: the same production hierarchy hosted with the
    /// scroll viewport grown to the full content height, so nothing beyond
    /// the 768pt band is clipped. Removing the same heads must move ink
    /// inside the deep-outside mask — the exact region where the clipped
    /// leg demands strict zero — not merely anywhere outside the band,
    /// which the excluded bleed strip alone could satisfy.
    func assertUnclippedControl(
        sheet: MountedSheet,
        offscreenCount: Int
    ) async throws {
        let fullHeight = CGSize(
            width: mountedViewport.width,
            height: sheet.engraving.contentHeight
        )
        let unclipped = try rasterizeInAncestor(sheet, sheetSize: fullHeight)
        reinstall(sheet, engraving: sheet.engraving.swapping(
            noteHeads: sheet.engraving.noteHeads.filter {
                CGRect(origin: .zero, size: mountedViewport).intersects($0.paintedBounds)
            }
        ))
        let stripped = try rasterizeInAncestor(sheet, sheetSize: fullHeight)
        let deepInk = changedPixels(
            in: deepOutsideClipRect(contentHeight: sheet.engraving.contentHeight),
            between: unclipped, and: stripped
        )
        #expect(
            deepInk > 0,
            """
            unclipped control: removing \(offscreenCount) off-viewport head(s) \
            moved \(deepInk) pixel(s) inside the deep-outside mask — the \
            clipped leg's strict zero there is unproven
            """
        )
        reinstall(sheet, engraving: sheet.engraving)
    }

    /// Boundary-crossing leg: with the sheet scrolled `crossingScrollY`
    /// document points down, the selected head straddles the 768pt clip
    /// edge. Removing exactly that head must (a) move ink inside the
    /// clipped viewport and (b) leave the head's own deep-outside mask —
    /// `crossingDeepMask` margin- and scroll-translated into canvas space —
    /// strict zero, along with every outside region. The full-height
    /// control must then (c) move ink inside that same document-space
    /// mask. One primitive and one mask drive all three legs; a broad
    /// outside-band count can no longer stand in for the deep region's
    /// pixel evidence.
    func assertCrossingHeadClipsAtEdge(
        sheet: MountedSheet,
        clipped: RasterBitmap,
        head: EngravedNoteHead
    ) async throws {
        let scrolledViewport = CGRect(
            origin: CGPoint(x: 0, y: crossingScrollY),
            size: mountedViewport
        )
        // Inside part of the crossing head, in ancestor-canvas
        // coordinates: sheet bounds shifted by the margin, minus the
        // document scroll offset.
        let insideRect = head.paintedBounds
            .intersection(scrolledViewport)
            .offsetBy(dx: sheetClipMargin, dy: sheetClipMargin - crossingScrollY)
        let deepMask = crossingDeepMask(of: head)
        // Same mask in the clipped capture's canvas space: ancestor
        // margin, minus the document scroll the clipped sheet carries.
        let clippedDeepMask = deepMask.offsetBy(
            dx: sheetClipMargin, dy: sheetClipMargin - crossingScrollY
        )
        reinstall(sheet, engraving: sheet.engraving.swapping(
            noteHeads: sheet.engraving.noteHeads.filter {
                $0.noteID != head.noteID
            }
        ))
        let stripped = try rasterizeInAncestor(
            sheet, sheetSize: mountedViewport, scrollY: crossingScrollY
        )
        #expect(
            changedPixels(in: insideRect, between: clipped, and: stripped) > 0,
            "crossing head's inside-viewport part painted no ink at \(insideRect)"
        )
        let deepEscape = changedPixels(
            in: clippedDeepMask, between: clipped, and: stripped
        )
        #expect(
            deepEscape == 0,
            """
            crossing head's clipped part changed \(deepEscape) pixel(s) in \
            its deep-outside mask \(clippedDeepMask) — content escaped the \
            clip edge
            """
        )
        for rect in outsideClipRects(contentHeight: sheet.engraving.contentHeight) {
            let outside = changedPixels(in: rect, between: clipped, and: stripped)
            #expect(
                outside == 0,
                """
                crossing head removal changed \(outside) pixel(s) in outside \
                region \(rect) — content escaped the clip edge
                """
            )
        }
        reinstall(sheet, engraving: sheet.engraving)
        try await assertCrossingHeadUnclipped(
            sheet: sheet, head: head, deepMask: deepMask
        )
    }

    /// Full-height control for the crossing leg: the same head mounted
    /// with no clip beyond the content — its removal must move ink inside
    /// the same deep-outside mask, proving the clipped leg's strict zero
    /// covers pixels that can actually carry the head's ink. The mask
    /// translates by the ancestor margin only: the unclipped sheet is not
    /// scrolled.
    private func assertCrossingHeadUnclipped(
        sheet: MountedSheet,
        head: EngravedNoteHead,
        deepMask: CGRect
    ) async throws {
        let fullHeight = CGSize(
            width: mountedViewport.width,
            height: sheet.engraving.contentHeight
        )
        let headful = try rasterizeInAncestor(sheet, sheetSize: fullHeight)
        reinstall(sheet, engraving: sheet.engraving.swapping(
            noteHeads: sheet.engraving.noteHeads.filter {
                $0.noteID != head.noteID
            }
        ))
        let stripped = try rasterizeInAncestor(sheet, sheetSize: fullHeight)
        // The same mask in the unclipped capture's canvas space: ancestor
        // margin only — the full-height sheet is not scrolled, so the
        // head sits `crossingScrollY` points lower than in the clipped
        // capture.
        let canvasMask = deepMask.offsetBy(
            dx: sheetClipMargin, dy: sheetClipMargin
        )
        let deepInk = changedPixels(
            in: canvasMask, between: headful, and: stripped
        )
        #expect(
            deepInk > 0,
            """
            unclipped crossing leg: removing the crossing head moved \
            \(deepInk) pixel(s) inside its deep-outside mask \(canvasMask) — \
            the clipped leg's strict zero there is unproven
            """
        )
        reinstall(sheet, engraving: sheet.engraving)
    }

    /// Last-row anchor reach: `scrollTo("row_N", anchor: .top)` can only
    /// land the final band top on the viewport's top edge when the scroll
    /// canvas extends a full viewport below it — `contentHeight` ends at
    /// the anchor block's own bottom. The hosted `NSScrollView` must
    /// actually reach the anchor's document offset (a shorter canvas reads
    /// back the clamped shortfall), and a last-row head must then paint
    /// inside the viewport's top band where the anchor promised it.
    @Test("sheetMusicView lets the last row anchor reach the viewport top")
    func mountedSheetReachesLastRowAnchor() async throws {
        try await TestSetup.withTestSetup {
            let sheet = try await mountFixture(DrumTabFixtureCatalog.multiRowStableWidths)
            defer { sheet.viewModel.cleanup() }
            let engraving = sheet.engraving
            let lastRow = try #require(engraving.rows.last)
            try #require(engraving.rows.count > 1, "fixture must mount multiple rows")

            let input = sheet.gameplayView.staticNotationInput(viewModel: sheet.viewModel)
            let lastAnchorTop = input.lastRowAnchorTop
            #expect(lastAnchorTop > 0)
            // The package sheet covers the anchor's full block; the mounted
            // canvas must additionally run one viewport below its top.
            #expect(engraving.contentHeight >= lastAnchorTop + input.rowAnchors.rowPitch)

            let reached = try #require(
                hostedSheetScrollOffset(sheet, scrollY: lastAnchorTop),
                "production sheet must host an NSScrollView"
            )
            #expect(
                abs(reached - lastAnchorTop) < 0.5,
                "scroll clamped at \(reached) — \(lastAnchorTop - reached)pt short of the last anchor top"
            )

            // Ink evidence: with the anchor pinned, a last-row head paints
            // where the anchor promised — removing it must change pixels
            // inside the viewport.
            let head = try #require(
                engraving.noteHeads
                    .filter { $0.rowIndex == lastRow.index }
                    .min { $0.paintedBounds.minY < $1.paintedBounds.minY },
                "last row must carry a head"
            )
            let pinned = try rasterize(sheet, scrollY: lastAnchorTop)
            reinstall(sheet, engraving: engraving.swapping(
                noteHeads: engraving.noteHeads.filter { $0.noteID != head.noteID }
            ))
            let stripped = try rasterize(sheet, scrollY: lastAnchorTop)
            let viewportRect = head.paintedBounds.offsetBy(dx: 0, dy: -lastAnchorTop)
            #expect(
                changedPixels(in: viewportRect, between: pinned, and: stripped) > 0,
                "last-row head \(head.noteID) painted nothing at \(viewportRect) with the anchor pinned"
            )
        }
    }

    /// Non-vacuity control for the clipped leg: removing a visible head
    /// must change the ancestor raster inside its painted bounds.
    func assertVisibleHeadChangesRaster(
        sheet: MountedSheet,
        clipped: RasterBitmap,
        visible: [EngravedNoteHead]
    ) async throws {
        let sacrifice = try #require(visible.first)
        reinstall(sheet, engraving: sheet.engraving.swapping(
            noteHeads: sheet.engraving.noteHeads.filter {
                $0.noteID != sacrifice.noteID
            }
        ))
        let sacrificed = try rasterizeInAncestor(sheet, sheetSize: mountedViewport)
        let headDiff = changedPixels(
            in: sacrifice.paintedBounds
                .offsetBy(dx: sheetClipMargin, dy: sheetClipMargin),
            between: clipped, and: sacrificed
        )
        let bandDiff = changedPixels(
            in: ancestorViewportRect, between: clipped, and: sacrificed
        )
        let canvasDiff = changedPixels(
            in: CGRect(
                origin: .zero,
                size: oversizedClipCanvasSize(
                    contentHeight: sheet.engraving.contentHeight
                )
            ),
            between: clipped, and: sacrificed
        )
        #expect(
            headDiff > 0,
            """
            removing a visible head left the raster unchanged — differential is \
            vacuous (head \(sacrifice.paintedBounds) rect-diff \(headDiff), \
            band \(bandDiff), canvas \(canvasDiff))
            """
        )
    }
}
#endif
