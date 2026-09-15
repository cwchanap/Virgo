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
        durationTicks: Int = ticksPerWholeNote
    ) -> ResolvedMeasure {
        ResolvedMeasure(index: index, startTick: startTick, durationTicks: durationTicks)
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
            visibleFlagDuration: .sixteenth
        )
    }

    /// Fully parameterized note for column/displacement/ink tests. Stem
    /// membership defaults to the stemmed-duration rule the caller maps
    /// (whole/half heads share no stem); pass an explicit value to model a
    /// supported/unsupported override.
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
        measureIndex: Int = 0
    ) -> ResolvedNote {
        ResolvedNote(
            id: id,
            position: NotationTickPosition(measureIndex: measureIndex, localTick: localTick),
            stemDirection: stem,
            staffStep: staffStep,
            stemMember: stemMember ?? (duration != .whole && duration != .half),
            noteheadStyle: headStyle,
            duration: duration,
            dotCount: dotCount,
            visibleFlagDuration: flag
        )
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
            isFullMeasure: false
        )
    }

    static func control(
        id: Int = 9,
        measureIndex: Int = 0,
        localTick: Int = 480
    ) -> ResolvedControl {
        ResolvedControl(id: id, position: NotationTickPosition(measureIndex: measureIndex, localTick: localTick))
    }

    static func document(
        ticksPerWholeNote: Int = Fixtures.ticksPerWholeNote,
        measures: [ResolvedMeasure] = [Fixtures.measure()],
        notes: [ResolvedNote] = [Fixtures.note()],
        rests: [ResolvedRest] = [Fixtures.rest()],
        controls: [ResolvedControl] = [Fixtures.control()]
    ) throws -> ResolvedNotationInput {
        try ResolvedNotationInput(
            ticksPerWholeNote: ticksPerWholeNote,
            measures: measures,
            notes: notes,
            rests: rests,
            controls: controls
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
