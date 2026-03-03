import Testing
import SwiftUI
@testable import Virgo

@Suite("DrumType Extensions and Drum Constants Tests")
@MainActor
struct DrumTypeExtensionsAndConstantsTests {
    private struct DrumTypeTestData {
        let type: DrumType
        let displayName: String
        let sortOrder: Int
    }

    @Test("DrumType display names and sort order cover all cases")
    func testDrumTypeDisplayNameAndSortOrder() {
        let expected: [DrumTypeTestData] = [
            DrumTypeTestData(type: .kick, displayName: "Kick Drum", sortOrder: 0),
            DrumTypeTestData(type: .snare, displayName: "Snare", sortOrder: 1),
            DrumTypeTestData(type: .hiHat, displayName: "Hi-Hat", sortOrder: 2),
            DrumTypeTestData(type: .hiHatPedal, displayName: "Hi-Hat Pedal", sortOrder: 3),
            DrumTypeTestData(type: .tom1, displayName: "High Tom", sortOrder: 4),
            DrumTypeTestData(type: .tom2, displayName: "Mid Tom", sortOrder: 5),
            DrumTypeTestData(type: .tom3, displayName: "Low Tom", sortOrder: 6),
            DrumTypeTestData(type: .crash, displayName: "Crash", sortOrder: 7),
            DrumTypeTestData(type: .ride, displayName: "Ride", sortOrder: 8),
            DrumTypeTestData(type: .cowbell, displayName: "Cowbell", sortOrder: 9)
        ]

        #expect(DrumType.allCases.count == expected.count)

        for data in expected {
            #expect(data.type.displayName == data.displayName)
            #expect(data.type.sortOrder == data.sortOrder)
        }
    }

    @Test("DrumType storageKey round-trips for all drum types")
    func testDrumTypeStorageKeyRoundTrip() {
        for drumType in DrumType.allCases {
            let key = drumType.storageKey
            #expect(DrumType(storageKey: key) == drumType)
        }

        #expect(DrumType(storageKey: "invalid_key") == nil)
    }

    @Test("DrumType.from(noteType:) maps all supported note types")
    func testDrumTypeFromNoteTypeMappings() {
        let expectedMappings: [(NoteType, DrumType?)] = [
            (.bass, .kick),
            (.snare, .snare),
            (.hiHat, .hiHat),
            (.openHiHat, .hiHat),
            (.hiHatPedal, .hiHatPedal),
            (.crash, .crash),
            (.china, .crash),
            (.splash, .crash),
            (.ride, .ride),
            (.highTom, .tom1),
            (.midTom, .tom2),
            (.lowTom, .tom3),
            (.cowbell, .cowbell)
        ]

        for (noteType, expectedDrumType) in expectedMappings {
            #expect(DrumType.from(noteType: noteType) == expectedDrumType)
        }
    }

    @Test("NoteInterval stem, flag, and flag count logic is consistent")
    func testNoteIntervalProperties() {
        let noStemIntervals: [NoteInterval] = [.full, .half]
        let stemIntervals: [NoteInterval] = [.quarter, .eighth, .sixteenth, .thirtysecond, .sixtyfourth]

        for interval in noStemIntervals {
            #expect(interval.needsStem == false)
        }
        for interval in stemIntervals {
            #expect(interval.needsStem == true)
        }

        #expect(NoteInterval.full.needsFlag == false)
        #expect(NoteInterval.half.needsFlag == false)
        #expect(NoteInterval.quarter.needsFlag == false)

        #expect(NoteInterval.eighth.needsFlag == true)
        #expect(NoteInterval.sixteenth.needsFlag == true)
        #expect(NoteInterval.thirtysecond.needsFlag == true)
        #expect(NoteInterval.sixtyfourth.needsFlag == true)

        #expect(NoteInterval.full.flagCount == 0)
        #expect(NoteInterval.half.flagCount == 0)
        #expect(NoteInterval.quarter.flagCount == 0)
        #expect(NoteInterval.eighth.flagCount == 1)
        #expect(NoteInterval.sixteenth.flagCount == 2)
        #expect(NoteInterval.thirtysecond.flagCount == 3)
        #expect(NoteInterval.sixtyfourth.flagCount == 4)
    }

    private struct TimeSignatureTestData {
        let signature: TimeSignature
        let beatsPerMeasure: Int
        let noteValue: Int
        let displayName: String
    }

    private struct DifficultyTestData {
        let difficulty: Difficulty
        let defaultLevel: Int
        let sortOrder: Int
        let color: Color
    }

    @Test("TimeSignature and Difficulty metadata covers all enum cases")
    func testTimeSignatureAndDifficultyMetadata() {
        let signatureExpectations: [TimeSignatureTestData] = [
            TimeSignatureTestData(signature: .twoFour, beatsPerMeasure: 2, noteValue: 4, displayName: "2/4"),
            TimeSignatureTestData(signature: .threeFour, beatsPerMeasure: 3, noteValue: 4, displayName: "3/4"),
            TimeSignatureTestData(signature: .fourFour, beatsPerMeasure: 4, noteValue: 4, displayName: "4/4"),
            TimeSignatureTestData(signature: .fiveFour, beatsPerMeasure: 5, noteValue: 4, displayName: "5/4"),
            TimeSignatureTestData(signature: .sixEight, beatsPerMeasure: 6, noteValue: 8, displayName: "6/8"),
            TimeSignatureTestData(signature: .sevenEight, beatsPerMeasure: 7, noteValue: 8, displayName: "7/8"),
            TimeSignatureTestData(signature: .nineEight, beatsPerMeasure: 9, noteValue: 8, displayName: "9/8"),
            TimeSignatureTestData(signature: .twelveEight, beatsPerMeasure: 12, noteValue: 8, displayName: "12/8")
        ]

        #expect(TimeSignature.allCases.count == signatureExpectations.count)

        for data in signatureExpectations {
            #expect(data.signature.beatsPerMeasure == data.beatsPerMeasure)
            #expect(data.signature.noteValue == data.noteValue)
            #expect(data.signature.displayName == data.displayName)
        }

        let difficultyExpectations: [DifficultyTestData] = [
            DifficultyTestData(difficulty: .easy, defaultLevel: 30, sortOrder: 0, color: .green),
            DifficultyTestData(difficulty: .medium, defaultLevel: 50, sortOrder: 1, color: .orange),
            DifficultyTestData(difficulty: .hard, defaultLevel: 70, sortOrder: 2, color: .red),
            DifficultyTestData(difficulty: .expert, defaultLevel: 90, sortOrder: 3, color: .purple)
        ]

        #expect(Difficulty.allCases.count == difficultyExpectations.count)

        for data in difficultyExpectations {
            #expect(data.difficulty.defaultLevel == data.defaultLevel)
            #expect(data.difficulty.sortOrder == data.sortOrder)
            #expect(data.difficulty.color == data.color)
        }
    }

    @Test("BeamGroupingConstants expose expected threshold")
    func testBeamGroupingConstant() {
        #expect(BeamGroupingConstants.maxConsecutiveInterval == 0.3)
    }
}
