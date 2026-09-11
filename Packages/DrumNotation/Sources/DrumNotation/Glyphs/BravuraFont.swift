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
    /// `glyphsWithAnchors` from metadata.json; point values are staff spaces.
    private static let stemAnchors: [String: [String: CGPoint]] = decodeStemAnchors()
    /// CTFont at size == unitsPerEm so glyph paths come out in font units.
    private static let ctFont: CTFont = CTFontCreateWithGraphicsFont(
        cgFont, CGFloat(cgFont.unitsPerEm), nil, nil
    )

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

    private static func decodeStemAnchors() -> [String: [String: CGPoint]] {
        guard let url = Bundle.module.url(forResource: "metadata", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let all = root["glyphsWithAnchors"] as? [String: [String: Any]]
        else {
            preconditionFailure("metadata.json is missing or malformed in DrumNotation package resources")
        }
        var anchors: [String: [String: CGPoint]] = [:]
        for (name, entry) in all {
            var points: [String: CGPoint] = [:]
            for key in ["stemUpSE", "stemDownNW"] {
                if let pair = entry[key] as? [CGFloat], pair.count == 2 {
                    points[key] = CGPoint(x: pair[0], y: pair[1])
                }
            }
            if !points.isEmpty { anchors[name] = points }
        }
        return anchors
    }

    /// Resolves a catalog glyph's Unicode scalar to its Bravura CGGlyph.
    static func glyphID(for glyph: SMuFLGlyph) -> CGGlyph {
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
        guard let path = CTFontCreatePathForGlyph(ctFont, glyphID(for: glyph), nil) else {
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
        let rawBounds = rawPath(for: glyph).boundingBox
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
        let rawBounds = rawPath(for: glyph).boundingBox
        return PrimitiveGlyphMetrics(paintedBounds: rawBounds.applying(transform(rawBounds: rawBounds, scale: scale)))
    }

    static func flagMetrics(glyph: SMuFLGlyph, staffSpace: CGFloat) -> FlagGlyphMetrics {
        let scale = staffScale(for: staffSpace)
        let rawBounds = rawPath(for: glyph).boundingBox
        let t = transform(rawBounds: rawBounds, scale: scale)
        // SMuFL flags carry no stemUpSE/stemDownNW anchors; the stem
        // attachment reference is the flag glyph origin (font origin 0, 0).
        return FlagGlyphMetrics(paintedBounds: rawBounds.applying(t), attachmentOffset: CGPoint.zero.applying(t))
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
        duration: NotationDuration,
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
