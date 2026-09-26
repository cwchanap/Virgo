import Testing
import Foundation
import DrumNotation
@testable import Virgo

@Suite("Drum tab fixture harness", .serialized)
@MainActor
struct DrumTabFixtureHarnessTests {
    @Test("harness renders a fixture through the timeline path")
    func rendersThroughTimelinePath() throws {
        let result = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.sameTimeTrio)

        // Six heads: three drums on each of two beats.
        #expect(result.engraved.noteHeads.count == 6)

        // Style must be the pinned one, so goldens cannot drift with window size.
        #expect(result.style == NotationLayoutStyle.gameplayDefault
            .with(rowWidth: GameplayLayout.maxRowWidth))

        // Two distinct time columns, three heads each, one x per column.
        let snapshotNoteByID = Dictionary(
            result.snapshot.notes.map { ($0.eventID.rawValue, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let byColumn = Dictionary(grouping: result.engraved.noteHeads) {
            snapshotNoteByID[$0.noteID]?.position.absoluteTick ?? -1
        }
        #expect(byColumn.count == 2)
        for (_, heads) in byColumn {
            #expect(heads.count == 3)
            #expect(Set(heads.map { $0.position.x }).count == 1)
        }
    }

    /// The returned engraving must BE the production prepared one — the
    /// direct projection/engraving seam exists only to expose
    /// `resolvedInput`, so a regression in `GameplayNotationPreparer.prepare`
    /// cannot be hidden behind a parallel test-side result.
    @Test("harness returns the production prepared engraving")
    func returnedEngravingIsProductionPrepared() throws {
        let result = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.sameTimeTrio)
        let prepared = try DrumTabFixtureHarness.requireEngraved(result.prepared)
        #expect(result.engraved == prepared)
    }

    /// When production preparation fails, the harness must surface the
    /// closed `.failed` state rather than returning an engraving the
    /// production route never produced.
    @Test("binding throws not-ready when production preparation failed")
    func bindingThrowsWhenPreparationFailed() throws {
        let direct = try NotationSnapshotTestSupport().engrave(notes: [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ])
        let prepared = GameplayNotationPreparedState.failed(
            GameplayNotationPreparationFailure(detail: "synthetic failure")
        )
        do {
            _ = try DrumTabFixtureHarness.boundEngraving(prepared: prepared, direct: direct)
            Issue.record("expected notationNotReady, got a bound engraving")
        } catch let error as DrumTabFixtureHarnessError {
            guard case .notationNotReady = error else {
                Issue.record("expected notationNotReady, got \(error)")
                return
            }
        }
    }

    /// The seam result is retained only for `resolvedInput`: if it ever
    /// diverges from the production prepared engraving the harness must
    /// fail rather than let the whole net pass on a parallel result.
    @Test("binding throws when the direct seam diverges from production")
    func bindingThrowsOnDivergence() throws {
        let fixture = DrumTabFixtureCatalog.sameTimeTrio
        let result = try DrumTabFixtureHarness.render(fixture)
        // Same snapshot through the seam at a different row width: the
        // formatting change makes a genuinely different EngravedNotation.
        let divergent = try DrumTabFixtureHarness.engrave(
            snapshot: result.snapshot,
            minimumMeasureCount: fixture.minimumMeasureCount,
            style: DrumTabFixtureHarness.lockedStyle.with(rowWidth: 2_400)
        )
        #expect(
            divergent.engraved != result.engraved,
            "the 2400pt sabotage must actually diverge from the locked-width engraving"
        )
        do {
            _ = try DrumTabFixtureHarness.boundEngraving(
                prepared: result.prepared,
                direct: divergent.engraved
            )
            Issue.record("expected engravingDiverged, got a bound engraving")
        } catch let error as DrumTabFixtureHarnessError {
            guard case .engravingDiverged = error else {
                Issue.record("expected engravingDiverged, got \(error)")
                return
            }
        }
    }
}
