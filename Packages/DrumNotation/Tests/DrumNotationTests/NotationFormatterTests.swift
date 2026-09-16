import CoreGraphics
import Testing
import DrumNotation

/// Compile-time Sendable proof: the call only compiles when `T` is `Sendable`.
private func requireSendable<T: Sendable>(_ value: T) -> T { value }

@Suite("Notation formatter model")
struct NotationFormatterTests {
    // MARK: Input document boundary

    @Test("resolved document round-trips measure, note, rest and control values")
    func documentRoundTrips() throws {
        let document = try Fixtures.document()

        #expect(document.ticksPerWholeNote == 1920)
        #expect(document.measures == [Fixtures.measure()])

        let note = document.notes.first
        #expect(note?.id == 42)
        #expect(note?.position == NotationTickPosition(measureIndex: 0, localTick: 0))
        #expect(note?.stemDirection == .up)
        #expect(note?.staffStep == 3)
        #expect(note?.noteheadStyle == .x)
        #expect(note?.duration == .sixteenth)
        #expect(note?.dotCount == 0)
        #expect(note?.visibleFlagDuration == .sixteenth)
        #expect(note?.voice == .upper)
        #expect(note?.durationTicks == 120)
        #expect(note?.tiebreakOrder == 0)
        #expect(note?.isRhythmEngravable == true)
        #expect(note?.articulation == nil)

        let rest = document.rests.first
        #expect(rest?.id == 7)
        #expect(rest?.position == NotationTickPosition(measureIndex: 0, localTick: 1440))
        #expect(rest?.duration == .quarter)
        #expect(rest?.dotCount == 1)
        #expect(rest?.isFullMeasure == false)
        #expect(rest?.voice == .upper)
        #expect(rest?.durationTicks == 480)

        #expect(document.controls.first == Fixtures.control())
        #expect(document.tuplets.isEmpty)
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
        _ = requireSendable(NotationVoiceRole.upper)
        _ = requireSendable(NotationMeter(beats: 4, noteValue: 4))
        _ = requireSendable(ResolvedBeatGroup(startTick: 0, durationTicks: 480))
        _ = requireSendable(NotationControlKind.stop)
        _ = requireSendable(ResolvedTupletRatio(actual: 3, normal: 2))
        _ = requireSendable(ResolvedTupletGroup(
            id: 0,
            measureIndex: 0,
            voice: .upper,
            ratio: ResolvedTupletRatio(actual: 3, normal: 2),
            memberNoteIDs: [],
            memberRestIDs: []
        ))
        _ = requireSendable(NotationTickPosition(measureIndex: 0, localTick: 0))
        _ = requireSendable(NotationFormattingStyle.virgoDefault)
        _ = requireSendable(Fixtures.formattedNotation())
        _ = requireSendable(FormattedMeasure(index: 0, rowIndex: 0, xOffset: 100, width: 490, columns: []))
        _ = requireSendable(FormattedColumn(localTick: 0, logicalColumnX: 100, noteHeads: [], rests: []))
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

    @Test("overlapping-measure payload order breaks startTick ties by index")
    func overlappingMeasurePayloadOrderBreaksStartTickTiesByIndex() {
        // Input order intentionally puts the higher index first: the payload
        // must still report the lower index as `first` (defined order, not
        // sort stability).
        let measures = [
            Fixtures.measure(index: 5, startTick: 0),
            Fixtures.measure(index: 2, startTick: 0)
        ]
        #expect {
            try Fixtures.document(measures: measures)
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .overlappingMeasures(
                    first: Fixtures.measure(index: 2, startTick: 0),
                    second: Fixtures.measure(index: 5, startTick: 0)
                )
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

    @Test("validation rejects a measure whose end tick overflows Int")
    func validationRejectsOverflowingMeasureEnd() {
        // startTick + durationTicks overflows; validation must reject, not trap.
        #expect {
            try Fixtures.document(measures: [
                Fixtures.measure(),
                Fixtures.measure(index: 1, startTick: Int.max - 10, durationTicks: 100)
            ])
        } throws: { error in
            error as? ResolvedNotationInput.ValidationError
                == .invalidMeasure(index: 1, startTick: Int.max - 10, durationTicks: 100)
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
        // The last valid onset carries a one-tick span ending exactly on the
        // measure end — onset and span both stay inside the measure.
        _ = try Fixtures.document(notes: [Fixtures.note(localTick: 1919, durationTicks: 1)])
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
        #expect(column?.logicalColumnX == 150)
        #expect(column?.noteHeads == [FormattedNoteHead(noteID: 42, headCenterX: 114)])
        #expect(column?.rests == [FormattedRest(restID: 7, visualX: 155)])
    }
}

@Suite("Notation formatter columns")
struct NotationFormatterColumnTests {
    @Test("same-tick kick/snare/hi-hat share one logical column")
    func sameTickEventsShareOneLogicalColumn() throws {
        let notes = [
            Fixtures.makeNote(id: 1, localTick: 480, staffStep: -2, headStyle: .normal),
            Fixtures.makeNote(id: 2, localTick: 480, staffStep: 3),
            Fixtures.makeNote(id: 3, localTick: 480, staffStep: 8)
        ]
        let notation = try Fixtures.format(try Fixtures.document(notes: notes, rests: [], controls: []))

        let measure = try #require(notation.measures.first)
        #expect(measure.columns.map(\.localTick) == [0, 480, 1920])
        let column = try Fixtures.column(notation, localTick: 480)
        #expect(column.noteHeads.map(\.noteID) == [1, 2, 3])
        #expect(column.noteHeads.allSatisfy { $0.headCenterX == column.logicalColumnX })
    }

    @Test("mixed stem directions at one tick stay on one column with no voice offset")
    func mixedStemDirectionsGetNoVoiceOffset() throws {
        let notes = [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, stem: .up),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 10, stem: .down)
        ]
        let notation = try Fixtures.format(try Fixtures.document(notes: notes, rests: [], controls: []))
        let column = try Fixtures.column(notation, localTick: 0)
        #expect(column.noteHeads.count == 2)
        #expect(column.noteHeads.allSatisfy { $0.headCenterX == column.logicalColumnX })
    }

    @Test("integer IDs and ticks survive formatting; one column per tick in tick order")
    func idsAndTicksSurviveFormatting() throws {
        let notes = [
            Fixtures.makeNote(id: 9, localTick: 960, staffStep: 3),
            Fixtures.makeNote(id: 5, localTick: 0, staffStep: -2, headStyle: .normal)
        ]
        let notation = try Fixtures.format(try Fixtures.document(
            notes: notes,
            rests: [Fixtures.rest(localTick: 1440)],
            controls: [Fixtures.control(localTick: 480)]
        ))

        let measure = try #require(notation.measures.first)
        #expect(measure.columns.map(\.localTick) == [0, 480, 960, 1440, 1920])
        #expect(try Fixtures.column(notation, localTick: 0).noteHeads.map(\.noteID) == [5])
        #expect(try Fixtures.column(notation, localTick: 960).noteHeads.map(\.noteID) == [9])
        #expect(try Fixtures.column(notation, localTick: 1440).rests.map(\.restID) == [7])
        // Sheet-local: row 0 origin 100 + leading inset 52 + rhythmic gap 50.
        #expect(notation.position(measureIndex: 0, localTick: 480) == FormattedNotation.Position(rowIndex: 0, x: 202))
    }

    @Test("input order does not affect output")
    func inputOrderDoesNotAffectOutput() throws {
        let notes = [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 4),
            Fixtures.makeNote(id: 3, localTick: 960, staffStep: -2, stem: .down)
        ]
        let rests = [Fixtures.rest(id: 7, localTick: 480), Fixtures.rest(id: 8, localTick: 960)]
        let controls = [Fixtures.control(id: 11, localTick: 240)]
        let measures = [Fixtures.measure(), Fixtures.measure(index: 1, startTick: 1920)]

        let forward = try ResolvedNotationInput(
            ticksPerWholeNote: 1920, measures: measures, notes: notes, rests: rests, controls: controls
        )
        let backward = try ResolvedNotationInput(
            ticksPerWholeNote: 1920,
            measures: measures.reversed(),
            notes: notes.reversed(),
            rests: rests.reversed(),
            controls: controls.reversed()
        )
        let forwardOutput = try Fixtures.format(forward)
        let backwardOutput = try Fixtures.format(backward)
        #expect(forwardOutput == backwardOutput)
    }

    @Test("empty measures get explicit start and end anchor columns")
    func emptyMeasureGetsStartAndEndAnchors() throws {
        let notation = try Fixtures.format(try Fixtures.document(
            measures: [Fixtures.measure(), Fixtures.measure(index: 1, startTick: 1920)],
            notes: [Fixtures.makeNote(id: 1, localTick: 480, staffStep: 3)],
            rests: [],
            controls: []
        ))
        let empty = try #require(notation.measures.first { $0.index == 1 })
        #expect(empty.columns.map(\.localTick) == [0, 1920])
        #expect(empty.columns.allSatisfy {
            $0.noteHeads.isEmpty && $0.rests.isEmpty && $0.leftExtent == 0 && $0.rightExtent == 0
        })
    }
}

@Suite("Notation formatter ink extents")
struct NotationFormatterInkTests {
    private let style = NotationFormattingStyle.virgoDefault

    @Test("visible flags expand the glyph's side; fully beamed notes pay no flag width")
    func flagFootprintFollowsVisibleDuration() throws {
        let flags: [NotationFlagDuration?] = NotationFlagDuration.allCases + [nil]
        for flagDuration in flags {
            for stem in [NotationStemDirection.up, .down] {
                let notes = [Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, stem: stem, flag: flagDuration)]
                let notation = try Fixtures.format(try Fixtures.document(notes: notes, rests: [], controls: []))
                let column = try Fixtures.column(notation, localTick: 0)
                let headReach = Fixtures.headReach(stem: stem)
                guard let flagDuration else {
                    #expect(abs(column.rightExtent - headReach) < 0.001)
                    #expect(abs(column.leftExtent - headReach) < 0.001)
                    continue
                }
                // Bravura attaches every flag at its glyph origin with all ink
                // to the right of that origin (left ink exactly 0 for up and
                // down alike); the formatter anchors that origin where Virgo
                // paints the flag — the stem axis minus half the stem width
                // (the painted stem origin convention). The left side keeps
                // the bare head reach; the right side is the union of head
                // ink and the flag ink.
                #expect(Fixtures.flagLeftInk(duration: flagDuration, stem: stem) == 0)
                // Flag ink starts at its attachment origin (zero left ink),
                // so for down-stems the origin — axis − stemWidth/2 — pokes
                // one stem-half-width left of the head and must be reserved.
                let flagInkMinX = Fixtures.stemAxisX(stem: stem) - style.stemWidth / 2
                let flagInkMaxX = flagInkMinX + Fixtures.flagRightInk(duration: flagDuration, stem: stem)
                #expect(abs(column.leftExtent - max(headReach, -flagInkMinX)) < 0.001)
                #expect(abs(column.rightExtent - max(headReach, flagInkMaxX)) < 0.001)
            }
        }
    }

    @Test("partially uncovered flag reserves one eighth-component footprint")
    func partialFlagReservesEighthFootprint() throws {
        func rightExtent(duration: NotationDuration, flag: NotationFlagDuration?) throws -> CGFloat {
            let notes = [Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, duration: duration, flag: flag)]
            let notation = try Fixtures.format(try Fixtures.document(notes: notes, rests: [], controls: []))
            return try Fixtures.column(notation, localTick: 0).rightExtent
        }

        let partial = try rightExtent(duration: .sixteenth, flag: .eighth)
        let eighthReference = try rightExtent(duration: .eighth, flag: .eighth)
        let fullStack = try rightExtent(duration: .sixteenth, flag: .sixteenth)
        #expect(abs(partial - eighthReference) < 0.001)
        #expect(partial < fullStack)
    }

    @Test("adjacent column reserves clearance beyond the visible flag ink")
    func adjacentColumnClearsFlagInk() throws {
        let notes = [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, flag: .eighth),
            Fixtures.makeNote(id: 2, localTick: 960, staffStep: 3)
        ]
        let notation = try Fixtures.format(try Fixtures.document(notes: notes, rests: [], controls: []))
        let flagged = try Fixtures.column(notation, localTick: 0)
        let next = try Fixtures.column(notation, localTick: 960)

        // Task 3 places the next column at rightExtent + clearance + leftExtent;
        // reserving the full flag ink (measured from the painted stem origin,
        // stem axis − stemWidth/2) in rightExtent is what clears it.
        let flagInk = Fixtures.stemAxisX(stem: .up)
            - style.stemWidth / 2
            + Fixtures.flagRightInk(duration: .eighth, stem: .up)
        #expect(abs(flagged.rightExtent - flagInk) < 0.001)
        #expect(abs(next.leftExtent - Fixtures.headReach()) < 0.001)
    }

    @Test("controls anchor timing with zero collision width")
    func controlsAnchorWithoutCollisionWidth() throws {
        let notation = try Fixtures.format(
            try Fixtures.document(notes: [], rests: [], controls: [Fixtures.control(localTick: 480)])
        )
        let measure = try #require(notation.measures.first)
        #expect(measure.columns.map(\.localTick) == [0, 480, 1920])
        let column = try Fixtures.column(notation, localTick: 480)
        #expect(column.noteHeads.isEmpty && column.rests.isEmpty)
        #expect(column.leftExtent == 0 && column.rightExtent == 0)
        // Sheet-local: row 0 origin 100 + leading inset 52 + rhythmic gap 50.
        #expect(notation.position(measureIndex: 0, localTick: 480) == FormattedNotation.Position(rowIndex: 0, x: 202))
    }

    @Test("rhythm dots extend the ink on the dotted side")
    func dottedNoteExtendsRightExtent() throws {
        let notes = [Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, dotCount: 1)]
        let notation = try Fixtures.format(try Fixtures.document(notes: notes, rests: [], controls: []))
        let column = try Fixtures.column(notation, localTick: 0)
        let headReach = Fixtures.headReach()
        let dotCenter = headReach + style.rhythmDotSpacing + style.rhythmDotRadius
        #expect(abs(column.rightExtent - (dotCenter + style.rhythmDotRadius)) < 0.001)
        #expect(abs(column.leftExtent - headReach) < 0.001)
    }

    @Test("printed rests anchor at the column with glyph extent")
    func printedRestIsAnchoredAndMeasured() throws {
        let notation = try Fixtures.format(try Fixtures.document(
            notes: [],
            rests: [Fixtures.rest(localTick: 480)],
            controls: []
        ))
        let measure = try #require(notation.measures.first)
        #expect(measure.columns.map(\.localTick) == [0, 480, 1920])

        let column = try Fixtures.column(notation, localTick: 480)
        let rest = try #require(column.rests.first)
        #expect(rest.restID == 7)
        #expect(rest.visualX == column.logicalColumnX)
        let bounds = PercussionGlyphMetrics.rest(duration: .quarter, staffSpace: style.staffSpace).paintedBounds
        let dotCenter = bounds.maxX + style.rhythmDotSpacing + style.rhythmDotRadius
        #expect(abs(column.rightExtent - (dotCenter + style.rhythmDotRadius)) < 0.001)
        #expect(abs(column.leftExtent - (-bounds.minX)) < 0.001)
    }
}
