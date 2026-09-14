import Testing
import CoreGraphics
@testable import Virgo

/// HPA-164 Task 6 Step 5: composed-layout regression invariants, asserted
/// against the measured formatter's output as rendered by
/// `GameplayNotationPreparer.prepare` (not just package output).
///
/// Binding numbers from the controller ruling: the vendored Bravura X-black
/// head paints 23.2pt (half 11.6), so adjacent sixteenth pitch is
/// 11.6 + 8 + 11.6 = 31.2pt and a 16-sixteenth 4/4 measure spans
/// 52 + 15 × 31.2 + 19.6 = 539.6pt; at the 100pt row-leading inset it ends
/// at 639.6, inside the 900pt row.
@Suite("Measured Geometry Invariants")
@MainActor
struct MeasuredGeometryInvariantsTests {
    private let support = NotationSnapshotTestSupport()
    /// `VirgoNotationProjection.formattingStyle`'s pinned clearance (spec F3).
    private let clearance: CGFloat = 8
    private let tolerance: CGFloat = 0.5

    // MARK: - Width invariants (composed RenderedMeasure)

    @Test("sparse named measure is narrower than its dense neighbor")
    func sparseMeasureIsNarrowerThanDenseNeighbor() throws {
        let layout = support.prepare(notes: [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 1.0 / 16.0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 2.0 / 16.0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 3.0 / 16.0)
        ]).layout
        let sparse = try #require(layout.measures.first { $0.measureIndex == 0 })
        let dense = try #require(layout.measures.first { $0.measureIndex == 1 })

        #expect(sparse.width < dense.width)
    }

    @Test("default sixteenth-run-4-4 first measure is 539.6pt wide and ends inside X=900")
    func sixteenthRunMeasureWidthMatchesBindingNumbers() throws {
        let result = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.sixteenthRun)
        let measure = try #require(result.layout.measures.first)

        // 52 leading inset + 15 columns × 31.2 pitch + 19.6 end remainder.
        let expectedWidth: CGFloat = 52 + 15 * 31.2 + 19.6
        #expect(abs(measure.width - expectedWidth) < tolerance)
        #expect(measure.xOffset + measure.width < 900)
    }

    // MARK: - Clearance invariants

    @Test("adjacent column ink clears by at least the inter-column clearance")
    func adjacentColumnsClearByMinimumClearance() throws {
        let style = NotationLayoutStyle.gameplayDefault
        // Dense sixteenths plus dotted notes, rests and isolated flags in one
        // measure exercise every ink family the formatter reserves for.
        let prepared = support.prepare(notes: [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 16.0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 2.0 / 16.0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 3.0 / 16.0),
            Note(interval: .quarter, noteType: .openHiHat, measureNumber: 1, measureOffset: 4.0 / 16.0),
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 8.0 / 16.0)
        ])
        let layout = prepared.layout

        struct Ink {
            var minX: CGFloat = .infinity
            var maxX: CGFloat = -.infinity
            mutating func add(_ bounds: CGRect) {
                guard !bounds.isNull else { return }
                minX = min(minX, bounds.minX)
                maxX = max(maxX, bounds.maxX)
            }
        }

        var inkByTick: [Int: Ink] = [:]
        func record(tick: Int?, _ bounds: CGRect) {
            guard let tick else { return }
            var ink = inkByTick[tick] ?? Ink()
            ink.add(bounds)
            inkByTick[tick] = ink
        }
        let headByEventID = Dictionary(
            layout.noteHeads.compactMap { head in head.eventID.map { ($0, head) } },
            uniquingKeysWith: { first, _ in first }
        )
        let restByID = Dictionary(uniqueKeysWithValues: layout.rests.map { ($0.id, $0) })

        for head in layout.noteHeads {
            record(tick: head.timeColumn.tickWithinMeasure, head.paintedBounds(style: style))
        }
        for dot in layout.rhythmDots {
            let tick: Int?
            switch dot.source {
            case let .event(eventID):
                tick = headByEventID[eventID]?.timeColumn.tickWithinMeasure
            case let .rest(restID):
                tick = restByID[restID]?.timeColumn.tickWithinMeasure
            }
            record(tick: tick, dot.paintedBounds(style: style))
        }
        for rest in layout.rests where rest.isPrinted {
            record(tick: rest.timeColumn.tickWithinMeasure, rest.paintedBounds(style: style))
        }
        let headByID = Dictionary(uniqueKeysWithValues: layout.noteHeads.map { ($0.id, $0) })
        for command in VirgoNotationAdapter.flagPaintCommands(
            flags: layout.flags,
            heads: layout.noteHeads,
            style: style
        ) {
            // A visible flag belongs to the column of the head it hangs from.
            let ownerID = layout.flags.first { $0.id == command.id }?.noteHeadID
            record(tick: ownerID.flatMap { headByID[$0] }?.timeColumn.tickWithinMeasure, command.paintedBounds)
        }

        let orderedTicks = inkByTick.keys.sorted()
        #expect(orderedTicks.count >= 4, "fixture must produce several ink columns to be meaningful")
        for (previous, next) in zip(orderedTicks, orderedTicks.dropFirst()) {
            guard let prevInk = inkByTick[previous], let nextInk = inkByTick[next] else { continue }
            let gap = nextInk.minX - prevInk.maxX
            #expect(
                gap >= clearance - 0.001,
                "columns \(previous)→\(next) clear by \(gap), need \(clearance)"
            )
        }
    }

    // MARK: - Column identity

    @Test("same tick resolves to one logical X and the playhead reads it")
    func playheadEventTickEqualsLogicalX() throws {
        let result = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.mixedEighthSixteenth)
        let formatted = result.layout.formattedNotation

        for measure in formatted.measures {
            for column in measure.columns {
                let onset = try #require(formatted.position(
                    measureIndex: measure.index,
                    localTick: Double(column.localTick)
                ))
                #expect(onset.x == column.logicalColumnX)
                #expect(onset.rowIndex == measure.rowIndex)
            }
        }
        // Every rendered event's own tick resolves to its column anchor.
        for head in result.layout.noteHeads {
            let onset = try #require(formatted.position(
                measureIndex: head.timeColumn.measureIndex,
                localTick: Double(head.timeColumn.tickWithinMeasure)
            ))
            let columnX = try #require(
                formatted.measures
                    .first { $0.index == head.timeColumn.measureIndex }?
                    .columns
                    .first { $0.localTick == head.timeColumn.tickWithinMeasure }?
                    .logicalColumnX
            )
            #expect(onset.x == columnX)
        }
    }

    // MARK: - Voice independence

    @Test("mixed voices are not shifted apart")
    func mixedVoicesAreNotShiftedApart() throws {
        func snapshot(voices: (upper: NoteType, lower: NoteType?)?) throws -> RhythmLayoutSnapshot {
            let measure = RhythmMeasure(
                measureIndex: 0,
                startTick: 0,
                durationTicks: 960,
                timeSignature: .fourFour,
                beatGroups: (0..<4).map {
                    RhythmBeatGroup(groupIndex: $0, startTick: $0 * 240, durationTicks: 240, isResidual: false)
                },
                engravingSupport: .supported
            )
            var notes: [RhythmLayoutNote] = []
            var eventID = 1
            let upperType = voices?.upper ?? .snare
            let lowerType = voices?.lower
            for tick in stride(from: 0, to: 960, by: 120) {
                notes.append(RhythmLayoutNote(
                    eventID: RhythmEventID(rawValue: eventID),
                    sourceLaneID: "1A",
                    sourceChipID: nil,
                    noteType: upperType,
                    position: RhythmEventPosition(measureIndex: 0, localTick: tick, absoluteTick: tick),
                    durationTicks: 120,
                    rhythm: NotationRhythm(baseInterval: .eighth),
                    tupletID: nil
                ))
                eventID += 1
                if let lowerType {
                    notes.append(RhythmLayoutNote(
                        eventID: RhythmEventID(rawValue: eventID),
                        sourceLaneID: "13",
                        sourceChipID: nil,
                        noteType: lowerType,
                        position: RhythmEventPosition(measureIndex: 0, localTick: tick, absoluteTick: tick),
                        durationTicks: 120,
                        rhythm: NotationRhythm(baseInterval: .eighth),
                        tupletID: nil
                    ))
                    eventID += 1
                }
            }
            return try RhythmLayoutSnapshot(
                ticksPerWholeNote: 960,
                measures: [measure],
                notes: notes,
                controls: [],
                rests: [],
                feel: .straight
            )
        }

        func columnX(_ prepared: GameplayNotationPreparedState) -> [CGFloat] {
            prepared.formatted.measures
                .flatMap(\.columns)
                .map(\.logicalColumnX)
        }

        let singleVoice = GameplayNotationPreparer.prepare(GameplayNotationPreparationRequest(
            snapshot: try snapshot(voices: nil),
            minimumMeasureCount: 1,
            style: .gameplayDefault,
            notePositionOverrides: [:]
        ))
        let mixedVoice = GameplayNotationPreparer.prepare(GameplayNotationPreparationRequest(
            snapshot: try snapshot(voices: (upper: .snare, lower: .bass)),
            minimumMeasureCount: 1,
            style: .gameplayDefault,
            notePositionOverrides: [:]
        ))

        #expect(columnX(singleVoice) == columnX(mixedVoice))
    }

    // MARK: - Reflow

    @Test("reflow at a new row width preserves musical identity")
    func reflowPreservesMusicalIdentity() throws {
        let result = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.multiRowStableWidths)
        // Re-prepare the same snapshot at a much wider row.
        let wide = GameplayNotationPreparer.prepare(GameplayNotationPreparationRequest(
            snapshot: result.snapshot,
            minimumMeasureCount: result.layout.measures.count,
            style: .gameplayDefault.with(rowWidth: 2_400),
            notePositionOverrides: DrumTabFixtureHarness.lockedOverrides
        ))

        func identity(_ layout: NotationLayout) -> Set<String> {
            Set(layout.noteHeads.map { head in
                "\(head.eventID?.rawValue ?? 0)@\(head.rhythmPosition.measureIndex):\(head.rhythmPosition.localTick)"
            })
        }

        let before = identity(result.layout)
        let after = identity(wide.layout)
        #expect(!before.isEmpty)
        #expect(before == after)
        // Rows may change; the installed playhead lookup follows the packing.
        let maxRow = wide.layout.formattedNotation.measures.map(\.rowIndex).max() ?? 0
        #expect(maxRow <= wide.layout.formattedNotation.measures.count)
    }

    // MARK: - Displaced second

    // The displaced-second invariant (second head's ink moves while the
    // shared stem/beam/playhead axis stays on the undisplaced stem-side
    // representative, in both stem directions) is pinned exhaustively by the
    // `Displaced Second Stem Axis` suite from Task 5; referenced, not
    // duplicated here.
}
