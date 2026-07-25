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
}
