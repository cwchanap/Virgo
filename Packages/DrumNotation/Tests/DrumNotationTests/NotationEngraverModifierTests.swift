import CoreGraphics
import Testing
@testable import DrumNotation

/// HPA-166 Task 4: the engraver's topology-driven primitives — stems,
/// beams, hooks, flags, articulations, controls, tuplets, measure bars and
/// the staff/clef/meter row descriptors — ported from Virgo's geometry
/// onto the package's stem groups and flag plans.
///
/// `@testable` reaches the internal plan-driven `engrave` seam so the
/// defensive component-flag arm can be exercised with synthetic coverage,
/// mirroring `NotationFormatter.format(_:style:stemTopology:)`.
@Suite("Engraver stems, beams and hooks")
struct EngraverStemBeamTests {
    private let style = NotationEngravingStyle()
    private let staffSpace = NotationFormattingStyle.virgoDefault.staffSpace

    private func head(_ engraved: EngravedNotation, id: Int) throws -> EngravedNoteHead {
        try #require(engraved.noteHeads.first { $0.noteID == id })
    }

    private func stem(_ engraved: EngravedNotation, serving noteID: Int) throws -> EngravedStem {
        try #require(engraved.stems.first { $0.noteIDs.contains(noteID) })
    }

    private func anchor(_ engraved: EngravedNotation, noteID: Int) throws -> CGPoint {
        let noteHead = try head(engraved, id: noteID)
        let metrics = PercussionGlyphMetrics.notehead(
            style: noteHead.noteheadStyle,
            duration: noteHead.duration,
            stemDirection: noteHead.stemDirection,
            staffSpace: staffSpace
        )
        return CGPoint(
            x: noteHead.position.x + metrics.stemAnchorOffset.x,
            y: noteHead.position.y + metrics.stemAnchorOffset.y
        )
    }

    /// Four contiguous sixteenths in one beat group: one primary run, full
    /// beams at levels 0 and 1, one stem per onset reaching the outermost
    /// (highest-level) beam.
    private func fourSixteenths() throws -> ResolvedNotationInput {
        try Fixtures.document(
            notes: (0..<4).map {
                Fixtures.makeNote(
                    id: $0 + 1, localTick: $0 * 120, staffStep: 3,
                    duration: .sixteenth, durationTicks: 120
                )
            },
            rests: [], controls: []
        )
    }

    @Test("beamed stems anchor on the representative and reach the outermost beam")
    func stemsAnchorOnRepresentativeAndReachOuterBeam() throws {
        let engraved = try NotationEngraver.engrave(fourSixteenths(), style: style)

        #expect(engraved.stems.count == 4)
        #expect(engraved.beams.count == 2)

        // The outermost beam for up-stems is the highest stack level — the
        // smallest Y. Every stem end lands on it.
        let outermostY = try #require(engraved.beams.map(\.start.y).min())
        for noteID in 1...4 {
            let noteStem = try stem(engraved, serving: noteID)
            let stemAnchor = try anchor(engraved, noteID: noteID)
            #expect(noteStem.direction == .up)
            #expect(noteStem.start == stemAnchor)
            #expect(noteStem.end == CGPoint(x: stemAnchor.x, y: outermostY))
        }
    }

    @Test("secondary beam stacks beamLevelSpacing above the primary beam")
    func beamLevelsStackByBeamLevelSpacing() throws {
        let engraved = try NotationEngraver.engrave(fourSixteenths(), style: style)

        let primary = try #require(engraved.beams.first { $0.level == 0 })
        let secondary = try #require(engraved.beams.first { $0.level == 1 })
        #expect(primary.kind == .full && secondary.kind == .full)
        #expect(primary.thickness == style.beamThickness)
        #expect(secondary.start.y == primary.start.y - style.beamLevelSpacing)

        // Full segments span first-to-last stem axis of the run.
        let firstAxis = try anchor(engraved, noteID: 1).x
        let lastAxis = try anchor(engraved, noteID: 4).x
        #expect(primary.start.x == firstAxis && primary.end.x == lastAxis)
        #expect(secondary.start.x == firstAxis && secondary.end.x == lastAxis)
    }

    @Test("forward and backward hooks follow the topology neighbor rule")
    func hooksFollowTopologyDirectionAndLength() throws {
        // Sixteenth + eighth: the sixteenth owns a forward hook at level 1.
        let forward = try NotationEngraver.engrave(Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, duration: .sixteenth, durationTicks: 120),
                Fixtures.makeNote(id: 2, localTick: 120, staffStep: 3, duration: .eighth, durationTicks: 240)
            ],
            rests: [], controls: []
        ), style: style)
        let forwardHook = try #require(forward.beams.first { $0.kind == .forwardHook })
        let forwardAxis = try anchor(forward, noteID: 1).x
        let neighborAxis = try anchor(forward, noteID: 2).x
        let forwardLength = min(style.beamHookLength, abs(neighborAxis - forwardAxis) / 2)
        #expect(forwardHook.level == 1)
        #expect(forwardHook.noteIDs == [1])
        #expect(forwardHook.start.x == forwardAxis)
        #expect(forwardHook.end.x == forwardAxis + forwardLength)

        // Eighth + sixteenth: the sixteenth owns a backward hook at level 1.
        let backward = try NotationEngraver.engrave(Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, duration: .eighth, durationTicks: 240),
                Fixtures.makeNote(id: 2, localTick: 240, staffStep: 3, duration: .sixteenth, durationTicks: 120)
            ],
            rests: [], controls: []
        ), style: style)
        let backwardHook = try #require(backward.beams.first { $0.kind == .backwardHook })
        let backwardAxis = try anchor(backward, noteID: 2).x
        #expect(backwardHook.start.x == backwardAxis)
        #expect(backwardHook.end.x == backwardAxis - min(
            style.beamHookLength,
            abs(try anchor(backward, noteID: 1).x - backwardAxis) / 2
        ))

        // The hooked stem still reaches its hook; the neighbor's stem stops
        // at the shared primary beam.
        let hookedStem = try stem(backward, serving: 2)
        #expect(hookedStem.end.y == backwardHook.start.y)
        let primaryY = try #require(backward.beams.first { $0.kind == .full }).start.y
        let neighborStem = try stem(backward, serving: 1)
        #expect(neighborStem.end.y == primaryY)
    }

    @Test("down-stem groups beam and stem below the heads")
    func downStemsBeamBelowHeads() throws {
        let engraved = try NotationEngraver.engrave(Fixtures.document(
            notes: (0..<2).map {
                Fixtures.makeNote(
                    id: $0 + 1, localTick: $0 * 120, staffStep: 3,
                    stem: .down, duration: .sixteenth, voice: .lower, durationTicks: 120
                )
            },
            rests: [], controls: []
        ), style: style)

        let primary = try #require(engraved.beams.first { $0.level == 0 })
        let secondary = try #require(engraved.beams.first { $0.level == 1 })
        #expect(primary.direction == .down)
        // Down-stem stacks grow downward: level 1 sits beamLevelSpacing lower.
        #expect(secondary.start.y == primary.start.y + style.beamLevelSpacing)
        let outermostY = try #require(engraved.beams.map(\.start.y).max())
        for noteID in 1...2 {
            let noteStem = try stem(engraved, serving: noteID)
            let noteHead = try head(engraved, id: noteID)
            #expect(noteStem.end.y == outermostY)
            #expect(noteStem.end.y > noteHead.position.y)
        }
    }

    @Test("unbeamed flagged stems clear the chord edge and the flag ink")
    func unbeamedFlaggedStemClearsChordAndFlag() throws {
        // Two isolated eighths — no beams, canonical flags; the stem must
        // reach default length AND keep the far chord edge + flag ink clear.
        let engraved = try NotationEngraver.engrave(Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 2, duration: .eighth, durationTicks: 240),
                Fixtures.makeNote(id: 2, localTick: 480, staffStep: 7, duration: .eighth, durationTicks: 240)
            ],
            rests: [], controls: []
        ), style: style)

        #expect(engraved.beams.isEmpty)
        #expect(engraved.stems.count == 2)

        // Flag inward extent of the canonical eighth glyph (the reach back
        // from the stem attachment toward the heads).
        let flagMetrics = PercussionGlyphMetrics.flag(
            duration: .eighth, direction: .up, staffSpace: staffSpace
        )
        let flagExtent = max(
            0,
            flagMetrics.paintedBounds.offsetBy(
                dx: -flagMetrics.attachmentOffset.x,
                dy: -flagMetrics.attachmentOffset.y
            ).maxY
        )
        let effectiveLength = max(
            style.stemLength,
            flagExtent + style.minimumStemExtensionPastChord
        )
        for noteID in [1, 2] {
            let noteStem = try stem(engraved, serving: noteID)
            let headBounds = try head(engraved, id: noteID).paintedBounds
            let expected = min(
                noteStem.start.y - effectiveLength,
                headBounds.minY - style.minimumStemExtensionPastChord - flagExtent
            )
            #expect(noteStem.end.y == expected)
        }
    }

    @Test("unflagged unbeamed stems use the default stem length")
    func unflaggedStemUsesDefaultLength() throws {
        let engraved = try NotationEngraver.engrave(Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 2, duration: .quarter, durationTicks: 480)
            ],
            rests: [], controls: []
        ), style: style)

        let noteStem = try stem(engraved, serving: 1)
        let headBounds = try head(engraved, id: 1).paintedBounds
        // No flag ink: clearance is the chord edge alone.
        let expected = min(
            noteStem.start.y - style.stemLength,
            headBounds.minY - style.minimumStemExtensionPastChord
        )
        #expect(noteStem.end.y == expected)
        #expect(engraved.beams.isEmpty && engraved.flags.isEmpty)
    }

    @Test("a displaced same-stem sibling never moves the shared stem axis")
    func displacedSiblingKeepsStemAxis() throws {
        let engraved = try NotationEngraver.engrave(Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 1, localTick: 240, staffStep: 3, duration: .quarter, durationTicks: 480),
                Fixtures.makeNote(id: 2, localTick: 240, staffStep: 4, duration: .quarter, durationTicks: 480)
            ],
            rests: [], controls: []
        ), style: style)

        let column = try Fixtures.column(engraved.formatted, localTick: 240)
        let lower = try head(engraved, id: 1)
        let upper = try head(engraved, id: 2)
        #expect(lower.position.x == column.logicalColumnX)
        #expect(upper.position.x != column.logicalColumnX)

        // One shared stem serves both heads; its axis stays on the
        // undisplaced stem representative (the lowest head for up-stems).
        let noteStem = try stem(engraved, serving: 1)
        let repAnchor = try anchor(engraved, noteID: 1)
        #expect(noteStem.noteIDs == [1, 2])
        #expect(noteStem.start == repAnchor)
        #expect(noteStem.end.x == noteStem.start.x)
    }

    @Test("whole notes paint no stem")
    func wholeNotesPaintNoStem() throws {
        let engraved = try NotationEngraver.engrave(Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, duration: .whole, durationTicks: 1920)
            ],
            rests: [], controls: []
        ), style: style)

        #expect(engraved.stems.isEmpty)
        #expect(engraved.beams.isEmpty && engraved.flags.isEmpty)
    }

    @Test("every beam group's member heads stay on one formatted row")
    func beamGroupStaysOnOneRow() throws {
        // Eight beamed measures forced across rows by a narrow row width.
        let narrow = NotationEngravingStyle(
            formatting: NotationFormattingStyle(availableRowWidth: 400)
        )
        let measures = (0..<4).map { Fixtures.measure(index: $0, startTick: $0 * 1920) }
        let input = try Fixtures.document(
            measures: measures,
            notes: measures.flatMap { measure in
                (0..<4).map { step in
                    Fixtures.makeNote(
                        id: measure.index * 10 + step, localTick: step * 120,
                        staffStep: 3, duration: .sixteenth,
                        measureIndex: measure.index, durationTicks: 120
                    )
                }
            },
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: narrow)

        #expect(Set(engraved.measures.map(\.rowIndex)).count > 1)
        #expect(engraved.beams.isEmpty == false)
        for beam in engraved.beams {
            let rows = Set(try beam.noteIDs.map { noteID -> Int in
                let head = try #require(
                    engraved.noteHeads.first { $0.noteID == noteID },
                    "missing note head for beam member \(noteID)"
                )
                return head.rowIndex
            })
            #expect(rows.count == 1, "beam \(beam) spans rows \(rows)")
        }
    }
}

@Suite("Engraver flags")
struct EngraverFlagTests {
    private let style = NotationEngravingStyle()
    private let staffSpace = NotationFormattingStyle.virgoDefault.staffSpace

    private func isolatedFlaggedNote(
        duration: NotationDuration,
        direction: NotationStemDirection = .up
    ) throws -> EngravedNotation {
        try NotationEngraver.engrave(Fixtures.document(
            notes: [
                Fixtures.makeNote(
                    id: 1, localTick: 0, staffStep: 3, stem: direction,
                    duration: duration, durationTicks: 240
                )
            ],
            rests: [], controls: []
        ), style: style)
    }

    @Test("a canonical plan paints one duration-specific flag at the stem end")
    func canonicalFlagPaintsAtStemEnd() throws {
        let engraved = try isolatedFlaggedNote(duration: .sixteenth)
        let stem = try #require(engraved.stems.first { $0.noteIDs.contains(1) })
        #expect(engraved.flags.count == 1)
        let flag = try #require(engraved.flags.first)
        #expect(flag.noteID == 1)
        #expect(flag.stemDirection == .up)
        #expect(flag.duration == .sixteenth)
        #expect(flag.flagIndex == 0)
        // The flag hangs off the stem's left edge at the stem end — the
        // shared stem-axis origin, not a glyph-em corner.
        #expect(flag.origin == CGPoint(
            x: stem.start.x - style.formatting.stemWidth / 2,
            y: stem.end.y
        ))
    }

    @Test("down-stem flags hang below the stem end")
    func downStemFlagHangsBelow() throws {
        let engraved = try isolatedFlaggedNote(duration: .eighth, direction: .down)
        let stem = try #require(engraved.stems.first { $0.noteIDs.contains(1) })
        #expect(engraved.flags.count == 1)
        let flag = try #require(engraved.flags.first)
        #expect(flag.stemDirection == .down)
        #expect(flag.origin == CGPoint(
            x: stem.start.x - style.formatting.stemWidth / 2,
            y: stem.end.y
        ))
        #expect(flag.origin.y > stem.start.y)
    }

    @Test("a fully beamed group paints no flags")
    func beamedGroupPaintsNoFlags() throws {
        let engraved = try NotationEngraver.engrave(Fixtures.document(
            notes: (0..<2).map {
                Fixtures.makeNote(
                    id: $0 + 1, localTick: $0 * 240, staffStep: 3,
                    duration: .eighth, durationTicks: 240
                )
            },
            rests: [], controls: []
        ), style: style)
        #expect(engraved.flags.isEmpty)
    }

    @Test("a partially covered plan paints one eighth component per uncovered level")
    func componentPlanPaintsUncoveredLevels() throws {
        // An isolated sixteenth chord normally plans canonical(2 levels).
        // Inject synthetic level-0 coverage through the shared planning seam
        // so the defensive component arm paints level 1 alone.
        let input = try Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, duration: .sixteenth, durationTicks: 120),
                Fixtures.makeNote(id: 2, localTick: 0, staffStep: 5, duration: .sixteenth, durationTicks: 120)
            ],
            rests: [], controls: []
        )
        let ownerIndex = try #require(
            StemTopologyBuilder().build(input).events.firstIndex { $0.localTick == 0 }
        )
        let synthetic = BeamTopologyResult(
            primaryGroups: [],
            coveredLevelsByEventIndex: [ownerIndex: [0]]
        )
        let stemTopology = StemTopologyBuilder().build(input, topology: synthetic)
        #expect(stemTopology.flagPlans == [.components([1])])

        let engraved = NotationEngraver.engrave(input, style: style, stemTopology: stemTopology)
        let stem = try #require(engraved.stems.first { $0.noteIDs.contains(1) })
        #expect(engraved.flags.count == 1)
        let flag = try #require(engraved.flags.first)
        #expect(flag.duration == .eighth)
        #expect(flag.flagIndex == 1)
        #expect(flag.noteID == 1)
        #expect(flag.origin == CGPoint(
            x: stem.start.x - style.formatting.stemWidth / 2,
            y: stem.end.y + style.flagVerticalSpacing
        ))
    }

    @Test("formatter-reserved column extents contain the painted flag bounds")
    func reservedExtentsContainPaintedFlagBounds() throws {
        // An unbeamed sixteenth run: the canonical flag is the widest ink the
        // formatter must have reserved inside its column extents.
        let input = try Fixtures.document(
            notes: (0..<3).map {
                Fixtures.makeNote(
                    id: $0 + 1, localTick: $0 * 480, staffStep: 3,
                    duration: .sixteenth, durationTicks: 240
                )
            },
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)
        #expect(engraved.flags.count == 3)

        let notesByID = Dictionary(input.notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for flag in engraved.flags {
            let note = try #require(notesByID[flag.noteID])
            let column = try Fixtures.column(
                engraved.formatted,
                measureIndex: note.position.measureIndex,
                localTick: note.position.localTick
            )
            let metrics = PercussionGlyphMetrics.flag(
                duration: flag.duration,
                direction: flag.stemDirection,
                staffSpace: staffSpace
            )
            let painted = metrics.paintedBounds.offsetBy(
                dx: flag.origin.x - metrics.attachmentOffset.x,
                dy: flag.origin.y - metrics.attachmentOffset.y
            )
            #expect(painted.minX >= column.logicalColumnX - column.leftExtent - 0.001)
            #expect(painted.maxX <= column.logicalColumnX + column.rightExtent + 0.001)
        }
    }
}

@Suite("Engraver articulations and controls")
struct EngraverArticulationControlTests {
    private let style = NotationEngravingStyle()
    private let halfSpace = NotationFormattingStyle.virgoDefault.staffSpace / 2

    @Test("notes without an articulation emit no marks")
    func notesWithoutArticulationEmitNoMarks() throws {
        let engraved = try NotationEngraver.engrave(Fixtures.document(
            notes: [
                Fixtures.makeNote(id: 7, localTick: 240, staffStep: 2, duration: .quarter, durationTicks: 480),
                Fixtures.makeNote(id: 9, localTick: 240, staffStep: 5, duration: .quarter, durationTicks: 480)
            ],
            rests: [], controls: []
        ), style: style)

        #expect(engraved.articulations.isEmpty)
    }

    @Test("articulated notes emit one mark per articulating head")
    func articulatedNotesEmitMarks() throws {
        let input = try Fixtures.document(
            notes: [
                Fixtures.makeNote(
                    id: 9, localTick: 240, staffStep: 5, duration: .quarter,
                    durationTicks: 480, articulation: .open
                ),
                Fixtures.makeNote(id: 7, localTick: 240, staffStep: 2, duration: .quarter, durationTicks: 480)
            ],
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)

        #expect(engraved.articulations.count == 1)
        let mark = try #require(engraved.articulations.first)
        let head = try #require(engraved.noteHeads.first { $0.noteID == 9 })
        #expect(mark.noteID == 9)
        #expect(mark.kind == .open)
        #expect(mark.position == CGPoint(
            x: head.position.x,
            y: head.position.y - style.articulationVerticalOffset
        ))
    }

    @Test("controls keep their kind and sit on the logical column at the target staff step")
    func controlsKeepKindAndPlacement() throws {
        let input = try Fixtures.document(
            notes: [],
            rests: [],
            controls: [
                ResolvedControl(
                    id: 1,
                    position: NotationTickPosition(measureIndex: 0, localTick: 0),
                    kind: .stop, targetStaffStep: 4
                ),
                ResolvedControl(
                    id: 2,
                    position: NotationTickPosition(measureIndex: 0, localTick: 480),
                    kind: .choke, targetStaffStep: 6
                ),
                ResolvedControl(
                    id: 3,
                    position: NotationTickPosition(measureIndex: 0, localTick: 960),
                    kind: .damp, targetStaffStep: 2
                )
            ]
        )
        let engraved = try NotationEngraver.engrave(input, style: style)
        #expect(engraved.controls.count == 3)
        #expect(engraved.controls.map(\.kind) == [.stop, .choke, .damp])
        #expect(engraved.controls.map(\.controlID) == [1, 2, 3])

        let row = try #require(engraved.rows.first)
        for control in engraved.controls {
            let resolved = try #require(input.controls.first { $0.id == control.controlID })
            let column = try Fixtures.column(
                engraved.formatted,
                measureIndex: resolved.position.measureIndex,
                localTick: resolved.position.localTick
            )
            let expectedY = row.staffCenterY
                + CGFloat(4 - resolved.targetStaffStep) * halfSpace
                - style.stopMarkVerticalOffset
            #expect(control.position == CGPoint(x: column.logicalColumnX, y: expectedY))
            #expect(control.rowIndex == row.index)
            #expect(control.measureIndex == resolved.position.measureIndex)
        }
    }
}
