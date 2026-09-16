import Testing
import Foundation
import DrumNotation
@testable import Virgo

@Suite("Drum tab golden digests", .serialized)
@MainActor
struct DrumTabGoldenTests {
    @Test("same-time-trio matches its golden digest")
    func sameTimeTrio() throws {
        let result = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.sameTimeTrio)
        #expect(result.engraved.noteHeads.count == 6)
        try GoldenFile.assertMatches(
            EngravedNotationDigest.make(result),
            fixture: DrumTabFixtureCatalog.sameTimeTrio.name
        )
    }

    @Test("sixteenth run beams per beat group, not per measure")
    func sixteenthRun() throws {
        let fixture = DrumTabFixtureCatalog.sixteenthRun
        let result = try DrumTabFixtureHarness.render(fixture)

        // Measure 0: 16 content sixteenths. Measure 1: 1 sentinel note that
        // keeps measure 0's last onset supported (see the fixture's doc
        // comment).
        #expect(result.engraved.noteHeads.count == 17)
        #expect(result.engraved.measures.count == 2)

        // 4/4 at this resolution has four quarter-note beat groups. Each
        // holds a contiguous run of four sixteenths, so beat-scoped topology
        // must produce exactly four distinct primary (level 0) beam runs of
        // four notes each -- never one run spanning the whole measure (the
        // HPA-97 "overlong connection bar" regression).
        let primaryRuns = result.engraved.beams.filter { $0.level == 0 }
        let distinctPrimaryRuns = Set(primaryRuns.map { $0.noteIDs.sorted() })
        #expect(distinctPrimaryRuns.count == 4)
        #expect(distinctPrimaryRuns.allSatisfy { $0.count == 4 })

        try GoldenFile.assertMatches(
            EngravedNotationDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("mixed eighth/sixteenth beat renders a partial secondary beam")
    func mixedEighthSixteenth() throws {
        let fixture = DrumTabFixtureCatalog.mixedEighthSixteenth
        let result = try DrumTabFixtureHarness.render(fixture)

        // Measure 0: 4 beats * (1 eighth + 2 sixteenths) = 12 content notes.
        // Measure 1: 1 sentinel note.
        #expect(result.engraved.noteHeads.count == 13)

        // Each beat's eighth + two sixteenths form one primary (level 0) run
        // of 3 notes (adjacency is exact: eighth spans 2 ticks to the first
        // sixteenth, which spans 1 tick to the second). Only the two
        // sixteenths need the second beam line, so the secondary (level 1)
        // beam for that beat covers just those 2 notes -- strictly fewer
        // than its primary run's 3. That is the partial secondary beam
        // required by HPA-142: a renderer that (incorrectly) beams the
        // eighth at the secondary level too would produce a level-1 beam
        // with noteIDs.count == 3, matching the primary and failing this
        // gate.
        let primaryRuns = result.engraved.beams.filter { $0.level == 0 }
        let secondaryBeams = result.engraved.beams.filter { $0.level >= 1 }
        #expect(Set(primaryRuns.map { $0.noteIDs.sorted() }).count == 4)
        #expect(primaryRuns.allSatisfy { $0.noteIDs.count == 3 })
        #expect(secondaryBeams.count == 4, "mixed beat must produce a partial secondary beam per beat")
        #expect(secondaryBeams.allSatisfy { $0.noteIDs.count == 2 })

        try GoldenFile.assertMatches(
            EngravedNotationDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("isolated beamable notes render flags and no beams")
    func isolatedFlaggedNotes() throws {
        let fixture = DrumTabFixtureCatalog.isolatedFlaggedNotes
        let result = try DrumTabFixtureHarness.render(fixture)

        // Measure 0: 4 hi-hat + 4 kick content notes. Measure 1: 1 hi-hat +
        // 1 kick sentinel note (see the fixture's doc comment for why the two
        // lone notes live on separate voices in the same measure rather than
        // in two same-voice measures).
        #expect(result.engraved.noteHeads.count == 10)
        #expect(result.engraved.measures.count == 2)

        // The hi-hat's lone sixteenth (position 3) has no beat-mate to run
        // with, so it must flag: the stem group's plan resolves to one
        // canonical `.sixteenth` flag glyph (the glyph itself carries both
        // flag arms). The kick's lone eighth (position 2) resolves to one
        // canonical `.eighth` flag. Total: 2 flags on 2 distinct stem-group
        // representatives, and zero beams anywhere (every note in both
        // voices is alone in its beat group). A plan that degraded to
        // `.eighth` components would emit the wrong durations here.
        #expect(result.engraved.flags.count == 2)
        #expect(result.engraved.beams.isEmpty, "a lone beamable note must flag, not beam")
        #expect(Set(result.engraved.flags.map(\.noteID)).count == 2)
        #expect(Set(result.engraved.flags.map(\.duration)) == [.sixteenth, .eighth])

        // The canonical family must follow the lone note's own duration:
        // the sixteenth flag hangs from the lane-11 hi-hat head, the eighth
        // flag from the lane-13 kick head.
        let sixteenthFlag = try #require(
            result.engraved.flags.first { $0.duration == .sixteenth }
        )
        let eighthFlag = try #require(
            result.engraved.flags.first { $0.duration == .eighth }
        )
        #expect(snapshotLane(of: sixteenthFlag.noteID, in: result) == "11")
        #expect(snapshotLane(of: eighthFlag.noteID, in: result) == "13")

        try GoldenFile.assertMatches(
            EngravedNotationDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("open, closed, and pedal hi-hat stay three distinct mappings")
    func hiHatOpenClosedPedal() throws {
        let fixture = DrumTabFixtureCatalog.hiHatOpenClosedPedal
        let result = try DrumTabFixtureHarness.render(fixture)

        #expect(result.engraved.noteHeads.count == 3)

        // (drumType, notehead style) is not enough: open and closed hi-hat
        // share `gameplayInstrument == .hiHat` and map to the same package
        // `PercussionNoteheadStyle.x` -- only `variant` carries the
        // open/closed/pedal distinction. A regression that collapses two of
        // the three articulations to the same variant (e.g. open reporting
        // as closed) must fail this set comparison, so the variants are
        // asserted directly. Variants are analyzer facts the package
        // primitives intentionally do not carry, so they are joined back
        // from the snapshot by source event ID.
        let variants = Set(result.engraved.noteHeads.compactMap {
            resolvedVariant(of: $0.noteID, in: result)
        })
        #expect(variants == [.openHiHat, .closedHiHat, .pedalHiHat],
                "expected the three hi-hat variants, got \(variants)")

        try GoldenFile.assertMatches(
            EngravedNotationDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("lane 1C imports as a playable kick instead of being dropped")
    func leftBass1C() throws {
        let fixture = DrumTabFixtureCatalog.leftBass1C
        let result = try DrumTabFixtureHarness.render(fixture)

        #expect(result.engraved.noteHeads.count == 2)
        // Count alone is not enough: another lane surviving would satisfy it
        // while 1C was silently dropped. `variant` is also required, not
        // just `sourceLaneID`/`drumType`: those two fields are copied
        // straight from the source note and stay "1C"/.kick even if
        // DrumNotationCatalog.resolve's lane lookup mismatches and falls
        // back to definition.defaultVariant (.standard, the same variant
        // plain lane 13 gets) -- a lane-matching bug in `resolve` would
        // silently collapse 1C into an indistinguishable-from-13 kick
        // without tripping sourceLaneID or drumType at all.
        let leftBass = result.engraved.noteHeads.filter { head in
            let note = snapshotNote(of: head.noteID, in: result)
            let resolved = note.flatMap {
                DrumNotationCatalog.resolve(noteType: $0.noteType, sourceLaneID: $0.sourceLaneID)
            }
            return note?.sourceLaneID == "1C"
                && resolved?.definition.gameplayInstrument == .kick
                && resolved?.variant == .leftBass
        }
        #expect(leftBass.count == 1, "lane 1C must map to a kick head with the leftBass variant")

        try GoldenFile.assertMatches(
            EngravedNotationDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("stop, choke, and damp render as stop marks without disturbing rests")
    func stopChokeDamp() throws {
        let fixture = DrumTabFixtureCatalog.stopChokeDamp
        let withControls = try DrumTabFixtureHarness.render(fixture, includeControls: true)
        let withoutControls = try DrumTabFixtureHarness.render(fixture, includeControls: false)

        #expect(withControls.engraved.controls.count == 3)
        #expect(withoutControls.engraved.controls.isEmpty)
        #expect(
            Set(withControls.engraved.controls.map(\.kind)) == [.stop, .choke, .damp]
        )

        // Count and kind distinctness alone would not catch a target lost,
        // defaulted, or swapped across the 16/11 boundary (e.g. damp
        // resolving to crash instead of hi-hat). They would NOT catch stop
        // and choke swapping targets with each other -- both declare "16",
        // so that particular swap is undetectable by any assertion here.
        // `Dictionary(grouping:)` rather than `uniqueKeysWithValues:` so a
        // regression that collapses two kinds together (the exact failure
        // this gate exists to catch) fails the #expect above and returns
        // gracefully, instead of trapping the whole test-host process on a
        // duplicate-key precondition.
        //
        // `EngravedControl` carries the resolved staff-step intent, not the
        // source lane, so the target lane/display name are joined back from
        // the analyzer snapshot by control event ID.
        let controlsByKind = Dictionary(grouping: withControls.engraved.controls, by: \.kind)
        let stop = controlsByKind[.stop]?.first
        let choke = controlsByKind[.choke]?.first
        let damp = controlsByKind[.damp]?.first
        #expect(controlTargetLane(of: stop?.controlID, in: withControls) == "16")
        #expect(controlTargetName(of: stop?.controlID, in: withControls) == "Crash")
        #expect(controlTargetLane(of: choke?.controlID, in: withControls) == "16")
        #expect(controlTargetName(of: choke?.controlID, in: withControls) == "Crash")
        #expect(controlTargetLane(of: damp?.controlID, in: withControls) == "11")
        #expect(controlTargetName(of: damp?.controlID, in: withControls) == "Hi-Hat")

        // Differential proof of separation: identical playable lanes must yield
        // identical rests whether or not control chips are present. "rests
        // unaffected" is only checkable against a baseline.
        #expect(restLines(withControls) == restLines(withoutControls))
        #expect(!restLines(withControls).isEmpty, "differential is vacuous unless both sides have rests")
        // Both-sides-non-empty is satisfiable by measure 0's always-present,
        // control-free lead-in rests alone (see the fixture's doc comment).
        // Pin the rest that actually sits in the control-bearing measure, so
        // if the measure-2 sentinel is ever removed and measure 1's rest is
        // stripped again, this gate -- not just prose -- catches it.
        #expect(
            restLines(withControls).contains { $0.hasPrefix("rest  m1 ") },
            "differential must include a rest from the control-bearing measure"
        )

        // Playable content must also be untouched by the control chips.
        #expect(
            withControls.engraved.noteHeads.count == withoutControls.engraved.noteHeads.count
        )

        try GoldenFile.assertMatches(
            EngravedNotationDigest.make(withControls),
            fixture: fixture.name
        )
    }

    @Test("sparse high-resolution grid preserves timing without 64th notes")
    func sparseHiResLane() throws {
        let fixture = DrumTabFixtureCatalog.sparseHiResLane
        let result = try DrumTabFixtureHarness.render(fixture)

        // Measure 0: 2 content chips. Measure 1: 1 sentinel chip (see the
        // fixture's doc comment for why the sentinel is needed even though
        // measure 0 is unsupported regardless of its presence).
        #expect(result.engraved.noteHeads.count == 3)
        let contentHeads = result.engraved.noteHeads.filter { $0.measureIndex == 0 }
        #expect(contentHeads.count == 2)
        // Grid resolution must not become visual duration: both chips are
        // spaced 33/64 apart, which snaps to a real, pinned `.half` -- not
        // merely "anything but .sixtyfourth" (six other wrong values would
        // still pass a `!=` check). The verdict is the analyzer's
        // `rhythm.baseInterval`, joined from the snapshot by event ID.
        #expect(contentHeads.allSatisfy {
            snapshotNote(of: $0.noteID, in: result)?.rhythm.baseInterval == .half
        })
        // Timing must survive: the second chip sits at 33/64 of the measure.
        // Looked up explicitly rather than via `measures.first` -- content
        // lives in measure 0 here, but that shortcut is unsafe in general
        // (see the fixture's doc comment and `sixteenthRun`'s).
        let measure = try #require(result.engraved.measures.first { $0.index == 0 })
        let ticks = contentHeads
            .compactMap { snapshotNote(of: $0.noteID, in: result)?.position.localTick }
            .sorted()
        #expect(ticks.first == 0)
        #expect(ticks.last == measure.durationTicks * 33 / 64)

        try GoldenFile.assertMatches(
            EngravedNotationDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("upper and lower voices get independent rests while sounding together")
    func voiceRests() throws {
        let fixture = DrumTabFixtureCatalog.voiceRests
        let result = try DrumTabFixtureHarness.render(fixture)

        // Measure 0: 3 hi-hat notes (beats 2-4) + 2 kick notes (beats 3-4),
        // both voices sounding in the same supported measure. Measure 1: 1
        // hi-hat sentinel + 1 kick sentinel (see the fixture's doc comment).
        #expect(result.engraved.noteHeads.count == 7)

        // Every engraved rest is printed by construction: the projection
        // filters hidden rests before the package ever sees them.
        let printedUpper = result.engraved.rests.filter { $0.voice == .upper }
        let printedLower = result.engraved.rests.filter { $0.voice == .lower }
        // Hi-hat rests only beat 1 (one quarter); kick rests beats 1-2 (two
        // quarters, one per beat group -- see the fixture's doc comment on
        // why a two-beat leading gap is two rest events, not one half
        // rest). Pinning count, measure, tick, AND duration for both voices
        // means a regression that computes one voice's gaps from the other
        // voice's onsets (e.g. dropping the `voice ==` filter in
        // `NotationRestTopologyBuilder.buildExact`, `NotationRestTopology
        // .swift:567`) would make the two sets match and fail here.
        #expect(printedUpper.count == 1)
        #expect(printedLower.count == 2)
        #expect(printedUpper.allSatisfy { $0.measureIndex == 0 && $0.duration == .quarter })
        #expect(printedLower.allSatisfy { $0.measureIndex == 0 && $0.duration == .quarter })
        #expect(Set(printedUpper.map { restLocalTick(of: $0.restID, in: result) }) == [0])
        #expect(Set(printedLower.map { restLocalTick(of: $0.restID, in: result) }) == [0, 1])

        try GoldenFile.assertMatches(
            EngravedNotationDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("multi-row chart keeps one tick scale across sparse and dense measures")
    func multiRowStableWidths() throws {
        let fixture = DrumTabFixtureCatalog.multiRowStableWidths
        let result = try DrumTabFixtureHarness.render(fixture)

        #expect(result.engraved.measures.count == 8)
        #expect(Set(result.engraved.measures.map(\.rowIndex)).count >= 2, "fixture must wrap rows")
        // Pins the dense/sparse alternation itself. A bare total
        // (`noteHeads.count == 68`, 4 sparse * 1 + 4 dense * 16) would pass
        // unchanged if the alternation were flipped -- 4 sparse + 4 dense
        // measures sum to 68 no matter which four indices are which -- so
        // it only catches the degenerate "every measure sparse/dense" case.
        // Pinning note count per measure index instead also catches a
        // flipped `isMultiple(of: 2)`.
        let perMeasureCounts = (0..<8).map { index in
            result.engraved.noteHeads.filter { $0.measureIndex == index }.count
        }
        #expect(perMeasureCounts == [1, 16, 1, 16, 1, 16, 1, 16])

        try GoldenFile.assertMatches(
            EngravedNotationDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("triplet grid engraves tuplets, or falls back with a specific diagnostic")
    func tripletGrid() throws {
        let fixture = DrumTabFixtureCatalog.tripletGrid
        let result = try DrumTabFixtureHarness.render(fixture)

        // Measure 0: 12 content notes (four eighth-note triplet groups).
        // Measure 1: 1 sentinel note (see the fixture's doc comment).
        #expect(result.engraved.noteHeads.count == 13)

        // Content lives in measure 0 (not 1), so this lookup is unambiguous:
        // there is no empty lead-in measure ahead of it (see the fixture's
        // doc comment and `sixteenthRun`'s).
        let measure = try #require(
            result.snapshot.measures.first { $0.measureIndex == 0 }
        )

        // Conditional, not a free choice: if the engine can engrave this
        // measure, the tuplet form is required. Accepting either branch
        // would let a regression that degrades real triplets into the
        // fallback pass.
        switch measure.engravingSupport {
        case .supported:
            // Dead today (the live branch is the fallback below), so it has
            // to be written for the day HPA-145 lands rather than merely
            // compile. A chart-wide `!tuplets.isEmpty` would pass on a fix
            // that engraved 1 of the 4 groups -- the exact partial fix this
            // fixture exists to reject -- so scope it to the measure under
            // test and pin the count. `EngravedTuplet` carries no measure
            // index, so membership is joined through the resolved input.
            let engraved = result.engraved.tuplets.filter {
                resolvedInputMeasure(of: $0.tupletID, in: result) == 0
            }
            #expect(
                engraved.count == 4,
                "engraving is supported, so all four triplet groups must render as tuplets"
            )
        case let .warning(codes):
            Issue.record(
                "triplet grid must remain structurally unsupported, got warning codes \(codes.map(\.rawValue).sorted())"
            )
        case let .unsupported(codes):
            // A bare "codes is non-empty" check would be vacuous: an
            // `.unsupported` measure always names at least one code, so it
            // passes whether triplets engrave, degrade, or fail outright.
            // Pin the exact set instead, so adding or dropping a diagnostic
            // here has to be a deliberate re-blessing.
            //
            // `.incompleteTuplet` is the triplet-specific half and the one
            // that makes this fixture mean something.
            //
            // `.indeterminateTerminalDuration` rides along, but NOT because
            // of the chart-terminal trap that `sixteenthRun` and
            // `stopChokeDamp` guard against. `resolveStream` builds its
            // `dtxOnsets` set from the events of one beat-group stream
            // (`NotationRhythmAnalyzer.swift:208-210`), so
            // `hasFollowingDTXOnset` is beat-group-scoped: the last onset of
            // *each* of the four triplet groups has no follower within its
            // own stream and reaches `terminalDTXResolution` (:239). Four of
            // the twelve onsets, in the middle of the chart as much as at
            // its end -- which is why adding or removing a trailing measure
            // changes nothing here (measured directly).
            //
            // The other eight onsets are `.unsupported(.ambiguousBeatGrouping)`:
            // `classify(spanTicks: 1, ticksPerWholeNote: 12)` finds no match,
            // since at this grid `.quarter`/.half/.full ARE integral (3/6/12
            // ticks) but a 1-tick span equals none of them and `.eighth`
            // would need 1.5 (`NotationRhythmAnalyzer.swift:37-54`, :681-694).
            // That code never reaches the measure's code set: it only makes
            // `unsupportedSpan` true, which is what produces
            // `.incompleteTuplet` (:492-503).
            #expect(
                Set(codes) == [.incompleteTuplet, .indeterminateTerminalDuration],
                Comment(rawValue: "expected the documented HPA-145 fallback set, got "
                    + "\(codes.map(\.rawValue).sorted())")
            )

            // An unsupported measure must not also emit tuplet marks: an
            // engine that renders tuplet brackets while still reporting the
            // measure unsupported is a new inconsistency, not a fix.
            #expect(result.engraved.tuplets.isEmpty)
        }

        // Differential proof that `.incompleteTuplet` is caused by the
        // 12-position content rather than being ambient: the sentinel
        // measure holds one plain full-measure note and must remain
        // supported. Run unconditionally so the guard survives the day
        // HPA-145 lands and measure 0 flips to `.supported` -- otherwise
        // the supported branch would skip this check entirely, and a
        // regression that stamped `.incompleteTuplet` on every measure
        // would pass the supported-branch assertion above while breaking
        // the sentinel silently.
        let sentinelMeasure = try #require(
            result.snapshot.measures.first { $0.measureIndex == 1 }
        )
        #expect(sentinelMeasure.engravingSupport == .supported)

        try GoldenFile.assertMatches(
            EngravedNotationDigest.make(result),
            fixture: fixture.name
        )
    }

    /// The `rest` subsection of a digest, for differential comparison.
    private func restLines(_ result: FixtureRenderResult) -> [String] {
        EngravedNotationDigest.make(result)
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("rest ") }
    }

    /// The analyzer's source note for one engraved head, joined by source
    /// event ID — lane/variant/rhythm are analyzer facts the package
    /// primitives intentionally do not carry.
    private func snapshotNote(of noteID: Int, in result: FixtureRenderResult) -> RhythmLayoutNote? {
        result.snapshot.notes.first { $0.eventID.rawValue == noteID }
    }

    /// The analyzer's catalog variant for one engraved head.
    private func resolvedVariant(
        of noteID: Int,
        in result: FixtureRenderResult
    ) -> DrumNotationVariant? {
        snapshotNote(of: noteID, in: result).flatMap {
            DrumNotationCatalog.resolve(noteType: $0.noteType, sourceLaneID: $0.sourceLaneID)?.variant
        }
    }

    /// The source lane an engraved control targets, joined by control event ID.
    private func controlTargetLane(of controlID: Int?, in result: FixtureRenderResult) -> String? {
        guard let controlID else { return nil }
        return result.snapshot.controls
            .first { $0.eventID.rawValue == controlID }?
            .event.targetLaneID
    }

    /// The display name of an engraved control's target lane.
    private func controlTargetName(of controlID: Int?, in result: FixtureRenderResult) -> String? {
        controlTargetLane(of: controlID, in: result)
            .flatMap { DrumNotationCatalog.resolveTarget(laneID: $0)?.displayName }
    }

    /// A printed rest's local tick, joined through the resolved input —
    /// `EngravedRest` carries final geometry, not timing.
    private func restLocalTick(of restID: Int, in result: FixtureRenderResult) -> Int {
        result.resolvedInput.rests.first { $0.id == restID }?.position.localTick ?? -1
    }

    /// A resolved tuplet group's measure index — `EngravedTuplet` carries
    /// the adapter-local ID, not the measure.
    private func resolvedInputMeasure(of tupletID: Int, in result: FixtureRenderResult) -> Int {
        result.resolvedInput.tuplets.first { $0.id == tupletID }?.measureIndex ?? -1
    }

    /// A head's source lane ID, joined through the analyzer snapshot.
    private func snapshotLane(of noteID: Int, in result: FixtureRenderResult) -> String? {
        snapshotNote(of: noteID, in: result)?.sourceLaneID
    }
}
