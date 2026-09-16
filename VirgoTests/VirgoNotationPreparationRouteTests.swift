import Testing
@testable import Virgo

/// HPA-164 Step 6/7: the one preparation route — synchronous and detached
/// invocation produce identical package geometry, and the prepared state
/// exposes the formatted output alongside the layout. Split from
/// `VirgoNotationProjectionTests` to stay under SwiftLint's file-length
/// limit.
@Suite("Virgo Notation Preparation Route")
struct VirgoNotationPreparationRouteTests {
    private let ticksPerWholeNote = 960

    @Test("Synchronous and detached preparation produce identical package geometry")
    func synchronousAndDetachedPreparationAgree() async throws {
        let request = try makeMultiMeasureRequest(measureCount: 4)

        let synchronous = GameplayNotationPreparer.prepare(request)
        let detached = try await Task.detached {
            GameplayNotationPreparer.prepare(request)
        }.value

        let (syncEngraved, _) = try NotationSnapshotTestSupport().requireReady(synchronous)
        let (detachedEngraved, _) = try NotationSnapshotTestSupport().requireReady(detached)

        // Identical package measure geometry.
        #expect(syncEngraved.formatted == detachedEngraved.formatted)
        #expect(!syncEngraved.formatted.measures.isEmpty)

        // Row-leading origin: the first measure of every row starts at the
        // leading inset.
        var firstMeasureXPerRow: [Int: CGFloat] = [:]
        for measure in syncEngraved.formatted.measures
        where firstMeasureXPerRow[measure.rowIndex] == nil {
            firstMeasureXPerRow[measure.rowIndex] = measure.xOffset
        }
        #expect(!firstMeasureXPerRow.isEmpty)
        for (_, x) in firstMeasureXPerRow {
            #expect(x == GameplayLayout.leftMargin)
        }

        // Logical tick lookup identical between the two routes, including a
        // between-anchor interpolation.
        for measure in syncEngraved.formatted.measures {
            for column in measure.columns {
                #expect(
                    syncEngraved.formatted.position(measureIndex: measure.index, localTick: Double(column.localTick))
                        == detachedEngraved.formatted.position(
                            measureIndex: measure.index,
                            localTick: Double(column.localTick)
                        )
                )
            }
            let midpoint = Double(measure.columns.first?.localTick ?? 0) + 60
            #expect(
                syncEngraved.formatted.position(measureIndex: measure.index, localTick: midpoint)
                    == detachedEngraved.formatted.position(measureIndex: measure.index, localTick: midpoint)
            )
        }
    }

    @Test("The one route installs the formatted output alongside the engraving")
    func preparedStateExposesFormattedOutput() throws {
        let request = try makeMultiMeasureRequest(measureCount: 2)
        let prepared = GameplayNotationPreparer.prepare(request)

        let (engraved, _) = try NotationSnapshotTestSupport().requireReady(prepared)
        #expect(engraved.measures.map(\.index) == engraved.formatted.measures.map(\.index))
    }

    // MARK: - Fixtures

    /// Four-beat 4/4 measure at 960 ticks/whole-note: quarter = 240 ticks.
    private func makeMeasure(index: Int, startTick: Int = 0) -> RhythmMeasure {
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
        notes: [RhythmLayoutNote] = [],
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
        absoluteTick: Int? = nil,
        interval: NoteInterval,
        dotCount: Int = 0
    ) -> RhythmLayoutNote {
        RhythmLayoutNote(
            eventID: RhythmEventID(rawValue: eventID),
            sourceLaneID: nil,
            sourceChipID: nil,
            noteType: noteType,
            position: RhythmEventPosition(
                measureIndex: measureIndex,
                localTick: localTick,
                absoluteTick: absoluteTick ?? measureIndex * 960 + localTick
            ),
            durationTicks: durationTicks(of: interval),
            rhythm: NotationRhythm(baseInterval: interval, dotCount: dotCount),
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

    /// A multi-measure request whose measures wrap across several rows at the
    /// 900pt floor, so row-leading origin checks are meaningful.
    private func makeMultiMeasureRequest(measureCount: Int) throws -> GameplayNotationPreparationRequest {
        let measures = (0..<measureCount).map { index in
            makeMeasure(index: index, startTick: index * 960)
        }
        let notes = (0..<measureCount).flatMap { measureIndex -> [RhythmLayoutNote] in
            [0, 240, 480, 720].map { tick in
                makeNote(
                    eventID: measureIndex * 4 + tick / 240 + 1,
                    noteType: .snare,
                    measureIndex: measureIndex,
                    localTick: tick,
                    absoluteTick: measureIndex * 960 + tick,
                    interval: .quarter
                )
            }
        }
        let snapshot = try makeSnapshot(measures: measures, notes: notes)
        return GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: measureCount,
            style: .gameplayDefault,
            notePositionOverrides: [:]
        )
    }
}
