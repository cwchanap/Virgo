import CoreGraphics
import DrumNotation
import Testing
@testable import Virgo

/// HPA-164 Task 5: `composeVirgoLayout` copies package geometry straight from
/// `FormattedNotation` — measure rows/bounds, head centers, rest and control
/// X, measure bars — while stems and beams stay on the undisplaced stem-side
/// representative.
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

    // MARK: - Composition copying

    @Test("composition copies package measure geometry verbatim")
    func compositionCopiesPackageMeasureGeometry() throws {
        let prepared = try GameplayNotationPreparer.prepare(makeCompositionRequest())

        #expect(prepared.layout.measures.count == prepared.formatted.measures.count)
        for (measure, packageMeasure) in zip(prepared.layout.measures, prepared.formatted.measures) {
            #expect(measure.measureIndex == packageMeasure.index)
            #expect(measure.row == packageMeasure.rowIndex)
            #expect(measure.xOffset == packageMeasure.xOffset)
            #expect(measure.width == packageMeasure.width)
        }

        // The sixteenth measure's collision-driven package width exceeds the
        // uniform TabGrid width it used to carry (52 inset + 960 ticks ×
        // 200/960 = 252), proving the X source switched to the package.
        let sixteenthsMeasure = try #require(prepared.layout.measures.first)
        #expect(sixteenthsMeasure.width > 252)
    }

    @Test("note heads take package headCenterX and keep Virgo staff Y")
    func noteHeadsTakePackageHeadCenterXAndKeepVirgoY() throws {
        let prepared = try GameplayNotationPreparer.prepare(makeCompositionRequest())

        var centerXByID: [UInt64: CGFloat] = [:]
        for measure in prepared.formatted.measures {
            for column in measure.columns {
                for head in column.noteHeads {
                    centerXByID[UInt64(head.noteID)] = head.headCenterX
                }
            }
        }
        #expect(centerXByID.count == 16)

        for head in prepared.layout.noteHeads {
            let centerX = try #require(centerXByID[head.id])
            #expect(head.position.x == centerX)
            let expectedY = GameplayLayout.StaffLinePosition.line1.absoluteY(for: head.row)
                + DrumType.snare.notePosition.yOffset
            #expect(head.position.y == expectedY)
        }
    }

    @Test("rests take the package visual X")
    func restsTakePackageVisualX() throws {
        let prepared = try GameplayNotationPreparer.prepare(makeCompositionRequest())

        var visualXByKey: [String: CGFloat] = [:]
        for measure in prepared.formatted.measures {
            for column in measure.columns {
                if let rest = column.rest {
                    visualXByKey["\(measure.index)-\(column.localTick)"] = rest.visualX
                }
            }
        }
        let printedRest = try #require(prepared.layout.rests.first { $0.isPrinted })
        let expectedX = try #require(visualXByKey["1-0"])
        #expect(printedRest.position.x == expectedX)
    }

    @Test("controls take the logical column X")
    func controlsTakeLogicalColumnX() throws {
        let prepared = try GameplayNotationPreparer.prepare(makeCompositionRequest())

        let controlColumn = try #require(
            prepared.formatted.measures
                .first { $0.index == 1 }?
                .columns
                .first { $0.localTick == 480 }
        )
        let stop = try #require(prepared.layout.stopNotes.first)
        #expect(stop.timeColumn.measureIndex == 1)
        #expect(stop.position.x == controlColumn.logicalColumnX)
    }

    @Test("measure bars span the package measure bounds")
    func measureBarsSpanPackageBounds() throws {
        let prepared = try GameplayNotationPreparer.prepare(makeCompositionRequest())
        let layout = prepared.layout

        for measure in layout.measures {
            let endBar = try #require(
                layout.measureBars.first { $0.id == "bar_\(measure.measureIndex)_end" }
            )
            #expect(endBar.row == measure.row)
            #expect(endBar.x == measure.xOffset + measure.width)

            let isFirstInRow = layout.measures
                .first { $0.row == measure.row }?.measureIndex == measure.measureIndex
            if isFirstInRow {
                let startBar = try #require(
                    layout.measureBars.first { $0.id == "bar_\(measure.measureIndex)" }
                )
                #expect(startBar.x == measure.xOffset)
            }
        }
        #expect(layout.measureBars.last?.isFinal == true)
    }

    @Test("installed layout embeds the formatted notation for live lookup")
    func installedLayoutEmbedsFormattedNotation() throws {
        let prepared = try GameplayNotationPreparer.prepare(makeCompositionRequest())

        #expect(prepared.layout.formattedNotation == prepared.formatted)
        let onset = try #require(prepared.layout.formattedNotation.position(measureIndex: 0, localTick: 0))
        #expect(onset.rowIndex == prepared.layout.measures[0].row)
        #expect(onset.x == prepared.formatted.measures[0].columns.first?.logicalColumnX)
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

    @Test("up-stem second: stem and beam stay on the undisplaced lower head")
    func upStemSecondKeepsUndisplacedStemAxis() throws {
        // Snare (line3) + highTom (space 3-4): adjacent staff steps, both up.
        let prepared = try GameplayNotationPreparer.prepare(
            makeChordRequest(noteTypes: (.snare, .highTom), overrides: [:])
        )

        // One logical column carries both heads; only the upper (displaced)
        // head moves off `logicalColumnX`, to the right.
        let column = try #require(prepared.formatted.measures[0].columns.first { $0.localTick == 0 })
        #expect(Set(column.noteHeads.map(\.noteID)) == Set([1, 2]))
        let stemSidePackage = try #require(column.noteHeads.first { $0.noteID == 1 })
        let displacedPackage = try #require(column.noteHeads.first { $0.noteID == 2 })
        #expect(stemSidePackage.headCenterX == column.logicalColumnX)
        #expect(displacedPackage.headCenterX > column.logicalColumnX)

        let stemSideHead = try #require(prepared.layout.noteHeads.first { $0.id == 1 })
        let displacedHead = try #require(prepared.layout.noteHeads.first { $0.id == 2 })
        #expect(stemSideHead.position.x == column.logicalColumnX)
        #expect(displacedHead.position.x == displacedPackage.headCenterX)

        // The shared stem anchors on the undisplaced stem-side head.
        let stem = try #require(prepared.layout.stems.first { $0.noteHeadIDs.contains(1) })
        let stemSideAnchor = VirgoNotationAdapter
            .noteheadMetrics(for: stemSideHead, style: .gameplayDefault).stemAnchorOffset
        #expect(stem.start.x == stemSideHead.position.x + stemSideAnchor.x)
        let displacedAnchor = VirgoNotationAdapter
            .noteheadMetrics(for: displacedHead, style: .gameplayDefault).stemAnchorOffset
        #expect(stem.start.x != displacedHead.position.x + displacedAnchor.x)

        // Both heads touch or overlap the shared stem (pinned VexFlow rule).
        for head in [stemSideHead, displacedHead] {
            let bounds = VirgoNotationAdapter
                .noteheadMetrics(for: head, style: .gameplayDefault).paintedBounds
                .offsetBy(dx: head.position.x, dy: head.position.y)
            // Guarded by a tolerance: offsetBy rounding can miss by one ULP.
            #expect(bounds.minX <= stem.start.x + 0.001)
            #expect(bounds.maxX >= stem.start.x - 0.001)
        }

        // The beam endpoint shares that stem axis.
        let beam = try #require(
            prepared.layout.beams.first { $0.noteHeadIDs.contains(1) && $0.noteHeadIDs.contains(2) }
        )
        let stemAtSecondChord = try #require(prepared.layout.stems.first { $0.noteHeadIDs.contains(3) })
        #expect(beam.start.x == stem.start.x)
        #expect(beam.end.x == stemAtSecondChord.start.x)

        // The playhead's logical onset stays on the undisplaced column axis.
        let onset = try #require(prepared.formatted.position(measureIndex: 0, localTick: 0))
        #expect(onset.x == column.logicalColumnX)
    }

    @Test("down-stem second: stem and beam stay on the undisplaced upper head")
    func downStemSecondKeepsUndisplacedStemAxis() throws {
        // Kick below line1 + hi-hat pedal in the space below line1: adjacent
        // staff steps, both down-stem, both lower voice.
        let prepared = try GameplayNotationPreparer.prepare(
            makeChordRequest(
                noteTypes: (.hiHatPedal, .bass),
                overrides: [.kick: .belowLine1, .hiHatPedal: .spaceBetweenLine1AndBelow]
            )
        )

        // One logical column; the lower (displaced) head shifts left while the
        // stem-side upper head stays put.
        let column = try #require(prepared.formatted.measures[0].columns.first { $0.localTick == 0 })
        #expect(Set(column.noteHeads.map(\.noteID)) == Set([1, 2]))
        let stemSidePackage = try #require(column.noteHeads.first { $0.noteID == 1 })
        let displacedPackage = try #require(column.noteHeads.first { $0.noteID == 2 })
        #expect(stemSidePackage.headCenterX == column.logicalColumnX)
        #expect(displacedPackage.headCenterX < column.logicalColumnX)

        let stemSideHead = try #require(prepared.layout.noteHeads.first { $0.id == 1 })
        let displacedHead = try #require(prepared.layout.noteHeads.first { $0.id == 2 })
        #expect(stemSideHead.position.x == column.logicalColumnX)
        #expect(displacedHead.position.x == displacedPackage.headCenterX)

        // The shared stem anchors on the undisplaced stem-side head.
        let stem = try #require(prepared.layout.stems.first { $0.noteHeadIDs.contains(1) })
        let stemSideAnchor = VirgoNotationAdapter
            .noteheadMetrics(for: stemSideHead, style: .gameplayDefault).stemAnchorOffset
        #expect(stem.start.x == stemSideHead.position.x + stemSideAnchor.x)
        let displacedAnchor = VirgoNotationAdapter
            .noteheadMetrics(for: displacedHead, style: .gameplayDefault).stemAnchorOffset
        #expect(stem.start.x != displacedHead.position.x + displacedAnchor.x)

        // Both heads touch or overlap the shared stem (pinned VexFlow rule).
        for head in [stemSideHead, displacedHead] {
            let bounds = VirgoNotationAdapter
                .noteheadMetrics(for: head, style: .gameplayDefault).paintedBounds
                .offsetBy(dx: head.position.x, dy: head.position.y)
            // Guarded by a tolerance: offsetBy rounding can miss by one ULP.
            #expect(bounds.minX <= stem.start.x + 0.001)
            #expect(bounds.maxX >= stem.start.x - 0.001)
        }

        // The beam endpoint shares that stem axis.
        let beam = try #require(
            prepared.layout.beams.first { $0.noteHeadIDs.contains(1) && $0.noteHeadIDs.contains(2) }
        )
        let stemAtSecondChord = try #require(prepared.layout.stems.first { $0.noteHeadIDs.contains(3) })
        #expect(beam.start.x == stem.start.x)
        #expect(beam.end.x == stemAtSecondChord.start.x)

        // The playhead's logical onset stays on the undisplaced column axis.
        let onset = try #require(prepared.formatted.position(measureIndex: 0, localTick: 0))
        #expect(onset.x == column.logicalColumnX)
    }
}

/// Task 5 live-lookup wiring: the snapshot-driven playhead branch resolves
/// its X from the installed `formattedNotation`, never from the grid.
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

        // The snapshot route installed the formatter output alongside the
        // layout, so the playhead can resolve ticks against it.
        let formatted = viewModel.cachedNotationLayout.formattedNotation
        #expect(!formatted.measures.isEmpty)

        viewModel.isPlaying = true
        viewModel.updateContinuousVisualsForTesting(elapsedTime: 0)
        let position = try #require(viewModel.purpleBarPosition)
        let expected = try #require(formatted.position(measureIndex: 0, localTick: 0))
        #expect(position.x == Double(expected.x))
        #expect(position.y == Double(GameplayLayout.StaffLinePosition.line3.absoluteY(for: expected.rowIndex)))
    }
}
