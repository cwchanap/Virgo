import Testing
@testable import Virgo

@Suite("Notation Layout Rest and Control Tests")
struct NotationLayoutRestAndControlTests {
    private func layout(
        notes: [Note],
        controls: [NotationControlEvent] = [],
        minimumMeasureCount: Int = 1,
        style: NotationLayoutStyle = .gameplayDefault,
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition] = [:]
    ) -> NotationLayout {
        NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                notes: notes,
                controlEvents: controls,
                timeSignature: .fourFour,
                minimumMeasureCount: minimumMeasureCount,
                style: style,
                notePositionOverrides: notePositionOverrides
            )
        )
    }

    private func control(
        kind: NotationControlEventKind = .stop,
        measureNumber: Int = 1,
        measureOffset: Double = 0,
        originKind: NoteOriginKind = .manual,
        sourceLaneID: String? = nil,
        sourceNoteID: String? = nil,
        sourceGridPosition: Int? = nil,
        sourceGridSize: Int? = nil,
        normalizedMeasureIndex: Int? = nil,
        normalizedAbsoluteTick: Int? = nil,
        normalizedTickWithinMeasure: Int? = nil,
        normalizedTicksPerMeasure: Int? = nil,
        targetLaneID: String? = "1A"
    ) -> NotationControlEvent {
        NotationControlEvent(ChartControlEvent(
            kind: kind,
            measureNumber: measureNumber,
            measureOffset: measureOffset,
            originKind: originKind,
            sourceLaneID: sourceLaneID,
            sourceNoteID: sourceNoteID,
            sourceGridPosition: sourceGridPosition,
            sourceGridSize: sourceGridSize,
            normalizedMeasureIndex: normalizedMeasureIndex,
            normalizedAbsoluteTick: normalizedAbsoluteTick,
            normalizedTickWithinMeasure: normalizedTickWithinMeasure,
            normalizedTicksPerMeasure: normalizedTicksPerMeasure,
            targetLaneID: targetLaneID
        ))
    }

    private func fallbackGridNote() -> Note {
        Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
    }

    @Test("empty measure materializes one printed and one hidden full-measure rest")
    func emptyMeasureMaterializesFullMeasureRests() throws {
        let result = layout(notes: [])
        let upper = try #require(result.rests.first { $0.voice == .upper })
        let lower = try #require(result.rests.first { $0.voice == .lower })

        #expect(result.rests.count == 2)
        #expect(upper.duration == .fullMeasure)
        #expect(upper.durationTicks == result.tabGrid.ticksPerMeasure)
        #expect(upper.visibility == .printed)
        #expect(lower.duration == .fullMeasure)
        #expect(lower.durationTicks == result.tabGrid.ticksPerMeasure)
        #expect(lower.visibility == .hiddenDuplicate)
        #expect(upper.id.contains("m0"))
        #expect(upper.id.contains("vupper"))
        #expect(upper.id.contains("t0"))
        #expect(upper.id.contains("dfullMeasure"))
        #expect(upper.id.contains("xprinted"))
        #expect(upper.id.hasSuffix("-duplicate-0"))
    }

    @Test("single upper snare prints the lower full-measure companion")
    func upperSnarePrintsLowerFullMeasureRest() {
        let result = layout(notes: [
            Note(interval: .full, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ])

        #expect(result.rests.contains {
            $0.voice == .lower && $0.duration == .fullMeasure && $0.isPrinted
        })
        #expect(!result.rests.contains {
            $0.voice == .upper && $0.duration == .fullMeasure
        })
    }

    @Test("single lower kick prints the upper full-measure companion")
    func lowerKickPrintsUpperFullMeasureRest() {
        let result = layout(notes: [
            Note(interval: .full, noteType: .bass, measureNumber: 1, measureOffset: 0)
        ])

        #expect(result.rests.contains {
            $0.voice == .upper && $0.duration == .fullMeasure && $0.isPrinted
        })
        #expect(!result.rests.contains {
            $0.voice == .lower && $0.duration == .fullMeasure
        })
    }

    @Test("active upper and lower voices receive independent internal rests")
    func activeVoicesReceiveIndependentInternalRests() {
        let result = layout(notes: [
            Note(interval: .half, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .half, noteType: .bass, measureNumber: 1, measureOffset: 0.5)
        ])
        let upperPrinted = result.rests.filter { $0.voice == .upper && $0.isPrinted }
        let lowerPrinted = result.rests.filter { $0.voice == .lower && $0.isPrinted }

        #expect(upperPrinted.map(\.timeColumn.tickWithinMeasure) == [480])
        #expect(upperPrinted.map(\.duration) == [.half])
        #expect(lowerPrinted.map(\.timeColumn.tickWithinMeasure) == [0])
        #expect(lowerPrinted.map(\.duration) == [.half])
        #expect(!result.rests.contains { $0.duration == .fullMeasure })
    }

    @Test("full-measure rests use the measure midpoint but retain semantic tick zero")
    func fullMeasureRestUsesMeasureMidpoint() throws {
        let result = layout(notes: [])
        let measure = try #require(result.measures.first)
        let rest = try #require(result.rests.first { $0.isPrinted })

        #expect(rest.timeColumn.tickWithinMeasure == 0)
        #expect(rest.timeColumn.absoluteLayoutTick == 0)
        #expect(rest.position.x == measure.xOffset + measure.width / 2)
    }

    @Test("interval rests anchor to the exact tab-grid start column")
    func intervalRestUsesStartColumn() throws {
        let result = layout(notes: [
            Note(interval: .half, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ])
        let measure = try #require(result.measures.first)
        let rest = try #require(result.rests.first {
            $0.voice == .upper && $0.duration == .half && $0.isPrinted
        })

        #expect(rest.timeColumn.tickWithinMeasure == 480)
        #expect(rest.position.x == result.tabGrid.xPosition(in: measure, tickIndex: 480))
    }

    @Test("printed voice rests use distinct style-owned baselines")
    func printedRestsUseVoiceBaselines() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let result = layout(notes: [
            Note(interval: .half, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .half, noteType: .bass, measureNumber: 1, measureOffset: 0)
        ], style: style)
        let upper = try #require(result.rests.first { $0.voice == .upper && $0.isPrinted })
        let lower = try #require(result.rests.first { $0.voice == .lower && $0.isPrinted })
        let staffLine3Y = GameplayLayout.StaffLinePosition.line3.absoluteY(for: 0)

        #expect(upper.position.y == staffLine3Y + style.upperVoiceRestOffset)
        #expect(lower.position.y == staffLine3Y + style.lowerVoiceRestOffset)
        #expect(upper.position.y != lower.position.y)
    }

    @Test("hidden rests stay in the layout without becoming printed content")
    func hiddenRestsRemainNonPrinted() throws {
        let result = layout(notes: [])
        let hidden = try #require(result.rests.first { $0.visibility == .hiddenDuplicate })

        #expect(!hidden.isPrinted)
        #expect(result.rests.contains(hidden))
        #expect(result.rests.filter(\.isPrinted).count == 1)
    }

    @Test("rest materialization leaves existing notation artifacts and content width note-driven")
    func restsDoNotFeedExistingArtifactBuilders() throws {
        let notes = [
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125),
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.5)
        ]
        let input = NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        let engine = NotationLayoutEngine()
        let result = engine.layout(input: input)
        let measure = try #require(result.measures.first)
        let beamBuild = engine.buildBeams(
            noteHeads: result.noteHeads,
            tabGrid: result.tabGrid,
            timeSignature: input.timeSignature,
            style: input.style
        )
        let expectedStems = engine.buildStems(
            noteHeads: result.noteHeads, beams: beamBuild.beams, style: input.style
        )
        let expectedFlags = engine.buildFlags(
            noteHeads: result.noteHeads,
            beamBuild: beamBuild,
            stems: expectedStems,
            style: input.style
        )
        var resultWithoutRests = result
        resultWithoutRests.rests = []

        #expect(!result.rests.isEmpty)
        #expect(result.tabGrid == engine.buildTabGrid(notes: notes, input: input))
        #expect(result.measures == [RenderedMeasure(
            id: 0,
            measureIndex: 0,
            row: 0,
            xOffset: GameplayLayout.leftMargin,
            width: result.tabGrid.measureWidth
        )])
        #expect(result.noteHeads.map(\.position.x) == [
            result.tabGrid.xPosition(in: measure, tickIndex: 0),
            result.tabGrid.xPosition(in: measure, tickIndex: 120),
            result.tabGrid.xPosition(in: measure, tickIndex: 480)
        ])
        #expect(result.beams == beamBuild.beams)
        #expect(Set(result.stems) == Set(expectedStems))
        #expect(Set(result.flags) == Set(expectedFlags))
        #expect(
            Set(result.ledgerLines)
                == Set(engine.buildLedgerLines(noteHeads: result.noteHeads, style: input.style))
        )
        #expect(Set(result.measureBars) == Set(engine.buildMeasureBars(measures: result.measures)))
        #expect(result.contentWidth == resultWithoutRests.contentWidth)
    }

    @Test("shuffled note input preserves rendered rest order and semantic IDs")
    func shuffledNotesPreserveRestOrderingAndIDs() {
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.75)
        ]
        let ordered = layout(notes: notes).rests
        let shuffled = layout(notes: [notes[2], notes[0], notes[1]]).rests

        #expect(!ordered.isEmpty)
        #expect(shuffled == ordered)
        #expect(shuffled.map(\.id) == ordered.map(\.id))
    }
}

extension NotationLayoutRestAndControlTests {
    @Test("stop choke and damp preserve semantics while sharing plus-mark geometry")
    func controlKindsShareGeometryWithoutCollapsingSemantics() {
        let controls = NotationControlEventKind.allCases.map {
            control(
                kind: $0,
                originKind: .dtx,
                normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 1,
                normalizedTickWithinMeasure: 1,
                normalizedTicksPerMeasure: 4
            )
        }
        let result = layout(notes: [fallbackGridNote()], controls: controls)

        #expect(result.stopNotes.map(\.kind) == [.choke, .damp, .stop])
        #expect(Set(result.stopNotes.map(\.position)).count == 1)
        #expect(Set(result.stopNotes.map(\.timeColumn)).count == 1)
        #expect(Set(result.stopNotes.map(\.id)).count == 3)
    }

    @Test("complete normalized control timing overrides conflicting manual timing")
    func normalizedTimingTakesPrecedence() throws {
        let event = control(
            measureNumber: 99,
            measureOffset: 0.9,
            originKind: .manual,
            normalizedMeasureIndex: 0,
            normalizedAbsoluteTick: 1,
            normalizedTickWithinMeasure: 1,
            normalizedTicksPerMeasure: 4
        )
        let result = layout(notes: [fallbackGridNote()], controls: [event])
        let stop = try #require(result.stopNotes.first)

        #expect(result.measures.count == 1)
        #expect(stop.timeColumn.measureIndex == 0)
        #expect(stop.timeColumn.tickWithinMeasure == 240)
    }

    @Test("invalid complete normalized tuples contribute neither measures nor marks")
    func invalidNormalizedTimingIsRejected() {
        let invalidControls = [
            control(
                measureNumber: 8, normalizedMeasureIndex: -1,
                normalizedAbsoluteTick: 1, normalizedTickWithinMeasure: 1, normalizedTicksPerMeasure: 4
            ),
            control(
                measureNumber: 8, normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: -1, normalizedTickWithinMeasure: 1, normalizedTicksPerMeasure: 4
            ),
            control(
                measureNumber: 8, normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 0, normalizedTickWithinMeasure: -1, normalizedTicksPerMeasure: 4
            ),
            control(
                measureNumber: 8, normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 5, normalizedTickWithinMeasure: 5, normalizedTicksPerMeasure: 4
            ),
            control(
                measureNumber: 8, normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 1, normalizedTickWithinMeasure: 1, normalizedTicksPerMeasure: 0
            ),
            control(
                measureNumber: 8, normalizedMeasureIndex: 1,
                normalizedAbsoluteTick: 4, normalizedTickWithinMeasure: 1, normalizedTicksPerMeasure: 4
            )
        ]
        let result = layout(notes: [], controls: invalidControls)

        #expect(result.measures.count == 1)
        #expect(result.stopNotes.isEmpty)
    }

    @Test("a partial normalized tuple is invalid instead of using manual fallback")
    func partialNormalizedTimingIsRejected() {
        let partials = [
            control(measureNumber: 4, normalizedMeasureIndex: 3),
            control(measureNumber: 4, normalizedMeasureIndex: 3, normalizedAbsoluteTick: 12),
            control(
                measureNumber: 4,
                normalizedMeasureIndex: 3,
                normalizedAbsoluteTick: 12,
                normalizedTickWithinMeasure: 0
            )
        ]
        let result = layout(notes: [], controls: partials)

        #expect(result.measures.count == 1)
        #expect(result.stopNotes.isEmpty)
    }

    @Test("all-nil normalized timing permits only exact manual grid columns")
    func manualTimingRequiresExactGridProjection() {
        let controls = [
            control(measureOffset: 0.25, sourceNoteID: "exact"),
            control(measureOffset: 1.0 / 7.0, sourceNoteID: "inexact")
        ]
        let result = layout(notes: [fallbackGridNote()], controls: controls)

        #expect(result.stopNotes.count == 1)
        #expect(result.stopNotes.first?.sourceNoteID == "exact")
        #expect(result.stopNotes.first?.timeColumn.tickWithinMeasure == 240)
    }

    @Test("manual timing validates measure number offset finiteness and range")
    func invalidManualTimingIsRejected() {
        let controls = [
            control(measureNumber: 0, measureOffset: 0),
            control(measureNumber: 4, measureOffset: -0.1),
            control(measureNumber: 4, measureOffset: 1.1),
            control(measureNumber: 4, measureOffset: .nan)
        ]
        let result = layout(notes: [], controls: controls)

        #expect(result.measures.count == 1)
        #expect(result.stopNotes.isEmpty)
    }

    @Test("manual offset one normalizes to the next measure at tick zero")
    func manualEndOffsetNormalizesToNextMeasure() throws {
        let result = layout(
            notes: [fallbackGridNote()],
            controls: [control(measureNumber: 1, measureOffset: 1)]
        )
        let stop = try #require(result.stopNotes.first)

        #expect(result.measures.count == 2)
        #expect(stop.timeColumn.measureIndex == 1)
        #expect(stop.timeColumn.tickWithinMeasure == 0)
    }

    @Test("DTX controls never use manual timing fallback")
    func dtxTimingRequiresCompleteNormalizedTuple() {
        let result = layout(notes: [], controls: [
            control(measureNumber: 4, measureOffset: 0.25, originKind: .dtx)
        ])

        #expect(result.measures.count == 1)
        #expect(result.stopNotes.isEmpty)
    }

    @Test("normalized quarter timing projects exactly onto the fixed 960 grid")
    func normalizedQuarterProjectsExactly() throws {
        let result = layout(notes: [fallbackGridNote()], controls: [
            control(
                originKind: .dtx,
                normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 1,
                normalizedTickWithinMeasure: 1,
                normalizedTicksPerMeasure: 4
            )
        ])
        let stop = try #require(result.stopNotes.first)

        #expect(result.tabGrid.ticksPerMeasure == 960)
        #expect(stop.timeColumn.tickWithinMeasure == 240)
    }

    @Test("valid inexact source timing contributes its measure without a mark")
    func inexactProjectionStillContributesMeasure() {
        let result = layout(notes: [fallbackGridNote()], controls: [
            control(
                measureNumber: 99,
                originKind: .dtx,
                normalizedMeasureIndex: 2,
                normalizedAbsoluteTick: 15,
                normalizedTickWithinMeasure: 1,
                normalizedTicksPerMeasure: 7
            )
        ])

        #expect(result.tabGrid.ticksPerMeasure == 960)
        #expect(result.measures.count == 3)
        #expect(result.stopNotes.isEmpty)
    }

    @Test("a measure-three control adds no playable or note-derived artifact")
    func controlCanExtendMeasuresWithoutBecomingPlayable() {
        let result = layout(notes: [], controls: [
            control(
                originKind: .dtx,
                normalizedMeasureIndex: 2,
                normalizedAbsoluteTick: 8,
                normalizedTickWithinMeasure: 0,
                normalizedTicksPerMeasure: 4
            )
        ])

        #expect(result.measures.count == 3)
        #expect(result.noteHeads.isEmpty)
        #expect(result.stems.isEmpty)
        #expect(result.beams.isEmpty)
        #expect(result.flags.isEmpty)
        #expect(!result.hasPlayableContent)
    }

    @Test("missing and unknown targets preserve measure contribution but omit geometry")
    func unresolvedTargetsOmitGeometry() {
        let controls = [
            control(
                originKind: .dtx,
                normalizedMeasureIndex: 2,
                normalizedAbsoluteTick: 8,
                normalizedTickWithinMeasure: 0,
                normalizedTicksPerMeasure: 4,
                targetLaneID: nil
            ),
            control(
                originKind: .dtx,
                normalizedMeasureIndex: 2,
                normalizedAbsoluteTick: 9,
                normalizedTickWithinMeasure: 1,
                normalizedTicksPerMeasure: 4,
                targetLaneID: "ZZ"
            )
        ]
        let result = layout(notes: [], controls: controls)

        #expect(result.measures.count == 3)
        #expect(result.stopNotes.isEmpty)
    }

    @Test("lane 1A resolves to Crash and follows the active crash position override")
    func crashTargetUsesPositionOverride() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let result = layout(
            notes: [fallbackGridNote()],
            controls: [control(measureOffset: 0.25, targetLaneID: "1a")],
            style: style,
            notePositionOverrides: [.crash: .line3]
        )
        let stop = try #require(result.stopNotes.first)
        let expectedY = GameplayLayout.StaffLinePosition.line1.absoluteY(for: 0)
            + GameplayLayout.NotePosition.line3.yOffset
            - style.stopMarkVerticalOffset

        #expect(stop.targetLaneID == "1A")
        #expect(stop.targetDisplayName == "Crash")
        #expect(stop.position.y == expectedY)
    }

    @Test("controls never alter the note-driven grid wrapping or artifacts")
    func controlsDoNotFeedGridOrExistingArtifactBuilders() {
        let notes = [
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125),
            Note(interval: .quarter, noteType: .bass, measureNumber: 2, measureOffset: 0.5)
        ]
        let baseline = layout(notes: notes, minimumMeasureCount: 3)
        let withControls = layout(notes: notes, controls: [
            control(
                originKind: .dtx,
                normalizedMeasureIndex: 2,
                normalizedAbsoluteTick: 9,
                normalizedTickWithinMeasure: 1,
                normalizedTicksPerMeasure: 4
            )
        ], minimumMeasureCount: 3)

        #expect(withControls.tabGrid == baseline.tabGrid)
        #expect(withControls.measures == baseline.measures)
        #expect(withControls.noteHeads == baseline.noteHeads)
        #expect(withControls.stems == baseline.stems)
        #expect(withControls.beams == baseline.beams)
        #expect(withControls.flags == baseline.flags)
        #expect(withControls.rests == baseline.rests)
        #expect(withControls.contentWidth == baseline.contentWidth)
    }

    @Test("control order and IDs use the full stable semantic tuple")
    func controlsUseStableSemanticTupleOrdering() {
        let events = [
            control(
                kind: .stop, sourceLaneID: "B", sourceNoteID: "B",
                sourceGridPosition: 1, sourceGridSize: 8,
                normalizedMeasureIndex: 0, normalizedAbsoluteTick: 1,
                normalizedTickWithinMeasure: 1, normalizedTicksPerMeasure: 4,
                targetLaneID: "1A"
            ),
            control(
                kind: .stop, sourceLaneID: "B", sourceNoteID: "B",
                sourceGridPosition: 1, sourceGridSize: 4,
                normalizedMeasureIndex: 0, normalizedAbsoluteTick: 1,
                normalizedTickWithinMeasure: 1, normalizedTicksPerMeasure: 4,
                targetLaneID: "1A"
            ),
            control(
                kind: .stop, sourceLaneID: "B", sourceNoteID: "B",
                sourceGridPosition: 0, sourceGridSize: 4,
                normalizedMeasureIndex: 0, normalizedAbsoluteTick: 1,
                normalizedTickWithinMeasure: 1, normalizedTicksPerMeasure: 4,
                targetLaneID: "1A"
            ),
            control(
                kind: .stop, sourceLaneID: "B", sourceNoteID: "A",
                sourceGridPosition: 0, sourceGridSize: 4,
                normalizedMeasureIndex: 0, normalizedAbsoluteTick: 1,
                normalizedTickWithinMeasure: 1, normalizedTicksPerMeasure: 4,
                targetLaneID: "1A"
            ),
            control(
                kind: .stop, sourceLaneID: "A", sourceNoteID: "A",
                sourceGridPosition: 0, sourceGridSize: 4,
                normalizedMeasureIndex: 0, normalizedAbsoluteTick: 1,
                normalizedTickWithinMeasure: 1, normalizedTicksPerMeasure: 4,
                targetLaneID: "1A"
            ),
            control(
                kind: .stop, sourceLaneID: "A", sourceNoteID: "A",
                sourceGridPosition: 0, sourceGridSize: 4,
                normalizedMeasureIndex: 0, normalizedAbsoluteTick: 1,
                normalizedTickWithinMeasure: 1, normalizedTicksPerMeasure: 4,
                targetLaneID: "11"
            ),
            control(
                kind: .damp, sourceLaneID: "A", sourceNoteID: "A",
                sourceGridPosition: 0, sourceGridSize: 4,
                normalizedMeasureIndex: 0, normalizedAbsoluteTick: 1,
                normalizedTickWithinMeasure: 1, normalizedTicksPerMeasure: 4,
                targetLaneID: "11"
            ),
            control(
                kind: .choke, sourceLaneID: "A", sourceNoteID: "A",
                sourceGridPosition: 0, sourceGridSize: 4,
                normalizedMeasureIndex: 0, normalizedAbsoluteTick: 1,
                normalizedTickWithinMeasure: 1, normalizedTicksPerMeasure: 4,
                targetLaneID: "11"
            ),
            control(
                kind: .stop, sourceLaneID: "Z", sourceNoteID: "Z",
                sourceGridPosition: 9, sourceGridSize: 9,
                normalizedMeasureIndex: 0, normalizedAbsoluteTick: 0,
                normalizedTickWithinMeasure: 0, normalizedTicksPerMeasure: 4,
                targetLaneID: "1A"
            ),
            control(
                kind: .stop, sourceLaneID: "Z", sourceNoteID: "Z",
                sourceGridPosition: 9, sourceGridSize: 9,
                normalizedMeasureIndex: 1, normalizedAbsoluteTick: 4,
                normalizedTickWithinMeasure: 0, normalizedTicksPerMeasure: 4,
                targetLaneID: "1A"
            )
        ]
        let ordered = layout(notes: [fallbackGridNote()], controls: events).stopNotes
        let shuffled = layout(notes: [fallbackGridNote()], controls: Array(events.reversed())).stopNotes

        #expect(ordered == shuffled)
        #expect(ordered.map(\.kind) == [.stop, .choke, .damp, .stop, .stop, .stop, .stop, .stop, .stop, .stop])
        #expect(ordered.map(\.targetLaneID) == ["1A", "11", "11", "11", "1A", "1A", "1A", "1A", "1A", "1A"])
        #expect(ordered.map(\.sourceLaneID) == ["Z", "A", "A", "A", "A", "B", "B", "B", "B", "Z"])
        #expect(ordered.map(\.sourceNoteID) == ["Z", "A", "A", "A", "A", "A", "B", "B", "B", "Z"])
        #expect(ordered.map(\.id) == [
            "control-m0-t0-kstop-target1A-sourceZ-idZ-gp9-gs9-duplicate-0",
            "control-m0-t240-kchoke-target11-sourceA-idA-gp0-gs4-duplicate-0",
            "control-m0-t240-kdamp-target11-sourceA-idA-gp0-gs4-duplicate-0",
            "control-m0-t240-kstop-target11-sourceA-idA-gp0-gs4-duplicate-0",
            "control-m0-t240-kstop-target1A-sourceA-idA-gp0-gs4-duplicate-0",
            "control-m0-t240-kstop-target1A-sourceB-idA-gp0-gs4-duplicate-0",
            "control-m0-t240-kstop-target1A-sourceB-idB-gp0-gs4-duplicate-0",
            "control-m0-t240-kstop-target1A-sourceB-idB-gp1-gs4-duplicate-0",
            "control-m0-t240-kstop-target1A-sourceB-idB-gp1-gs8-duplicate-0",
            "control-m1-t0-kstop-target1A-sourceZ-idZ-gp9-gs9-duplicate-0"
        ])
    }

    @Test("exact duplicate controls receive deterministic duplicate ordinals")
    func duplicateControlsReceiveStableOrdinals() {
        let duplicate = control(
            kind: .choke,
            sourceLaneID: "55",
            sourceNoteID: "0A",
            sourceGridPosition: 1,
            sourceGridSize: 4,
            normalizedMeasureIndex: 0,
            normalizedAbsoluteTick: 1,
            normalizedTickWithinMeasure: 1,
            normalizedTicksPerMeasure: 4,
            targetLaneID: "1A"
        )
        let first = layout(notes: [fallbackGridNote()], controls: [duplicate, duplicate]).stopNotes
        let second = layout(notes: [fallbackGridNote()], controls: [duplicate, duplicate]).stopNotes

        #expect(first == second)
        #expect(first.map(\.id) == [
            "control-m0-t240-kchoke-target1A-source55-id0A-gp1-gs4-duplicate-0",
            "control-m0-t240-kchoke-target1A-source55-id0A-gp1-gs4-duplicate-1"
        ])
    }

    @Test("only rendered open hi-hat heads produce articulation circles")
    func onlyOpenHiHatProducesArticulation() throws {
        let result = layout(notes: [
            Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .openHiHat, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0.5)
        ])
        let articulation = try #require(result.articulations.first)
        let openHead = try #require(result.noteHeads.first { $0.variant == .openHiHat })

        #expect(result.articulations.count == 1)
        #expect(articulation.kind == .openHiHat)
        #expect(articulation.sourceNoteHeadID == openHead.id)
        #expect(articulation.id == "openHiHat-head-\(openHead.id)")
        #expect(articulation.row == openHead.row)
        #expect(articulation.position.x == openHead.position.x)
        #expect(
            articulation.position.y
                == openHead.position.y - NotationLayoutStyle.gameplayDefault.articulationVerticalOffset
        )
    }

    @Test("hi-hat variants and stop semantics expose distinct accessibility labels")
    func renderedAccessibilityLabelsAreSemantic() throws {
        let result = layout(notes: [
            Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .openHiHat, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0.5)
        ], controls: [control(kind: .damp, measureOffset: 0.75, targetLaneID: "1A")])
        let labels = Set(result.noteHeads.map(\.accessibilityLabel))
        let stop = try #require(result.stopNotes.first)

        #expect(labels == ["Closed hi-hat", "Open hi-hat", "Pedal hi-hat"])
        #expect(stop.accessibilityLabel == "Damp Crash")
    }
}
