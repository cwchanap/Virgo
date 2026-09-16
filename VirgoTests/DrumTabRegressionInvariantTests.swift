import Testing
import Foundation
import CoreGraphics
import DrumNotation
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
///
/// HPA-166 Task 6 retargeted every check onto `FixtureRenderResult.engraved`
/// — the package `EngravedNotation` produced from the same real
/// DTX/analyzer/projection path. These stay in `VirgoTests` (not the package
/// test bundle) precisely because the harness exercises that app path; pure
/// package-geometry assertions remain the package tests' job and are not
/// duplicated here.
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
    /// heads it claims (`beam.noteIDs`) as members, with `beamHookLength`
    /// slack for hook segments that deliberately extend partway past their
    /// single owner toward a neighbor (see the package's
    /// `NotationEngraver+Beams.swift`, `beamEndpoint`'s
    /// `.forwardHook`/`.backwardHook` case).
    ///
    /// This catches a *geometry* bug: a beam's `start`/`end` computed from the
    /// wrong representative note, or a hook overshooting its capped length. It
    /// would NOT by itself catch a *grouping* bug where beat groups are merged
    /// (e.g. all sixteen notes in a measure treated as one run instead of four
    /// beat-scoped ones) -- in that case `noteIDs` and the drawn extent
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
        let stemXByNote = stemAxisXByNoteID(result)
        let hookSlack = result.engraved.style.beamHookLength + tolerance

        #expect(!result.engraved.beams.isEmpty,
                "\(fixture.name) must produce beams for this check to be non-vacuous")

        for beam in result.engraved.beams {
            let memberXs = beam.noteIDs.compactMap { stemXByNote[$0] }
            #expect(memberXs.count == beam.noteIDs.count,
                    "beam \(beamLabel(beam)): \(beam.noteIDs.count - memberXs.count) member(s) have no stem")
            guard let low = memberXs.min(), let high = memberXs.max() else { continue }
            let beamLow = min(beam.start.x, beam.end.x)
            let beamHigh = max(beam.start.x, beam.end.x)

            #expect(
                beamLow >= low - hookSlack,
                "beam \(beamLabel(beam)) starts \(beamLow) left of its members (\(low))"
            )
            #expect(
                beamHigh <= high + hookSlack,
                "beam \(beamLabel(beam)) ends \(beamHigh) right of its members (\(high))"
            )
        }
    }

    /// The genuinely independent half of the overlong-beam check:
    /// `groupWidth` comes from `RhythmMeasure.beatGroups`
    /// (`RhythmBeatGroupBuilder`, the rhythm-timeline side), while `beamWidth`
    /// comes from the package `StemTopology` by way of engraved beam
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
        let formatted = result.engraved.formatted
        // Dictionary(grouping:) rather than uniqueKeysWithValues: a duplicate
        // note-head ID fails this test's own lookup instead of trapping the
        // whole in-process test host (same reasoning as
        // `DrumTabGoldenTests.stopChokeDamp`'s `controlsByKind`).
        let headByID = Dictionary(grouping: result.engraved.noteHeads, by: \.noteID)

        #expect(!result.engraved.beams.isEmpty,
                "sixteenthRun must produce beams for this check to be non-vacuous")

        for beam in result.engraved.beams {
            let heads = beam.noteIDs.compactMap { headByID[$0]?.first }
            #expect(heads.count == beam.noteIDs.count,
                    "beam \(beamLabel(beam)): \(beam.noteIDs.count - heads.count) member(s) have no head")
            guard let first = heads.first else { continue }

            // Derive the beat-group key for every member head and require they
            // all belong to exactly one beat group. A short beam connecting
            // the last note of one beat to the first note of the next can
            // cross the boundary while still being narrower than either group,
            // so the width check below alone would not catch it. The sibling
            // partition guard (`beamMembersShareTheirPartition`) checks
            // measure/row/voice/direction but not beat-group identity.
            let beatGroupKeys = Set(heads.map { beatGroupKey(head: $0, in: result) })
            #expect(
                beatGroupKeys.count == 1,
                "beam \(beamLabel(beam)) members span \(beatGroupKeys.count) beat groups: \(beatGroupKeys)"
            )

            let measureIndex = first.measureIndex
            let localTick = try #require(
                result.resolvedInput.notes.first { $0.id == first.noteID }
            ).position.localTick
            let rhythmMeasure = try #require(
                result.snapshot.measures.first { $0.measureIndex == measureIndex }
            )
            let group = try #require(
                rhythmMeasure.beatGroups.first {
                    localTick >= $0.startTick && localTick < $0.endTick
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
                beamWidth <= groupWidth + result.engraved.style.beamHookLength + tolerance,
                "beam \(beamLabel(beam)) spans \(beamWidth) > beat group \(groupWidth)"
            )
        }
    }

    /// Beat-group identity key for an engraved note head: `(measureIndex,
    /// groupIndex)` of the `RhythmBeatGroup` whose tick range contains the
    /// head's resolved local tick. Returns `nil` (mapped to `-1`) if the head
    /// falls outside every beat group — which would itself be a bug worth
    /// surfacing, since the `beatGroupKeys.count == 1` check above would then
    /// fail rather than silently passing.
    private func beatGroupKey(
        head: EngravedNoteHead,
        in result: FixtureRenderResult
    ) -> [Int] {
        let note = result.resolvedInput.notes.first { $0.id == head.noteID }
        let measureIndex = note?.position.measureIndex ?? head.measureIndex
        let localTick = note?.position.localTick ?? -1
        guard let rhythmMeasure = result.snapshot.measures.first(where: { $0.measureIndex == measureIndex }) else {
            return [measureIndex, -1]
        }
        let groupIndex = rhythmMeasure.beatGroups.first {
            localTick >= $0.startTick && localTick < $0.endTick
        }?.groupIndex ?? -1
        return [measureIndex, groupIndex]
    }

    /// Structural guard, not a behavioral invariant: the package
    /// `StemTopology` partitions events by `measureIndex`, `row`, `voice`,
    /// `direction`, and beat-group identity before any run or beam is built,
    /// and every `EngravedBeam.noteIDs` traces back to one primary group
    /// built from one partition key. So the four fields checked below cannot
    /// currently disagree within a beam -- this exists to catch a future
    /// change that drops `measureIndex`, `row`, `voice`, or `direction` from
    /// that key (e.g. merging two voices' beat-group streams together), not
    /// a behavior this suite can observe going wrong today.
    @Test("beam members agree on measure, row, voice, and direction (partition guard)")
    func beamMembersShareTheirPartition() throws {
        for fixture in DrumTabFixtureCatalog.all {
            let result = try DrumTabFixtureHarness.render(fixture)
            // Dictionary(grouping:) rather than uniqueKeysWithValues: see
            // `beamsStayWithinTheirBeatGroup`'s `headByID` above.
            let headByID = Dictionary(grouping: result.engraved.noteHeads, by: \.noteID)
            for beam in result.engraved.beams {
                let heads = beam.noteIDs.compactMap { headByID[$0]?.first }
                #expect(heads.count == beam.noteIDs.count,
                        "beam \(beamLabel(beam)): \(beam.noteIDs.count - heads.count) member(s) have no head")
                #expect(Set(heads.map(\.measureIndex)).count <= 1)
                #expect(Set(heads.map(\.rowIndex)).count <= 1)
                #expect(Set(heads.map(\.voice)).count <= 1)
                #expect(Set(heads.map(\.stemDirection)).count <= 1)
            }
        }
    }

    // MARK: - Cross-cutting

    /// Every engraved head sits exactly at its package `headCenterX` (the
    /// formatter is the X authority, so a head drifting off the formatted
    /// column is a composition bug). This is the suite's density-invariance
    /// gate for screenshot failure mode 1 (inconsistent spacing): it compares
    /// real `head.position.x` for every head in every fixture against the
    /// package output, so placement that stops routing through the composed
    /// columns (e.g. computing x from note index or local density instead of
    /// the package column) fails here.
    @Test("every note head sits on its package head center x", arguments: DrumTabFixtureCatalog.all)
    func headsSitOnGridPositions(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let formatted = result.engraved.formatted
        var headCenterXByID: [Int: CGFloat] = [:]
        for measure in formatted.measures {
            for column in measure.columns {
                for head in column.noteHeads {
                    headCenterXByID[head.noteID] = head.headCenterX
                }
            }
        }

        #expect(
            !result.engraved.noteHeads.isEmpty,
            "\(fixture.name) must have note heads for this check to be non-vacuous"
        )

        for head in result.engraved.noteHeads {
            let expected = try #require(headCenterXByID[head.noteID])
            #expect(
                abs(head.position.x - expected) < tolerance,
                "head \(head.noteID) at x \(head.position.x), package says \(expected)"
            )
        }
    }

    /// Notes struck together (same absolute tick) must land on one x column --
    /// the direct regression check for HPA-141 (`same-time-trio`'s subject),
    /// generalized to every fixture. Rounds to the nearest 1/100pt before
    /// comparing so this only flags a real column disagreement, not float
    /// noise from independently-derived positions. The tick comes from the
    /// analyzer snapshot — the engraved head carries final geometry, not
    /// timing.
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
        let snapshotNoteByID = Dictionary(
            result.snapshot.notes.map { ($0.eventID.rawValue, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let byTick = Dictionary(grouping: result.engraved.noteHeads) {
            snapshotNoteByID[$0.noteID]?.position.absoluteTick ?? -1
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

    /// `EngravedNotation.paintedBounds` is set once, in
    /// `SheetComposer.compose`, as the union of every primitive's ink across
    /// *every* category the engraving carries (note heads, rests, ledgers,
    /// rhythm dots, row furniture, stems, beams, flags, articulations,
    /// controls, tuplets, measure bars). This check recomputes bounds for
    /// all twelve categories — stored bounds where the primitive carries
    /// them, the composer's own formulas where it doesn't — and asserts each
    /// is contained in that stored union. Because the stored union already
    /// covers a strict superset of what is checked, this cannot fail today
    /// except by the compose pass itself becoming incomplete (dropping a
    /// primitive category from the union) -- exactly the shape of bug that
    /// would clip a primitive out of the rendered/scrollable content area
    /// without necessarily changing any single primitive's own recorded
    /// position.
    @Test("painted bounds contain every primitive", arguments: DrumTabFixtureCatalog.all)
    func paintedBoundsContainEveryPrimitive(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let engraved = result.engraved

        var checked = 0
        for rect in primitiveInkBounds(engraved) where !rect.isNull {
            checked += 1
            #expect(
                engraved.paintedBounds.contains(rect),
                "primitive ink \(rect) escapes paintedBounds \(engraved.paintedBounds)"
            )
        }
        #expect(checked > 0, "\(fixture.name) must have at least one non-null primitive to check")
    }

    /// Every primitive's ink bounds, computed exactly the way
    /// `SheetComposer` unions them: stored `paintedBounds` for heads, rests,
    /// ledgers, dots and row furniture; `lineBounds` for stems and beams;
    /// Bravura metrics offset to the origin for flags and articulations; the
    /// mark square for controls; bracket+label for tuplets; the staff-height
    /// bar rect for measure bars.
    private func primitiveInkBounds(_ engraved: EngravedNotation) -> [CGRect] {
        let style = engraved.style
        let staffSpace = style.formatting.staffSpace
        let centerYByRow = Dictionary(
            engraved.rows.map { ($0.index, $0.staffCenterY) },
            uniquingKeysWith: { first, _ in first }
        )
        var bounds: [CGRect] = []
        bounds.append(contentsOf: engraved.noteHeads.map(\.paintedBounds))
        bounds.append(contentsOf: engraved.rests.map(\.paintedBounds))
        bounds.append(contentsOf: engraved.ledgerLines.map(\.paintedBounds))
        bounds.append(contentsOf: engraved.rhythmDots.map(\.paintedBounds))
        bounds.append(contentsOf: engraved.rows.map(\.paintedBounds))
        bounds.append(contentsOf: engraved.stems.map {
            lineBounds(start: $0.start, end: $0.end, lineWidth: style.formatting.stemWidth)
        })
        bounds.append(contentsOf: engraved.beams.map {
            lineBounds(start: $0.start, end: $0.end, lineWidth: $0.thickness)
        })
        bounds.append(contentsOf: engraved.flags.map { flag in
            let metrics = PercussionGlyphMetrics.flag(
                duration: flag.duration,
                direction: flag.stemDirection,
                staffSpace: staffSpace
            )
            return metrics.paintedBounds.offsetBy(
                dx: flag.origin.x - metrics.attachmentOffset.x,
                dy: flag.origin.y - metrics.attachmentOffset.y
            )
        })
        bounds.append(contentsOf: engraved.articulations.map {
            PercussionGlyphMetrics.articulation($0.kind, staffSpace: staffSpace)
                .paintedBounds.offsetBy(dx: $0.position.x, dy: $0.position.y)
        })
        bounds.append(contentsOf: engraved.controls.map {
            let markExtent = style.stopMarkSize + style.stopMarkStrokeWidth
            return CGRect(
                x: $0.position.x - markExtent / 2,
                y: $0.position.y - markExtent / 2,
                width: markExtent,
                height: markExtent
            )
        })
        bounds.append(contentsOf: engraved.tuplets.map {
            tupletInkBounds($0, style: style)
        })
        bounds.append(contentsOf: engraved.measureBars.map { bar in
            let centerY = centerYByRow[bar.rowIndex] ?? 0
            let staffHeight = 4 * staffSpace
            if bar.isFinal {
                let width = style.doubleBarThinWidth
                    + style.doubleBarSpacing + style.doubleBarThickWidth
                return CGRect(
                    x: bar.x - width, y: centerY - staffHeight / 2,
                    width: width, height: staffHeight
                )
            }
            return CGRect(
                x: bar.x - style.barLineWidth / 2, y: centerY - staffHeight / 2,
                width: style.barLineWidth, height: staffHeight
            )
        })
        return bounds
    }

    /// The composer's `lineBounds`: the segment's bounding rect inflated by
    /// half the stroke width on every side.
    private func lineBounds(start: CGPoint, end: CGPoint, lineWidth: CGFloat) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
    }

    /// The composer's `tupletPaintedBounds`: bracket polyline unioned with
    /// the label rect, stroked by `tupletLineWidth`.
    private func tupletInkBounds(_ tuplet: EngravedTuplet, style: NotationEngravingStyle) -> CGRect {
        var bounds = tuplet.bracketPoints.isEmpty
            ? CGRect.null
            : tuplet.bracketPoints.dropFirst().reduce(
                CGRect(origin: tuplet.bracketPoints[0], size: .zero)
            ) { $0.union(CGRect(origin: $1, size: .zero)) }
        bounds = bounds.union(CGRect(
            x: tuplet.labelPosition.x - style.tupletLabelSize.width / 2,
            y: tuplet.labelPosition.y - style.tupletLabelSize.height / 2,
            width: style.tupletLabelSize.width,
            height: style.tupletLabelSize.height
        ))
        return bounds.insetBy(dx: -style.tupletLineWidth / 2, dy: -style.tupletLineWidth / 2)
    }

    /// Stem x is the stem anchor, not the head centre -- beam geometry operates
    /// on the shared stem axis. Mapping heads to stem x through the stems keeps
    /// the beam-extent checks honest.
    private func stemAxisXByNoteID(_ result: FixtureRenderResult) -> [Int: CGFloat] {
        var map: [Int: CGFloat] = [:]
        for stem in result.engraved.stems {
            for noteID in stem.noteIDs {
                map[noteID] = stem.start.x
            }
        }
        return map
    }

    /// `EngravedBeam` carries no synthesized id — this label gives failure
    /// messages the same identifying payload the old `beam.id` provided.
    private func beamLabel(_ beam: EngravedBeam) -> String {
        "ids=\(beam.noteIDs.sorted()) level=\(beam.level) kind=\(beam.kind.rawValue) "
            + "start=(\(beam.start.x),\(beam.start.y)) end=(\(beam.end.x),\(beam.end.y))"
    }
}
