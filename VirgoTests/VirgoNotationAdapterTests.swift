import Testing
import CoreGraphics
import DrumNotation
@testable import Virgo

@Suite("Virgo Notation Adapter Tests")
struct VirgoNotationAdapterTests {
    // MARK: - Exhaustive semantic mappings

    @Test("Every NoteType maps to the required package notehead style")
    func noteheadStyleMappingIsExhaustive() {
        let expected: [NoteType: PercussionNoteheadStyle] = [
            .bass: .normal,
            .snare: .normal,
            .highTom: .normal,
            .midTom: .normal,
            .lowTom: .normal,
            .hiHat: .x,
            .hiHatPedal: .x,
            .openHiHat: .x,
            .crash: .x,
            .ride: .x,
            .china: .x,
            .splash: .x,
            .cowbell: .diamond
        ]

        #expect(expected.count == NoteType.allCases.count)
        for noteType in NoteType.allCases {
            #expect(VirgoNotationAdapter.noteheadStyle(for: noteType) == expected[noteType])
        }
    }

    @Test("All seven NoteIntervals map to package durations")
    func intervalDurationMappingIsExhaustive() {
        let expected: [NoteInterval: NotationDuration] = [
            .full: .whole,
            .half: .half,
            .quarter: .quarter,
            .eighth: .eighth,
            .sixteenth: .sixteenth,
            .thirtysecond: .thirtySecond,
            .sixtyfourth: .sixtyFourth
        ]

        #expect(expected.count == NoteInterval.allCases.count)
        for interval in NoteInterval.allCases {
            #expect(VirgoNotationAdapter.duration(for: interval) == expected[interval])
        }
    }

    @Test("Both StemDirections map to package stem directions")
    func stemDirectionMappingIsExhaustive() {
        let expected: [StemDirection: NotationStemDirection] = [
            .up: .up,
            .down: .down
        ]

        for direction in [StemDirection.up, .down] {
            #expect(VirgoNotationAdapter.stemDirection(direction) == expected[direction])
        }
    }

    @Test("Every NotationRestDuration maps to a package duration; indeterminate maps to nil")
    func restDurationMappingIsExhaustive() {
        let expected: [NotationRestDuration: NotationDuration] = [
            .fullMeasure: .whole,
            .half: .half,
            .quarter: .quarter,
            .eighth: .eighth,
            .sixteenth: .sixteenth,
            .thirtySecond: .thirtySecond,
            .sixtyFourth: .sixtyFourth
        ]

        for duration in NotationRestDuration.allCases {
            #expect(VirgoNotationAdapter.restDuration(duration) == expected[duration])
        }
        #expect(VirgoNotationAdapter.restDuration(.indeterminate) == nil)
    }

    @Test("staffSpace derives from the style's staff line spacing")
    func staffSpaceComesFromStaffLineSpacing() {
        let style = NotationLayoutStyle.gameplayDefault
        #expect(VirgoNotationAdapter.staffSpace(for: style) == style.staffLineSpacing)
    }

    // MARK: - Flag paint commands

    @Test("An isolated eighth note emits one .eighth command")
    func isolatedEighthEmitsOneCommand() {
        let style = NotationLayoutStyle.gameplayDefault
        let head = makeHead(id: 1, interval: .eighth)
        let flags = [
            makeFlag(id: "flag_1_0", headID: 1, level: 0, origin: CGPoint(x: 40, y: 100))
        ]

        let commands = VirgoNotationAdapter.flagPaintCommands(
            flags: flags,
            heads: [head],
            style: style
        )

        #expect(commands.count == 1)
        guard let command = commands.first else { return }
        #expect(command.duration == .eighth)
        #expect(command.direction == .up)
        #expect(command.staffSpace == style.staffLineSpacing)
    }

    @Test("Isolated 16th/32nd/64th notes emit one canonical command from level 0 and suppress siblings")
    func isolatedFlaggedNotesCollapseToCanonicalCommand() {
        let style = NotationLayoutStyle.gameplayDefault
        let cases: [(interval: NoteInterval, duration: NotationDuration)] = [
            (.sixteenth, .sixteenth),
            (.thirtysecond, .thirtySecond),
            (.sixtyfourth, .sixtyFourth)
        ]

        for (interval, canonicalDuration) in cases {
            let head = makeHead(id: 7, interval: interval)
            let flags = (0..<interval.flagCount).map { level in
                makeFlag(
                    id: "flag_7_\(level)",
                    headID: 7,
                    level: level,
                    origin: CGPoint(
                        x: 50,
                        y: 100 + CGFloat(level) * GameplayLayout.flagVerticalSpacing
                    )
                )
            }

            let commands = VirgoNotationAdapter.flagPaintCommands(
                flags: flags,
                heads: [head],
                style: style
            )

            #expect(commands.count == 1)
            guard let command = commands.first else { continue }
            #expect(command.duration == canonicalDuration)
            // The single command is emitted from flag level 0.
            #expect(command.id == "flag_7_0")
            assertCenterRecoversOrigin(command, origin: flags[0].origin)
        }
    }

    @Test("A partially beamed note emits one .eighth command per uncovered flag, preserving origins")
    func partiallyBeamedEmitsEighthPerUncoveredFlag() {
        let style = NotationLayoutStyle.gameplayDefault
        let head = makeHead(id: 9, interval: .sixtyfourth)
        // Level 1 is covered by a beam and therefore absent from the flags.
        let uncoveredLevels = [0, 2, 3]
        let flags = uncoveredLevels.map { level in
            makeFlag(
                id: "flag_9_\(level)",
                headID: 9,
                level: level,
                origin: CGPoint(x: 60 + CGFloat(level), y: 120 - CGFloat(level) * 8)
            )
        }

        let commands = VirgoNotationAdapter.flagPaintCommands(
            flags: flags,
            heads: [head],
            style: style
        )

        #expect(commands.count == 3)
        for (command, flag) in zip(commands, flags) {
            #expect(command.duration == .eighth)
            #expect(command.id == flag.id)
            assertCenterRecoversOrigin(command, origin: flag.origin)
        }
    }

    @Test("Commands preserve the original flags order")
    func commandsPreserveFlagOrder() {
        let style = NotationLayoutStyle.gameplayDefault
        // Fully flagged eighth (collapse), fully flagged sixteenth with its
        // level-1 flag listed before level 0 (collapse at level 0), and a
        // partially beamed thirty-second with levels {0, 2} uncovered.
        let flags = [
            makeFlag(id: "a_0", headID: 1, level: 0, origin: CGPoint(x: 10, y: 100)),
            makeFlag(id: "b_1", headID: 2, level: 1, origin: CGPoint(x: 20, y: 108)),
            makeFlag(id: "b_0", headID: 2, level: 0, origin: CGPoint(x: 20, y: 100)),
            makeFlag(id: "c_0", headID: 3, level: 0, origin: CGPoint(x: 30, y: 100)),
            makeFlag(id: "c_2", headID: 3, level: 2, origin: CGPoint(x: 30, y: 116))
        ]
        let heads = [
            makeHead(id: 1, interval: .eighth),
            makeHead(id: 2, interval: .sixteenth),
            makeHead(id: 3, interval: .thirtysecond)
        ]

        let commands = VirgoNotationAdapter.flagPaintCommands(
            flags: flags,
            heads: heads,
            style: style
        )

        // b_1 is suppressed; b's canonical command takes b_0's position.
        #expect(commands.map(\.id) == ["a_0", "b_0", "c_0", "c_2"])
        #expect(commands.map(\.duration) == [.eighth, .sixteenth, .eighth, .eighth])
    }

    @Test("Every command's center plus package attachment offset recovers the flag origin")
    func commandCentersRoundTripThroughAttachmentOffset() {
        let style = NotationLayoutStyle.gameplayDefault
        let flags = [
            makeFlag(
                id: "up_0",
                headID: 1,
                level: 0,
                origin: CGPoint(x: 88, y: 200),
                direction: .up
            ),
            makeFlag(
                id: "down_0",
                headID: 2,
                level: 0,
                origin: CGPoint(x: 130, y: 340),
                direction: .down
            )
        ]
        let heads = [
            makeHead(id: 1, interval: .sixtyfourth),
            makeHead(id: 2, interval: .sixtyfourth, stemDirection: .down)
        ]

        let commands = VirgoNotationAdapter.flagPaintCommands(
            flags: flags,
            heads: heads,
            style: style
        )

        #expect(commands.count == 2)
        for (command, flag) in zip(commands, flags) {
            assertCenterRecoversOrigin(command, origin: flag.origin)
        }
    }

    // MARK: - Isolated-flag stem clearance

    /// Independently recomputes the brief's expected clearance for one
    /// canonical flag: flag bounds relative to the stem attachment point.
    private func expectedUnbeamedStemLength(
        interval: NoteInterval,
        direction: StemDirection,
        style: NotationLayoutStyle
    ) -> CGFloat {
        let metrics = PercussionGlyphMetrics.flag(
            duration: VirgoNotationAdapter.duration(for: interval),
            direction: VirgoNotationAdapter.stemDirection(direction),
            staffSpace: style.staffLineSpacing
        )
        let relativeBounds = metrics.paintedBounds.offsetBy(
            dx: -metrics.attachmentOffset.x,
            dy: -metrics.attachmentOffset.y
        )
        let inwardExtent: CGFloat
        switch direction {
        case .up:
            inwardExtent = max(0, relativeBounds.maxY)
        case .down:
            inwardExtent = max(0, -relativeBounds.minY)
        }
        return max(style.stemLength, inwardExtent + style.minimumStemExtensionPastChord)
    }

    @Test("Isolated 8th/16th/32nd/64th in both directions require max(stemLength, flag clearance)")
    func isolatedFlagStemClearanceMatchesBriefFormula() {
        let style = NotationLayoutStyle.gameplayDefault
        let intervals: [NoteInterval] = [.eighth, .sixteenth, .thirtysecond, .sixtyfourth]

        for direction in [StemDirection.up, .down] {
            for interval in intervals {
                let head = makeHead(id: 1, interval: interval, stemDirection: direction)
                let actual = VirgoNotationAdapter.minimumUnbeamedStemLength(
                    heads: [head],
                    style: style
                )
                let expected = expectedUnbeamedStemLength(
                    interval: interval,
                    direction: direction,
                    style: style
                )
                #expect(actual == expected)
            }
        }
    }

    @Test("Quarter/half/full notes do not lengthen the default stem policy")
    func unflaggedNotesKeepDefaultStemLength() {
        let style = NotationLayoutStyle.gameplayDefault
        let heads = [
            makeHead(id: 1, interval: .full),
            makeHead(id: 2, interval: .half),
            makeHead(id: 3, interval: .quarter)
        ]

        #expect(VirgoNotationAdapter.minimumUnbeamedStemLength(heads: heads, style: style) == style.stemLength)
        #expect(VirgoNotationAdapter.minimumUnbeamedStemLength(heads: [], style: style) == style.stemLength)
    }

    @Test("A mixed unbeamed stem group requires the maximum across its flagged members")
    func mixedStemGroupTakesMaximumAcrossMembers() {
        let style = NotationLayoutStyle.gameplayDefault
        let direction = StemDirection.down
        let heads = [
            makeHead(id: 1, interval: .eighth, stemDirection: direction),
            makeHead(id: 2, interval: .sixtyfourth, stemDirection: direction)
        ]

        let expected = max(
            expectedUnbeamedStemLength(interval: .eighth, direction: direction, style: style),
            expectedUnbeamedStemLength(interval: .sixtyfourth, direction: direction, style: style)
        )
        #expect(VirgoNotationAdapter.minimumUnbeamedStemLength(heads: heads, style: style) == expected)
    }
}

// MARK: - Flag paint command fixtures

private extension VirgoNotationAdapterTests {
    private func makeHead(
        id: UInt64,
        interval: NoteInterval,
        stemDirection: StemDirection = .up
    ) -> RenderedNoteHead {
        RenderedNoteHead(
            id: id,
            sourceLaneID: nil,
            sourceChipID: nil,
            noteType: .snare,
            drumType: .snare,
            variant: .standard,
            voice: .upper,
            stemDirection: stemDirection,
            timeColumn: NotationTimeColumn(
                measureIndex: 0,
                tickWithinMeasure: 0,
                absoluteLayoutTick: 0
            ),
            timePosition: 0,
            row: 0,
            position: .zero,
            staffStep: 0,
            interval: interval,
            catalogOrder: 0
        )
    }

    private func makeFlag(
        id: String,
        headID: UInt64,
        level: Int,
        origin: CGPoint,
        direction: StemDirection = .up
    ) -> RenderedFlag {
        RenderedFlag(
            id: id,
            noteHeadID: headID,
            stemDirection: direction,
            flagIndex: level,
            origin: origin
        )
    }

    /// Independently recomputes the package attachment offset a command must
    /// round-trip against.
    private func attachmentOffset(of command: FlagPaintCommand) -> CGPoint {
        PercussionGlyphMetrics.flag(
            duration: command.duration,
            direction: command.direction,
            staffSpace: command.staffSpace
        ).attachmentOffset
    }

    private func assertCenterRecoversOrigin(
        _ command: FlagPaintCommand,
        origin: CGPoint
    ) {
        let offset = attachmentOffset(of: command)
        #expect(abs(command.center.x + offset.x - origin.x) < 0.0001)
        #expect(abs(command.center.y + offset.y - origin.y) < 0.0001)
    }
}
