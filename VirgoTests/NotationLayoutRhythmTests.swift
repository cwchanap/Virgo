import Testing
@testable import Virgo

@Suite("Notation Layout Rhythm Tests")
struct NotationLayoutRhythmTests {
    @Test("timeline snapshot requires an explicit positive whole-note quantum")
    func snapshotRequiresPositiveWholeNoteQuantum() throws {
        let measure = rhythmMeasure(
            index: 0,
            startTick: 0,
            durationTicks: 720,
            groupDurationTicks: 240
        )

        #expect(throws: RhythmMetadataValidationError.invalidTicksPerWholeNote) {
            _ = try RhythmLayoutSnapshot(
                ticksPerWholeNote: 0,
                measures: [measure],
                notes: [],
                controls: [],
                rests: [],
                feel: .straight
            )
        }

        let snapshot = try RhythmLayoutSnapshot(
            ticksPerWholeNote: 960,
            measures: [measure],
            notes: [],
            controls: [],
            rests: [],
            feel: .straight
        )
        let input = NotationLayoutInput(timing: .timeline(snapshot))

        #expect(snapshot.ticksPerWholeNote == 960)
        #expect(input.minimumMeasureCount == 1)
        guard case let .timeline(captured) = input.timing else {
            Issue.record("Expected timeline input")
            return
        }
        #expect(captured == snapshot)
    }

    @Test("timeline positions notes controls and rests without consulting legacy fractions")
    func timelineUsesExactSnapshotPositions() throws {
        let sourceNote = Note(
            interval: .full,
            noteType: .snare,
            measureNumber: 99,
            measureOffset: 0.99
        )
        let control = NotationControlEvent(ChartControlEvent(
            kind: .stop,
            measureNumber: 88,
            measureOffset: 0.88,
            targetLaneID: "1A"
        ))
        let notePosition = RhythmEventPosition(measureIndex: 0, localTick: 120, absoluteTick: 120)
        let restPosition = RhythmEventPosition(measureIndex: 0, localTick: 240, absoluteTick: 240)
        let noteRhythm = NotationRhythm(baseInterval: .eighth)
        let restRhythm = NotationRhythm(baseInterval: .half)
        let snapshot = try RhythmLayoutSnapshot(
            ticksPerWholeNote: 960,
            measures: [rhythmMeasure(
                index: 0,
                startTick: 0,
                durationTicks: 720,
                groupDurationTicks: 240
            )],
            notes: [RhythmLayoutNote(
                eventID: RhythmEventID(rawValue: 41),
                sourceObjectID: ObjectIdentifier(sourceNote),
                sourceLaneID: "1A",
                sourceChipID: "chip-note",
                noteType: .snare,
                position: notePosition,
                durationTicks: 120,
                rhythm: noteRhythm,
                tupletID: nil
            )],
            controls: [RhythmLayoutControl(
                eventID: RhythmEventID(rawValue: 42),
                event: control,
                position: notePosition
            )],
            rests: [RhythmLayoutRest(
                position: restPosition,
                durationTicks: 480,
                voice: .upper,
                rhythm: restRhythm,
                visibility: .printed,
                tupletID: nil
            )],
            feel: .straight
        )

        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(timing: .timeline(snapshot))
        )
        let measure = try #require(layout.measures.first)
        let head = try #require(layout.noteHeads.first)
        let stop = try #require(layout.stopNotes.first)
        let rest = try #require(layout.rests.first { $0.voice == .upper && $0.isPrinted })

        #expect(layout.tabGrid.ticksPerWholeNote == 960)
        #expect(measure.startTick == 0)
        #expect(measure.durationTicks == 720)
        #expect(head.eventID == RhythmEventID(rawValue: 41))
        #expect(head.rhythmPosition == notePosition)
        #expect(head.rhythm == noteRhythm)
        #expect(head.interval == .eighth)
        #expect(stop.eventID == RhythmEventID(rawValue: 42))
        #expect(stop.rhythmPosition == notePosition)
        #expect(rest.rhythmPosition == restPosition)
        #expect(rest.rhythm == restRhythm)
        #expect(head.position.x == layout.tabGrid.xPosition(in: measure, localTick: 120))
        #expect(stop.position.x == head.position.x)
        #expect(rest.position.x == layout.tabGrid.xPosition(in: measure, localTick: 240))
    }

    @Test("timeline grid clamps local queries at each measure boundary")
    func timelineGridClampsPerMeasure() throws {
        let snapshot = try RhythmLayoutSnapshot(
            ticksPerWholeNote: 960,
            measures: [rhythmMeasure(
                index: 0,
                startTick: 0,
                durationTicks: 720,
                groupDurationTicks: 240
            )],
            notes: [],
            controls: [],
            rests: [],
            feel: .straight
        )
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(timing: .timeline(snapshot))
        )
        let measure = try #require(layout.measures.first)
        let startX = measure.contentStartX
        let endX = startX + CGFloat(measure.durationTicks) * layout.tabGrid.tickWidth

        #expect(layout.tabGrid.xPosition(in: measure, localTick: -1) == startX)
        #expect(layout.tabGrid.xPosition(in: measure, localTick: measure.durationTicks) == endX)
        #expect(layout.tabGrid.xPosition(in: measure, localTick: measure.durationTicks + 1) == endX)
        #expect(measure.width == layout.tabGrid.leftPadding + CGFloat(720) * layout.tabGrid.tickWidth)
    }

    @Test("variable measure spans scale proportionally and pack by pixel claim")
    func variableMeasureWidthsAndRowPacking() throws {
        let variableMeasures = [
            rhythmMeasure(index: 0, startTick: 0, durationTicks: 720, groupDurationTicks: 240),
            rhythmMeasure(index: 1, startTick: 720, durationTicks: 960, groupDurationTicks: 240),
            rhythmMeasure(index: 2, startTick: 1_680, durationTicks: 1_440, groupDurationTicks: 240)
        ]
        let equalMeasures = [
            rhythmMeasure(index: 0, startTick: 0, durationTicks: 960, groupDurationTicks: 240),
            rhythmMeasure(index: 1, startTick: 960, durationTicks: 960, groupDurationTicks: 240),
            rhythmMeasure(index: 2, startTick: 1_920, durationTicks: 960, groupDurationTicks: 240)
        ]
        let style = NotationLayoutStyle.gameplayDefault.with(rowWidth: 600)
        let variable = NotationLayoutEngine().layout(input: NotationLayoutInput(
            timing: .timeline(try emptySnapshot(measures: variableMeasures)),
            style: style
        ))
        let equal = NotationLayoutEngine().layout(input: NotationLayoutInput(
            timing: .timeline(try emptySnapshot(measures: equalMeasures)),
            style: style
        ))
        let short = variable.measures[0].width - variable.tabGrid.leftPadding
        let normal = variable.measures[1].width - variable.tabGrid.leftPadding
        let extended = variable.measures[2].width - variable.tabGrid.leftPadding

        #expect(abs(short / normal - 0.75) < 0.000_001)
        #expect(abs(extended / normal - 1.5) < 0.000_001)
        #expect(Set(equal.measures.map(\.width)).count == 1)
        #expect(variable.measures.map(\.row) == [0, 0, 1])
        #expect(equal.measures.map(\.row) == [0, 0, 0])

        for measure in variable.measures {
            let endBar = try #require(
                variable.measureBars.first { $0.id == "bar_\(measure.measureIndex)_end" }
            )
            #expect(endBar.x == variable.tabGrid.xPosition(
                in: measure,
                localTick: measure.durationTicks
            ))
        }
    }

    @Test("timeline minimum count extends from resolved cumulative measures")
    func timelineMinimumCountExtendsResolvedMeasures() throws {
        let pickup = rhythmMeasure(
            index: 0,
            startTick: 0,
            durationTicks: 720,
            groupDurationTicks: 240
        )
        let layout = NotationLayoutEngine().layout(input: NotationLayoutInput(
            timing: .timeline(try emptySnapshot(measures: [pickup])),
            minimumMeasureCount: 3
        ))

        #expect(layout.measures.map(\.measureIndex) == [0, 1, 2])
        #expect(layout.measures.map(\.startTick) == [0, 720, 1_680])
        #expect(layout.measures.map(\.durationTicks) == [720, 960, 960])
    }

    @Test("adjacent exact ticks remain distinct timeline columns")
    func adjacentExactTicksDoNotCollide() throws {
        let measure = rhythmMeasure(
            index: 0,
            startTick: 0,
            durationTicks: 960,
            groupDurationTicks: 240
        )
        let notes = [
            layoutNote(id: 1, tick: 1, interval: .sixtyfourth, durationTicks: 15),
            layoutNote(id: 2, tick: 2, interval: .sixtyfourth, durationTicks: 15)
        ]
        let layout = NotationLayoutEngine().layout(input: NotationLayoutInput(
            timing: .timeline(try emptySnapshot(measures: [measure], notes: notes))
        ))
        let positions = layout.noteHeads.map(\.position.x).sorted()

        #expect(positions.count == 2)
        #expect(positions[1] > positions[0])
    }

    @Test("timeline beam endpoints and playhead input share notehead x production")
    func beamAndPlayheadCoordinateShareTimelineGrid() throws {
        let measure = rhythmMeasure(
            index: 0,
            startTick: 0,
            durationTicks: 960,
            groupDurationTicks: 240
        )
        let notes = [
            layoutNote(id: 1, tick: 0, interval: .eighth, durationTicks: 120),
            layoutNote(id: 2, tick: 120, interval: .eighth, durationTicks: 120)
        ]
        let layout = NotationLayoutEngine().layout(input: NotationLayoutInput(
            timing: .timeline(try emptySnapshot(measures: [measure], notes: notes))
        ))
        let renderedMeasure = try #require(layout.measures.first)
        let heads = layout.noteHeads.sorted { $0.timeColumn.absoluteLayoutTick < $1.timeColumn.absoluteLayoutTick }
        let first = try #require(heads.first)
        let last = try #require(heads.last)
        let beam = try #require(layout.beams.first { $0.kind == .full })
        let playheadInputX = layout.tabGrid.xPosition(
            in: renderedMeasure,
            localTick: last.timeColumn.tickWithinMeasure
        )
        let engine = NotationLayoutEngine()

        #expect(first.position.x == layout.tabGrid.xPosition(in: renderedMeasure, localTick: 0))
        #expect(last.position.x == playheadInputX)
        #expect(beam.start.x == engine.stemAnchor(for: first, style: .gameplayDefault).x)
        #expect(beam.end.x == engine.stemAnchor(for: last, style: .gameplayDefault).x)
    }

    @Test("semantic rests do not change the note-column scale")
    func restsDoNotInflateTimelineTickWidth() throws {
        let measure = rhythmMeasure(
            index: 0,
            startTick: 0,
            durationTicks: 960,
            groupDurationTicks: 240
        )
        let notes = [
            layoutNote(id: 1, tick: 0, interval: .quarter, durationTicks: 240),
            layoutNote(id: 2, tick: 240, interval: .quarter, durationTicks: 240)
        ]
        let baseline = NotationLayoutEngine().layout(input: NotationLayoutInput(
            timing: .timeline(try emptySnapshot(measures: [measure], notes: notes))
        ))
        let withDenseRest = NotationLayoutEngine().layout(input: NotationLayoutInput(
            timing: .timeline(try emptySnapshot(
                measures: [measure],
                notes: notes,
                rests: [RhythmLayoutRest(
                    position: RhythmEventPosition(measureIndex: 0, localTick: 1, absoluteTick: 1),
                    durationTicks: 1,
                    voice: .lower,
                    rhythm: NotationRhythm(baseInterval: .sixtyfourth),
                    visibility: .hiddenSpacing,
                    tupletID: nil
                )]
            ))
        ))

        #expect(withDenseRest.tabGrid.tickWidth == baseline.tabGrid.tickWidth)
    }

    private func rhythmMeasure(
        index: Int,
        startTick: Int,
        durationTicks: Int,
        groupDurationTicks: Int
    ) -> RhythmMeasure {
        RhythmMeasure(
            measureIndex: index,
            startTick: startTick,
            durationTicks: durationTicks,
            timeSignature: .fourFour,
            beatGroups: stride(from: 0, to: durationTicks, by: groupDurationTicks).enumerated().map {
                RhythmBeatGroup(
                    groupIndex: $0.offset,
                    startTick: $0.element,
                    durationTicks: min(groupDurationTicks, durationTicks - $0.element),
                    isResidual: durationTicks - $0.element < groupDurationTicks
                )
            },
            engravingSupport: .supported
        )
    }

    private func emptySnapshot(
        measures: [RhythmMeasure],
        notes: [RhythmLayoutNote] = [],
        rests: [RhythmLayoutRest] = []
    ) throws -> RhythmLayoutSnapshot {
        try RhythmLayoutSnapshot(
            ticksPerWholeNote: 960,
            measures: measures,
            notes: notes,
            controls: [],
            rests: rests,
            feel: .straight
        )
    }

    private func layoutNote(
        id: Int,
        tick: Int,
        interval: NoteInterval,
        durationTicks: Int
    ) -> RhythmLayoutNote {
        let source = Note(
            interval: .full,
            noteType: .snare,
            measureNumber: 99,
            measureOffset: 0.99
        )
        return RhythmLayoutNote(
            eventID: RhythmEventID(rawValue: id),
            sourceObjectID: ObjectIdentifier(source),
            sourceLaneID: "1A",
            sourceChipID: "chip-\(id)",
            noteType: .snare,
            position: RhythmEventPosition(measureIndex: 0, localTick: tick, absoluteTick: tick),
            durationTicks: durationTicks,
            rhythm: NotationRhythm(baseInterval: interval),
            tupletID: nil
        )
    }
}
