import Testing
import Foundation
@testable import Virgo

@Suite("Drum tab golden digests", .serialized)
@MainActor
struct DrumTabGoldenTests {
    @Test("same-time-trio matches its golden digest")
    func sameTimeTrio() throws {
        let result = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.sameTimeTrio)
        #expect(result.layout.noteHeads.count == 6)
        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
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
        #expect(result.layout.noteHeads.count == 17)
        #expect(result.layout.measures.count == 2)

        // 4/4 at this resolution has four quarter-note beat groups. Each
        // holds a contiguous run of four sixteenths, so beat-scoped topology
        // must produce exactly four distinct primary (level 0) beam runs of
        // four notes each -- never one run spanning the whole measure (the
        // HPA-97 "overlong connection bar" regression).
        let primaryRuns = result.layout.beams.filter { $0.level == 0 }
        let distinctPrimaryRuns = Set(primaryRuns.map { $0.noteHeadIDs.sorted() })
        #expect(distinctPrimaryRuns.count == 4)
        #expect(distinctPrimaryRuns.allSatisfy { $0.count == 4 })

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("mixed eighth/sixteenth beat renders a partial secondary beam")
    func mixedEighthSixteenth() throws {
        let fixture = DrumTabFixtureCatalog.mixedEighthSixteenth
        let result = try DrumTabFixtureHarness.render(fixture)

        // Measure 0: 4 beats * (1 eighth + 2 sixteenths) = 12 content notes.
        // Measure 1: 1 sentinel note.
        #expect(result.layout.noteHeads.count == 13)

        // Each beat's eighth + two sixteenths form one primary (level 0) run
        // of 3 notes (adjacency is exact: eighth spans 2 ticks to the first
        // sixteenth, which spans 1 tick to the second). Only the two
        // sixteenths need the second beam line, so the secondary (level 1)
        // beam for that beat covers just those 2 notes -- strictly fewer
        // than its primary run's 3. That is the partial secondary beam
        // required by HPA-142: a renderer that (incorrectly) beams the
        // eighth at the secondary level too would produce a level-1 beam
        // with noteHeadIDs.count == 3, matching the primary and failing this
        // gate.
        let primaryRuns = result.layout.beams.filter { $0.level == 0 }
        let secondaryBeams = result.layout.beams.filter { $0.level >= 1 }
        #expect(Set(primaryRuns.map { $0.noteHeadIDs.sorted() }).count == 4)
        #expect(primaryRuns.allSatisfy { $0.noteHeadIDs.count == 3 })
        #expect(secondaryBeams.count == 4, "mixed beat must produce a partial secondary beam per beat")
        #expect(secondaryBeams.allSatisfy { $0.noteHeadIDs.count == 2 })

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
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
        #expect(result.layout.noteHeads.count == 10)
        #expect(result.layout.measures.count == 2)

        // The hi-hat's lone sixteenth (position 3) has no beat-mate to run
        // with, so it must flag: sixteenth = 2 flag levels, both uncovered,
        // both on the same head. The kick's lone eighth (position 2) is the
        // same story at 1 flag level. Total: 3 flags across 2 distinct heads,
        // and zero beams anywhere (every note in both voices is alone in its
        // beat group).
        #expect(result.layout.flags.count == 3)
        #expect(result.layout.beams.isEmpty, "a lone beamable note must flag, not beam")

        let flagsByHead = Dictionary(grouping: result.layout.flags, by: \.noteHeadID)
        #expect(flagsByHead.count == 2)
        #expect(flagsByHead.values.map(\.count).sorted() == [1, 2])

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("open, closed, and pedal hi-hat stay three distinct mappings")
    func hiHatOpenClosedPedal() throws {
        let fixture = DrumTabFixtureCatalog.hiHatOpenClosedPedal
        let result = try DrumTabFixtureHarness.render(fixture)

        #expect(result.layout.noteHeads.count == 3)

        // (drumType, glyph) is not enough: open and closed hi-hat share both
        // `gameplayInstrument == .hiHat` and `glyph == .cross` in
        // `DrumNotationCatalog.definitions` -- only `variant` carries the
        // open/closed/pedal distinction. A regression that collapses two of
        // the three articulations to the same variant (e.g. open reporting
        // as closed) must fail this count, so the pair is (glyph, variant).
        let pairs = Set(result.layout.noteHeads.map { "\($0.glyph)|\($0.variant)" })
        #expect(pairs.count == 3, "expected three distinct (glyph, variant) pairs, got \(pairs)")

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("lane 1C imports as a playable kick instead of being dropped")
    func leftBass1C() throws {
        let fixture = DrumTabFixtureCatalog.leftBass1C
        let result = try DrumTabFixtureHarness.render(fixture)

        #expect(result.layout.noteHeads.count == 2)
        // Count alone is not enough: another lane surviving would satisfy it
        // while 1C was silently dropped. `variant` is also required, not
        // just `sourceLaneID`/`drumType`: those two fields are copied
        // straight from the source note and stay "1C"/.kick even if
        // DrumNotationCatalog.resolve's lane lookup mismatches and falls
        // back to definition.defaultVariant (.standard, the same variant
        // plain lane 13 gets) -- a lane-matching bug in `resolve` would
        // silently collapse 1C into an indistinguishable-from-13 kick
        // without tripping sourceLaneID or drumType at all.
        let leftBass = result.layout.noteHeads.filter {
            $0.sourceLaneID == "1C" && $0.drumType == .kick && $0.variant == .leftBass
        }
        #expect(leftBass.count == 1, "lane 1C must map to a kick head with the leftBass variant")

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("stop, choke, and damp render as stop marks without disturbing rests")
    func stopChokeDamp() throws {
        let fixture = DrumTabFixtureCatalog.stopChokeDamp
        let withControls = try DrumTabFixtureHarness.render(fixture, includeControls: true)
        let withoutControls = try DrumTabFixtureHarness.render(fixture, includeControls: false)

        #expect(withControls.layout.stopNotes.count == 3)
        #expect(withoutControls.layout.stopNotes.isEmpty)
        #expect(
            Set(withControls.layout.stopNotes.map(\.kind)) == [.stop, .choke, .damp]
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
        let stopNotesByKind = Dictionary(grouping: withControls.layout.stopNotes, by: \.kind)
        let stop = stopNotesByKind[.stop]?.first
        let choke = stopNotesByKind[.choke]?.first
        let damp = stopNotesByKind[.damp]?.first
        #expect(stop?.targetLaneID == "16")
        #expect(stop?.targetDisplayName == "Crash")
        #expect(choke?.targetLaneID == "16")
        #expect(choke?.targetDisplayName == "Crash")
        #expect(damp?.targetLaneID == "11")
        #expect(damp?.targetDisplayName == "Hi-Hat")

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
            withControls.layout.noteHeads.count == withoutControls.layout.noteHeads.count
        )

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(withControls),
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
        #expect(result.layout.noteHeads.count == 3)
        let contentHeads = result.layout.noteHeads.filter { $0.timeColumn.measureIndex == 0 }
        #expect(contentHeads.count == 2)
        // Grid resolution must not become visual duration: both chips are
        // spaced 33/64 apart, which snaps to a real, pinned `.half` -- not
        // merely "anything but .sixtyfourth" (six other wrong values would
        // still pass a `!=` check).
        #expect(contentHeads.allSatisfy { $0.interval == .half })
        // Timing must survive: the second chip sits at 33/64 of the measure.
        // Looked up explicitly rather than via `measures.first` -- content
        // lives in measure 0 here, but that shortcut is unsafe in general
        // (see the fixture's doc comment and `sixteenthRun`'s).
        let measure = try #require(result.layout.measures.first { $0.measureIndex == 0 })
        let ticks = contentHeads
            .map(\.timeColumn.tickWithinMeasure)
            .sorted()
        #expect(ticks.first == 0)
        #expect(ticks.last == measure.durationTicks * 33 / 64)

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
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
        #expect(result.layout.noteHeads.count == 7)

        let printedUpper = result.layout.rests.filter { $0.isPrinted && $0.voice == .upper }
        let printedLower = result.layout.rests.filter { $0.isPrinted && $0.voice == .lower }
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
        #expect(Set(printedUpper.map(\.timeColumn.tickWithinMeasure)) == [0])
        #expect(Set(printedLower.map(\.timeColumn.tickWithinMeasure)) == [0, 1])

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("multi-row chart keeps one tick scale across sparse and dense measures")
    func multiRowStableWidths() throws {
        let fixture = DrumTabFixtureCatalog.multiRowStableWidths
        let result = try DrumTabFixtureHarness.render(fixture)

        #expect(result.layout.measures.count == 8)
        #expect(Set(result.layout.measures.map(\.row)).count >= 2, "fixture must wrap rows")
        // Pins the dense/sparse alternation itself. A bare total
        // (`noteHeads.count == 68`, 4 sparse * 1 + 4 dense * 16) would pass
        // unchanged if the alternation were flipped -- 4 sparse + 4 dense
        // measures sum to 68 no matter which four indices are which -- so
        // it only catches the degenerate "every measure sparse/dense" case.
        // Pinning note count per measure index instead also catches a
        // flipped `isMultiple(of: 2)`.
        let perMeasureCounts = (0..<8).map { index in
            result.layout.noteHeads.filter { $0.timeColumn.measureIndex == index }.count
        }
        #expect(perMeasureCounts == [1, 16, 1, 16, 1, 16, 1, 16])

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: fixture.name
        )
    }

    @Test("triplet grid engraves tuplets, or falls back with a specific diagnostic")
    func tripletGrid() throws {
        let fixture = DrumTabFixtureCatalog.tripletGrid
        let result = try DrumTabFixtureHarness.render(fixture)

        // Measure 0: 12 content notes (four eighth-note triplet groups).
        // Measure 1: 1 sentinel note (see the fixture's doc comment).
        #expect(result.layout.noteHeads.count == 13)

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
            #expect(
                !result.layout.tuplets.isEmpty,
                "engraving is supported, so the triplet must render as a tuplet"
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
            // `.indeterminateTerminalDuration` rides along because at
            // ticksPerWholeNote 12 no regular interval is integral (an
            // eighth would be 1.5 ticks), so every onset's duration is
            // indeterminate -- here it is NOT evidence of the
            // terminal-measure trap. Verified empirically: measure 0
            // carries both codes identically with and without the
            // trailing sentinel.
            #expect(
                Set(codes) == [.incompleteTuplet, .indeterminateTerminalDuration],
                Comment(rawValue: "expected the documented HPA-145 fallback set, got "
                    + "\(codes.map(\.rawValue).sorted())")
            )

            // Differential proof that `.incompleteTuplet` is caused by the
            // 12-position content rather than being ambient: the sentinel
            // measure holds one plain note and must carry ONLY the
            // indeterminate code. If a regression started stamping
            // `.incompleteTuplet` on every measure, the assertion above
            // would still pass and only this one would catch it.
            let sentinelMeasure = try #require(
                result.snapshot.measures.first { $0.measureIndex == 1 }
            )
            #expect(
                sentinelMeasure.engravingSupport == .unsupported([.indeterminateTerminalDuration])
            )

            // An unsupported measure must not also emit tuplet marks: an
            // engine that renders tuplet brackets while still reporting the
            // measure unsupported is a new inconsistency, not a fix.
            #expect(result.layout.tuplets.isEmpty)
        }

        try GoldenFile.assertMatches(
            NotationLayoutDigest.make(result),
            fixture: fixture.name
        )
    }

    /// The `rest` subsection of a digest, for differential comparison.
    private func restLines(_ result: FixtureRenderResult) -> [String] {
        NotationLayoutDigest.make(result)
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("rest ") }
    }
}
