import CoreGraphics
import Testing
@testable import DrumNotation

/// HPA-166 Task 4: resolved-semantics primitives — tuplets, measure bars
/// and the staff/clef/meter row descriptors — split from
/// `NotationEngraverModifierTests.swift` for the file-length limit.
///
@Suite("Engraver tuplets")
struct EngraverTupletTests {
    private let style = NotationEngravingStyle()

    /// Three eighth-note triplet members tiling a quarter beat — beamed
    /// when every member lands in the same beat group.
    private func triplet(
        duration: NotationDuration = .eighth,
        memberTicks: [Int] = [0, 160, 320],
        memberDurationTicks: Int = 160,
        voice: NotationVoiceRole = .upper,
        stem: NotationStemDirection = .up,
        dotCount: Int = 0
    ) throws -> ResolvedNotationInput {
        let noteIDs = memberTicks.indices.map { $0 + 1 }
        return try Fixtures.document(
            notes: memberTicks.enumerated().map { index, tick in
                Fixtures.makeNote(
                    id: index + 1, localTick: tick, staffStep: 3, stem: stem,
                    duration: duration, dotCount: dotCount, voice: voice,
                    durationTicks: memberDurationTicks
                )
            },
            rests: [], controls: [],
            tuplets: [
                ResolvedTupletGroup(
                    id: 1, measureIndex: 0, voice: voice,
                    ratio: ResolvedTupletRatio(actual: 3, normal: 2),
                    memberNoteIDs: noteIDs, memberRestIDs: []
                )
            ]
        )
    }

    private func memberBounds(
        _ engraved: EngravedNotation,
        noteIDs: [Int],
        restIDs: [Int] = []
    ) -> CGRect {
        let heads = engraved.noteHeads.filter { noteIDs.contains($0.noteID) }.map(\.paintedBounds)
        let rests = engraved.rests.filter { restIDs.contains($0.restID) }.map(\.paintedBounds)
        let all = heads + rests
        return all.dropFirst().reduce(all.first ?? .null) { $0.union($1) }
    }

    @Test("a continuously beamed triplet paints its label only")
    func beamedTripletPaintsLabelOnly() throws {
        let engraved = try NotationEngraver.engrave(triplet(), style: style)
        #expect(engraved.tuplets.count == 1)
        let tuplet = try #require(engraved.tuplets.first)

        #expect(tuplet.tupletID == 1)
        #expect(tuplet.voice == .upper)
        #expect(tuplet.ratio == ResolvedTupletRatio(actual: 3, normal: 2))
        #expect(tuplet.memberNoteIDs == [1, 2, 3])
        #expect(tuplet.memberRestIDs.isEmpty)
        #expect(tuplet.isBracketVisible == false)
        #expect(tuplet.bracketPoints.isEmpty)

        // Label centers on the member-bounds midpoint and floats
        // tupletVerticalOffset above the highest member beam.
        let bounds = memberBounds(engraved, noteIDs: [1, 2, 3])
        let topBeamY = try #require(engraved.beams.map(\.start.y).min())
        #expect(tuplet.labelPosition == CGPoint(
            x: bounds.midX,
            y: topBeamY - style.tupletVerticalOffset
        ))
    }

    @Test("an unbeamed triplet paints a bracket around its label")
    func unbeamedTripletPaintsBracket() throws {
        // Quarter-note triplet members take stems but no beams — the
        // bracket must span the member bounds with hooks and a label gap.
        let engraved = try NotationEngraver.engrave(
            triplet(duration: .quarter, memberTicks: [0, 320, 640], memberDurationTicks: 320),
            style: style
        )
        #expect(engraved.tuplets.count == 1)
        let tuplet = try #require(engraved.tuplets.first)
        #expect(tuplet.isBracketVisible)
        #expect(engraved.beams.isEmpty)

        let bounds = memberBounds(engraved, noteIDs: [1, 2, 3])
        let labelY = bounds.minY - style.tupletVerticalOffset
        let hookY = labelY + style.tupletHookLength
        let halfGap = style.tupletLabelSize.width / 2 + style.formatting.rhythmDotSpacing
        #expect(tuplet.labelPosition == CGPoint(x: bounds.midX, y: labelY))
        #expect(tuplet.bracketPoints == [
            CGPoint(x: bounds.minX, y: hookY),
            CGPoint(x: bounds.minX, y: labelY),
            CGPoint(x: max(bounds.minX, bounds.midX - halfGap), y: labelY),
            CGPoint(x: min(bounds.maxX, bounds.midX + halfGap), y: labelY),
            CGPoint(x: bounds.maxX, y: labelY),
            CGPoint(x: bounds.maxX, y: hookY)
        ])
    }

    @Test("a rest member forces the bracket even when the notes beam")
    func restMemberForcesBracket() throws {
        let input = try Fixtures.document(
            notes: [0, 160].enumerated().map { index, tick in
                Fixtures.makeNote(
                    id: index + 1, localTick: tick, staffStep: 3,
                    duration: .eighth, durationTicks: 160
                )
            },
            rests: [
                ResolvedRest(
                    id: 10,
                    position: NotationTickPosition(measureIndex: 0, localTick: 320),
                    duration: .eighth, dotCount: 0, isFullMeasure: false,
                    voice: .upper, durationTicks: 160
                )
            ],
            controls: [],
            tuplets: [
                ResolvedTupletGroup(
                    id: 1, measureIndex: 0, voice: .upper,
                    ratio: ResolvedTupletRatio(actual: 3, normal: 2),
                    memberNoteIDs: [1, 2], memberRestIDs: [10]
                )
            ]
        )
        let engraved = try NotationEngraver.engrave(input, style: style)
        #expect(engraved.tuplets.count == 1)
        let tuplet = try #require(engraved.tuplets.first)
        #expect(tuplet.isBracketVisible)
        #expect(tuplet.memberRestIDs == [10])

        // The rest's bounds join the union that anchors the bracket span.
        let bounds = memberBounds(engraved, noteIDs: [1, 2], restIDs: [10])
        #expect(tuplet.labelPosition.x == bounds.midX)
        #expect(tuplet.bracketPoints.first?.x == bounds.minX)
        #expect(tuplet.bracketPoints.last?.x == bounds.maxX)
    }

    @Test("a down-stem triplet floats its label below the member beams")
    func downStemTripletLabelsBelow() throws {
        let engraved = try NotationEngraver.engrave(
            triplet(voice: .lower, stem: .down),
            style: style
        )
        #expect(engraved.tuplets.count == 1)
        let tuplet = try #require(engraved.tuplets.first)
        #expect(tuplet.isBracketVisible == false)

        let lowestBeamY = try #require(engraved.beams.map(\.start.y).max())
        let bounds = memberBounds(engraved, noteIDs: [1, 2, 3])
        #expect(tuplet.labelPosition == CGPoint(
            x: bounds.midX,
            y: lowestBeamY + style.tupletVerticalOffset
        ))
        #expect(tuplet.labelPosition.y > bounds.maxY)
    }

    @Test("a dotted beamed member still paints label-only")
    func dottedMemberStaysLabelOnly() throws {
        // Dots never influence the bracket rule — only beaming and rests do.
        let input = try Fixtures.document(
            notes: [0, 160, 320].enumerated().map { index, tick in
                Fixtures.makeNote(
                    id: index + 1, localTick: tick, staffStep: 3,
                    duration: .eighth, dotCount: index == 1 ? 1 : 0,
                    durationTicks: 160
                )
            },
            rests: [], controls: [],
            tuplets: [
                ResolvedTupletGroup(
                    id: 1, measureIndex: 0, voice: .upper,
                    ratio: ResolvedTupletRatio(actual: 3, normal: 2),
                    memberNoteIDs: [1, 2, 3], memberRestIDs: []
                )
            ]
        )
        let engraved = try NotationEngraver.engrave(input, style: style)
        #expect(engraved.tuplets.count == 1)
        let tuplet = try #require(engraved.tuplets.first)
        #expect(tuplet.isBracketVisible == false)
        #expect(tuplet.bracketPoints.isEmpty)
    }

    @Test("two disconnected beam runs still paint the bracket")
    func disconnectedBeamRunsPaintBracket() throws {
        // Four sixteenth members in two adjacent pairs: every onset is
        // beamed, but no single primary run covers all of them — the
        // label cannot float bracket-free over the gap between the runs.
        let input = try Fixtures.document(
            notes: [0, 120, 480, 600].enumerated().map { index, tick in
                Fixtures.makeNote(
                    id: index + 1, localTick: tick, staffStep: 3,
                    duration: .sixteenth, durationTicks: 120
                )
            },
            rests: [], controls: [],
            tuplets: [
                ResolvedTupletGroup(
                    id: 1, measureIndex: 0, voice: .upper,
                    ratio: ResolvedTupletRatio(actual: 3, normal: 2),
                    memberNoteIDs: [1, 2, 3, 4], memberRestIDs: []
                )
            ]
        )
        let engraved = try NotationEngraver.engrave(input, style: style)

        // Two primary runs — one level-0 full beam each.
        #expect(engraved.beams.filter { $0.level == 0 && $0.kind == .full }.count == 2)
        let tuplet = try #require(engraved.tuplets.first)
        #expect(tuplet.isBracketVisible)
        #expect(tuplet.bracketPoints.count == 6)

        // The label still floats above the members' highest beam, and the
        // bracket spans every member's bounds.
        let bounds = memberBounds(engraved, noteIDs: [1, 2, 3, 4])
        let topBeamY = try #require(engraved.beams.map(\.start.y).min())
        #expect(tuplet.labelPosition == CGPoint(
            x: bounds.midX,
            y: topBeamY - style.tupletVerticalOffset
        ))
        #expect(tuplet.bracketPoints.first?.x == bounds.minX)
        #expect(tuplet.bracketPoints.last?.x == bounds.maxX)
    }

    @Test("simultaneous members inside one tuplet order deterministically")
    func simultaneousMembersOrderDeterministically() throws {
        // A chord on the middle onset: heads 2 and 4 share tiebreak 0 (id
        // breaks their tie) while head 3 carries tiebreak 1 — the member-head
        // ordering must consult (absoluteTick, tiebreakOrder, id).
        let input = try Fixtures.document(
            notes: [
                Fixtures.makeNote(
                    id: 1, localTick: 0, staffStep: 3,
                    duration: .quarter, durationTicks: 320
                ),
                Fixtures.makeNote(
                    id: 2, localTick: 320, staffStep: 3,
                    duration: .quarter, durationTicks: 320, tiebreakOrder: 0
                ),
                Fixtures.makeNote(
                    id: 3, localTick: 320, staffStep: 5,
                    duration: .quarter, durationTicks: 320, tiebreakOrder: 1
                ),
                Fixtures.makeNote(
                    id: 4, localTick: 320, staffStep: 4,
                    duration: .quarter, durationTicks: 320, tiebreakOrder: 0
                ),
                Fixtures.makeNote(
                    id: 5, localTick: 640, staffStep: 3,
                    duration: .quarter, durationTicks: 320
                )
            ],
            rests: [], controls: [],
            tuplets: [
                ResolvedTupletGroup(
                    id: 1, measureIndex: 0, voice: .upper,
                    ratio: ResolvedTupletRatio(actual: 3, normal: 2),
                    memberNoteIDs: [1, 2, 3, 4, 5], memberRestIDs: []
                )
            ]
        )
        let engraved = try NotationEngraver.engrave(input, style: style)
        let tuplet = try #require(engraved.tuplets.first)

        // Quarter members never beam, so the bracket spans every head in the
        // chord — not just one head per onset.
        #expect(engraved.beams.isEmpty)
        #expect(tuplet.isBracketVisible)
        let bounds = memberBounds(engraved, noteIDs: [1, 2, 3, 4, 5])
        #expect(tuplet.labelPosition.x == bounds.midX)
        #expect(tuplet.bracketPoints.first?.x == bounds.minX)
        #expect(tuplet.bracketPoints.last?.x == bounds.maxX)
    }

    @Test("tuplets carry their members' row")
    func tupletCarriesMemberRow() throws {
        let engraved = try NotationEngraver.engrave(triplet(), style: style)
        let tuplet = try #require(engraved.tuplets.first)
        let memberRow = try #require(engraved.noteHeads.first { $0.noteID == 1 }).rowIndex
        #expect(tuplet.rowIndex == memberRow)
    }
}

@Suite("Engraver measure bars and row descriptors")
struct EngraverBarRowTests {
    private let style = NotationEngravingStyle()

    private func document(
        measureCount: Int
    ) throws -> ResolvedNotationInput {
        let measures = (0..<measureCount).map {
            Fixtures.measure(index: $0, startTick: $0 * 1920)
        }
        return try Fixtures.document(
            measures: measures,
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, duration: .quarter, durationTicks: 480)
            ],
            rests: [], controls: []
        )
    }

    @Test("every measure paints an end bar; only row-leading measures paint a leading bar")
    func barsDeriveFromFormattedBounds() throws {
        let engraved = try NotationEngraver.engrave(document(measureCount: 2), style: style)
        let formatted = engraved.formatted.measures
        #expect(formatted.count == 2)
        #expect(Set(formatted.map(\.rowIndex)).count == 1)

        // [lead m0, end m0, end m1] — no leading bar between same-row measures.
        let bars = engraved.measureBars
        #expect(bars.count == 3)
        #expect(bars.map(\.measureIndex) == [0, 0, 1])
        #expect(bars[0].x == formatted[0].xOffset)
        #expect(bars[1].x == formatted[0].xOffset + formatted[0].width)
        #expect(bars[2].x == formatted[1].xOffset + formatted[1].width)
        #expect(bars.map(\.isFinal) == [false, false, true])
        #expect(bars.map(\.rowIndex) == [0, 0, 0])
    }

    @Test("a row-leading measure earns its own leading bar")
    func leadingBarPerRow() throws {
        let narrow = NotationEngravingStyle(
            formatting: NotationFormattingStyle(availableRowWidth: 500)
        )
        let engraved = try NotationEngraver.engrave(document(measureCount: 2), style: narrow)
        let formatted = engraved.formatted.measures
        #expect(Set(formatted.map(\.rowIndex)).count == 2)

        let bars = engraved.measureBars
        #expect(bars.count == 4)
        #expect(bars.map(\.measureIndex) == [0, 0, 1, 1])
        #expect(bars[2].x == formatted[1].xOffset)
        #expect(bars.map(\.isFinal) == [false, false, false, true])
    }

    @Test("rows carry staff lines, a clef and the first measure's meter")
    func rowsCarryDescriptors() throws {
        let staffSpace = NotationFormattingStyle.virgoDefault.staffSpace
        let engraved = try NotationEngraver.engrave(document(measureCount: 1), style: style)
        #expect(engraved.rows.count == 1)
        let row = try #require(engraved.rows.first)

        // Staff lines in pitch-ascending order: bottom line first.
        #expect(row.staffLineYs == [
            row.staffCenterY + 2 * staffSpace,
            row.staffCenterY + staffSpace,
            row.staffCenterY,
            row.staffCenterY - staffSpace,
            row.staffCenterY - 2 * staffSpace
        ])
        #expect(row.clef.position == CGPoint(x: style.clefWidth / 2, y: row.staffCenterY))
        #expect(row.meterSignature.meter == NotationMeter(beats: 4, noteValue: 4))
        #expect(row.meterSignature.position == CGPoint(
            x: style.clefWidth + style.meterWidth / 2,
            y: row.staffCenterY
        ))
    }

    @Test("row furniture exposes painted bounds inside the final painted union")
    func rowFurnitureInsidePaintedBounds() throws {
        let staffSpace = NotationFormattingStyle.virgoDefault.staffSpace
        let engraved = try NotationEngraver.engrave(document(measureCount: 1), style: style)
        let row = try #require(engraved.rows.first)

        // The clef and meter slots: furniture advance × staff height,
        // centered on each descriptor's position.
        #expect(row.clef.paintedBounds == CGRect(
            x: 0, y: row.staffCenterY - 2 * staffSpace,
            width: style.clefWidth, height: 4 * staffSpace
        ))
        #expect(row.meterSignature.paintedBounds == CGRect(
            x: style.clefWidth, y: row.staffCenterY - 2 * staffSpace,
            width: style.meterWidth, height: 4 * staffSpace
        ))

        // Staff lines stroke the fixed staffLineWidth (the app's legacy
        // 1pt, not barLineWidth) across the full declared sheet width —
        // the app's row painter drew every row to the floored
        // `contentWidth`, not to each row's last measure edge.
        let staffLineWidth = NotationEngravingStyle.staffLineWidth
        for lineY in row.staffLineYs {
            let line = CGRect(
                x: 0, y: lineY - staffLineWidth / 2,
                width: engraved.contentWidth, height: staffLineWidth
            )
            #expect(row.paintedBounds.contains(line))
        }
        #expect(row.paintedBounds.maxX == engraved.contentWidth)
        // The stroked staff lines are the furniture union's vertical
        // extremes — the slots end at the outer line centers — so the
        // edges pin the stroke width exactly.
        #expect(row.paintedBounds.minY == row.staffLineYs.last.map { $0 - staffLineWidth / 2 })
        #expect(row.paintedBounds.maxY == row.staffLineYs.first.map { $0 + staffLineWidth / 2 })
        #expect(row.paintedBounds.contains(row.clef.paintedBounds))
        #expect(row.paintedBounds.contains(row.meterSignature.paintedBounds))
        #expect(engraved.paintedBounds.contains(row.paintedBounds))
    }

    @Test("an event-free row still bounds its furniture — never a null union")
    func furnitureAloneProducesPaintedBounds() throws {
        let input = try Fixtures.document(notes: [], rests: [], controls: [])
        let engraved = try NotationEngraver.engrave(input, style: style)
        let row = try #require(engraved.rows.first)

        #expect(engraved.paintedBounds.isNull == false)
        #expect(engraved.paintedBounds.contains(row.paintedBounds))
        #expect(engraved.contentHeight >= row.paintedBounds.maxY)
    }

    @Test("row furniture shares the single Y normalization")
    func rowFurnitureTranslatesOnce() throws {
        // Ink above the staff shifts every primitive down once; the
        // furniture must land in the same shifted coordinates.
        let staffSpace = NotationFormattingStyle.virgoDefault.staffSpace
        let input = try Fixtures.document(
            notes: [Fixtures.makeNote(id: 1, localTick: 0, staffStep: 18)],
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)
        let row = try #require(engraved.rows.first)

        #expect(engraved.paintedBounds.minY == 0)
        #expect(row.paintedBounds.minY >= 0)
        // The descriptors' slots stay centered on their positions, and the
        // staff lines keep their staff-center-relative spacing.
        #expect(row.clef.paintedBounds.midY == row.clef.position.y)
        #expect(row.clef.position.y == row.staffCenterY)
        #expect(row.meterSignature.paintedBounds.midY == row.meterSignature.position.y)
        #expect(row.staffLineYs.first == row.staffCenterY + 2 * staffSpace)
        #expect(row.staffLineYs.last == row.staffCenterY - 2 * staffSpace)
    }

    @Test("a wrapped row signs its own first measure's meter")
    func wrappedRowSignsOwnMeter() throws {
        let narrow = NotationEngravingStyle(
            formatting: NotationFormattingStyle(availableRowWidth: 500)
        )
        let input = try Fixtures.document(
            measures: [
                Fixtures.measure(index: 0, startTick: 0),
                Fixtures.measure(
                    index: 1, startTick: 1920,
                    meter: NotationMeter(beats: 6, noteValue: 8)
                )
            ],
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, duration: .quarter, durationTicks: 480)
            ],
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: narrow)
        #expect(engraved.rows.count == 2)
        let secondRow = try #require(engraved.rows.first { $0.index == 1 })
        #expect(secondRow.meterSignature.meter == NotationMeter(beats: 6, noteValue: 8))
        #expect(engraved.rows.first?.meterSignature.meter == NotationMeter(beats: 4, noteValue: 4))
    }

    @Test("content width keeps the wrap-width floor plus trailing room")
    func contentWidthFloorAndTrailingRoom() throws {
        // The pre-cutover contract — `max(maxRowWidth, ink.maxX +
        // uniformSpacing)` — survives the ownership move: the formatter's
        // `availableRowWidth` is the floor (the app's 900pt row width) and
        // `minimumQuarterNoteSpacing` is the trailing room (the app's
        // `uniformSpacing`). A sparse sheet never narrows below the floor,
        // and every row's staff lines span the declared width.
        let sparse = try NotationEngraver.engrave(document(measureCount: 1), style: style)
        #expect(sparse.contentWidth == style.formatting.availableRowWidth)
        #expect(sparse.paintedBounds.maxX == sparse.contentWidth)
        #expect(sparse.rows.allSatisfy { $0.paintedBounds.maxX == sparse.contentWidth })

        // Ink past the floor keeps one spacing unit of trailing room. The
        // bar tier is the rightmost ink here — the only note sits on the
        // first column — so the pre-furniture union ends at the widest
        // measure edge's bar ink (interior bars stroke half a width past
        // their X; the final double bar ends at it).
        let narrow = NotationEngravingStyle(
            formatting: NotationFormattingStyle(availableRowWidth: 200)
        )
        let wrapped = try NotationEngraver.engrave(document(measureCount: 3), style: narrow)
        let barInkMaxX = try #require(wrapped.measureBars.map {
            $0.isFinal ? $0.x : $0.x + narrow.barLineWidth / 2
        }.max())
        let expected = max(
            narrow.formatting.availableRowWidth,
            barInkMaxX + narrow.formatting.minimumQuarterNoteSpacing
        )
        try #require(
            expected > narrow.formatting.availableRowWidth,
            "fixture must push ink past the floor"
        )
        #expect(wrapped.contentWidth == expected)
        #expect(wrapped.paintedBounds.maxX == wrapped.contentWidth)
        #expect(wrapped.rows.allSatisfy { $0.paintedBounds.maxX == wrapped.contentWidth })
    }
}
