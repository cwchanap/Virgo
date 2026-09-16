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
        CGRect(
            x: 0, y: bleedLine,
            width: canvas.width, height: canvas.height - bleedLine
        )
    ]
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
    /// the 768pt band is clipped. Removing the same heads must change ink
    /// outside that band — proving the canvas can capture the overflow the
    /// clipped leg forbids.
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
        let overflow = ancestorOverflowInk(
            between: unclipped, and: stripped, contentHeight: sheet.engraving.contentHeight
        )
        #expect(
            overflow > 0,
            """
            unclipped control: removing \(offscreenCount) off-viewport head(s) \
            produced no ink outside the 768pt band — the clipping gate is vacuous
            """
        )
        reinstall(sheet, engraving: sheet.engraving)
    }

    /// Boundary-crossing leg: with the sheet scrolled `scrollY` document
    /// points down, every head straddling the 768pt clip edge loses its
    /// inside-viewport ink when removed, while nothing changes outside the
    /// viewport — top/side margins and the deep region below the
    /// `clipEdgeBleed` AA band all stay identical. In the full-height
    /// control the same removal must move ink outside the band. The
    /// upstream `#require` makes a missing or shallow crossing selection a
    /// failure, so the gate can never silently vacate.
    func assertCrossingHeadClipsAtEdge(
        sheet: MountedSheet,
        clipped: RasterBitmap,
        crossing: [EngravedNoteHead]
    ) async throws {
        let crossingIDs = Set(crossing.map(\.noteID))
        let scrolledViewport = CGRect(
            origin: CGPoint(x: 0, y: crossingScrollY),
            size: mountedViewport
        )
        // Inside part of each crossing head, in ancestor-canvas
        // coordinates: sheet bounds shifted by the margin, minus the
        // document scroll offset.
        let insideRects = crossing.map {
            $0.paintedBounds
                .intersection(scrolledViewport)
                .offsetBy(dx: sheetClipMargin, dy: sheetClipMargin - crossingScrollY)
        }
        reinstall(sheet, engraving: sheet.engraving.swapping(
            noteHeads: sheet.engraving.noteHeads.filter {
                !crossingIDs.contains($0.noteID)
            }
        ))
        let stripped = try rasterizeInAncestor(
            sheet, sheetSize: mountedViewport, scrollY: crossingScrollY
        )
        for rect in insideRects {
            #expect(
                changedPixels(in: rect, between: clipped, and: stripped) > 0,
                "crossing head's inside-viewport part painted no ink at \(rect)"
            )
        }
        for rect in outsideClipRects(contentHeight: sheet.engraving.contentHeight) {
            let outside = changedPixels(in: rect, between: clipped, and: stripped)
            #expect(
                outside == 0,
                """
                crossing head's clipped part changed \(outside) pixel(s) in \
                outside region \(rect) — content escaped the clip edge
                """
            )
        }
        reinstall(sheet, engraving: sheet.engraving)
        try await assertCrossingHeadUnclipped(sheet: sheet, crossingIDs: crossingIDs)
    }

    /// Full-height control for the crossing leg: the same heads, mounted
    /// with no clip beyond the content — their removal must move ink
    /// outside the 768pt band.
    private func assertCrossingHeadUnclipped(
        sheet: MountedSheet,
        crossingIDs: Set<Int>
    ) async throws {
        let fullHeight = CGSize(
            width: mountedViewport.width,
            height: sheet.engraving.contentHeight
        )
        let headful = try rasterizeInAncestor(sheet, sheetSize: fullHeight)
        reinstall(sheet, engraving: sheet.engraving.swapping(
            noteHeads: sheet.engraving.noteHeads.filter {
                !crossingIDs.contains($0.noteID)
            }
        ))
        let stripped = try rasterizeInAncestor(sheet, sheetSize: fullHeight)
        let overflow = ancestorOverflowInk(
            between: headful, and: stripped,
            contentHeight: sheet.engraving.contentHeight
        )
        #expect(
            overflow > 0,
            "unclipped crossing leg: no ink moved outside the 768pt band — gate is vacuous"
        )
        reinstall(sheet, engraving: sheet.engraving)
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
