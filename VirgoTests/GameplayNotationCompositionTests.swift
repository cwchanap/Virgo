import CoreGraphics
import DrumNotation
import Testing
@testable import Virgo

/// HPA-164 Task 5 / HPA-166 Task 7: the installed `EngravedNotation` copies
/// package geometry straight from `FormattedNotation` — measure rows/bounds,
/// head centers, rest and control X, measure bars — while stems and beams
/// stay on the undisplaced stem-side representative.
@Suite("Gameplay Notation Composition")
struct GameplayNotationCompositionTests {
    private let ticksPerWholeNote = 960

    // MARK: - Fixtures

    private func makeMeasure(index: Int, startTick: Int) -> RhythmMeasure {
        RhythmMeasure(
            measureIndex: index,
            startTick: startTick,
            durationTicks: 960,
            timeSignature: .fourFour,
            beatGroups: (0..<4).map {
                RhythmBeatGroup(groupIndex: $0, startTick: $0 * 240, durationTicks: 240, isResidual: false)
            },
            engravingSupport: .supported
        )
    }

    private func makeSnapshot(
        measures: [RhythmMeasure],
        notes: [RhythmLayoutNote],
        rests: [RhythmLayoutRest] = [],
        controls: [RhythmLayoutControl] = []
    ) throws -> RhythmLayoutSnapshot {
        try RhythmLayoutSnapshot(
            ticksPerWholeNote: ticksPerWholeNote,
            measures: measures,
            notes: notes,
            controls: controls,
            rests: rests,
            feel: .straight
        )
    }

    private func makeNote(
        eventID: Int,
        noteType: NoteType,
        measureIndex: Int,
        localTick: Int,
        interval: NoteInterval
    ) -> RhythmLayoutNote {
        RhythmLayoutNote(
            eventID: RhythmEventID(rawValue: eventID),
            sourceLaneID: nil,
            sourceChipID: nil,
            noteType: noteType,
            position: RhythmEventPosition(
                measureIndex: measureIndex,
                localTick: localTick,
                absoluteTick: measureIndex * 960 + localTick
            ),
            durationTicks: durationTicks(of: interval),
            rhythm: NotationRhythm(baseInterval: interval),
            tupletID: nil
        )
    }

    private func durationTicks(of interval: NoteInterval) -> Int {
        switch interval {
        case .full: return ticksPerWholeNote
        case .half: return ticksPerWholeNote / 2
        case .quarter: return ticksPerWholeNote / 4
        case .eighth: return ticksPerWholeNote / 8
        case .sixteenth: return ticksPerWholeNote / 16
        case .thirtysecond: return ticksPerWholeNote / 32
        case .sixtyfourth: return ticksPerWholeNote / 64
        }
    }

    /// Measure 0 packs sixteen sixteenths so the formatter's collision rule
    /// widens it past the uniform TabGrid width; measure 1 holds a
    /// full-measure rest plus a stop control on the snare lane.
    private func makeCompositionRequest() throws -> GameplayNotationPreparationRequest {
        let measures = [makeMeasure(index: 0, startTick: 0), makeMeasure(index: 1, startTick: 960)]
        let sixteenths = (0..<16).map { index in
            makeNote(
                eventID: index + 1,
                noteType: .snare,
                measureIndex: 0,
                localTick: index * 60,
                interval: .sixteenth
            )
        }
        let rest = RhythmLayoutRest(
            position: RhythmEventPosition(measureIndex: 1, localTick: 0, absoluteTick: 960),
            durationTicks: 960,
            voice: .upper,
            rhythm: NotationRhythm(baseInterval: .full),
            visibility: .printed,
            tupletID: nil
        )
        let control = RhythmLayoutControl(
            eventID: RhythmEventID(rawValue: 100),
            event: NotationControlEvent(ChartControlEvent(
                kind: .stop,
                measureNumber: 2,
                measureOffset: 0.5,
                targetLaneID: "12"
            )),
            position: RhythmEventPosition(measureIndex: 1, localTick: 480, absoluteTick: 1440)
        )
        let snapshot = try makeSnapshot(
            measures: measures,
            notes: sixteenths,
            rests: [rest],
            controls: [control]
        )
        return GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: 2,
            style: .gameplayDefault,
            notePositionOverrides: [:]
        )
    }

    /// The `.ready` engraving out of a prepared state; preparation of these
    /// fixtures must never degrade to `.failed`.
    private func requireEngraved(
        _ prepared: GameplayNotationPreparedState
    ) throws -> EngravedNotation {
        try DrumTabFixtureHarness.requireEngraved(prepared)
    }

    // MARK: - Composition copying

    @Test("engraving copies package measure geometry verbatim")
    func compositionCopiesPackageMeasureGeometry() throws {
        let engraved = try requireEngraved(GameplayNotationPreparer.prepare(makeCompositionRequest()))

        #expect(engraved.measures.count == engraved.formatted.measures.count)
        for (measure, formattedMeasure) in zip(engraved.measures, engraved.formatted.measures) {
            #expect(measure.index == formattedMeasure.index)
            #expect(measure.rowIndex == formattedMeasure.rowIndex)
            #expect(measure.xOffset == formattedMeasure.xOffset)
            #expect(measure.width == formattedMeasure.width)
        }

        // The sixteenth measure's collision-driven package width exceeds the
        // uniform TabGrid width it used to carry (52 inset + 960 ticks ×
        // 200/960 = 252), proving the X source is the package.
        let sixteenthsMeasure = try #require(engraved.measures.first)
        #expect(sixteenthsMeasure.width > 252)
    }

    @Test("note heads take package headCenterX and staff-step Y")
    func noteHeadsTakePackageHeadCenterAndStaffStepY() throws {
        let engraved = try requireEngraved(GameplayNotationPreparer.prepare(makeCompositionRequest()))

        var centerXByID: [Int: CGFloat] = [:]
        for measure in engraved.formatted.measures {
            for column in measure.columns {
                for head in column.noteHeads {
                    centerXByID[head.noteID] = head.headCenterX
                }
            }
        }
        #expect(centerXByID.count == 16)

        let staffSpace = engraved.style.formatting.staffSpace
        for head in engraved.noteHeads {
            let centerX = try #require(centerXByID[head.noteID])
            #expect(head.position.x == centerX)
            // Package Y: pitch-ascending staff step around the row's
            // normalized staff center (step 4 = middle line).
            let row = try #require(engraved.rows.first { $0.index == head.rowIndex })
            #expect(head.position.y == row.staffCenterY - CGFloat(head.staffStep - 4) * staffSpace / 2)
        }
    }

    @Test("rests take the package visual X")
    func restsTakePackageVisualX() throws {
        let engraved = try requireEngraved(GameplayNotationPreparer.prepare(makeCompositionRequest()))

        var visualXByKey: [String: CGFloat] = [:]
        for measure in engraved.formatted.measures {
            for column in measure.columns {
                for rest in column.rests {
                    visualXByKey["\(measure.index)-\(column.localTick)"] = rest.visualX
                }
            }
        }
        // Every engraved rest is printed — hidden rests never cross into the
        // package input.
        let printedRest = try #require(engraved.rests.first { $0.measureIndex == 1 })
        let expectedX = try #require(visualXByKey["1-0"])
        #expect(printedRest.position.x == expectedX)
    }

    @Test("controls take the logical column X")
    func controlsTakeLogicalColumnX() throws {
        let engraved = try requireEngraved(GameplayNotationPreparer.prepare(makeCompositionRequest()))

        let controlColumn = try #require(
            engraved.formatted.measures
                .first { $0.index == 1 }?
                .columns
                .first { $0.localTick == 480 }
        )
        let stop = try #require(engraved.controls.first)
        #expect(stop.measureIndex == 1)
        #expect(stop.position.x == controlColumn.logicalColumnX)
    }

    @Test("measure bars span the package measure bounds")
    func measureBarsSpanPackageBounds() throws {
        let engraved = try requireEngraved(GameplayNotationPreparer.prepare(makeCompositionRequest()))

        for measure in engraved.measures {
            // A closing bar cites the measure it closes; a leading bar cites
            // the measure it opens — disambiguate by X.
            let endBar = try #require(
                engraved.measureBars.first {
                    $0.measureIndex == measure.index && $0.x == measure.xOffset + measure.width
                }
            )
            #expect(endBar.rowIndex == measure.rowIndex)

            let isFirstInRow = engraved.measures
                .first { $0.rowIndex == measure.rowIndex }?.index == measure.index
            if isFirstInRow {
                _ = try #require(
                    engraved.measureBars.first {
                        $0.measureIndex == measure.index && $0.x == measure.xOffset
                    }
                )
            }
        }
        #expect(engraved.measureBars.last?.isFinal == true)
    }

    @Test("engraved notation embeds the formatted notation for live lookup")
    func engravedNotationEmbedsFormattedNotation() throws {
        let engraved = try requireEngraved(GameplayNotationPreparer.prepare(makeCompositionRequest()))

        let onset = try #require(engraved.formatted.position(measureIndex: 0, localTick: 0))
        #expect(onset.rowIndex == engraved.measures[0].rowIndex)
        #expect(onset.x == engraved.formatted.measures[0].columns.first?.logicalColumnX)
    }
}

/// Task 5 Step 3 regression: a displaced-second chord keeps its shared stem
/// and beam axis on the undisplaced stem-side representative, in both stem
/// directions, while only the second head's ink moves.
@Suite("Displaced Second Stem Axis")
struct DisplacedSecondStemAxisTests {
    private func makeMeasure(index: Int, startTick: Int) -> RhythmMeasure {
        RhythmMeasure(
            measureIndex: index,
            startTick: startTick,
            durationTicks: 960,
            timeSignature: .fourFour,
            beatGroups: (0..<4).map {
                RhythmBeatGroup(groupIndex: $0, startTick: $0 * 240, durationTicks: 240, isResidual: false)
            },
            engravingSupport: .supported
        )
    }

    /// Two adjacent eighth-note chords (ticks 0 and 120, one beat group) of
    /// one stem direction so the pair beams; `overrides` is only needed for
    /// the down-stem adjacency.
    private func makeChordRequest(
        noteTypes: (stemSide: NoteType, displaced: NoteType),
        overrides: [DrumType: GameplayLayout.NotePosition]
    ) throws -> GameplayNotationPreparationRequest {
        let measure = makeMeasure(index: 0, startTick: 0)
        let notes = [
            (eventID: 1, noteType: noteTypes.stemSide, tick: 0),
            (eventID: 2, noteType: noteTypes.displaced, tick: 0),
            (eventID: 3, noteType: noteTypes.stemSide, tick: 120),
            (eventID: 4, noteType: noteTypes.displaced, tick: 120)
        ].map { entry in
            RhythmLayoutNote(
                eventID: RhythmEventID(rawValue: entry.eventID),
                sourceLaneID: nil,
                sourceChipID: nil,
                noteType: entry.noteType,
                position: RhythmEventPosition(
                    measureIndex: 0,
                    localTick: entry.tick,
                    absoluteTick: entry.tick
                ),
                durationTicks: 120,
                rhythm: NotationRhythm(baseInterval: .eighth),
                tupletID: nil
            )
        }
        let snapshot = try RhythmLayoutSnapshot(
            ticksPerWholeNote: 960,
            measures: [measure],
            notes: notes,
            controls: [],
            rests: [],
            feel: .straight
        )
        return GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: 1,
            style: .gameplayDefault,
            notePositionOverrides: overrides
        )
    }

    /// The `.ready` engraving out of a prepared state.
    private func requireEngraved(
        _ prepared: GameplayNotationPreparedState
    ) throws -> EngravedNotation {
        try DrumTabFixtureHarness.requireEngraved(prepared)
    }

    /// Bravura stem-anchor offset for an engraved head — the same metrics the
    /// package engraver uses to attach the shared stem.
    private func stemAnchorX(for head: EngravedNoteHead, engraved: EngravedNotation) -> CGFloat {
        PercussionGlyphMetrics.notehead(
            style: head.noteheadStyle,
            duration: head.duration,
            stemDirection: head.stemDirection,
            staffSpace: engraved.style.formatting.staffSpace
        ).stemAnchorOffset.x
    }

    @Test("up-stem second: stem and beam stay on the undisplaced lower head")
    func upStemSecondKeepsUndisplacedStemAxis() throws {
        // Snare (line3) + highTom (space 3-4): adjacent staff steps, both up.
        let engraved = try requireEngraved(GameplayNotationPreparer.prepare(
            makeChordRequest(noteTypes: (.snare, .highTom), overrides: [:])
        ))

        // One logical column carries both heads; only the upper (displaced)
        // head moves off `logicalColumnX`, to the right.
        let column = try #require(engraved.formatted.measures[0].columns.first { $0.localTick == 0 })
        #expect(Set(column.noteHeads.map(\.noteID)) == Set([1, 2]))
        let stemSidePackage = try #require(column.noteHeads.first { $0.noteID == 1 })
        let displacedPackage = try #require(column.noteHeads.first { $0.noteID == 2 })
        #expect(stemSidePackage.headCenterX == column.logicalColumnX)
        #expect(displacedPackage.headCenterX > column.logicalColumnX)

        let stemSideHead = try #require(engraved.noteHeads.first { $0.noteID == 1 })
        let displacedHead = try #require(engraved.noteHeads.first { $0.noteID == 2 })
        #expect(stemSideHead.position.x == column.logicalColumnX)
        #expect(displacedHead.position.x == displacedPackage.headCenterX)

        // The shared stem anchors on the undisplaced stem-side head.
        let stem = try #require(engraved.stems.first { $0.noteIDs.contains(1) })
        #expect(stem.start.x == stemSideHead.position.x + stemAnchorX(for: stemSideHead, engraved: engraved))
        #expect(stem.start.x != displacedHead.position.x + stemAnchorX(for: displacedHead, engraved: engraved))

        // Both heads touch or overlap the shared stem (pinned VexFlow rule).
        for head in [stemSideHead, displacedHead] {
            let bounds = head.paintedBounds
            #expect(bounds.minX <= stem.start.x + 0.001)
            #expect(bounds.maxX >= stem.start.x - 0.001)
        }

        // The beam endpoint shares that stem axis.
        let beam = try #require(
            engraved.beams.first { $0.noteIDs.contains(1) && $0.noteIDs.contains(2) }
        )
        let stemAtSecondChord = try #require(engraved.stems.first { $0.noteIDs.contains(3) })
        #expect(beam.start.x == stem.start.x)
        #expect(beam.end.x == stemAtSecondChord.start.x)

        // The playhead's logical onset stays on the undisplaced column axis.
        let onset = try #require(engraved.formatted.position(measureIndex: 0, localTick: 0))
        #expect(onset.x == column.logicalColumnX)
    }

    @Test("down-stem second: stem and beam stay on the undisplaced upper head")
    func downStemSecondKeepsUndisplacedStemAxis() throws {
        // Kick below line1 + hi-hat pedal in the space below line1: adjacent
        // staff steps, both down-stem, both lower voice.
        let engraved = try requireEngraved(GameplayNotationPreparer.prepare(
            makeChordRequest(
                noteTypes: (.hiHatPedal, .bass),
                overrides: [.kick: .belowLine1, .hiHatPedal: .spaceBetweenLine1AndBelow]
            )
        ))

        // One logical column; the lower (displaced) head shifts left while the
        // stem-side upper head stays put.
        let column = try #require(engraved.formatted.measures[0].columns.first { $0.localTick == 0 })
        #expect(Set(column.noteHeads.map(\.noteID)) == Set([1, 2]))
        let stemSidePackage = try #require(column.noteHeads.first { $0.noteID == 1 })
        let displacedPackage = try #require(column.noteHeads.first { $0.noteID == 2 })
        #expect(stemSidePackage.headCenterX == column.logicalColumnX)
        #expect(displacedPackage.headCenterX < column.logicalColumnX)

        let stemSideHead = try #require(engraved.noteHeads.first { $0.noteID == 1 })
        let displacedHead = try #require(engraved.noteHeads.first { $0.noteID == 2 })
        #expect(stemSideHead.position.x == column.logicalColumnX)
        #expect(displacedHead.position.x == displacedPackage.headCenterX)

        // The shared stem anchors on the undisplaced stem-side head.
        let stem = try #require(engraved.stems.first { $0.noteIDs.contains(1) })
        #expect(stem.start.x == stemSideHead.position.x + stemAnchorX(for: stemSideHead, engraved: engraved))
        #expect(stem.start.x != displacedHead.position.x + stemAnchorX(for: displacedHead, engraved: engraved))

        // Both heads touch or overlap the shared stem (pinned VexFlow rule).
        for head in [stemSideHead, displacedHead] {
            let bounds = head.paintedBounds
            #expect(bounds.minX <= stem.start.x + 0.001)
            #expect(bounds.maxX >= stem.start.x - 0.001)
        }

        // The beam endpoint shares that stem axis.
        let beam = try #require(
            engraved.beams.first { $0.noteIDs.contains(1) && $0.noteIDs.contains(2) }
        )
        let stemAtSecondChord = try #require(engraved.stems.first { $0.noteIDs.contains(3) })
        #expect(beam.start.x == stem.start.x)
        #expect(beam.end.x == stemAtSecondChord.start.x)

        // The playhead's logical onset stays on the undisplaced column axis.
        let onset = try #require(engraved.formatted.position(measureIndex: 0, localTick: 0))
        #expect(onset.x == column.logicalColumnX)
    }
}

/// Task 5 live-lookup wiring: the snapshot-driven playhead branch resolves
/// its X from the installed engraving's `position(measureIndex:localTick:)`
/// (the embedded formatter), never from the grid.
@Suite("Timeline Playhead Lookup", .serialized)
@MainActor
struct TimelinePlayheadLookupTests {
    @Test("timeline playhead resolves X from the installed formatted notation")
    func timelinePlayheadResolvesFromFormattedLookup() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)
        defer { viewModel.cleanup() }

        // The snapshot route installed the engraving (which embeds the
        // formatter output), so the playhead can resolve ticks against it.
        let engraved = try #require(viewModel.cachedEngravedNotation)
        let formatted = engraved.formatted
        #expect(!formatted.measures.isEmpty)

        viewModel.isPlaying = true
        viewModel.updateContinuousVisualsForTesting(elapsedTime: 0)
        let position = try #require(viewModel.purpleBarPosition)
        let expected = try #require(formatted.position(measureIndex: 0, localTick: 0))
        let row = try #require(engraved.rows.first { $0.index == expected.rowIndex })
        #expect(position.x == Double(expected.x))
        #expect(position.y == Double(row.staffCenterY))
    }
}
