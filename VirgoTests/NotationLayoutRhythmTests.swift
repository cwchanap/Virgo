import Testing
@testable import Virgo

@Suite("Notation Layout Rhythm Tests")
struct NotationLayoutRhythmTests {
    /// The one preparation route (HPA-164): layouts compose from the
    /// measured formatter output.
    private func preparedLayout(
        _ snapshot: RhythmLayoutSnapshot,
        minimumMeasureCount: Int = 1,
        style: NotationLayoutStyle = .gameplayDefault
    ) -> GameplayNotationPreparedState {
        GameplayNotationPreparer.prepare(GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: minimumMeasureCount,
            style: style,
            notePositionOverrides: [:]
        ))
    }

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

        #expect(snapshot.ticksPerWholeNote == 960)
    }

    @Test("timeline positions notes controls and rests on formatted columns")
    func timelineUsesExactSnapshotPositions() throws {
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

        let prepared = preparedLayout(snapshot)
        let layout = prepared.layout
        let head = try #require(layout.noteHeads.first)
        let stop = try #require(layout.stopNotes.first)
        let rest = try #require(layout.rests.first { $0.voice == .upper && $0.isPrinted })
        let noteColumn = try #require(
            prepared.formatted.measures
                .first { $0.index == 0 }?
                .columns
                .first { $0.localTick == 120 }
        )
        let restColumn = try #require(
            prepared.formatted.measures
                .first { $0.index == 0 }?
                .columns
                .first { $0.localTick == 240 }
        )

        #expect(head.eventID == RhythmEventID(rawValue: 41))
        #expect(head.rhythmPosition == notePosition)
        #expect(head.rhythm == noteRhythm)
        #expect(head.interval == .eighth)
        #expect(stop.eventID == RhythmEventID(rawValue: 42))
        #expect(stop.rhythmPosition == notePosition)
        #expect(rest.rhythmPosition == restPosition)
        #expect(rest.rhythm == restRhythm)
        // The undisplaced head, the control, and the playhead lookup share
        // the logical column X; the printed rest takes the package visual X.
        #expect(head.position.x == noteColumn.logicalColumnX)
        #expect(stop.position.x == head.position.x)
        #expect(
            prepared.formatted.position(measureIndex: 0, localTick: 120)?.x == noteColumn.logicalColumnX
        )
        #expect(rest.position.x == restColumn.rest?.visualX)
    }

    @Test("timeline minimum count extends from resolved cumulative measures")
    func timelineMinimumCountExtendsResolvedMeasures() throws {
        let pickup = rhythmMeasure(
            index: 0,
            startTick: 0,
            durationTicks: 720,
            groupDurationTicks: 240
        )
        let layout = preparedLayout(
            try emptySnapshot(measures: [pickup]),
            minimumMeasureCount: 3
        ).layout

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
        let layout = preparedLayout(try emptySnapshot(measures: [measure], notes: notes)).layout
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
        let prepared = preparedLayout(try emptySnapshot(measures: [measure], notes: notes))
        let layout = prepared.layout
        let heads = layout.noteHeads.sorted { $0.timeColumn.absoluteLayoutTick < $1.timeColumn.absoluteLayoutTick }
        let first = try #require(heads.first)
        let last = try #require(heads.last)
        let beam = try #require(layout.beams.first { $0.kind == .full })
        let engine = NotationLayoutEngine()

        // The playhead's event-tick lookup and the undisplaced heads agree
        // on X; the beam endpoints anchor on those same head stem axes.
        let firstOnset = try #require(prepared.formatted.position(measureIndex: 0, localTick: 0))
        let lastOnset = try #require(prepared.formatted.position(measureIndex: 0, localTick: 120))
        #expect(first.position.x == firstOnset.x)
        #expect(last.position.x == lastOnset.x)
        #expect(beam.start.x == engine.stemAnchor(for: first, style: .gameplayDefault).x)
        #expect(beam.end.x == engine.stemAnchor(for: last, style: .gameplayDefault).x)
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
        return RhythmLayoutNote(
            eventID: RhythmEventID(rawValue: id),
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
