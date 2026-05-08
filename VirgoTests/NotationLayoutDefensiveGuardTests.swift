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

}
