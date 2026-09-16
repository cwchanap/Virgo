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

@MainActor
extension GameplaySheetMusicGeometrySmokeTests {
    /// Rasterizes the production sheet fixed at `sheetSize`, inset by
    /// `sheetClipMargin` inside the oversized ancestor canvas. Neither the
    /// ancestor nor the hosting view clips — only the sheet's own
    /// `ScrollView` does — so content escaping the sheet paints into the
    /// captured margin bands where `ancestorOverflowInk` can measure it.
    /// Spacer layout (not `.offset`, which the hosted scroll hierarchy
    /// ignores) positions the sheet at (`sheetClipMargin`,
    /// `sheetClipMargin`).
    func rasterizeInAncestor(
        _ sheet: MountedSheet,
        sheetSize: CGSize
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
            size: oversizedClipCanvasSize(contentHeight: sheet.engraving.contentHeight)
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
