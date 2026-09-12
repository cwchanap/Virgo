import CoreGraphics

public enum NotationDuration: String, CaseIterable, Sendable {
    case whole, half, quarter, eighth, sixteenth, thirtySecond, sixtyFourth
}

/// The subset of `NotationDuration` that can carry a flag: eighth notes and
/// shorter. Flag APIs take this type so durations that have no flag glyph
/// (whole/half/quarter) are unrepresentable rather than rejected at paint time.
public enum NotationFlagDuration: String, CaseIterable, Sendable {
    case eighth, sixteenth, thirtySecond, sixtyFourth
}

public enum PercussionNoteheadStyle: String, CaseIterable, Sendable {
    case normal, x, diamond
}

public enum NotationStemDirection: String, Sendable {
    case up, down
}

public enum PercussionArticulation: String, Sendable {
    case open
}

public struct PrimitiveGlyphMetrics: Equatable, Sendable {
    public let paintedBounds: CGRect
}

public struct NoteheadMetrics: Equatable, Sendable {
    public let paintedBounds: CGRect
    public let stemAnchorOffset: CGPoint
}

public struct FlagGlyphMetrics: Equatable, Sendable {
    public let paintedBounds: CGRect
    public let attachmentOffset: CGPoint
}
