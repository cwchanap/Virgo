import CoreGraphics
import CoreText
import Foundation

/// The single owner of Bravura font geometry: loads the pinned Bravura.otf and
/// SMuFL metadata.json from the package bundle (never AppFonts, never
/// Bundle.main) and turns catalog glyphs into staff-space-scaled metrics.
///
/// Path convention: the CTFont is created with size == unitsPerEm, so
/// `CTFontCreatePathForGlyph` returns raw outlines in font units (Y-up). The
/// single centered transform (`transform(rawBounds:scale:)`) then scales by
/// `staffSpace / (unitsPerEm / 4)` — one staff space is a quarter em — flips
/// into SwiftUI's Y-down space, and centers the glyph bounds on the origin.
enum BravuraFont {
    /// Cached package font. Swift `static let` initialization is thread-safe
    /// by construction (dispatch_once semantics).
    static let cgFont: CGFont = makeCGFont()
    /// metadata.json decoded once — both tables derive from the single parse.
    private static let metadata = decodeMetadata()
    /// `glyphsWithAnchors` from metadata.json; point values are staff spaces.
    private static var stemAnchors: [String: [String: CGPoint]] { metadata.stemAnchors }
    /// `glyphAdvanceWidths` from metadata.json; values are staff spaces.
    private static var advanceWidths: [String: CGFloat] { metadata.advanceWidths }
    /// CTFont at size == unitsPerEm so glyph paths come out in font units.
    private static let ctFont: CTFont = CTFontCreateWithGraphicsFont(
        cgFont, CGFloat(cgFont.unitsPerEm), nil, nil
    )
    /// Glyph ID + raw outline + outline bounds per glyph — the CoreText
    /// calls are the same for a given glyph at any staffSpace, so each
    /// catalog glyph pays them once.
    private static let glyphCache = GlyphCache()

    private static func makeCGFont() -> CGFont {
        guard let url = Bundle.module.url(forResource: "Bravura", withExtension: "otf"),
            let data = try? Data(contentsOf: url),
            let provider = CGDataProvider(data: data as CFData),
            let font = CGFont(provider)
        else {
            preconditionFailure("Bravura.otf is missing or unreadable in DrumNotation package resources")
        }
        return font
    }

    /// Both decoded metadata tables in one JSON parse — the file is ~730KB
    /// and was previously read and parsed per table.
    private struct Metadata {
        let stemAnchors: [String: [String: CGPoint]]
        let advanceWidths: [String: CGFloat]
    }

    private static func decodeMetadata() -> Metadata {
        guard let url = Bundle.module.url(forResource: "metadata", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            preconditionFailure("metadata.json is missing or malformed in DrumNotation package resources")
        }
        var anchors: [String: [String: CGPoint]] = [:]
        for (name, entry) in (root["glyphsWithAnchors"] as? [String: [String: Any]]) ?? [:] {
            var points: [String: CGPoint] = [:]
            for key in ["stemUpSE", "stemDownNW"] {
                if let pair = entry[key] as? [CGFloat], pair.count == 2 {
                    points[key] = CGPoint(x: pair[0], y: pair[1])
                }
            }
            if !points.isEmpty { anchors[name] = points }
        }
        let widths = (root["glyphAdvanceWidths"] as? [String: Any]) ?? [:]
        return Metadata(
            stemAnchors: anchors,
            advanceWidths: widths.compactMapValues { value in
                (value as? NSNumber).map { CGFloat(truncating: $0) }
            }
        )
    }

    /// Lock-guarded per-glyph cache: engraving runs off-main and the view
    /// reads the same outlines on the main actor, so misses populate under
    /// the lock while hits stay a dictionary read.
    struct GlyphCacheEntry {
        let glyphID: CGGlyph
        let outline: CGPath
        let bounds: CGRect
    }

    private final class GlyphCache {
        private var entries: [UInt32: GlyphCacheEntry] = [:]
        private let lock = NSLock()

        func entry(for glyph: SMuFLGlyph, ctFont: CTFont) -> GlyphCacheEntry {
            lock.lock()
            defer { lock.unlock() }
            if let cached = entries[glyph.scalar] { return cached }
            let glyphID = BravuraFont.resolveGlyphID(for: glyph, ctFont: ctFont)
            let outline = BravuraFont.makeRawPath(for: glyph, glyphID: glyphID, ctFont: ctFont)
            let entry = GlyphCacheEntry(glyphID: glyphID, outline: outline, bounds: outline.boundingBox)
            entries[glyph.scalar] = entry
            return entry
        }
    }

    /// Resolves a catalog glyph's Unicode scalar to its Bravura CGGlyph.
    static func glyphID(for glyph: SMuFLGlyph) -> CGGlyph {
        glyphCache.entry(for: glyph, ctFont: ctFont).glyphID
    }

    private static func resolveGlyphID(for glyph: SMuFLGlyph, ctFont: CTFont) -> CGGlyph {
        guard let scalar = Unicode.Scalar(glyph.scalar) else {
            let hex = String(glyph.scalar, radix: 16)
            preconditionFailure("glyph \(glyph.name) scalar U+\(hex) is not a Unicode scalar")
        }
        let units = Array(scalar.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        let mapped = units.withUnsafeBufferPointer { buffer in
            CTFontGetGlyphsForCharacters(ctFont, buffer.baseAddress!, &glyphs, units.count)
        }
        guard mapped, glyphs.contains(where: { $0 != 0 }) else {
            preconditionFailure("Bravura does not map glyph \(glyph.name) (U+\(String(glyph.scalar, radix: 16)))")
        }
        return glyphs[0]
    }

    /// Raw Bravura outline in font units (Y-up), per the CTFont size convention above.
    static func rawPath(for glyph: SMuFLGlyph) -> CGPath {
        glyphCache.entry(for: glyph, ctFont: ctFont).outline
    }

    /// The raw outline's font-unit bounds — cached with the outline.
    static func rawBounds(for glyph: SMuFLGlyph) -> CGRect {
        glyphCache.entry(for: glyph, ctFont: ctFont).bounds
    }

    private static func makeRawPath(for glyph: SMuFLGlyph, glyphID: CGGlyph, ctFont: CTFont) -> CGPath {
        guard let path = CTFontCreatePathForGlyph(ctFont, glyphID, nil) else {
            preconditionFailure("Bravura has no outline for glyph \(glyph.name)")
        }
        return path
    }

    /// The single transform for raw path bounds `rawBounds` at staff scale
    /// `scale`: scales by `scale`, flips into Y-down space, and centers the
    /// glyph bounds on the origin. Reused by metrics and paint.
    static func transform(rawBounds: CGRect, scale: CGFloat) -> CGAffineTransform {
        CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: -scale,
            tx: -rawBounds.midX * scale,
            ty: rawBounds.midY * scale
        )
    }

    /// Font-unit scale that renders one staff space as `staffSpace` points.
    static func staffScale(for staffSpace: CGFloat) -> CGFloat {
        staffSpace / (CGFloat(cgFont.unitsPerEm) / 4)
    }

    static func noteheadMetrics(
        glyph: SMuFLGlyph,
        stemDirection: NotationStemDirection,
        staffSpace: CGFloat,
        requiresStemAnchor: Bool
    ) -> NoteheadMetrics {
        let scale = staffScale(for: staffSpace)
        let rawBounds = BravuraFont.rawBounds(for: glyph)
        let t = transform(rawBounds: rawBounds, scale: scale)
        let anchorKey = stemDirection == .up ? "stemUpSE" : "stemDownNW"
        let stemAnchorOffset: CGPoint
        if let staffAnchor = stemAnchors[glyph.name]?[anchorKey] {
            // Metadata anchors are staff spaces; convert to font units before
            // applying the transform (one staff space = unitsPerEm / 4).
            let unitsPerStaffSpace = CGFloat(cgFont.unitsPerEm) / 4
            let rawAnchor = CGPoint(
                x: staffAnchor.x * unitsPerStaffSpace,
                y: staffAnchor.y * unitsPerStaffSpace
            )
            stemAnchorOffset = rawAnchor.applying(t)
        } else if requiresStemAnchor {
            preconditionFailure("Bravura metadata is missing \(anchorKey) for \(glyph.name)")
        } else {
            // Whole noteheads take no stems, so Bravura documents no anchor
            // for them and none is consumed downstream.
            stemAnchorOffset = .zero
        }
        return NoteheadMetrics(paintedBounds: rawBounds.applying(t), stemAnchorOffset: stemAnchorOffset)
    }

    static func primitiveMetrics(glyph: SMuFLGlyph, staffSpace: CGFloat) -> PrimitiveGlyphMetrics {
        let scale = staffScale(for: staffSpace)
        let rawBounds = BravuraFont.rawBounds(for: glyph)
        return PrimitiveGlyphMetrics(paintedBounds: rawBounds.applying(transform(rawBounds: rawBounds, scale: scale)))
    }

    static func flagMetrics(glyph: SMuFLGlyph, staffSpace: CGFloat) -> FlagGlyphMetrics {
        let scale = staffScale(for: staffSpace)
        let rawBounds = BravuraFont.rawBounds(for: glyph)
        let t = transform(rawBounds: rawBounds, scale: scale)
        // SMuFL flags carry no stemUpSE/stemDownNW anchors; the stem
        // attachment reference is the flag glyph origin (font origin 0, 0).
        return FlagGlyphMetrics(paintedBounds: rawBounds.applying(t), attachmentOffset: CGPoint.zero.applying(t))
    }

    /// A fitted numeral path for `actual`: every digit paints as its Bravura
    /// `tupletN` glyph (U+E880–U+E889), placed by the metadata advance
    /// widths — real measurement, not a scale-factor floor — and the whole
    /// run uniformly scaled so its union fits `size`. The returned path is
    /// centered on the origin in Y-down points, ready to frame to the
    /// reserved label rect. `ratio.actual` is an arbitrary positive Int per
    /// the resolved-input model, so any digit count must fit.
    ///
    /// Results are cached per (actual, size) — `DrumNotationView` calls this
    /// inside its body, and the result is identical for repeated evaluations
    /// of the same tuplet at the same label size.
    static func tupletNumeralPath(actual: Int, fitting size: CGSize) -> CGPath {
        precondition(actual > 0, "tuplet ratio.actual must be positive (got \(actual))")
        return numeralPathCache.path(actual: actual, size: size) {
            makeTupletNumeralPath(actual: actual, fitting: size)
        }
    }

    private static let numeralPathCache = NumeralPathCache()

    private struct NumeralKey: Hashable {
        let actual: Int
        let width: CGFloat
        let height: CGFloat
    }

    private final class NumeralPathCache {
        private var paths: [NumeralKey: CGPath] = [:]
        private let lock = NSLock()

        func path(actual: Int, size: CGSize, build: () -> CGPath) -> CGPath {
            let key = NumeralKey(actual: actual, width: size.width, height: size.height)
            lock.lock()
            defer { lock.unlock() }
            if let cached = paths[key] { return cached }
            let path = build()
            paths[key] = path
            return path
        }
    }

    private static func makeTupletNumeralPath(actual: Int, fitting size: CGSize) -> CGPath {
        let unitsPerStaffSpace = CGFloat(cgFont.unitsPerEm) / 4
        var placed: [CGPath] = []
        var xOffset: CGFloat = 0
        for digit in String(actual).compactMap(\.wholeNumberValue) {
            let name = "tuplet\(digit)"
            guard let advance = advanceWidths[name] else {
                preconditionFailure("Bravura metadata is missing glyphAdvanceWidths.\(name)")
            }
            let glyph = SMuFLGlyph(name: name, scalar: 0xE880 + UInt32(digit))
            var placement = CGAffineTransform(translationX: xOffset, y: 0)
            if let shifted = rawPath(for: glyph).copy(using: &placement) {
                placed.append(shifted)
            }
            xOffset += advance * unitsPerStaffSpace
        }
        var union = CGRect.null
        for path in placed { union = union.union(path.boundingBox) }
        let scale = min(size.width / union.width, size.height / union.height)
        let fit = transform(rawBounds: union, scale: scale)
        let combined = CGMutablePath()
        for path in placed { combined.addPath(path, transform: fit) }
        return combined
    }
}

/// Staff-space-scaled Bravura metrics. The only public sizing API: everything
/// downstream consumes these metrics; there is deliberately no CGSize primitive
/// sizing and no natural-size helper.
public enum PercussionGlyphMetrics {
    public static func notehead(
        style: PercussionNoteheadStyle,
        duration: NotationDuration,
        stemDirection: NotationStemDirection,
        staffSpace: CGFloat
    ) -> NoteheadMetrics {
        let glyph = SMuFLGlyphCatalog.notehead(style: style, duration: duration)
        return BravuraFont.noteheadMetrics(
            glyph: glyph,
            stemDirection: stemDirection,
            staffSpace: staffSpace,
            requiresStemAnchor: duration != .whole
        )
    }

    public static func rest(
        duration: NotationDuration,
        staffSpace: CGFloat
    ) -> PrimitiveGlyphMetrics {
        BravuraFont.primitiveMetrics(glyph: SMuFLGlyphCatalog.rest(for: duration), staffSpace: staffSpace)
    }

    public static func flag(
        duration: NotationFlagDuration,
        direction: NotationStemDirection,
        staffSpace: CGFloat
    ) -> FlagGlyphMetrics {
        let flagGlyph = SMuFLGlyphCatalog.flag(duration: duration, direction: direction)
        return BravuraFont.flagMetrics(glyph: flagGlyph, staffSpace: staffSpace)
    }

    public static func articulation(
        _ articulation: PercussionArticulation,
        staffSpace: CGFloat
    ) -> PrimitiveGlyphMetrics {
        BravuraFont.primitiveMetrics(glyph: SMuFLGlyphCatalog.articulation(articulation), staffSpace: staffSpace)
    }
}
