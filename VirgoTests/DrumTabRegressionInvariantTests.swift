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

    /// `multiRowStableWidths` alternates 16-note and 1-note measures and wraps
    /// to multiple rows -- it is the catalog's only fixture built specifically
    /// to expose density-dependent spacing.
    ///
    /// `TabGrid` carries exactly one `tickWidth` for the whole rendered chart
    /// (`NotationLayout.tabGrid` is a single value, not one grid per measure),
    /// and `TabGrid.xPosition(in:localTick:)` computes
    /// `measure.contentStartX + clampedTick * tickWidth` from only that shared
    /// `tickWidth` and the measure's own `contentStartX`/`durationTicks`. So
    /// the first `#expect` below -- recomputing `xPosition` at a measure's own
    /// `durationTicks` and comparing it to `durationTicks * tickWidth` -- holds
    /// by construction today: both sides read the same stored `tickWidth`, so
    /// this cannot currently fail without `xPosition`'s own formula becoming
    /// non-linear or per-measure (which is exactly the shape a reintroduced
    /// HPA-97 spacing bug would take, so it stays as a named regression pin on
    /// that formula rather than being deleted).
    ///
    /// The second `#expect` was originally written to compare `measure.width`
    /// against `grid.leftPadding + durationTicks * tickWidth`, on the theory
    /// that `.width` came from a different code path than `.contentStartX`.
    /// It did not: `width = tabGrid.leftPadding + durationTicks * tickWidth`
    /// is `NotationLayoutEngine.buildMeasures`'s own formula
    /// (`NotationLayoutEngine.swift:259`) restated verbatim off the same
    /// `grid` instance, so it was exactly as tautological as the first
    /// `#expect` -- confirmed by fault injection in review: a +37 shift added
    /// to `RenderedMeasure.contentStartX`'s formula left both assertions
    /// green while `DrumTabGoldenTests` went red 11/11.
    ///
    /// It has been replaced with a genuine cross-check between two
    /// independently-written expressions of the same padding constant:
    /// `RenderedMeasure.contentStartX` (`NotationLayout.swift:343`, `xOffset +
    /// GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing`) versus
    /// `TabGrid.leftPadding` (`NotationLayoutEngine+TabGrid.swift:28,55`, the
    /// same two constants, written independently in a different file).
    /// `contentStartX - xOffset` isolates the padding term from the first
    /// expression; comparing it to `grid.leftPadding` is what would catch a
    /// future edit to either expression (e.g. adding a label margin to one)
    /// without updating the other. Verified to go red under the exact fault
    /// injected above (re-checked locally before committing this fix).
    @Test("one tick scale spans every measure and row", arguments: DrumTabFixtureCatalog.all)
    func singleTickScaleChartWide(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let grid = result.layout.tabGrid
        for measure in result.layout.measures {
            let expectedContentSpan = CGFloat(measure.durationTicks) * grid.tickWidth
            let actualContentSpan = grid
                .xPosition(in: measure, localTick: measure.durationTicks)
                - measure.contentStartX
            #expect(
                abs(actualContentSpan - expectedContentSpan) < tolerance,
                Comment(rawValue: "measure \(measure.measureIndex) content span \(actualContentSpan) "
                    + "!= tick span \(expectedContentSpan)")
            )

            let actualPadding = measure.contentStartX - measure.xOffset
            #expect(
                abs(actualPadding - grid.leftPadding) < tolerance,
                Comment(rawValue: "measure \(measure.measureIndex) contentStartX padding \(actualPadding) "
                    + "!= grid.leftPadding \(grid.leftPadding)")
            )
        }
    }

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
        let grid = result.layout.tabGrid
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
            let measureIndex = first.timeColumn.measureIndex
            let renderedMeasure = try #require(
                result.layout.measures.first { $0.measureIndex == measureIndex }
            )
            let rhythmMeasure = try #require(
                result.snapshot.measures.first { $0.measureIndex == measureIndex }
            )
            let group = try #require(
                rhythmMeasure.beatGroups.first {
                    first.timeColumn.tickWithinMeasure >= $0.startTick
                        && first.timeColumn.tickWithinMeasure < $0.endTick
                }
            )
            let groupWidth = grid.xPosition(
                in: renderedMeasure,
                localTick: group.startTick + group.durationTicks
            ) - grid.xPosition(in: renderedMeasure, localTick: group.startTick)

            let beamWidth = abs(beam.end.x - beam.start.x)
            #expect(
                beamWidth <= groupWidth + result.style.beamHookLength + tolerance,
                "beam \(beam.id) spans \(beamWidth) > beat group \(groupWidth)"
            )
        }
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

    /// Every note head's rendered x must equal what the grid says its own
    /// tick should place it at. This is the suite's actual density-invariance
    /// gate for screenshot failure mode 1 (inconsistent spacing): it compares
    /// real `head.position.x` -- as `NotationLayoutEngine.buildNoteHeads`
    /// actually computed it, for every head in every fixture, including
    /// `multiRowStableWidths`'s alternating 16-note/1-note measures -- against
    /// `TabGrid.xPosition` recomputed independently. This is what would catch
    /// a regression where note placement stops routing through `xPosition`
    /// (e.g. computing x from note index or local density instead of tick).
    ///
    /// An earlier version of this suite also had a dedicated dense-vs-sparse
    /// test that called `TabGrid.xPosition` directly on both sides instead of
    /// reading real positions. It was removed (not weakened, deleted): it
    /// reduced algebraically to `delta * grid.tickWidth == delta *
    /// grid.tickWidth` off one shared grid instance and could not fail short
    /// of rewriting `xPosition` itself. Unlike here, there was no way to
    /// substitute real head positions for its sparse side -- every sparse
    /// measure in `multiRowStableWidths` has exactly one onset, so there is
    /// no second real data point in a sparse measure to derive a slope from,
    /// and every other geometric quantity in this layout engine (measure
    /// widths, bar positions) is likewise defined in terms of the same single
    /// `tickWidth`, leaving no independent ground truth to compare against.
    /// This test is the replacement: it doesn't need a second data point per
    /// measure, because it checks each head's own tick against its own
    /// position directly, across all 11 fixtures.
    ///
    /// Know what it does and does not own. Production assigns
    /// `head.position.x = tabGrid.xPosition(in:localTick:)`
    /// (`NotationLayoutEngine.swift:354-355`) and this test recomputes that
    /// same call, so it pins *routing*: every head reaching its own tick's
    /// column through the one shared grid, which is what catches
    /// index-based-instead-of-tick-based placement. It cannot catch a change
    /// to `xPosition`'s own formula -- if that became measure- or
    /// density-dependent (the literal HPA-97 shape), both sides of this
    /// comparison would move together and stay green.
    ///
    /// The durable mitigation for that case is `singleTickScaleChartWide`'s
    /// first `#expect` above: it compares `xPosition(in: measure, localTick:
    /// measure.durationTicks) - measure.contentStartX` against
    /// `measure.durationTicks * grid.tickWidth` -- an expression derived
    /// independently of any recorded output -- so it fails outright if
    /// `xPosition` starts reading anything other than the one shared
    /// `tickWidth`. Unlike a golden, there is nothing to re-bless: this
    /// assertion has no stored expected value that a good-faith regeneration
    /// could carry the bug into, so it survives regeneration in a way the
    /// goldens structurally cannot. The goldens (which pin every head's exact
    /// `pos=`, see `NotationLayoutDigest.swift`) are secondary cover for the
    /// same case -- they would also fail, 11 of them at once -- but they are
    /// the weaker net because someone re-blessing a golden in good faith
    /// would bless the regression along with it.
    @Test("every note head sits on its own tick's grid x", arguments: DrumTabFixtureCatalog.all)
    func headsSitOnGridPositions(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let grid = result.layout.tabGrid
        // Dictionary(grouping:) rather than uniqueKeysWithValues: so a
        // regression that ever produced two measures sharing a measureIndex
        // fails this test's own #require, instead of trapping the whole
        // in-process test host on a duplicate-key precondition (same
        // reasoning as `DrumTabGoldenTests.stopChokeDamp`'s `stopNotesByKind`).
        let measuresByIndex = Dictionary(grouping: result.layout.measures, by: \.measureIndex)

        #expect(
            !result.layout.noteHeads.isEmpty,
            "\(fixture.name) must have note heads for this check to be non-vacuous"
        )

        for head in result.layout.noteHeads {
            let measure = try #require(measuresByIndex[head.timeColumn.measureIndex]?.first)
            let expected = grid.xPosition(
                in: measure,
                localTick: head.timeColumn.tickWithinMeasure
            )
            #expect(
                abs(head.position.x - expected) < tolerance,
                "head \(head.id) at x \(head.position.x), grid says \(expected)"
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
    /// nine of those thirteen categories (the ones with layout-affecting
    /// visual extent most relevant to a screenshot regression) and asserts
    /// each is contained in that stored union. Because the stored union
    /// already covers a strict superset of what is checked, this cannot fail
    /// today except by `calculatePaintedBounds` itself becoming incomplete
    /// (dropping a primitive category from the union, or being invoked with a
    /// different style than layout actually used) -- exactly the shape of bug
    /// that would clip a primitive out of the rendered/scrollable content
    /// area without necessarily changing any single primitive's own recorded
    /// position.
    @Test("painted bounds contain every primitive", arguments: DrumTabFixtureCatalog.all)
    func paintedBoundsContainEveryPrimitive(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let layout = result.layout
        let style = result.style
        let bounds = layout.noteHeads.map { $0.paintedBounds(style: style) }
            + layout.rests.filter(\.isPrinted).map { $0.paintedBounds(style: style) }
            + layout.stopNotes.map { $0.paintedBounds(style: style) }
            + layout.articulations.map { $0.paintedBounds(style: style) }
            + layout.stems.map { $0.paintedBounds(style: style) }
            + layout.beams.map { $0.paintedBounds(style: style) }
            + layout.flags.map { $0.paintedBounds(style: style) }
            + layout.ledgerLines.map { $0.paintedBounds(style: style) }
            + layout.measureBars.map { $0.paintedBounds(style: style) }

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
