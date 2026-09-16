import Testing
import CoreGraphics
import DrumNotation
@testable import Virgo

/// The surviving `VirgoNotationAdapter` surface after HPA-166 Task 7: the
/// four vocabulary mappers `VirgoNotationProjection` uses. Flag-paint
/// commands and stem-footprint policy moved wholesale into the package
/// engraver, so their tests were deleted with the legacy renderer.
@Suite("Virgo Notation Adapter Tests")
struct VirgoNotationAdapterTests {
    // MARK: - Exhaustive semantic mappings

    @Test("Every NoteType maps to the required package notehead style")
    func noteheadStyleMappingIsExhaustive() {
        let expected: [NoteType: PercussionNoteheadStyle] = [
            .bass: .normal,
            .snare: .normal,
            .highTom: .normal,
            .midTom: .normal,
            .lowTom: .normal,
            .hiHat: .x,
            .hiHatPedal: .x,
            .openHiHat: .x,
            .crash: .x,
            .ride: .x,
            .china: .x,
            .splash: .x,
            .cowbell: .diamond
        ]

        #expect(expected.count == NoteType.allCases.count)
        for noteType in NoteType.allCases {
            #expect(VirgoNotationAdapter.noteheadStyle(for: noteType) == expected[noteType])
        }
    }

    @Test("All seven NoteIntervals map to package durations")
    func intervalDurationMappingIsExhaustive() {
        let expected: [NoteInterval: NotationDuration] = [
            .full: .whole,
            .half: .half,
            .quarter: .quarter,
            .eighth: .eighth,
            .sixteenth: .sixteenth,
            .thirtysecond: .thirtySecond,
            .sixtyfourth: .sixtyFourth
        ]

        #expect(expected.count == NoteInterval.allCases.count)
        for interval in NoteInterval.allCases {
            #expect(VirgoNotationAdapter.duration(for: interval) == expected[interval])
        }
    }

    @Test("Both StemDirections map to package stem directions")
    func stemDirectionMappingIsExhaustive() {
        let expected: [StemDirection: NotationStemDirection] = [
            .up: .up,
            .down: .down
        ]

        for direction in [StemDirection.up, .down] {
            #expect(VirgoNotationAdapter.stemDirection(direction) == expected[direction])
        }
    }

    @Test("Every NotationRestDuration maps to a package duration; indeterminate maps to nil")
    func restDurationMappingIsExhaustive() {
        let expected: [NotationRestDuration: NotationDuration] = [
            .fullMeasure: .whole,
            .half: .half,
            .quarter: .quarter,
            .eighth: .eighth,
            .sixteenth: .sixteenth,
            .thirtySecond: .thirtySecond,
            .sixtyFourth: .sixtyFourth
        ]

        for duration in NotationRestDuration.allCases {
            #expect(VirgoNotationAdapter.restDuration(duration) == expected[duration])
        }
        #expect(VirgoNotationAdapter.restDuration(.indeterminate) == nil)
    }
}
