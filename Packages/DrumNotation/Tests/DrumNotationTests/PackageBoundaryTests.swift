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

@Test("resolved input engraves and feeds the package view through ordinary import")
func engraverFeedsView() throws {
    let input = try ResolvedNotationInput(
        ticksPerWholeNote: 1920,
        measures: [
            ResolvedMeasure(
                index: 0,
                startTick: 0,
                durationTicks: 1920,
                meter: NotationMeter(beats: 4, noteValue: 4),
                beatGroups: [ResolvedBeatGroup(startTick: 0, durationTicks: 1920)]
            )
        ],
        notes: [
            ResolvedNote(
                id: 1,
                position: NotationTickPosition(measureIndex: 0, localTick: 0),
                stemDirection: .up,
                staffStep: 3,
                stemMember: true,
                noteheadStyle: .x,
                duration: .quarter,
                dotCount: 0,
                visibleFlagDuration: nil,
                voice: .upper,
                durationTicks: 480,
                tiebreakOrder: 0,
                isRhythmEngravable: true
            )
        ]
    )
    let layout = try NotationEngraver.engrave(
        input,
        style: NotationEngravingStyle()
    )
    #expect(layout.position(measureIndex: 0, localTick: 0)?.rowIndex == 0)
    _ = DrumNotationView(layout: layout, accessibilityLabels: [:])
}
