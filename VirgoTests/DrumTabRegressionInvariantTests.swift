import Testing
import Foundation
import CoreGraphics
@testable import Virgo

/// Cross-cutting geometric invariants over the drum-tab fixture catalog.
///
/// Where `DrumTabGoldenTests` pins exact per-fixture output, this suite targets
/// the two HPA-97 screenshot failure modes directly: inconsistent spacing
/// (dense measures compressing or sparse ones stretching relative to a shared
/// tick scale -- the genuinely falsifiable gate for this is
/// `headsSitOnGridPositions` under Cross-cutting, which compares real
/// rendered note positions against the grid; see its doc comment) and
/// overlong connection bars (beams whose drawn extent exceeds what their own
/// members or beat group justify). It also carries a few chart-wide sanity
/// checks (grid placement, simultaneous-onset alignment, painted-bounds
/// coverage) that goldens exercise per fixture but never state as an
/// explicit, reusable claim.
@Suite("Drum tab regression invariants", .serialized)
@MainActor
struct DrumTabRegressionInvariantTests {
    private let tolerance: CGFloat = 0.01

    // MARK: - Screenshot failure mode 1: inconsistent spacing

    // `multiRowStableWidths` alternates 16-note and 1-note measures and wraps
    // to multiple rows -- it is the catalog's only fixture built specifically
    // to expose density-dependent spacing. Its fixed-grid "one tick scale"
    // invariant was deleted with the grid (HPA-164 Task 6); measured spacing
    // invariants now live in `MeasuredGeometryInvariantsTests` and the
    // package's `NotationFormatterSpacingTests`.

    // MARK: - Screenshot failure mode 2: overlong connection bars

    /// Checks a beam's drawn extent against the stem-anchor x of the note
    /// heads it claims (`beam.noteHeadIDs`) as members, with `beamHookLength`
    /// slack for hook segments that deliberately extend partway past their
    /// single owner toward a neighbor (see `NotationLayoutEngine+Beams.swift`,
    /// `beamEndpoint`'s `.forwardHook`/`.backwardHook` case).
    ///
    /// This catches a *geometry* bug: a beam's `start`/`end` computed from the
    /// wrong representative note, or a hook overshooting its capped length. It
    /// would NOT by itself catch a *grouping* bug where beat groups are merged
    /// (e.g. all sixteen notes in a measure treated as one run instead of four
    /// beat-scoped ones) -- in that case `noteHeadIDs` and the drawn extent
    /// would still agree with each other, just both be wrong relative to the
    /// music. `beamsStayWithinTheirBeatGroup` below catches that class
    /// instead, by comparing against `RhythmMeasure.beatGroups`, a source
    /// independent of the beam topology itself.
    ///
    /// Every beam in every one of the eleven catalog fixtures is currently
    /// `kind == .full` (confirmed against the committed goldens -- none
    /// contain `kind=forwardHook`/`kind=backwardHook`), so `hookSlack` is not
    /// exercised on its interesting branch by any fixture today; it is kept
    /// so a future fixture that does produce a hook segment is covered
    /// without editing this test.
    @Test("no beam extends past its own member stems", arguments: [
        DrumTabFixtureCatalog.sixteenthRun,
        DrumTabFixtureCatalog.mixedEighthSixteenth,
        DrumTabFixtureCatalog.multiRowStableWidths
    ])
    func beamsStayWithinTheirMembers(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let stemXByHead = stemXByHeadID(result)
        let hookSlack = result.style.beamHookLength + tolerance

        #expect(!result.layout.beams.isEmpty, "\(fixture.name) must produce beams for this check to be non-vacuous")

        for beam in result.layout.beams {
            let memberXs = beam.noteHeadIDs.compactMap { stemXByHead[$0] }
            #expect(memberXs.count == beam.noteHeadIDs.count,
                    "beam \(beam.id): \(beam.noteHeadIDs.count - memberXs.count) member(s) have no stem")
            guard let low = memberXs.min(), let high = memberXs.max() else { continue }
            let beamLow = min(beam.start.x, beam.end.x)
            let beamHigh = max(beam.start.x, beam.end.x)

            #expect(
                beamLow >= low - hookSlack,
                "beam \(beam.id) starts \(beamLow) left of its members (\(low))"
            )
            #expect(
                beamHigh <= high + hookSlack,
                "beam \(beam.id) ends \(beamHigh) right of its members (\(high))"
            )
        }
    }

    /// The genuinely independent half of the overlong-beam check:
    /// `groupWidth` comes from `RhythmMeasure.beatGroups`
    /// (`RhythmBeatGroupBuilder`, the rhythm-timeline side), while `beamWidth`
    /// comes from `NotationBeamTopologyBuilder` by way of rendered beam
    /// geometry -- two separate subsystems. A regression that merged beat
    /// groups in the beam builder (the historical HPA-97 shape: one beam
    /// spanning a whole measure instead of one per beat) would widen
    /// `beamWidth` well past `groupWidth` while leaving the rhythm timeline's
    /// own beat groups untouched, and this assertion would fail. The sibling
    /// golden test (`DrumTabGoldenTests.sixteenthRun`) already pins the exact
    /// beam count/membership for this fixture; this test pins the geometric
    /// consequence instead, so the two fail independently if either the
    /// grouping or the pixel math regresses.
    @Test("no beam spans wider than its beat group")
    func beamsStayWithinTheirBeatGroup() throws {
        let result = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.sixteenthRun)
        let formatted = result.layout.formattedNotation
        // Dictionary(grouping:) rather than uniqueKeysWithValues: a duplicate
        // note-head ID fails this test's own lookup instead of trapping the
        // whole in-process test host (same reasoning as
        // `DrumTabGoldenTests.stopChokeDamp`'s `stopNotesByKind`).
        let headByID = Dictionary(grouping: result.layout.noteHeads, by: \.id)

        #expect(!result.layout.beams.isEmpty, "sixteenthRun must produce beams for this check to be non-vacuous")

        for beam in result.layout.beams {
            let heads = beam.noteHeadIDs.compactMap { headByID[$0]?.first }
            #expect(heads.count == beam.noteHeadIDs.count,
                    "beam \(beam.id): \(beam.noteHeadIDs.count - heads.count) member(s) have no head")
            guard let first = heads.first else { continue }

            // Derive the beat-group key for every member head and require they
            // all belong to exactly one beat group. A short beam connecting
            // the last note of one beat to the first note of the next can
            // cross the boundary while still being narrower than either group,
            // so the width check below alone would not catch it. The sibling
            // partition guard (`beamMembersShareTheirPartition`) checks
            // measure/row/voice/direction but not beat-group identity.
            let beatGroupKeys = Set(heads.map { beatGroupKey(head: $0, in: result.snapshot) })
            #expect(
                beatGroupKeys.count == 1,
                "beam \(beam.id) members span \(beatGroupKeys.count) beat groups: \(beatGroupKeys)"
            )

            let measureIndex = first.timeColumn.measureIndex
            let rhythmMeasure = try #require(
                result.snapshot.measures.first { $0.measureIndex == measureIndex }
            )
            let group = try #require(
                rhythmMeasure.beatGroups.first {
                    first.timeColumn.tickWithinMeasure >= $0.startTick
                        && first.timeColumn.tickWithinMeasure < $0.endTick
                }
            )
            // Group width from the composed formatter lookup (the live
            // playhead's own X source), not from any engine-side grid.
            let groupStartX = try #require(
                formatted.position(measureIndex: measureIndex, localTick: Double(group.startTick))
            ).x
            let groupEndX = try #require(
                formatted.position(measureIndex: measureIndex, localTick: Double(group.startTick + group.durationTicks))
            ).x
            let groupWidth = abs(groupEndX - groupStartX)

            let beamWidth = abs(beam.end.x - beam.start.x)
            #expect(
                beamWidth <= groupWidth + result.style.beamHookLength + tolerance,
                "beam \(beam.id) spans \(beamWidth) > beat group \(groupWidth)"
            )
        }
    }

    /// Beat-group identity key for a rendered note head: `(measureIndex,
    /// groupIndex)` of the `RhythmBeatGroup` whose tick range contains the
    /// head's `tickWithinMeasure`. Returns `nil` (mapped to `-1`) if the head
    /// falls outside every beat group — which would itself be a bug worth
    /// surfacing, since the `beatGroupKeys.count == 1` check above would then
    /// fail rather than silently passing.
    private func beatGroupKey(
        head: RenderedNoteHead,
        in snapshot: RhythmLayoutSnapshot
    ) -> [Int] {
        let measureIndex = head.timeColumn.measureIndex
        guard let rhythmMeasure = snapshot.measures.first(where: { $0.measureIndex == measureIndex }) else {
            return [measureIndex, -1]
        }
        let groupIndex = rhythmMeasure.beatGroups.first {
            head.timeColumn.tickWithinMeasure >= $0.startTick
                && head.timeColumn.tickWithinMeasure < $0.endTick
        }?.groupIndex ?? -1
        return [measureIndex, groupIndex]
    }

    /// Structural guard, not a behavioral invariant:
    /// `NotationBeamTopologyBuilder.GroupKey` (`NotationBeamTopology.swift`)
    /// partitions events by `measureIndex`, `row`, `voice`, `direction`,
    /// `beatGroupIndex`, `beatGroupStartTick`, and `beatGroupDurationTicks`
    /// before any run or beam is built, and every `RenderedBeam.noteHeadIDs`
    /// traces back to one `BeamPrimaryGroup` built from one `GroupKey`. So the
    /// four fields checked below cannot currently disagree within a beam --
    /// this exists to catch a future change that drops `measureIndex`, `row`,
    /// `voice`, or `direction` from that key (e.g. merging two voices'
    /// beat-group streams together), not a behavior this suite can observe
    /// going wrong today.
    @Test("beam members agree on measure, row, voice, and direction (partition guard)")
    func beamMembersShareTheirPartition() throws {
        for fixture in DrumTabFixtureCatalog.all {
            let result = try DrumTabFixtureHarness.render(fixture)
            // Dictionary(grouping:) rather than uniqueKeysWithValues: see
            // `beamsStayWithinTheirBeatGroup`'s `headByID` above.
            let headByID = Dictionary(grouping: result.layout.noteHeads, by: \.id)
            for beam in result.layout.beams {
                let heads = beam.noteHeadIDs.compactMap { headByID[$0]?.first }
                #expect(heads.count == beam.noteHeadIDs.count,
                        "beam \(beam.id): \(beam.noteHeadIDs.count - heads.count) member(s) have no head")
                #expect(Set(heads.map(\.timeColumn.measureIndex)).count <= 1)
                #expect(Set(heads.map(\.row)).count <= 1)
                #expect(Set(heads.map(\.voice)).count <= 1)
                #expect(Set(heads.map(\.stemDirection)).count <= 1)
            }
        }
    }

    // MARK: - Cross-cutting

    /// Every composed head sits exactly at its package `headCenterX` (HPA-164
    /// replaced the fixed grid: the formatter is the X authority, so a head
    /// drifting off the package column is a composition bug). Undisplaced
    /// heads additionally sit on the tick's `logicalColumnX` — the playhead's
    /// own anchor. This is the suite's density-invariance gate for screenshot
    /// failure mode 1 (inconsistent spacing): it compares real
    /// `head.position.x` for every head in every fixture against the package
    /// output, so placement that stops routing through the composed columns
    /// (e.g. computing x from note index or local density instead of the
    /// package column) fails here.
    @Test("every note head sits on its package head center x", arguments: DrumTabFixtureCatalog.all)
    func headsSitOnGridPositions(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let formatted = result.layout.formattedNotation
        var headCenterXByID: [UInt64: CGFloat] = [:]
        for measure in formatted.measures {
            for column in measure.columns {
                for head in column.noteHeads {
                    headCenterXByID[UInt64(head.noteID)] = head.headCenterX
                }
            }
        }

        #expect(
            !result.layout.noteHeads.isEmpty,
            "\(fixture.name) must have note heads for this check to be non-vacuous"
        )

        for head in result.layout.noteHeads {
            let expected = try #require(headCenterXByID[head.id])
            #expect(
                abs(head.position.x - expected) < tolerance,
                "head \(head.id) at x \(head.position.x), package says \(expected)"
            )
        }
    }

    /// Notes struck together (same absolute tick) must land on one x column --
    /// the direct regression check for HPA-141 (`same-time-trio`'s subject),
    /// generalized to every fixture. Rounds to the nearest 1/100pt before
    /// comparing so this only flags a real column disagreement, not float
    /// noise from independently-derived positions.
    ///
    /// Only 3 of the 11 fixtures actually strike more than one head on the
    /// same tick (verified against their goldens): `same-time-trio` (2
    /// three-note chords, its entire subject), `isolated-flagged-notes` (4
    /// shared ticks across its two independent voices), and `voice-rests` (3,
    /// same reason). The other 8 are single-onset-per-tick by construction,
    /// so `xs.count == 1` holds vacuously for them -- reporting "11 test
    /// cases passed" would overstate how many actually exercise the column
    /// check by ~3.7x. The guard below keeps that honest by failing loudly if
    /// one of the three chord-bearing fixtures ever stops producing a shared
    /// tick (e.g. a fixture edit that accidentally desyncs the two voices).
    @Test("simultaneous heads share one x column", arguments: DrumTabFixtureCatalog.all)
    func simultaneousHeadsShareColumn(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let byTick = Dictionary(grouping: result.layout.noteHeads) {
            $0.timeColumn.absoluteLayoutTick
        }

        let fixturesRequiringAChord: Set<String> = [
            DrumTabFixtureCatalog.sameTimeTrio.name,
            DrumTabFixtureCatalog.isolatedFlaggedNotes.name,
            DrumTabFixtureCatalog.voiceRests.name
        ]
        if fixturesRequiringAChord.contains(fixture.name) {
            #expect(
                byTick.values.contains { $0.count > 1 },
                "\(fixture.name) must have a shared-tick chord for this check to be non-vacuous"
            )
        }

        for (tick, heads) in byTick {
            let xs = Set(heads.map { ($0.position.x * 100).rounded() })
            #expect(xs.count == 1, "tick \(tick) heads span \(xs.count) x positions")
        }
    }

    /// `NotationLayout.paintedBounds` is set once, in
    /// `NotationLayoutEngine.finalizedLayout`, as the union of
    /// `paintedBounds(style:)` across *every* primitive category the layout
    /// carries (noteHeads, rests, stopNotes, articulations, stems, beams,
    /// flags, ledgerLines, measureBars, rhythmDots, tuplets, feelMarks,
    /// rhythmWarnings -- `calculatePaintedBounds`,
    /// `NotationRhythmRendering.swift`). This check recomputes bounds for
    /// all thirteen categories and asserts each is contained in that stored
    /// union. Because the stored union already covers a strict superset of
    /// what is checked, this cannot fail today except by
    /// `calculatePaintedBounds` itself becoming incomplete (dropping a
    /// primitive category from the union, or being invoked with a different
    /// style than layout actually used) -- exactly the shape of bug that
    /// would clip a primitive out of the rendered/scrollable content area
    /// without necessarily changing any single primitive's own recorded
    /// position.
    @Test("painted bounds contain every primitive", arguments: DrumTabFixtureCatalog.all)
    func paintedBoundsContainEveryPrimitive(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let layout = result.layout
        let style = result.style
        var bounds: [CGRect] = []
        bounds.append(contentsOf: layout.noteHeads.map { $0.paintedBounds(style: style) })
        bounds.append(contentsOf: layout.rests.filter(\.isPrinted).map { $0.paintedBounds(style: style) })
        bounds.append(contentsOf: layout.stopNotes.map { $0.paintedBounds(style: style) })
        bounds.append(contentsOf: layout.articulations.map { $0.paintedBounds(style: style) })
        bounds.append(contentsOf: layout.stems.map { $0.paintedBounds(style: style) })
        bounds.append(contentsOf: layout.beams.map { $0.paintedBounds(style: style) })
        bounds.append(contentsOf: VirgoNotationAdapter.flagPaintCommands(
            flags: layout.flags,
            heads: layout.noteHeads,
            style: style
        ).map(\.paintedBounds))
        bounds.append(contentsOf: layout.ledgerLines.map { $0.paintedBounds(style: style) })
        bounds.append(contentsOf: layout.measureBars.map { $0.paintedBounds(style: style) })
        bounds.append(contentsOf: layout.rhythmDots.map { $0.paintedBounds(style: style) })
        bounds.append(contentsOf: layout.tuplets.map { $0.paintedBounds(style: style) })
        bounds.append(contentsOf: layout.feelMarks.map { $0.paintedBounds(style: style) })
        bounds.append(contentsOf: layout.rhythmWarnings.map { $0.paintedBounds(style: style) })

        var checked = 0
        for rect in bounds where !rect.isNull {
            checked += 1
            #expect(layout.paintedBounds.contains(rect))
        }
        #expect(checked > 0, "\(fixture.name) must have at least one non-null primitive to check")
    }

    /// Stem x is the stem anchor, not the head centre -- beam geometry operates
    /// on `stemAnchor(for:).x`. Mapping heads to stem x through the stems keeps
    /// the beam-extent checks honest.
    private func stemXByHeadID(_ result: FixtureRenderResult) -> [UInt64: CGFloat] {
        var map: [UInt64: CGFloat] = [:]
        for stem in result.layout.stems {
            for headID in stem.noteHeadIDs {
                map[headID] = stem.start.x
            }
        }
        return map
    }
}
