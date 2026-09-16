import CoreGraphics
import Testing
import DrumNotation

/// Compile-time Sendable proof: the call only compiles when `T` is `Sendable`.
private func requireSendable<T: Sendable>(_ value: T) -> T { value }

/// HPA-166 Task 3: the single package engraving style — a fully defaulted
/// initializer pins the Virgo mapping (`GameplayLayout` + the app's layout
/// style), so package-only tests engrave with ordinary construction.
@Suite("Notation engraving style")
struct NotationEngravingStyleTests {
    @Test("zero-argument construction pins the Virgo mapping")
    func zeroArgumentStylePinsVirgoMapping() {
        let style = NotationEngravingStyle()

        #expect(style.formatting == .virgoDefault)
        #expect(style.rowHeight == 280)
        #expect(style.rowVerticalSpacing == 60)
        #expect(style.stemLength == 75)
        #expect(style.minimumStemExtensionPastChord == 10)
        #expect(style.beamThickness == 4)
        #expect(style.beamLevelSpacing == 6)
        #expect(style.beamHookLength == 12)
        #expect(style.flagVerticalSpacing == 8)
        #expect(style.ledgerLineOverhang == 6)
        #expect(style.upperVoiceRestOffset == -20)
        #expect(style.lowerVoiceRestOffset == 20)
        #expect(style.stopMarkSize == 14)
        #expect(style.stopMarkStrokeWidth == 2)
        #expect(style.stopMarkVerticalOffset == 18)
        #expect(style.articulationVerticalOffset == 24)
        #expect(style.tupletLineWidth == 1.5)
        #expect(style.tupletLabelSize == CGSize(width: 14, height: 16))
        #expect(style.tupletVerticalOffset == 10)
        #expect(style.tupletHookLength == 6)
        #expect(style.barLineWidth == 2)
        #expect(style.doubleBarThinWidth == 2)
        #expect(style.doubleBarThickWidth == 4)
        #expect(style.doubleBarSpacing == 3)
        #expect(style.clefWidth == 40)
        #expect(style.meterWidth == 30)
    }

    @Test("flag spacing defaults to the app value and stays overridable")
    func flagSpacingDefaultAndOverride() {
        // The package default IS GameplayLayout.flagVerticalSpacing; the
        // later Virgo projection still passes it explicitly, and the
        // override must keep working.
        #expect(NotationEngravingStyle().flagVerticalSpacing == 8)
        #expect(NotationEngravingStyle(flagVerticalSpacing: 11).flagVerticalSpacing == 11)
        // Flag stem origins read the formatter's stem width — the engraving
        // style deliberately carries no second stem-width scalar.
        #expect(NotationEngravingStyle().formatting.stemWidth == 2)
    }

    @Test("engraving model types are Sendable")
    func engravingModelTypesAreSendable() throws {
        _ = requireSendable(NotationEngravingStyle())
        _ = requireSendable(EngravedRow(index: 0, staffCenterY: 40))
        _ = requireSendable(EngravedMeasure(
            index: 0, rowIndex: 0, xOffset: 100, width: 252,
            startTick: 0, durationTicks: 1920,
            meter: NotationMeter(beats: 4, noteValue: 4)
        ))
        _ = requireSendable(EngravedStem(noteIDs: [1], direction: .up, start: .zero, end: .zero))
        _ = requireSendable(EngravedBeam(
            noteIDs: [1, 2], direction: .up, level: 0, kind: .full,
            start: .zero, end: .zero, thickness: 4
        ))
        _ = requireSendable(EngravedFlag(
            noteID: 1, stemDirection: .up, duration: .eighth,
            flagIndex: 0, origin: .zero
        ))
        _ = requireSendable(EngravedLedgerLine(
            noteID: 1, rowIndex: 0, start: .zero, end: .zero, paintedBounds: .zero
        ))
        _ = requireSendable(EngravedRhythmDot(
            source: .note(1), position: .zero, rowIndex: 0, paintedBounds: .zero
        ))
        _ = requireSendable(EngravedRhythmDot(
            source: .rest(2), position: .zero, rowIndex: 0, paintedBounds: .zero
        ))
        _ = requireSendable(EngravedArticulation(noteID: 1, kind: .open, position: .zero))
        _ = requireSendable(EngravedControl(
            controlID: 9, kind: .stop, measureIndex: 0, rowIndex: 0, position: .zero
        ))
        _ = requireSendable(EngravedTuplet(
            tupletID: 0, voice: .upper, ratio: ResolvedTupletRatio(actual: 3, normal: 2),
            memberNoteIDs: [1, 2, 3], memberRestIDs: [], isBracketVisible: false,
            bracketPoints: [], labelPosition: .zero, rowIndex: 0
        ))
        _ = requireSendable(EngravedMeasureBar(
            measureIndex: 0, rowIndex: 0, x: 100, isFinal: false
        ))
        let input = try Fixtures.document(notes: [Fixtures.note()], rests: [], controls: [])
        let engraved = try NotationEngraver.engrave(input, style: NotationEngravingStyle())
        _ = requireSendable(engraved)
    }
}

/// HPA-166 Task 3: the engraver's vertical/primitive geometry — package-owned
/// staff Y, formatted X, Bravura painted bounds, and the one Y normalization.
@Suite("Notation engraver geometry")
struct NotationEngraverGeometryTests {
    private let style = NotationEngravingStyle()
    private let staffSpace = NotationFormattingStyle.virgoDefault.staffSpace

    private func head(_ engraved: EngravedNotation, id: Int) throws -> EngravedNoteHead {
        try #require(engraved.noteHeads.first { $0.noteID == id })
    }

    private func rest(_ engraved: EngravedNotation, id: Int) throws -> EngravedRest {
        try #require(engraved.rests.first { $0.restID == id })
    }

    @Test("engrave embeds the formatter and forwards musical-position lookup")
    func embedsFormatterAndForwardsLookup() throws {
        let input = try Fixtures.document(
            notes: [Fixtures.makeNote(id: 1, localTick: 480, staffStep: 3)],
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)

        #expect(engraved.formatted.measures.count == 1)
        // The musical-position lookup forwards to the embedded formatter —
        // exact anchors and interpolated ticks alike.
        #expect(
            engraved.position(measureIndex: 0, localTick: 480)
                == engraved.formatted.position(measureIndex: 0, localTick: 480)
        )
        #expect(
            engraved.position(measureIndex: 0, localTick: 240)
                == engraved.formatted.position(measureIndex: 0, localTick: 240)
        )
        #expect(engraved.position(measureIndex: 5, localTick: 0) == nil)
        let head1 = try head(engraved, id: 1)
        #expect(engraved.noteHeadPosition(noteID: 1) == head1.position)
        #expect(engraved.noteHeadPosition(noteID: 99) == nil)
    }

    @Test("engraved measures carry formatted bounds and resolved meter")
    func engravedMeasuresCarryFormattedBoundsAndMeter() throws {
        let input = try Fixtures.document(
            measures: [
                Fixtures.measure(),
                Fixtures.measure(index: 1, startTick: 1920)
            ],
            notes: [Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3)],
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)

        #expect(engraved.measures.count == 2)
        let first = engraved.measures[0]
        #expect(first.index == 0 && first.rowIndex == 0)
        #expect(first.xOffset == engraved.formatted.measures[0].xOffset)
        #expect(first.width == engraved.formatted.measures[0].width)
        #expect(first.startTick == 0 && first.durationTicks == 1920)
        #expect(first.meter == NotationMeter(beats: 4, noteValue: 4))
        #expect(engraved.measures[1].index == 1 && engraved.measures[1].startTick == 1920)
    }

    @Test("two formatted rows stack their staff centers by the row pitch")
    func twoRowsStackByRowPitch() throws {
        let narrow = NotationEngravingStyle(
            formatting: NotationFormattingStyle(availableRowWidth: 300)
        )
        let input = try Fixtures.document(
            measures: [
                Fixtures.measure(),
                Fixtures.measure(index: 1, startTick: 1920)
            ],
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3),
                Fixtures.makeNote(id: 2, localTick: 0, staffStep: 3, measureIndex: 1)
            ],
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: narrow)

        #expect(engraved.rows.map(\.index) == [0, 1])
        #expect(engraved.measures.map(\.rowIndex) == [0, 1])
        // Row pitch = rowHeight + rowVerticalSpacing = 340.
        #expect(engraved.rows[1].staffCenterY - engraved.rows[0].staffCenterY == 340)
        let head1 = try head(engraved, id: 1)
        let head2 = try head(engraved, id: 2)
        #expect(head2.position.y - head1.position.y == 340)
    }

    @Test("head Y tracks staff step away from the row staff center")
    func headYTracksStaffStepFromStaffCenter() throws {
        let input = try Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 8),
                Fixtures.makeNote(id: 2, localTick: 480, staffStep: 4),
                Fixtures.makeNote(id: 3, localTick: 960, staffStep: -4, stem: .down)
            ],
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)
        let center = try #require(engraved.rows.first).staffCenterY
        let halfSpace = staffSpace / 2

        // staffStep 4 is the middle line: delta = (step - 4) * staffSpace / 2.
        let head1 = try head(engraved, id: 1)
        let head2 = try head(engraved, id: 2)
        let head3 = try head(engraved, id: 3)
        #expect(head1.position.y == center - 4 * halfSpace)
        #expect(head2.position.y == center)
        #expect(head3.position.y == center + 8 * halfSpace)
    }

    @Test("rest Y is the row staff center plus its voice offset")
    func restYUsesVoiceOffsetFromStaffCenter() throws {
        let input = try Fixtures.document(
            notes: [],
            rests: [
                ResolvedRest(
                    id: 1, position: NotationTickPosition(measureIndex: 0, localTick: 480),
                    duration: .quarter, dotCount: 0, isFullMeasure: false,
                    voice: .upper, durationTicks: 480
                ),
                ResolvedRest(
                    id: 2, position: NotationTickPosition(measureIndex: 0, localTick: 960),
                    duration: .quarter, dotCount: 0, isFullMeasure: false,
                    voice: .lower, durationTicks: 480
                )
            ],
            controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)
        let center = try #require(engraved.rows.first).staffCenterY

        let rest1 = try rest(engraved, id: 1)
        let rest2 = try rest(engraved, id: 2)
        #expect(rest1.position.y == center + style.upperVoiceRestOffset)
        #expect(rest2.position.y == center + style.lowerVoiceRestOffset)
    }

    @Test("full-measure rest paints at the measure's content center")
    func fullMeasureRestCentersInMeasure() throws {
        let input = try Fixtures.document(
            notes: [],
            rests: [
                ResolvedRest(
                    id: 0, position: NotationTickPosition(measureIndex: 0, localTick: 0),
                    duration: .whole, dotCount: 0, isFullMeasure: true,
                    voice: .upper, durationTicks: 1920
                )
            ],
            controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)
        let measure = try #require(engraved.measures.first)
        let formatting = style.formatting
        let expected = measure.xOffset
            + (formatting.leadingMeasureInset + measure.width - formatting.trailingMeasureInset) / 2

        let fullRest = try rest(engraved, id: 0)
        #expect(fullRest.position.x == expected)
    }

    @Test("displaced same-stem second shifts only the upper head")
    func displacedSameStemSeconds() throws {
        let input = try Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 1, localTick: 480, staffStep: 3),
                Fixtures.makeNote(id: 2, localTick: 480, staffStep: 4)
            ],
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)
        let lower = try head(engraved, id: 1)
        let upper = try head(engraved, id: 2)
        let column = try Fixtures.column(engraved.formatted, localTick: 480)
        let headWidth = PercussionGlyphMetrics.notehead(
            style: .x, duration: .quarter, stemDirection: .up, staffSpace: staffSpace
        ).paintedBounds.width

        // The undisplaced head stays on the logical column; the staff-second
        // shift moves the upper head right by head width − half the stem width.
        #expect(lower.position.x == column.logicalColumnX)
        #expect(
            upper.position.x == column.logicalColumnX + headWidth - style.formatting.stemWidth / 2
        )
    }

    @Test("ledger lines overhang the high head's painted bounds")
    func ledgerLinesOverhangHeadBounds() throws {
        // staffStep 10 sits two steps above the staff (line5 = 8) — one ledger.
        let input = try Fixtures.document(
            notes: [Fixtures.makeNote(id: 1, localTick: 0, staffStep: 10)],
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)
        let cymbal = try head(engraved, id: 1)
        let center = try #require(engraved.rows.first).staffCenterY

        #expect(engraved.ledgerLines.count == 1)
        let ledger = try #require(engraved.ledgerLines.first)
        #expect(ledger.noteID == 1)
        #expect(ledger.start.y == center - 6 * staffSpace / 2)
        #expect(ledger.end.y == ledger.start.y)
        #expect(ledger.start.x == cymbal.paintedBounds.minX - style.ledgerLineOverhang)
        #expect(ledger.end.x == cymbal.paintedBounds.maxX + style.ledgerLineOverhang)
    }

    @Test("a single rhythm dot trails the painted ink maxX at formatter spacing")
    func rhythmDotsTrailPaintedInk() throws {
        let input = try Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, dotCount: 1)
            ],
            rests: [
                ResolvedRest(
                    id: 5, position: NotationTickPosition(measureIndex: 0, localTick: 960),
                    duration: .quarter, dotCount: 1, isFullMeasure: false,
                    voice: .upper, durationTicks: 480
                )
            ],
            controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)
        let formatting = style.formatting
        let cymbal = try head(engraved, id: 1)
        let printedRest = try rest(engraved, id: 5)

        // Single-dot parity with the app painter: one center at
        // ink maxX + spacing + radius, vertically on the head/rest center.
        let noteDots = engraved.rhythmDots.filter { $0.source == .note(1) }
        #expect(noteDots.count == 1)
        #expect(
            noteDots[0].position.x
                == cymbal.paintedBounds.maxX + formatting.rhythmDotSpacing + formatting.rhythmDotRadius
        )
        #expect(noteDots[0].position.y == cymbal.position.y)

        let restDots = engraved.rhythmDots.filter { $0.source == .rest(5) }
        #expect(restDots.count == 1)
        #expect(
            restDots[0].position.x
                == printedRest.paintedBounds.maxX + formatting.rhythmDotSpacing + formatting.rhythmDotRadius
        )
        #expect(restDots[0].position.y == printedRest.position.y)
    }

    @Test("dot counts other than one paint no dots — app parity")
    func nonSingleDotCountsPaintNoDots() throws {
        // The ported painter guards `dotCount == 1`; 0 and 2+ emit nothing
        // (the formatter still reserves their ink — painting is the parity
        // surface, reservation stays the formatter's).
        let input = try Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, dotCount: 0),
                Fixtures.makeNote(id: 2, localTick: 480, staffStep: 3, dotCount: 2)
            ],
            rests: [
                ResolvedRest(
                    id: 5, position: NotationTickPosition(measureIndex: 0, localTick: 960),
                    duration: .quarter, dotCount: 2, isFullMeasure: false,
                    voice: .upper, durationTicks: 480
                )
            ],
            controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)

        #expect(engraved.rhythmDots.isEmpty)
    }

    @Test("non-engravable notes keep their heads but drop their dots")
    func nonEngravableNotesDropDots() throws {
        let input = try Fixtures.document(
            notes: [
                Fixtures.makeNote(
                    id: 1, localTick: 0, staffStep: 3, dotCount: 1,
                    isRhythmEngravable: false
                )
            ],
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)

        #expect(engraved.noteHeads.count == 1)
        #expect(engraved.rhythmDots.isEmpty)
    }

    @Test("every primitive paints inside the final painted bounds")
    func primitivesInsidePaintedBounds() throws {
        let input = try Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 10, dotCount: 1),
                Fixtures.makeNote(id: 2, localTick: 960, staffStep: -4, stem: .down, headStyle: .normal)
            ],
            rests: [Fixtures.rest(id: 3, localTick: 480)],
            controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)
        let bounds = engraved.paintedBounds
        let primitiveInk = engraved.noteHeads.map(\.paintedBounds)
            + engraved.rests.map(\.paintedBounds)
            + engraved.ledgerLines.map(\.paintedBounds)
            + engraved.rhythmDots.map(\.paintedBounds)

        #expect(primitiveInk.allSatisfy(bounds.contains))
    }

    @Test("ink above the staff triggers the single package Y normalization")
    func topInkNormalizesOnce() throws {
        // A far-above-staff cymbal (the app's aboveLine9 = staffStep 18)
        // pushes raw ink negative; the engraver translates rows and every
        // primitive once so painted minY lands on 0.
        let input = try Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 18),
                Fixtures.makeNote(id: 2, localTick: 960, staffStep: -4, stem: .down, headStyle: .normal)
            ],
            rests: [Fixtures.rest(id: 3, localTick: 480)],
            controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)

        #expect(engraved.paintedBounds.minY == 0)
        // Rows translate with the primitives: staff-relative Y is unchanged.
        let center = try #require(engraved.rows.first).staffCenterY
        let head1 = try head(engraved, id: 1)
        let rest3 = try rest(engraved, id: 3)
        #expect(head1.position.y - center == -(18 - 4) * staffSpace / 2)
        #expect(rest3.position.y - center == style.upperVoiceRestOffset)
        // The result still covers the lowest row's staff bottom, and the
        // deep kick ink reaches past it — height is the *shifted* ink union.
        #expect(engraved.contentHeight >= center + 2 * staffSpace)
        #expect(engraved.contentHeight == engraved.paintedBounds.maxY)
        #expect(engraved.contentWidth >= engraved.paintedBounds.maxX)
    }

    @Test("low-only ink keeps the unshifted deterministic staff center")
    func lowOnlyInkKeepsUnshiftedOrigin() throws {
        // Only low ink: raw painted bounds stay non-negative, so the engraver
        // applies no translation — row 0's staff is band-centered at
        // `rowHeight / 2`, deterministic from the row pitch alone.
        let input = try Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: -2, stem: .down, headStyle: .normal)
            ],
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)

        #expect(engraved.rows.first?.staffCenterY == style.rowHeight / 2)
        #expect(engraved.paintedBounds.minY > 0)
        // Painted ink already reaches below the staff bottom, so content
        // height is exactly the painted union — no extra translation.
        #expect(engraved.contentHeight == engraved.paintedBounds.maxY)
    }
}
