import CoreGraphics
import Testing
import DrumNotation

/// Shared package-only fixtures for the formatter input/output suites.
/// Kept in one helper file so both test files can stay under the lint
/// file-length limit; the enum is internal to the test target.
enum Fixtures {
    static let ticksPerWholeNote = 1920

    static func measure(
        index: Int = 0,
        startTick: Int = 0,
        durationTicks: Int = ticksPerWholeNote,
        meter: NotationMeter = NotationMeter(beats: 4, noteValue: 4),
        beatGroups: [ResolvedBeatGroup]? = nil
    ) -> ResolvedMeasure {
        ResolvedMeasure(
            index: index,
            startTick: startTick,
            durationTicks: durationTicks,
            meter: meter,
            beatGroups: beatGroups ?? [ResolvedBeatGroup(startTick: 0, durationTicks: durationTicks)]
        )
    }

    static func note(
        id: Int = 42,
        measureIndex: Int = 0,
        localTick: Int = 0
    ) -> ResolvedNote {
        ResolvedNote(
            id: id,
            position: NotationTickPosition(measureIndex: measureIndex, localTick: localTick),
            stemDirection: .up,
            staffStep: 3,
            stemMember: true,
            noteheadStyle: .x,
            duration: .sixteenth,
            dotCount: 0,
            visibleFlagDuration: .sixteenth,
            voice: .upper,
            durationTicks: 120,
            tiebreakOrder: 0,
            isRhythmEngravable: true
        )
    }

    /// Fully parameterized note for column/displacement/ink tests. Stem
    /// membership defaults to the stemmed-duration rule the caller maps
    /// (whole heads share no stem); pass an explicit value to model a
    /// supported/unsupported override. `durationTicks` defaults to the
    /// interval's exact tick count at the fixture's 1920 ticks per whole
    /// note; pass an explicit value to pin boundary cases.
    static func makeNote(
        id: Int,
        localTick: Int,
        staffStep: Int,
        stem: NotationStemDirection = .up,
        headStyle: PercussionNoteheadStyle = .x,
        duration: NotationDuration = .quarter,
        dotCount: Int = 0,
        flag: NotationFlagDuration? = nil,
        stemMember: Bool? = nil,
        measureIndex: Int = 0,
        voice: NotationVoiceRole = .upper,
        durationTicks: Int? = nil,
        tiebreakOrder: Int = 0,
        isRhythmEngravable: Bool = true,
        articulation: PercussionArticulation? = nil
    ) -> ResolvedNote {
        ResolvedNote(
            id: id,
            position: NotationTickPosition(measureIndex: measureIndex, localTick: localTick),
            stemDirection: stem,
            staffStep: staffStep,
            stemMember: stemMember ?? (duration != .whole),
            noteheadStyle: headStyle,
            duration: duration,
            dotCount: dotCount,
            visibleFlagDuration: flag,
            voice: voice,
            durationTicks: durationTicks ?? ticks(for: duration),
            tiebreakOrder: tiebreakOrder,
            isRhythmEngravable: isRhythmEngravable,
            articulation: articulation
        )
    }

    /// Exact tick count of a `NotationDuration` at the fixture's
    /// 1920 ticks per whole note.
    private static func ticks(for duration: NotationDuration) -> Int {
        switch duration {
        case .whole: return ticksPerWholeNote
        case .half: return ticksPerWholeNote / 2
        case .quarter: return ticksPerWholeNote / 4
        case .eighth: return ticksPerWholeNote / 8
        case .sixteenth: return ticksPerWholeNote / 16
        case .thirtySecond: return ticksPerWholeNote / 32
        case .sixtyFourth: return ticksPerWholeNote / 64
        }
    }

    static func rest(
        id: Int = 7,
        measureIndex: Int = 0,
        localTick: Int = 1440
    ) -> ResolvedRest {
        ResolvedRest(
            id: id,
            position: NotationTickPosition(measureIndex: measureIndex, localTick: localTick),
            duration: .quarter,
            dotCount: 1,
            isFullMeasure: false,
            voice: .upper,
            durationTicks: 480
        )
    }

    static func control(
        id: Int = 9,
        measureIndex: Int = 0,
        localTick: Int = 480
    ) -> ResolvedControl {
        ResolvedControl(
            id: id,
            position: NotationTickPosition(measureIndex: measureIndex, localTick: localTick),
            kind: .stop,
            targetStaffStep: 0
        )
    }

    static func document(
        ticksPerWholeNote: Int = Fixtures.ticksPerWholeNote,
        measures: [ResolvedMeasure] = [Fixtures.measure()],
        notes: [ResolvedNote] = [Fixtures.note()],
        rests: [ResolvedRest] = [Fixtures.rest()],
        controls: [ResolvedControl] = [Fixtures.control()],
        tuplets: [ResolvedTupletGroup] = []
    ) throws -> ResolvedNotationInput {
        try ResolvedNotationInput(
            ticksPerWholeNote: ticksPerWholeNote,
            measures: measures,
            notes: notes,
            rests: rests,
            controls: controls,
            tuplets: tuplets
        )
    }

    /// Formats through the production entry point at the Virgo default style.
    static func format(_ input: ResolvedNotationInput) throws -> FormattedNotation {
        try NotationFormatter.format(input, style: .virgoDefault)
    }

    /// The column at `localTick` in `measureIndex`.
    static func column(
        _ notation: FormattedNotation,
        measureIndex: Int = 0,
        localTick: Int
    ) throws -> FormattedColumn {
        try #require(
            notation.measures.first { $0.index == measureIndex }?.columns.first { $0.localTick == localTick }
        )
    }

    /// Right reach of a centered head's ink past its center X.
    static func headReach(
        headStyle: PercussionNoteheadStyle = .x,
        duration: NotationDuration = .quarter,
        stem: NotationStemDirection = .up,
        staffSpace: CGFloat = NotationFormattingStyle.virgoDefault.staffSpace
    ) -> CGFloat {
        PercussionGlyphMetrics.notehead(
            style: headStyle, duration: duration, stemDirection: stem, staffSpace: staffSpace
        ).paintedBounds.maxX
    }

    /// Shared stem axis X at the column base: the head glyph's
    /// stemUpSE/stemDownNW anchor for `stem` (undisplaced head at X = 0).
    static func stemAxisX(stem: NotationStemDirection) -> CGFloat {
        PercussionGlyphMetrics.notehead(
            style: .x, duration: .quarter, stemDirection: stem,
            staffSpace: NotationFormattingStyle.virgoDefault.staffSpace
        ).stemAnchorOffset.x
    }

    /// Flag ink right edge measured from the flag's attachment point (glyph
    /// origin). Add `stemAxisX(stem:)` for column-base-relative ink.
    static func flagRightInk(duration: NotationFlagDuration, stem: NotationStemDirection) -> CGFloat {
        let metrics = PercussionGlyphMetrics.flag(
            duration: duration, direction: stem, staffSpace: NotationFormattingStyle.virgoDefault.staffSpace
        )
        return -metrics.attachmentOffset.x + metrics.paintedBounds.maxX
    }

    /// Flag ink left reach from the flag's attachment point (glyph property).
    static func flagLeftInk(duration: NotationFlagDuration, stem: NotationStemDirection) -> CGFloat {
        let metrics = PercussionGlyphMetrics.flag(
            duration: duration, direction: stem, staffSpace: NotationFormattingStyle.virgoDefault.staffSpace
        )
        return metrics.attachmentOffset.x - metrics.paintedBounds.minX
    }

    /// Hand-built output exercising the declared `FormattedNotation` surface;
    /// the real formatter populates it in later tasks.
    static func formattedNotation() -> FormattedNotation {
        let tick0 = FormattedColumn(
            localTick: 0,
            logicalColumnX: 100,
            noteHeads: [FormattedNoteHead(noteID: 42, headCenterX: 100)],
            rests: []
        )
        let tick480 = FormattedColumn(
            localTick: 480,
            logicalColumnX: 150,
            noteHeads: [FormattedNoteHead(noteID: 42, headCenterX: 114)],
            rests: [FormattedRest(restID: 7, visualX: 155)]
        )
        return FormattedNotation(
            measures: [
                FormattedMeasure(
                    index: 0,
                    rowIndex: 0,
                    xOffset: 100,
                    width: 490,
                    columns: [tick0, tick480]
                ),
                FormattedMeasure(
                    index: 1,
                    rowIndex: 1,
                    xOffset: 602,
                    width: 490,
                    columns: [
                        FormattedColumn(localTick: 0, logicalColumnX: 100, noteHeads: [], rests: [])
                    ]
                )
            ]
        )
    }
}
