//
//  RenderRasterProbe.swift
//  VirgoTests
//

import SwiftUI
import Foundation
import CoreGraphics

#if os(macOS)
import AppKit

enum RenderRasterProbeError: Error {
    case missingCGImage
    case missingPixelBuffer
    case missingBitmapContext
    case missingPNGData
}

/// One pixel's channels, as a struct rather than a 4-tuple so SwiftLint's
/// `large_tuple` rule (error at 3 members) does not reject it.
struct RasterPixel {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}

/// A rasterized SwiftUI view as premultiplied-last RGBA bytes.
///
/// Shared so the two pixel-level probes in this target — the yellow-fill checks in
/// `SwiftUIRenderingNotationTests` and the differential ink probe in
/// `DrumTabRenderProbeTests` — rasterize through one implementation. They previously
/// carried separate copies of the same `ImageRenderer` → `CGContext` sequence, with
/// nothing keeping the two in step.
struct RasterBitmap {
    let bytes: [UInt8]
    let width: Int
    let height: Int

    static let bytesPerPixel = 4

    var pixelCount: Int { width * height }

    func pixel(at index: Int) -> RasterPixel {
        let base = index * Self.bytesPerPixel
        return RasterPixel(
            red: bytes[base],
            green: bytes[base + 1],
            blue: bytes[base + 2],
            alpha: bytes[base + 3]
        )
    }

    /// Counts pixels whose channels satisfy `predicate`.
    func count(where predicate: (RasterPixel) -> Bool) -> Int {
        (0..<pixelCount).reduce(0) { total, index in
            total + (predicate(pixel(at: index)) ? 1 : 0)
        }
    }
}

/// Renders `view` at exactly `size` into an offscreen bitmap.
///
/// `scale = 1` so pixel coordinates match SwiftUI points and a caller can sample a
/// layout rect directly. Throws rather than returning an empty bitmap, so a renderer
/// that produces nothing in this host fails loudly instead of reading as "no ink".
@MainActor
func rasterizeView<V: View>(_ view: V, size: CGSize) throws -> RasterBitmap {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = 1
    guard let cgImage = renderer.cgImage else {
        throw RenderRasterProbeError.missingCGImage
    }

    let width = cgImage.width
    let height = cgImage.height
    let bytesPerRow = width * RasterBitmap.bytesPerPixel
    var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)

    try bytes.withUnsafeMutableBytes { buffer in
        guard let baseAddress = buffer.baseAddress else {
            throw RenderRasterProbeError.missingPixelBuffer
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
            throw RenderRasterProbeError.missingBitmapContext
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    return RasterBitmap(bytes: bytes, width: width, height: height)
}

/// Renders `view` at exactly `size` by mounting it in a real `NSHostingView`
/// and snapshotting the laid-out layer.
///
/// `ImageRenderer` does not paint `ScrollView` document content in this
/// headless test host, so production branches that mount notation inside the
/// sheet's `ScrollView` must rasterize through this hosted path instead.
///
/// `scrollY` scrolls the first `NSScrollView` found inside the hosted view
/// by that many document points before snapshotting — the production scroll
/// path (`NSClipView` bounds origin), used to position a boundary-crossing
/// primitive mid-glyph across the sheet's clip edge.
@MainActor
func rasterizeHostedView<V: View>(
    _ view: V,
    size: CGSize,
    scrollY: CGFloat = 0
) throws -> RasterBitmap {
    let hostingView = NSHostingView(
        rootView: AnyView(view.frame(width: size.width, height: size.height))
    )
    hostingView.frame = CGRect(origin: .zero, size: size)
    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    if scrollY != 0, let scrollView = firstScrollView(in: hostingView) {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
    hostingView.layoutSubtreeIfNeeded()

    func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        return view.subviews.lazy.compactMap(firstScrollView(in:)).first
    }

    guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        throw RenderRasterProbeError.missingPixelBuffer
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
    guard let cgImage = rep.cgImage else {
        throw RenderRasterProbeError.missingCGImage
    }

    let width = Int(size.width)
    let height = Int(size.height)
    let bytesPerRow = width * RasterBitmap.bytesPerPixel
    var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)

    try bytes.withUnsafeMutableBytes { buffer in
        guard let baseAddress = buffer.baseAddress else {
            throw RenderRasterProbeError.missingPixelBuffer
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
            throw RenderRasterProbeError.missingBitmapContext
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    return RasterBitmap(bytes: bytes, width: width, height: height)
}

/// Rasterizes `view` at exactly `size` (scale 1) and writes it as a PNG to `url`
/// so a generated visual preview can be opened by its absolute path.
@MainActor
func writeRasterPNG<V: View>(
    _ view: V,
    size: CGSize,
    url: URL
) throws {
    let renderer = ImageRenderer(
        content: view.frame(width: size.width, height: size.height)
    )
    renderer.scale = 1
    guard let cgImage = renderer.cgImage else {
        throw RenderRasterProbeError.missingCGImage
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw RenderRasterProbeError.missingPNGData
    }
    try data.write(to: url)
}
#endif
