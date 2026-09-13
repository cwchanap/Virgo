import CoreGraphics
import Testing
import DrumNotation

/// Compile-time Sendable proof: the call only compiles when `T` is `Sendable`.
private func requireSendable<T: Sendable>(_ value: T) -> T { value }

/// Shared package-only fixture for the formatter input/output model boundary.
private enum Fixtures {
    static let ticksPerWholeNote = 1920

    static func measure(
        index: Int = 0,
        startTick: Int = 0,
        durationTicks: Int = ticksPerWholeNote
    ) -> ResolvedMeasure {
        ResolvedMeasure(index: index, startTick: startTick, durationTicks: durationTicks)
    }

    static func note(
        id: Int = 42,
        measureIndex: Int = 0,
        localTick: Int = 0
    ) -> ResolvedNote {
        ResolvedNote(
            id: id,
            position: NotationTickPosition(measureIndex: measureIndex, localTick: localTick),
            stemDirection: .up,
            staffStep: 3,
            noteheadStyle: .x,
            duration: .sixteenth,
            dotCount: 0,
            visibleFlagDuration: .sixteenth
        )
    }

    static func rest(
        id: Int = 7,
        measureIndex: Int = 0,
        localTick: Int = 1440
    ) -> ResolvedRest {
        ResolvedRest(
            id: id,
            position: NotationTickPosition(measureIndex: measureIndex, localTick: localTick),
            duration: .quarter,
            dotCount: 1,
            isFullMeasure: false
        )
    }

    static func control(
        id: Int = 9,
        measureIndex: Int = 0,
        localTick: Int = 480
    ) -> ResolvedControl {
        ResolvedControl(id: id, position: NotationTickPosition(measureIndex: measureIndex, localTick: localTick))
    }

    static func document(
        ticksPerWholeNote: Int = Fixtures.ticksPerWholeNote,
        measures: [ResolvedMeasure] = [Fixtures.measure()],
        notes: [ResolvedNote] = [Fixtures.note()],
        rests: [ResolvedRest] = [Fixtures.rest()],
        controls: [ResolvedControl] = [Fixtures.control()]
    ) throws -> ResolvedNotationInput {
        try ResolvedNotationInput(
            ticksPerWholeNote: ticksPerWholeNote,
            measures: measures,
            notes: notes,
            rests: rests,
            controls: controls
        )
    }
}

@Suite("Notation formatter model")
struct NotationFormatterTests {
    // MARK: Input document boundary

    @Test("resolved document round-trips measure, note, rest and control values")
    func documentRoundTrips() throws {
        let document = try Fixtures.document()

        #expect(document.ticksPerWholeNote == 1920)
        #expect(document.measures == [ResolvedMeasure(index: 0, startTick: 0, durationTicks: 1920)])

        let note = document.notes.first
        #expect(note?.id == 42)
        #expect(note?.position == NotationTickPosition(measureIndex: 0, localTick: 0))
        #expect(note?.stemDirection == .up)
        #expect(note?.staffStep == 3)
        #expect(note?.noteheadStyle == .x)
        #expect(note?.duration == .sixteenth)
        #expect(note?.dotCount == 0)
        #expect(note?.visibleFlagDuration == .sixteenth)

        let rest = document.rests.first
        #expect(rest?.id == 7)
        #expect(rest?.position == NotationTickPosition(measureIndex: 0, localTick: 1440))
        #expect(rest?.duration == .quarter)
        #expect(rest?.dotCount == 1)
        #expect(rest?.isFullMeasure == false)

        #expect(
            document.controls.first == ResolvedControl(
                id: 9,
                position: NotationTickPosition(measureIndex: 0, localTick: 480)
            )
        )
        let again = try Fixtures.document()
        #expect(document == again)
    }

    @Test("formatter model types are Sendable")
    func formatterModelTypesAreSendable() throws {
        _ = requireSendable(try Fixtures.document())
        _ = requireSendable(Fixtures.measure())
        _ = requireSendable(Fixtures.note())
        _ = requireSendable(Fixtures.rest())
        _ = requireSendable(Fixtures.control())
        _ = requireSendable(NotationTickPosition(measureIndex: 0, localTick: 0))
        _ = requireSendable(NotationFormattingStyle.virgoDefault)
        _ = requireSendable(Fixtures.formattedNotation())
        _ = requireSendable(FormattedMeasure(index: 0, rowIndex: 0, xOffset: 100, width: 490, columns: []))
        _ = requireSendable(FormattedColumn(localTick: 0, onsetX: 100, noteHeads: [], rest: nil))
        _ = requireSendable(FormattedNoteHead(noteID: 42, headCenterX: 110))
        _ = requireSendable(FormattedRest(restID: 7, visualX: 155))
        _ = requireSendable(FormattedNotation.Position(rowIndex: 0, x: 150))
    }

    @Test("default style pins the Virgo mapping")
    func defaultStylePinsVirgoMapping() {
        let style = NotationFormattingStyle.virgoDefault

        #expect(style.availableRowWidth == 900)
        #expect(style.rowLeadingInset == 100)
        #expect(style.staffSpace == 20)
        #expect(style.stemWidth == 2)
        #expect(style.minimumInterColumnClearance == 8)
        #expect(style.minimumQuarterNoteSpacing == 50)
        #expect(style.measureSpacing == 12)
        #expect(style.leadingMeasureInset == 52)
        #expect(style.trailingMeasureInset == 0)
        #expect(style.rhythmDotRadius == 2.5)
        #expect(style.rhythmDotSpacing == 4)
    }

    // MARK: Validation

    @Test("validation rejects non-positive ticksPerWholeNote")
    func validationRejectsNonPositiveTicksPerWholeNote() {
        #expect(throws: ResolvedNotationInput.ValidationError.self) {
            try Fixtures.document(ticksPerWholeNote: 0)
        }
        #expect {
            try Fixtures.document(ticksPerWholeNote: -1)
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError == .invalidTicksPerWholeNote(-1)
        }
    }

    @Test("validation rejects duplicate measure index")
    func validationRejectsDuplicateMeasureIndex() {
        let measures = [
            Fixtures.measure(),
            Fixtures.measure(index: 0, startTick: 1920)
        ]
        #expect {
            try Fixtures.document(measures: measures)
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError == .duplicateMeasureIndex(0)
        }
    }

    @Test("validation rejects overlapping measures")
    func validationRejectsOverlappingMeasures() {
        let measures = [
            Fixtures.measure(),
            Fixtures.measure(index: 1, startTick: 960)
        ]
        #expect {
            try Fixtures.document(measures: measures)
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .overlappingMeasures(first: Fixtures.measure(), second: Fixtures.measure(index: 1, startTick: 960))
        }
    }

    @Test("validation rejects measures with invalid bounds")
    func validationRejectsInvalidMeasureBounds() {
        #expect {
            try Fixtures.document(measures: [Fixtures.measure(durationTicks: 0)])
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .invalidMeasure(index: 0, startTick: 0, durationTicks: 0)
        }
        #expect {
            try Fixtures.document(measures: [Fixtures.measure(startTick: -1)])
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .invalidMeasure(index: 0, startTick: -1, durationTicks: 1920)
        }
    }

    @Test("validation rejects event localTick outside its owning measure")
    func validationRejectsEventOutsideItsMeasure() {
        #expect {
            try Fixtures.document(notes: [Fixtures.note(localTick: 1920)])
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .eventOutsideMeasure(eventID: 42, measureIndex: 0, localTick: 1920)
        }
        #expect {
            try Fixtures.document(rests: [Fixtures.rest(localTick: -1)])
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .eventOutsideMeasure(eventID: 7, measureIndex: 0, localTick: -1)
        }
        #expect {
            try Fixtures.document(controls: [Fixtures.control(measureIndex: 5)])
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .eventOutsideMeasure(eventID: 9, measureIndex: 5, localTick: 480)
        }
    }

    @Test("validation accepts boundary local ticks")
    func validationAcceptsBoundaryLocalTicks() throws {
        _ = try Fixtures.document(notes: [Fixtures.note(localTick: 1919)])
        _ = try Fixtures.document(controls: [Fixtures.control(localTick: 0)])
    }

    // MARK: Output surface

    @Test("position resolves exact anchors to row and X")
    func positionResolvesExactAnchors() {
        let notation = Fixtures.formattedNotation()

        #expect(notation.position(measureIndex: 0, localTick: 480) == FormattedNotation.Position(rowIndex: 0, x: 150))
        #expect(notation.position(measureIndex: 1, localTick: 0) == FormattedNotation.Position(rowIndex: 1, x: 100))
        #expect(notation.position(measureIndex: 0, localTick: 481) == nil)
        #expect(notation.position(measureIndex: 5, localTick: 0) == nil)
    }

    @Test("formatted output round-trips measures, columns, heads and rests")
    func formattedOutputRoundTrips() {
        let notation = Fixtures.formattedNotation()

        let measure = notation.measures.first
        #expect(measure?.index == 0)
        #expect(measure?.rowIndex == 0)
        #expect(measure?.xOffset == 100)
        #expect(measure?.width == 490)
        #expect(measure?.columns.count == 2)

        let column = measure?.columns.last
        #expect(column?.localTick == 480)
        #expect(column?.onsetX == 150)
        #expect(column?.noteHeads == [FormattedNoteHead(noteID: 42, headCenterX: 114)])
        #expect(column?.rest == FormattedRest(restID: 7, visualX: 155))
    }
}

extension Fixtures {
    /// Hand-built output exercising the declared `FormattedNotation` surface;
    /// the real formatter populates it in later tasks.
    static func formattedNotation() -> FormattedNotation {
        let tick0 = FormattedColumn(
            localTick: 0,
            onsetX: 100,
            noteHeads: [FormattedNoteHead(noteID: 42, headCenterX: 100)],
            rest: nil
        )
        let tick480 = FormattedColumn(
            localTick: 480,
            onsetX: 150,
            noteHeads: [FormattedNoteHead(noteID: 42, headCenterX: 114)],
            rest: FormattedRest(restID: 7, visualX: 155)
        )
        return FormattedNotation(
            measures: [
                FormattedMeasure(
                    index: 0,
                    rowIndex: 0,
                    xOffset: 100,
                    width: 490,
                    columns: [tick0, tick480]
                ),
                FormattedMeasure(
                    index: 1,
                    rowIndex: 1,
                    xOffset: 602,
                    width: 490,
                    columns: [
                        FormattedColumn(localTick: 0, onsetX: 100, noteHeads: [], rest: nil)
                    ]
                )
            ]
        )
    }
}
