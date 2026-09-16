import CoreGraphics

/// Plain scalar engraving style; every value is points. `formatting` stays
/// the sole horizontal authority — this style adds the vertical, beam,
/// control, tuplet and bar metrics the final geometry pass consumes. The
/// defaults are the mapping Virgo uses (its `NotationLayoutStyle.gameplayDefault`
/// plus the `GameplayLayout` constants); Virgo maps every app scalar
/// explicitly through its own projection, so there is intentionally no
/// `.standard` convenience singleton — ordinary construction uses the
/// defaulted initializer below.
public struct NotationEngravingStyle: Hashable, Sendable {
    /// Horizontal formatting style — the only spacing/X authority.
    public let formatting: NotationFormattingStyle
    /// Height of one staff row's content band; successive row staff centers
    /// sit `rowHeight + rowVerticalSpacing` apart.
    public let rowHeight: CGFloat
    public let rowVerticalSpacing: CGFloat
    /// Default stem length from the head's Bravura stem anchor.
    public let stemLength: CGFloat
    /// Minimum stem reach past the far chord edge (and past flag ink).
    public let minimumStemExtensionPastChord: CGFloat
    public let beamThickness: CGFloat
    /// Vertical pitch between stacked beam levels.
    public let beamLevelSpacing: CGFloat
    /// Maximum horizontal reach of a beam hook segment.
    public let beamHookLength: CGFloat
    /// Vertical pitch between successive uncovered component flags painted
    /// below/above a shared stem tip. **No default**: Virgo must map
    /// `GameplayLayout.flagVerticalSpacing` explicitly so the package never
    /// silently pins a different value.
    public let flagVerticalSpacing: CGFloat
    /// Extra ledger-line reach past each side of the head's painted bounds.
    public let ledgerLineOverhang: CGFloat
    /// Rest-center offset from the row staff center per voice (negative is
    /// toward the staff top).
    public let upperVoiceRestOffset: CGFloat
    public let lowerVoiceRestOffset: CGFloat
    public let stopMarkSize: CGFloat
    public let stopMarkStrokeWidth: CGFloat
    /// Distance the control mark sits above its resolved target staff step.
    public let stopMarkVerticalOffset: CGFloat
    /// Distance an articulation sits above its note head.
    public let articulationVerticalOffset: CGFloat
    public let tupletLineWidth: CGFloat
    public let tupletLabelSize: CGSize
    /// Distance the tuplet label/bracket sits outside the member bounds or
    /// beam stack.
    public let tupletVerticalOffset: CGFloat
    /// Vertical leg length of a tuplet bracket hook.
    public let tupletHookLength: CGFloat
    public let barLineWidth: CGFloat
    public let doubleBarThinWidth: CGFloat
    public let doubleBarThickWidth: CGFloat
    public let doubleBarSpacing: CGFloat
    /// Horizontal advance reserved for the percussion clef at a row start.
    public let clefWidth: CGFloat
    /// Horizontal advance reserved for the meter signature at a row start.
    public let meterWidth: CGFloat

    public init(
        formatting: NotationFormattingStyle = .virgoDefault,
        rowHeight: CGFloat = 280,
        rowVerticalSpacing: CGFloat = 60,
        stemLength: CGFloat = 75,
        minimumStemExtensionPastChord: CGFloat = 10,
        beamThickness: CGFloat = 4,
        beamLevelSpacing: CGFloat = 6,
        beamHookLength: CGFloat = 12,
        flagVerticalSpacing: CGFloat,
        ledgerLineOverhang: CGFloat = 6,
        upperVoiceRestOffset: CGFloat = -20,
        lowerVoiceRestOffset: CGFloat = 20,
        stopMarkSize: CGFloat = 14,
        stopMarkStrokeWidth: CGFloat = 2,
        stopMarkVerticalOffset: CGFloat = 18,
        articulationVerticalOffset: CGFloat = 24,
        tupletLineWidth: CGFloat = 1.5,
        tupletLabelSize: CGSize = CGSize(width: 14, height: 16),
        tupletVerticalOffset: CGFloat = 10,
        tupletHookLength: CGFloat = 6,
        barLineWidth: CGFloat = 2,
        doubleBarThinWidth: CGFloat = 2,
        doubleBarThickWidth: CGFloat = 4,
        doubleBarSpacing: CGFloat = 3,
        clefWidth: CGFloat = 40,
        meterWidth: CGFloat = 30
    ) {
        self.formatting = formatting
        self.rowHeight = rowHeight
        self.rowVerticalSpacing = rowVerticalSpacing
        self.stemLength = stemLength
        self.minimumStemExtensionPastChord = minimumStemExtensionPastChord
        self.beamThickness = beamThickness
        self.beamLevelSpacing = beamLevelSpacing
        self.beamHookLength = beamHookLength
        self.flagVerticalSpacing = flagVerticalSpacing
        self.ledgerLineOverhang = ledgerLineOverhang
        self.upperVoiceRestOffset = upperVoiceRestOffset
        self.lowerVoiceRestOffset = lowerVoiceRestOffset
        self.stopMarkSize = stopMarkSize
        self.stopMarkStrokeWidth = stopMarkStrokeWidth
        self.stopMarkVerticalOffset = stopMarkVerticalOffset
        self.articulationVerticalOffset = articulationVerticalOffset
        self.tupletLineWidth = tupletLineWidth
        self.tupletLabelSize = tupletLabelSize
        self.tupletVerticalOffset = tupletVerticalOffset
        self.tupletHookLength = tupletHookLength
        self.barLineWidth = barLineWidth
        self.doubleBarThinWidth = doubleBarThinWidth
        self.doubleBarThickWidth = doubleBarThickWidth
        self.doubleBarSpacing = doubleBarSpacing
        self.clefWidth = clefWidth
        self.meterWidth = meterWidth
    }
}
