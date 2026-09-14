import CoreGraphics
import Testing
@testable import Virgo

/// HPA-164 final review F2: the package's measured flag footprint must match
/// the flag geometry Virgo actually paints — one footprint per stem group,
/// attached at the painted stem origin (stem axis − stemWidth/2).
@Suite("Virgo Notation Adapter Flag Footprint")
struct VirgoNotationAdapterFlagFootprintTests {
    private let style = NotationLayoutStyle.gameplayDefault

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
            durationTicks: 960 / Self.tickDivisor(of: interval),
            rhythm: NotationRhythm(baseInterval: interval),
            tupletID: nil
        )
    }

    private static func tickDivisor(of interval: NoteInterval) -> Int {
        switch interval {
        case .full: return 1
        case .half: return 2
        case .quarter: return 4
        case .eighth: return 8
        case .sixteenth: return 16
        case .thirtysecond: return 32
        case .sixtyfourth: return 64
        }
    }

    @Test("package flag footprint equals the painted flag geometry at the stem origin")
    func packageFlagFootprintMatchesPaintedGeometry() throws {
        // An isolated sixteenth (alone in beat 1) paints one unbeamed flag.
        let measure = makeMeasure(index: 0)
        let snapshot = try RhythmLayoutSnapshot(
            ticksPerWholeNote: 960,
            measures: [measure],
            notes: [makeNote(eventID: 1, noteType: .snare, measureIndex: 0, localTick: 240, interval: .sixteenth)],
            controls: [],
            rests: [],
            feel: .straight
        )
        let prepared = GameplayNotationPreparer.prepare(GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: 1,
            style: style,
            notePositionOverrides: [:]
        ))
        let column = try #require(
            prepared.formatted.measures.first?.columns.first { $0.localTick == 240 }
        )
        let head = try #require(prepared.layout.noteHeads.first)
        let stem = try #require(
            prepared.layout.stems.first { $0.noteHeadIDs.contains(head.id) }
        )
        let flagBounds = VirgoNotationAdapter
            .flagPaintCommands(flags: prepared.layout.flags, heads: prepared.layout.noteHeads, style: style)
            .reduce(CGRect.null) { $0.union($1.paintedBounds) }

        // Virgo paints the flag from the painted stem origin convention...
        #expect(abs(flagBounds.minX - NotationLayoutEngine().flagStemOrigin(for: stem, style: style).x) < 0.001)
        // ...and the package reserved exactly that painted ink at the column.
        let ink = head.paintedBounds(style: style).union(flagBounds)
        #expect(abs(column.leftExtent - (column.logicalColumnX - ink.minX)) < 0.001)
        #expect(abs(column.rightExtent - (ink.maxX - column.logicalColumnX)) < 0.001)
    }

    @Test("same-tick chord reserves ONE flag footprint at the shared stem axis")
    func chordReservesOneFlagFootprintAtSharedStem() throws {
        let measure = makeMeasure(index: 0)
        // Same tick, same voice and stem direction: one stem group of two
        // heads, one painted flag.
        let notes = [
            makeNote(eventID: 1, noteType: .hiHat, measureIndex: 0, localTick: 240, interval: .eighth),
            makeNote(eventID: 2, noteType: .snare, measureIndex: 0, localTick: 240, interval: .eighth)
        ]
        let snapshot = try RhythmLayoutSnapshot(
            ticksPerWholeNote: 960,
            measures: [measure],
            notes: notes,
            controls: [],
            rests: [],
            feel: .straight
        )

        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: [measure],
            notePositionOverrides: [:]
        )
        let flagged = input.notes.filter { $0.visibleFlagDuration != nil }
        #expect(flagged.count == 1, "one stem group must measure exactly one flag anchor")

        // The measured anchor is the head Virgo actually paints the flag on.
        let prepared = GameplayNotationPreparer.prepare(GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: 1,
            style: style,
            notePositionOverrides: [:]
        ))
        let paintedHeadIDs = Set(prepared.layout.flags.map(\.noteHeadID))
        #expect(paintedHeadIDs.count == 1)
        let paintedEventID = try #require(
            prepared.layout.noteHeads
                .first { paintedHeadIDs.contains($0.id) }?
                .eventID
                .map { Int($0.rawValue) }
        )
        #expect(flagged.first?.id == paintedEventID)

        // The column reserves exactly one flag's ink at the shared axis plus
        // the chord's head ink — not two flags at two member anchors.
        let column = try #require(
            prepared.formatted.measures.first?.columns.first { $0.localTick == 240 }
        )
        var ink = prepared.layout.noteHeads
            .filter { $0.timeColumn.tickWithinMeasure == 240 }
            .reduce(CGRect.null) { $0.union($1.paintedBounds(style: style)) }
        ink = VirgoNotationAdapter
            .flagPaintCommands(flags: prepared.layout.flags, heads: prepared.layout.noteHeads, style: style)
            .reduce(ink) { $0.union($1.paintedBounds) }
        #expect(abs(column.leftExtent - (column.logicalColumnX - ink.minX)) < 0.001)
        #expect(abs(column.rightExtent - (ink.maxX - column.logicalColumnX)) < 0.001)
    }
}
