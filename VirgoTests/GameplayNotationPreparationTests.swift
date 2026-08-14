import CoreGraphics
import Testing
@testable import Virgo

@Suite("Gameplay Notation Preparation")
struct GameplayNotationPreparationTests {
    @Test("request and prepared state are Sendable values")
    func requestAndPreparedStateAreSendableValues() {
        requireSendable(GameplayNotationPreparationRequest.self)
        requireSendable(GameplayNotationPreparedState.self)
    }

    @Test("timeline beat positions produce pinned coordinates across wrapped rows")
    func timelineBeatPositionsProducePinnedCoordinatesAcrossWrappedRows() throws {
        let snapshot = try makeSnapshot(
            measures: (0..<4).map { measureIndex in
                makeMeasure(
                    index: measureIndex,
                    startTick: measureIndex * 960,
                    durationTicks: 960
                )
            },
            notes: [
                makeNote(id: 1, measureIndex: 0, localTick: 480),
                makeNote(id: 2, measureIndex: 3, localTick: 240)
            ]
        )
        let request = GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: 4,
            style: .gameplayDefault,
            notePositionOverrides: [:],
            beatPositionsByID: [
                101: RhythmEventPosition(measureIndex: 0, localTick: 480, absoluteTick: 480),
                404: RhythmEventPosition(measureIndex: 3, localTick: 240, absoluteTick: 3_120)
            ]
        )

        let prepared = GameplayNotationPreparer.prepare(request)

        let first = try #require(prepared.beatPositionsByID[101])
        let wrapped = try #require(prepared.beatPositionsByID[404])
        #expect(prepared.layout.measures.first { $0.measureIndex == 0 }?.row == 0)
        #expect(prepared.layout.measures.first { $0.measureIndex == 3 }?.row == 1)
        #expect(first == CGPoint(x: 252, y: 150))
        #expect(wrapped == CGPoint(x: 202, y: 470))
    }

    @Test("timeline with no notes preserves printable renderable content")
    func timelineWithNoNotesPreservesPrintableRenderableContent() throws {
        let snapshot = try makeSnapshot(
            measures: [makeMeasure(index: 0, startTick: 0, durationTicks: 960)],
            rests: [RhythmLayoutRest(
                position: RhythmEventPosition(measureIndex: 0, localTick: 0, absoluteTick: 0),
                durationTicks: 960,
                voice: .upper,
                rhythm: NotationRhythm(baseInterval: .full),
                visibility: .printed,
                tupletID: nil
            )]
        )
        let request = GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: 1,
            style: .gameplayDefault,
            notePositionOverrides: [:],
            beatPositionsByID: [:]
        )

        let prepared = GameplayNotationPreparer.prepare(request)

        #expect(prepared.layout.noteHeads.isEmpty)
        #expect(!prepared.layout.hasPlayableContent)
        #expect(prepared.layout.hasRenderableContent)
        #expect(prepared.layout.rests.contains { $0.isPrinted })
        #expect(prepared.beatPositionsByID.isEmpty)
    }

    @Test("request and result expose no model identity fields")
    func requestAndResultExposeNoModelIdentityFields() throws {
        let snapshot = try makeSnapshot(
            measures: [makeMeasure(index: 0, startTick: 0, durationTicks: 960)]
        )
        let request = GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: 1,
            style: .gameplayDefault,
            notePositionOverrides: [:],
            beatPositionsByID: [:]
        )
        let prepared = GameplayNotationPreparer.prepare(request)

        let requestLabels = Set(Mirror(reflecting: request).children.compactMap(\.label))
        let resultLabels = Set(Mirror(reflecting: prepared).children.compactMap(\.label))
        let forbiddenLabels = [
            "model",
            "modelID",
            "objectID",
            "sourceObjectID",
            "sourceObjectIdentifier"
        ]

        for label in forbiddenLabels {
            #expect(!requestLabels.contains(label))
            #expect(!resultLabels.contains(label))
        }
    }

    private func requireSendable<T: Sendable>(_: T.Type) {}

    private func makeSnapshot(
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

    private func makeMeasure(index: Int, startTick: Int, durationTicks: Int) -> RhythmMeasure {
        RhythmMeasure(
            measureIndex: index,
            startTick: startTick,
            durationTicks: durationTicks,
            timeSignature: .fourFour,
            beatGroups: [RhythmBeatGroup(
                groupIndex: 0,
                startTick: 0,
                durationTicks: durationTicks,
                isResidual: false
            )],
            engravingSupport: .supported
        )
    }

    private func makeNote(id: Int, measureIndex: Int, localTick: Int) -> RhythmLayoutNote {
        RhythmLayoutNote(
            eventID: RhythmEventID(rawValue: id),
            sourceLaneID: "12",
            sourceChipID: "chip-\(id)",
            noteType: .snare,
            position: RhythmEventPosition(
                measureIndex: measureIndex,
                localTick: localTick,
                absoluteTick: measureIndex * 960 + localTick
            ),
            durationTicks: 240,
            rhythm: NotationRhythm(baseInterval: .quarter),
            tupletID: nil
        )
    }
}
