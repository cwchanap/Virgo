import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import DrumNotation

/// Geometry tests for the Bravura glyph pipeline. Expected values are
/// recomputed independently from the package CGFont and the source
/// metadata.json — production metrics are never fed into the expectations.
@Suite("Bravura geometry")
struct BravuraGeometryTests {
    private static let flagDurations: [NotationDuration] = [
        .eighth, .sixteenth, .thirtySecond, .sixtyFourth
    ]
    /// Only stem-carrying notehead durations; whole noteheads document no stem
    /// anchors in Bravura because whole notes take no stems.
    private static let anchoredNoteheadDurations: [NotationDuration] = [.half, .quarter]
    /// Per-fixture widened edge-band widths where a documented Bravura anchor
    /// sits just outside the outline by less than a stem thickness.
    private static let edgeBandWidths: [String: CGFloat] = [:]
    /// Independent CTFont at size == unitsPerEm (the convention documented on
    /// BravuraFont) so reference paths come out in font units.
    private static let referenceFont: CTFont = CTFontCreateWithGraphicsFont(
        BravuraFont.cgFont, CGFloat(BravuraFont.cgFont.unitsPerEm), nil, nil
    )
    /// `glyphsWithAnchors` read straight from the source metadata.json.
    private static let sourceStemAnchors: [String: [String: CGPoint]] = {
        let url = Bundle.module.url(forResource: "metadata", withExtension: "json")!
        let root = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let all = root["glyphsWithAnchors"] as! [String: [String: Any]]
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
    }()

    private static var allGlyphs: [SMuFLGlyph] {
        var glyphs: [SMuFLGlyph] = []
        for style in PercussionNoteheadStyle.allCases {
            for duration in NotationDuration.allCases {
                glyphs.append(SMuFLGlyphCatalog.notehead(style: style, duration: duration))
            }
        }
        for duration in NotationDuration.allCases {
            glyphs.append(SMuFLGlyphCatalog.rest(for: duration))
        }
        for duration in flagDurations {
            for direction in [NotationStemDirection.up, .down] {
                glyphs.append(SMuFLGlyphCatalog.flag(duration: duration, direction: direction))
            }
        }
        for articulation in [PercussionArticulation.open] {
            glyphs.append(SMuFLGlyphCatalog.articulation(articulation))
        }
        return glyphs
    }

    // MARK: Step 1 — package resources and glyph plumbing

    @Test("Bundle.module resolves all three Bravura files")
    func bundleResolvesBravuraFiles() throws {
        for (resource, ext) in [("Bravura", "otf"), ("metadata", "json"), ("LICENSE", "txt")] {
            let url = try #require(
                Bundle.module.url(forResource: resource, withExtension: ext),
                "missing \(resource).\(ext) in package bundle"
            )
            let data = try Data(contentsOf: url)
            #expect(!data.isEmpty, "\(resource).\(ext) is empty")
        }
    }

    @Test("every accepted scalar resolves to a nonzero CGGlyph")
    func scalarsResolveToNonzeroGlyphs() {
        for glyph in Self.allGlyphs {
            #expect(BravuraFont.glyphID(for: glyph) != 0, "unresolved glyph: \(glyph.name)")
        }
    }

    @Test("every accepted glyph produces a nonempty path")
    func glyphsProduceNonemptyPaths() {
        for glyph in Self.allGlyphs {
            #expect(!BravuraFont.rawPath(for: glyph).isEmpty, "empty path: \(glyph.name)")
        }
    }

    // MARK: Independent reference helpers

    private static func referenceRawPath(_ glyph: SMuFLGlyph) -> CGPath {
        guard let path = CTFontCreatePathForGlyph(referenceFont, BravuraFont.glyphID(for: glyph), nil) else {
            preconditionFailure("reference path unavailable for \(glyph.name)")
        }
        return path
    }

    private static func referenceRawBounds(_ glyph: SMuFLGlyph) -> CGRect {
        referenceRawPath(glyph).boundingBox
    }

    /// The brief's scale: one staff space is a quarter em.
    private static func referenceScale(staffSpace: CGFloat) -> CGFloat {
        staffSpace / (CGFloat(BravuraFont.cgFont.unitsPerEm) / 4)
    }

    /// The brief's single centered transform, recomputed independently.
    private static func referenceTransform(bounds: CGRect, scale: CGFloat) -> CGAffineTransform {
        CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: -bounds.midX * scale, ty: bounds.midY * scale)
    }

    /// Painted bounds from the public API for every accepted glyph.
    private func acceptedPaintedBounds(staffSpace: CGFloat) -> [(glyph: SMuFLGlyph, bounds: CGRect)] {
        var fixtures: [(glyph: SMuFLGlyph, bounds: CGRect)] = []
        for style in PercussionNoteheadStyle.allCases {
            for duration in NotationDuration.allCases {
                let glyph = SMuFLGlyphCatalog.notehead(style: style, duration: duration)
                let metrics = PercussionGlyphMetrics.notehead(
                    style: style, duration: duration, stemDirection: .up, staffSpace: staffSpace
                )
                fixtures.append((glyph, metrics.paintedBounds))
            }
        }
        for duration in NotationDuration.allCases {
            let glyph = SMuFLGlyphCatalog.rest(for: duration)
            let metrics = PercussionGlyphMetrics.rest(duration: duration, staffSpace: staffSpace)
            fixtures.append((glyph, metrics.paintedBounds))
        }
        for duration in Self.flagDurations {
            for direction in [NotationStemDirection.up, .down] {
                let glyph = SMuFLGlyphCatalog.flag(duration: duration, direction: direction)
                let metrics = PercussionGlyphMetrics.flag(
                    duration: duration, direction: direction, staffSpace: staffSpace
                )
                fixtures.append((glyph, metrics.paintedBounds))
            }
        }
        for articulation in [PercussionArticulation.open] {
            let glyph = SMuFLGlyphCatalog.articulation(articulation)
            let metrics = PercussionGlyphMetrics.articulation(articulation, staffSpace: staffSpace)
            fixtures.append((glyph, metrics.paintedBounds))
        }
        return fixtures
    }

    // MARK: Step 3 — exact staff-space scale (no legacy frame fitting)

    @Test("painted bounds use the exact staff-space scale at staffSpace = 20")
    func paintedBoundsUseExactStaffSpaceScale() {
        let staffSpace: CGFloat = 20
        let scale = Self.referenceScale(staffSpace: staffSpace)
        // Includes noteheadWhole, noteheadBlack, restWhole and restQuarter, so
        // no implementation can reintroduce fitting into the old 30×20, 18×5
        // or 18×28 frames.
        for (glyph, painted) in acceptedPaintedBounds(staffSpace: staffSpace) {
            let raw = Self.referenceRawBounds(glyph)
            #expect(abs(painted.width - raw.width * scale) < 0.001,
                    "\(glyph.name): width not at exact staff-space scale")
            #expect(abs(painted.height - raw.height * scale) < 0.001,
                    "\(glyph.name): height not at exact staff-space scale")
            let expected = raw.applying(Self.referenceTransform(bounds: raw, scale: scale))
            #expect(abs(painted.minX - expected.minX) < 0.001, "\(glyph.name): minX not centered at staff-space scale")
            #expect(abs(painted.minY - expected.minY) < 0.001, "\(glyph.name): minY not centered at staff-space scale")
        }
    }

    // MARK: Step 4 — notehead stem anchors through the single transform

    @Test("notehead stem anchors match the independent metadata transform")
    func noteheadStemAnchorsMatchIndependentTransform() throws {
        for style in PercussionNoteheadStyle.allCases {
            for duration in Self.anchoredNoteheadDurations {
                for direction in [NotationStemDirection.up, .down] {
                    try assertStemAnchor(style: style, duration: duration, direction: direction)
                }
            }
        }
    }

    @Test("whole noteheads carry no stem anchor")
    func wholeNoteheadsCarryNoStemAnchor() {
        for style in PercussionNoteheadStyle.allCases {
            for direction in [NotationStemDirection.up, .down] {
                let metrics = PercussionGlyphMetrics.notehead(
                    style: style, duration: .whole, stemDirection: direction, staffSpace: 20
                )
                #expect(metrics.stemAnchorOffset == .zero, "\(style) whole \(direction) must have no stem anchor")
            }
        }
    }

    private func assertStemAnchor(
        style: PercussionNoteheadStyle,
        duration: NotationDuration,
        direction: NotationStemDirection
    ) throws {
        let staffSpace: CGFloat = 20
        let scale = Self.referenceScale(staffSpace: staffSpace)
        let glyph = SMuFLGlyphCatalog.notehead(style: style, duration: duration)
        let metrics = PercussionGlyphMetrics.notehead(
            style: style, duration: duration, stemDirection: direction, staffSpace: staffSpace
        )
        let anchorKey = direction == .up ? "stemUpSE" : "stemDownNW"
        let staffAnchor = try #require(
            Self.sourceStemAnchors[glyph.name]?[anchorKey],
            "source metadata has no \(anchorKey) for \(glyph.name)"
        )
        // Anchor: staff spaces -> font units, then through the centered transform.
        let unitsPerStaffSpace = CGFloat(BravuraFont.cgFont.unitsPerEm) / 4
        let rawAnchor = CGPoint(x: staffAnchor.x * unitsPerStaffSpace, y: staffAnchor.y * unitsPerStaffSpace)
        let rawBounds = Self.referenceRawBounds(glyph)
        let expectedAnchor = CGPoint(
            x: (rawAnchor.x - rawBounds.midX) * scale,
            y: -(rawAnchor.y - rawBounds.midY) * scale
        )
        #expect(abs(metrics.stemAnchorOffset.x - expectedAnchor.x) < 0.001, "\(glyph.name) \(anchorKey): anchor x")
        #expect(abs(metrics.stemAnchorOffset.y - expectedAnchor.y) < 0.001, "\(glyph.name) \(anchorKey): anchor y")

        // The transformed anchor must sit in a narrow stroked edge band around
        // the transformed outline.
        var outlineTransform = Self.referenceTransform(bounds: rawBounds, scale: scale)
        guard let transformed = Self.referenceRawPath(glyph).copy(using: &outlineTransform) else {
            Issue.record("cannot transform path for \(glyph.name)")
            return
        }
        let bandWidth = Self.edgeBandWidths[glyph.name] ?? 1.0
        let band = transformed.copy(
            strokingWithWidth: bandWidth,
            lineCap: CGLineCap.round,
            lineJoin: CGLineJoin.round,
            miterLimit: 10
        )
        #expect(band.contains(metrics.stemAnchorOffset), "\(glyph.name) \(anchorKey): anchor outside outline band")
    }

    // MARK: Step 5 — flag attachment is the transformed glyph origin

    @Test("flag attachment offset is the transformed glyph origin")
    func flagAttachmentIsTransformedGlyphOrigin() {
        let staffSpace: CGFloat = 20
        let scale = Self.referenceScale(staffSpace: staffSpace)
        for duration in Self.flagDurations {
            for direction in [NotationStemDirection.up, .down] {
                let glyph = SMuFLGlyphCatalog.flag(duration: duration, direction: direction)
                let metrics = PercussionGlyphMetrics.flag(
                    duration: duration, direction: direction, staffSpace: staffSpace
                )
                let rawBounds = Self.referenceRawBounds(glyph)
                // Bravura flags have no stemUpSE/stemDownNW anchors; the stem
                // attachment reference is the flag glyph origin (0, 0).
                let expected = CGPoint.zero.applying(Self.referenceTransform(bounds: rawBounds, scale: scale))
                #expect(abs(metrics.attachmentOffset.x - expected.x) < 0.001, "\(glyph.name): attachment x")
                #expect(abs(metrics.attachmentOffset.y - expected.y) < 0.001, "\(glyph.name): attachment y")
                // Translating the centered path by center puts the attachment
                // back exactly on the requested stem origin.
                let stemOrigin = CGPoint(x: 120, y: 40)
                let center = CGPoint(
                    x: stemOrigin.x - metrics.attachmentOffset.x,
                    y: stemOrigin.y - metrics.attachmentOffset.y
                )
                let placed = CGPoint(
                    x: center.x + metrics.attachmentOffset.x,
                    y: center.y + metrics.attachmentOffset.y
                )
                #expect(abs(placed.x - stemOrigin.x) < 0.001, "\(glyph.name): round trip misses stem origin x")
                #expect(abs(placed.y - stemOrigin.y) < 0.001, "\(glyph.name): round trip misses stem origin y")
            }
        }
    }
}
