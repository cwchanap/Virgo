import Testing
import DrumNotation

@Test("public DrumNotation module imports without Virgo")
func packageImports() {
    #expect(NotationDuration.quarter.rawValue == "quarter")
}

@Test("public primitive views construct from semantic values")
func primitiveViewsConstruct() {
    _ = PercussionNoteheadView(
        style: .normal,
        duration: .quarter,
        staffSpace: 20
    )
    _ = NotationRestGlyphView(duration: .quarter, staffSpace: 20)
    _ = NotationFlagGlyphView(
        duration: .sixteenth,
        direction: .up,
        staffSpace: 20
    )
    _ = PercussionArticulationView(articulation: .open, staffSpace: 20)
}
