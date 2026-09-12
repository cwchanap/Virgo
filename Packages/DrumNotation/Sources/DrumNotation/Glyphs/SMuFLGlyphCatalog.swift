/// Closed catalog of the SMuFL glyphs DrumNotation uses, pinned to Bravura 1.392
/// (SMuFL 1.3 codepoints). Lookups are exhaustive switches over package semantic
/// enums — there is intentionally no public raw SMuFL lookup and no default branch.
enum SMuFLGlyphCatalog {
    static func notehead(style: PercussionNoteheadStyle, duration: NotationDuration) -> SMuFLGlyph {
        switch style {
        case .normal: return normalNotehead(for: duration)
        case .x: return xNotehead(for: duration)
        case .diamond: return diamondNotehead(for: duration)
        }
    }

    private static func normalNotehead(for duration: NotationDuration) -> SMuFLGlyph {
        switch duration {
        case .whole: return SMuFLGlyph(name: "noteheadWhole", scalar: 0xE0A2)
        case .half: return SMuFLGlyph(name: "noteheadHalf", scalar: 0xE0A3)
        case .quarter, .eighth, .sixteenth, .thirtySecond, .sixtyFourth:
            return SMuFLGlyph(name: "noteheadBlack", scalar: 0xE0A4)
        }
    }

    private static func xNotehead(for duration: NotationDuration) -> SMuFLGlyph {
        switch duration {
        case .whole: return SMuFLGlyph(name: "noteheadXWhole", scalar: 0xE0A7)
        case .half: return SMuFLGlyph(name: "noteheadXHalf", scalar: 0xE0A8)
        case .quarter, .eighth, .sixteenth, .thirtySecond, .sixtyFourth:
            return SMuFLGlyph(name: "noteheadXBlack", scalar: 0xE0A9)
        }
    }

    private static func diamondNotehead(for duration: NotationDuration) -> SMuFLGlyph {
        switch duration {
        case .whole: return SMuFLGlyph(name: "noteheadDiamondWhole", scalar: 0xE0D8)
        case .half: return SMuFLGlyph(name: "noteheadDiamondHalf", scalar: 0xE0D9)
        case .quarter, .eighth, .sixteenth, .thirtySecond, .sixtyFourth:
            return SMuFLGlyph(name: "noteheadDiamondBlack", scalar: 0xE0DB)
        }
    }

    static func rest(for duration: NotationDuration) -> SMuFLGlyph {
        switch duration {
        case .whole: return SMuFLGlyph(name: "restWhole", scalar: 0xE4E3)
        case .half: return SMuFLGlyph(name: "restHalf", scalar: 0xE4E4)
        case .quarter: return SMuFLGlyph(name: "restQuarter", scalar: 0xE4E5)
        case .eighth: return SMuFLGlyph(name: "rest8th", scalar: 0xE4E6)
        case .sixteenth: return SMuFLGlyph(name: "rest16th", scalar: 0xE4E7)
        case .thirtySecond: return SMuFLGlyph(name: "rest32nd", scalar: 0xE4E8)
        case .sixtyFourth: return SMuFLGlyph(name: "rest64th", scalar: 0xE4E9)
        }
    }

    static func flag(duration: NotationFlagDuration, direction: NotationStemDirection) -> SMuFLGlyph {
        switch (duration, direction) {
        case (.eighth, .up): return SMuFLGlyph(name: "flag8thUp", scalar: 0xE240)
        case (.eighth, .down): return SMuFLGlyph(name: "flag8thDown", scalar: 0xE241)
        case (.sixteenth, .up): return SMuFLGlyph(name: "flag16thUp", scalar: 0xE242)
        case (.sixteenth, .down): return SMuFLGlyph(name: "flag16thDown", scalar: 0xE243)
        case (.thirtySecond, .up): return SMuFLGlyph(name: "flag32ndUp", scalar: 0xE244)
        case (.thirtySecond, .down): return SMuFLGlyph(name: "flag32ndDown", scalar: 0xE245)
        case (.sixtyFourth, .up): return SMuFLGlyph(name: "flag64thUp", scalar: 0xE246)
        case (.sixtyFourth, .down): return SMuFLGlyph(name: "flag64thDown", scalar: 0xE247)
        }
    }

    static func articulation(_ articulation: PercussionArticulation) -> SMuFLGlyph {
        switch articulation {
        case .open: return SMuFLGlyph(name: "pictOpen", scalar: 0xE7F8)
        }
    }
}

/// A raw SMuFL glyph identity. Internal: callers never read arbitrary SMuFL names.
struct SMuFLGlyph: Equatable, Sendable {
    let name: String
    let scalar: UInt32
}
