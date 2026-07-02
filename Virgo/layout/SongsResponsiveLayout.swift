//
//  SongsResponsiveLayout.swift
//  Virgo
//
//  Responsive layout decision for the Songs tab: a multi-column card grid on
//  wide widths, compact rows when narrow. The mode is a pure function of the
//  available content width so it can be unit-tested without rendering.
//

import SwiftUI

enum SongsLayoutMode: Equatable {
    case rows
    case grid

    /// Minimum content width that warrants a multi-column card grid. Below this
    /// (e.g. iPad Split View / Slide Over) the compact row list is used.
    static let gridMinWidth: CGFloat = 700

    static func forWidth(_ width: CGFloat) -> SongsLayoutMode {
        width >= gridMinWidth ? .grid : .rows
    }
}

enum SongsGrid {
    /// Adaptive columns: ~2 at 700pt, 3-4 on full iPad/macOS. No manual math.
    static let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 260, maximum: 360), spacing: Spacing.md)
    ]
}
