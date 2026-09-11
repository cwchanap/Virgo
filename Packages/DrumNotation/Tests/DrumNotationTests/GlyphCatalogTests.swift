import Testing
@testable import DrumNotation

private let blackDurations: [NotationDuration] = [
    .quarter, .eighth, .sixteenth, .thirtySecond, .sixtyFourth
]

@Test("normal notehead: whole E0A2, half E0A3, quarter..64th E0A4")
func normalNoteheads() {
    #expect(SMuFLGlyphCatalog.notehead(style: .normal, duration: .whole)
        == SMuFLGlyph(name: "noteheadWhole", scalar: 0xE0A2))
    #expect(SMuFLGlyphCatalog.notehead(style: .normal, duration: .half)
        == SMuFLGlyph(name: "noteheadHalf", scalar: 0xE0A3))
    for duration in blackDurations {
        #expect(SMuFLGlyphCatalog.notehead(style: .normal, duration: duration)
            == SMuFLGlyph(name: "noteheadBlack", scalar: 0xE0A4))
    }
}

@Test("x notehead: whole E0A7, half E0A8, quarter..64th E0A9")
func xNoteheads() {
    #expect(SMuFLGlyphCatalog.notehead(style: .x, duration: .whole)
        == SMuFLGlyph(name: "noteheadXWhole", scalar: 0xE0A7))
    #expect(SMuFLGlyphCatalog.notehead(style: .x, duration: .half)
        == SMuFLGlyph(name: "noteheadXHalf", scalar: 0xE0A8))
    for duration in blackDurations {
        #expect(SMuFLGlyphCatalog.notehead(style: .x, duration: duration)
            == SMuFLGlyph(name: "noteheadXBlack", scalar: 0xE0A9))
    }
}

@Test("diamond notehead: whole E0D8, half E0D9, quarter..64th E0DB")
func diamondNoteheads() {
    #expect(SMuFLGlyphCatalog.notehead(style: .diamond, duration: .whole)
        == SMuFLGlyph(name: "noteheadDiamondWhole", scalar: 0xE0D8))
    #expect(SMuFLGlyphCatalog.notehead(style: .diamond, duration: .half)
        == SMuFLGlyph(name: "noteheadDiamondHalf", scalar: 0xE0D9))
    for duration in blackDurations {
        #expect(SMuFLGlyphCatalog.notehead(style: .diamond, duration: duration)
            == SMuFLGlyph(name: "noteheadDiamondBlack", scalar: 0xE0DB))
    }
}

@Test("rests: whole..64th E4E3..E4E9")
func rests() {
    let expected: [NotationDuration: UInt32] = [
        .whole: 0xE4E3, .half: 0xE4E4, .quarter: 0xE4E5, .eighth: 0xE4E6,
        .sixteenth: 0xE4E7, .thirtySecond: 0xE4E8, .sixtyFourth: 0xE4E9
    ]
    for (duration, scalar) in expected {
        #expect(SMuFLGlyphCatalog.rest(for: duration).scalar == scalar)
    }
}

@Test("flags: 8th..64th up E240/E242/E244/E246, down E241/E243/E245/E247")
func flags() {
    let expectedUp: [NotationDuration: UInt32] = [
        .eighth: 0xE240, .sixteenth: 0xE242, .thirtySecond: 0xE244, .sixtyFourth: 0xE246
    ]
    let expectedDown: [NotationDuration: UInt32] = [
        .eighth: 0xE241, .sixteenth: 0xE243, .thirtySecond: 0xE245, .sixtyFourth: 0xE247
    ]
    for (duration, scalar) in expectedUp {
        #expect(SMuFLGlyphCatalog.flag(duration: duration, direction: .up).scalar == scalar)
    }
    for (duration, scalar) in expectedDown {
        #expect(SMuFLGlyphCatalog.flag(duration: duration, direction: .down).scalar == scalar)
    }
}

@Test("open articulation -> pictOpen E7F8")
func openArticulation() {
    #expect(SMuFLGlyphCatalog.articulation(.open)
        == SMuFLGlyph(name: "pictOpen", scalar: 0xE7F8))
}
