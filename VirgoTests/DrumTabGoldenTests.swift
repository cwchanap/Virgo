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

    /// The `rest` subsection of a digest, for differential comparison.
    private func restLines(_ result: FixtureRenderResult) -> [String] {
        NotationLayoutDigest.make(result)
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("rest ") }
    }
}
