import SwiftUI

/// Collision-safe semantic key for `DrumNotationView`'s accessibility label
/// map. The package's note/rest/control/tuplet ID collections are separate
/// namespaces whose integers may coincide, so one bare `[Int: String]`
/// lookup would bleed labels across kinds — the enum keeps them apart at
/// the type level.
public enum NotationSemanticID: Hashable, Sendable {
    case note(Int)
    case rest(Int)
    case control(Int)
    case tuplet(Int)
}

/// The narrow view-only paint input for `DrumNotationView`: colors and
/// derived opacities only. Engraving geometry and stroke metrics stay on
/// `EngravedNotation`/`NotationEngravingStyle`; localized strings arrive
/// through the separate label map. No theme, `Palette`, or environment
/// reads cross this boundary.
public struct DrumNotationAppearance: Sendable {
    /// Ink for semantic and structural primitives: heads, rests, stems,
    /// beams, flags, dots, articulations, controls, tuplets, clef, meter
    /// and measure bars.
    public var foreground: Color
    /// Staff-line ink — the decorative furniture tier. Defaults to the
    /// foreground at half opacity, matching the app's staff-line tier.
    public var staffLines: Color

    public init(foreground: Color = .primary, staffLines: Color? = nil) {
        self.foreground = foreground
        self.staffLines = staffLines ?? foreground.opacity(0.5)
    }
}

/// Shared painter for the package primitives: resolves the SMuFL glyph through
/// the same catalog the metrics use, asks `BravuraFont` for the same
/// staff-space-scaled transformed path (no second size/transform path), and
/// fills the closed outline with `color`, framed exactly to the glyph's
/// painted bounds.
///
/// Bravura glyph outlines are single closed contours (the whole/half noteheads
/// included), so the standard nonzero fill rule is correct.
private struct GlyphFill: View {
    let glyph: SMuFLGlyph
    let staffSpace: CGFloat
    let color: Color

    var body: some View {
        let raw = BravuraFont.rawPath(for: glyph)
        let path = Path(raw).applying(
            BravuraFont.transform(
                rawBounds: raw.boundingBox,
                scale: BravuraFont.staffScale(for: staffSpace)
            )
        )
        let bounds = path.boundingRect
        return path
            .offset(x: -bounds.minX, y: -bounds.minY)
            .fill(color)
            .frame(width: bounds.width, height: bounds.height)
    }
}

/// A percussion notehead painted from Bravura, sized to its painted bounds.
public struct PercussionNoteheadView: View {
    private let style: PercussionNoteheadStyle
    private let duration: NotationDuration
    private let staffSpace: CGFloat
    private let color: Color

    public init(
        style: PercussionNoteheadStyle,
        duration: NotationDuration,
        staffSpace: CGFloat,
        color: Color = .primary
    ) {
        self.style = style
        self.duration = duration
        self.staffSpace = staffSpace
        self.color = color
    }

    public var body: some View {
        GlyphFill(
            glyph: SMuFLGlyphCatalog.notehead(style: style, duration: duration),
            staffSpace: staffSpace,
            color: color
        )
    }
}

/// A rest glyph painted from Bravura, sized to its painted bounds.
public struct NotationRestGlyphView: View {
    private let duration: NotationDuration
    private let staffSpace: CGFloat
    private let color: Color

    public init(duration: NotationDuration, staffSpace: CGFloat, color: Color = .primary) {
        self.duration = duration
        self.staffSpace = staffSpace
        self.color = color
    }

    public var body: some View {
        GlyphFill(
            glyph: SMuFLGlyphCatalog.rest(for: duration),
            staffSpace: staffSpace,
            color: color
        )
    }
}

/// A stem flag glyph painted from Bravura, sized to its painted bounds. The
/// flag's glyph-origin attachment point (see `FlagGlyphMetrics.attachmentOffset`)
/// is where a stem would join it.
public struct NotationFlagGlyphView: View {
    private let duration: NotationFlagDuration
    private let direction: NotationStemDirection
    private let staffSpace: CGFloat
    private let color: Color

    public init(
        duration: NotationFlagDuration,
        direction: NotationStemDirection,
        staffSpace: CGFloat,
        color: Color = .primary
    ) {
        self.duration = duration
        self.direction = direction
        self.staffSpace = staffSpace
        self.color = color
    }

    public var body: some View {
        GlyphFill(
            glyph: SMuFLGlyphCatalog.flag(duration: duration, direction: direction),
            staffSpace: staffSpace,
            color: color
        )
    }
}

/// A percussion articulation glyph painted from Bravura, sized to its painted bounds.
public struct PercussionArticulationView: View {
    private let articulation: PercussionArticulation
    private let staffSpace: CGFloat
    private let color: Color

    public init(articulation: PercussionArticulation, staffSpace: CGFloat, color: Color = .primary) {
        self.articulation = articulation
        self.staffSpace = staffSpace
        self.color = color
    }

    public var body: some View {
        GlyphFill(
            glyph: SMuFLGlyphCatalog.articulation(articulation),
            staffSpace: staffSpace,
            color: color
        )
    }
}
