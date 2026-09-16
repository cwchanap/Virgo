import Testing
import CoreGraphics
import DrumNotation
@testable import Virgo

/// Composed-engraving regression invariants, asserted against the package
/// `EngravedNotation` produced by `GameplayNotationPreparer.prepare` (not
/// just package-internal fixtures).
///
/// Binding numbers from the controller ruling: the vendored Bravura X-black
/// head paints 23.2pt (half 11.6), so adjacent sixteenth pitch is
/// 11.6 + 8 + 11.6 = 31.2pt and a 16-sixteenth 4/4 measure spans
/// 52 + 15 × 31.2 + 19.6 = 539.6pt. The silent-voice full-measure rest's
/// keep-clear pocket adds 50.16 (whole-rest ink half 11.28 + 8 clearance,
/// minus natural coverage around content center) for a 589.76pt measure;
/// at the 100pt row-leading inset it ends at 689.76, inside the 900pt row.
@Suite("Measured Geometry Invariants")
@MainActor
struct MeasuredGeometryInvariantsTests {
    private let support = NotationSnapshotTestSupport()
    /// `VirgoNotationProjection.formattingStyle`'s pinned clearance (spec F3).
    private let clearance: CGFloat = 8
    private let tolerance: CGFloat = 0.5

    // MARK: - Width invariants (composed EngravedMeasure)

    @Test("sparse named measure is narrower than its dense neighbor")
    func sparseMeasureIsNarrowerThanDenseNeighbor() throws {
        let engraved = try support.requireEngraved(support.prepare(notes: [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 1.0 / 16.0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 2.0 / 16.0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 3.0 / 16.0)
        ]))
        let sparse = try #require(engraved.measures.first { $0.index == 0 })
        let dense = try #require(engraved.measures.first { $0.index == 1 })

        #expect(sparse.width < dense.width)
    }

    @Test("default sixteenth-run-4-4 first measure is 589.76pt wide and ends inside X=900")
    func sixteenthRunMeasureWidthMatchesBindingNumbers() throws {
        let result = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.sixteenthRun)
        let measure = try #require(result.engraved.measures.first)

        // 52 leading inset + 15 columns × 31.2 pitch + 19.6 end remainder,
        // plus 50.16 for the centered full-measure rest's keep-clear pocket.
        let expectedWidth: CGFloat = 52 + 15 * 31.2 + 19.6 + 50.16
        #expect(abs(measure.width - expectedWidth) < tolerance)
        #expect(measure.xOffset + measure.width < 900)
    }

    // MARK: - Clearance invariants

    @Test("adjacent column ink clears by at least the inter-column clearance")
    func adjacentColumnsClearByMinimumClearance() throws {
        // Dense sixteenths plus dotted notes, rests and isolated flags in one
        // measure exercise every ink family the formatter reserves for.
        let engraved = try support.requireEngraved(support.prepare(notes: [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 16.0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 2.0 / 16.0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 3.0 / 16.0),
            Note(interval: .quarter, noteType: .openHiHat, measureNumber: 1, measureOffset: 4.0 / 16.0),
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 8.0 / 16.0)
        ]))

        struct Ink {
            var minX: CGFloat = .infinity
            var maxX: CGFloat = -.infinity
            mutating func add(_ bounds: CGRect) {
                guard !bounds.isNull else { return }
                minX = min(minX, bounds.minX)
                maxX = max(maxX, bounds.maxX)
            }
        }

        // Engraved primitives carry final geometry, not source ticks: each
        // head/rest's onset tick comes from its formatted-column membership.
        var tickByNoteID: [Int: Int] = [:]
        var tickByRestID: [Int: Int] = [:]
        for measure in engraved.formatted.measures {
            for column in measure.columns {
                for head in column.noteHeads { tickByNoteID[head.noteID] = column.localTick }
                for rest in column.rests { tickByRestID[rest.restID] = column.localTick }
            }
        }

        var inkByTick: [Int: Ink] = [:]
        func record(tick: Int?, _ bounds: CGRect) {
            guard let tick else { return }
            var ink = inkByTick[tick] ?? Ink()
            ink.add(bounds)
            inkByTick[tick] = ink
        }

        for head in engraved.noteHeads {
            record(tick: tickByNoteID[head.noteID], head.paintedBounds)
        }
        for dot in engraved.rhythmDots {
            let tick: Int?
            switch dot.source {
            case let .note(noteID):
                tick = tickByNoteID[noteID]
            case let .rest(restID):
                tick = tickByRestID[restID]
            }
            record(tick: tick, dot.paintedBounds)
        }
        // Every engraved rest is printed by construction.
        for rest in engraved.rests {
            record(tick: tickByRestID[rest.restID], rest.paintedBounds)
        }
        let staffSpace = engraved.style.formatting.staffSpace
        for flag in engraved.flags {
            // The package flag glyph paints a `paintedBounds`-sized frame
            // centered at `origin - attachmentOffset` (see DrumNotationView's
            // flagsLayer); a visible flag belongs to the column of the head
            // it hangs from.
            let metrics = PercussionGlyphMetrics.flag(
                duration: flag.duration,
                direction: flag.stemDirection,
                staffSpace: staffSpace
            )
            let center = CGPoint(
                x: flag.origin.x - metrics.attachmentOffset.x,
                y: flag.origin.y - metrics.attachmentOffset.y
            )
            let bounds = metrics.paintedBounds.offsetBy(
                dx: center.x - metrics.paintedBounds.midX,
                dy: center.y - metrics.paintedBounds.midY
            )
            record(tick: tickByNoteID[flag.noteID], bounds)
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
        let formatted = result.engraved.formatted

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
        // Every rendered event's own tick resolves to its column anchor —
        // the engraved head's onset tick is its formatted-column membership.
        for head in result.engraved.noteHeads {
            let column = try #require(
                formatted.measures
                    .first { $0.index == head.measureIndex }?
                    .columns
                    .first { $0.noteHeads.contains { $0.noteID == head.noteID } }
            )
            let onset = try #require(formatted.position(
                measureIndex: head.measureIndex,
                localTick: Double(column.localTick)
            ))
            #expect(onset.x == column.logicalColumnX)
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
            guard case let .ready(engraved, _) = prepared else { return [] }
            return engraved.formatted.measures
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
        let wideEngraved = try support.requireEngraved(GameplayNotationPreparer.prepare(
            GameplayNotationPreparationRequest(
                snapshot: result.snapshot,
                minimumMeasureCount: result.engraved.measures.count,
                style: .gameplayDefault.with(rowWidth: 2_400),
                notePositionOverrides: DrumTabFixtureHarness.lockedOverrides
            )
        ))

        // Musical identity = event ID at (measure, onset tick). Engraved
        // primitives carry final geometry, so the onset tick comes from the
        // head's formatted-column membership.
        func identity(_ engraved: EngravedNotation) -> Set<String> {
            var tickByNoteID: [Int: Int] = [:]
            for measure in engraved.formatted.measures {
                for column in measure.columns {
                    for head in column.noteHeads { tickByNoteID[head.noteID] = column.localTick }
                }
            }
            return Set(engraved.noteHeads.map { head in
                "\(head.noteID)@\(head.measureIndex):\(tickByNoteID[head.noteID] ?? -1)"
            })
        }

        let before = identity(result.engraved)
        let after = identity(wideEngraved)
        #expect(!before.isEmpty)
        #expect(before == after)
        // Rows may change; the installed playhead lookup follows the packing.
        // rowIndex is zero-based, so the maximum row is strictly below the
        // measure count (equality would mean a row index out of bounds).
        let maxRow = wideEngraved.measures.map(\.rowIndex).max() ?? 0
        #expect(maxRow < wideEngraved.measures.count)
    }

    // MARK: - Displaced second

    // The displaced-second invariant (second head's ink moves while the
    // shared stem/beam/playhead axis stays on the undisplaced stem-side
    // representative, in both stem directions) is pinned exhaustively by the
    // `Displaced Second Stem Axis` suite from Task 5; referenced, not
    // duplicated here.
}
