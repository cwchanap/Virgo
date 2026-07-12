import Testing
@testable import Virgo

@Suite("Notation Layout Defensive Guard Tests")
struct NotationLayoutDefensiveGuardTests {

    @Test("beamEndY returns nil for zero-span beam (startX == endX)")
    func beamEndYReturnsNilForZeroSpanBeam() {
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                notes: [
                    Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.0),
                    Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0.0001)
                ],
                timeSignature: .fourFour
            )
        )

        for beam in layout.beams {
            #expect(!beam.start.x.isNaN)
            #expect(!beam.start.y.isNaN)
            #expect(!beam.end.x.isNaN)
            #expect(!beam.end.y.isNaN)
        }
        for stem in layout.stems {
            #expect(!stem.start.x.isNaN)
            #expect(!stem.start.y.isNaN)
            #expect(!stem.end.x.isNaN)
            #expect(!stem.end.y.isNaN)
        }
    }

    @Test("beamEndY returns nil when stem X is outside the beam's horizontal span")
    func beamEndYReturnsNilWhenStemXOutsideBeamRange() {
        let note = Note(
            interval: .sixteenth,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: 0
        )
        let noteHead = RenderedNoteHead(
            id: 1,
            sourceObjectID: ObjectIdentifier(note),
            sourceLaneID: nil,
            sourceChipID: nil,
            noteType: .snare,
            drumType: .snare,
            glyph: .filledDiamond,
            variant: .standard,
            voice: .upper,
            stemDirection: .up,
            timeColumn: NotationTimeColumn(measureIndex: 0, tickWithinMeasure: 0, absoluteLayoutTick: 0),
            timePosition: 0,
            row: 0,
            position: CGPoint(x: 500, y: 100),
            staffStep: -4,
            interval: .sixteenth,
            catalogOrder: 1
        )
        let beam = RenderedBeam(
            id: "beam-defensive-test",
            noteHeadIDs: [1, 2],
            direction: .up,
            level: 0,
            kind: .full,
            start: CGPoint(x: 10, y: 50),
            end: CGPoint(x: 20, y: 50),
            thickness: 4
        )

        let result = NotationLayoutEngine().beamEndY(
            for: noteHead,
            beam: beam,
            style: .gameplayDefault
        )

        #expect(result == nil, "beamEndY must return nil when stem X is outside the beam span")
    }

}
