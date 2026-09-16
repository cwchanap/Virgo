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

    /// The cheap old-vs-package bridge (HPA-166 Task 6, step 5): the harness
    /// produces both surfaces from one snapshot, so a handful of high-value
    /// identities must agree while both renderers still exist. This is
    /// deliberately NOT a generalized dual-renderer comparator — only the
    /// identities named in the task are compared: measure count/index, note
    /// event IDs, control (ID, kind) pairs, and formatted tick → row/X.
    /// Whole `FormattedNotation` values, row packing, measure offsets and
    /// measure widths are intentionally NOT compared.
    @Test("old layout and package engraving agree on shared identities",
          arguments: DrumTabFixtureCatalog.all)
    func oldAndPackageOutputsBridge(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)

        // Measure count + index sequence only.
        #expect(
            result.engraved.measures.map(\.index) == result.layout.measures.map(\.measureIndex),
            "\(fixture.name): measure index lists disagree"
        )

        // Note event IDs as sorted arrays — multiplicity is load-bearing, so
        // a dropped or duplicated head fails instead of hiding inside a Set.
        let noteIDs = result.bridgeNoteIDs
        #expect(
            noteIDs.package == noteIDs.legacy,
            "\(fixture.name): note event ID lists disagree"
        )

        // Control identities as sorted (eventID, kind) tuples — a kind swap
        // between two controls or a dropped duplicate cannot pass, and a
        // nil legacy eventID fails inside the helper rather than silently
        // narrowing the comparison.
        let controlIdentities = try result.bridgeControlIdentities()
        #expect(
            controlIdentities.package == controlIdentities.legacy,
            "\(fixture.name): control identities disagree"
        )

        // formatted tick -> row/X for every probe tick: every formatted
        // logical column plus every resolved note/rest/control onset, so no
        // relevant tick escapes the check.
        for tick in result.bridgeProbeTicks {
            let oldPosition = result.layout.formattedNotation.position(
                measureIndex: tick.measureIndex,
                localTick: Double(tick.localTick)
            )
            let newPosition = result.engraved.position(
                measureIndex: tick.measureIndex,
                localTick: Double(tick.localTick)
            )
            #expect(
                oldPosition?.rowIndex == newPosition?.rowIndex,
                "\(fixture.name): tick \(tick) row disagrees"
            )
            #expect(
                oldPosition?.x == newPosition?.x,
                "\(fixture.name): tick \(tick) x disagrees"
            )
        }
    }

    /// The probe set must cover every tick the bridge promises to check:
    /// all formatted logical columns plus every resolved note/rest/control
    /// onset — deduplicated, so the loop above cannot silently skip or
    /// double-visit a tick.
    @Test("bridge probe ticks cover every column and event onset",
          arguments: DrumTabFixtureCatalog.all)
    func bridgeProbeTicksCoverAllOnsets(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)
        let probes = Set(result.bridgeProbeTicks)

        for measure in result.engraved.formatted.measures {
            for column in measure.columns {
                #expect(probes.contains(NotationTickPosition(
                    measureIndex: measure.index,
                    localTick: column.localTick
                )), "\(fixture.name): column m\(measure.index) t\(column.localTick) missing from probes")
            }
        }
        let onsets = result.resolvedInput.notes.map(\.position)
            + result.resolvedInput.rests.map(\.position)
            + result.resolvedInput.controls.map(\.position)
        for onset in onsets {
            #expect(
                probes.contains(onset),
                "\(fixture.name): onset \(onset) missing from probes"
            )
        }
        #expect(
            probes.count == result.bridgeProbeTicks.count,
            "\(fixture.name): probe ticks contain duplicates"
        )
    }

    /// Identity helpers must be lossless: sorted ID arrays keep duplicate
    /// note heads, and control tuples keep (eventID, kind) pairs — the
    /// fixture with real controls proves the legacy IDs are all non-nil.
    @Test("bridge identity helpers preserve multiplicity and pairs")
    func bridgeIdentityHelpersAreLossless() throws {
        let result = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.stopChokeDamp)

        let noteIDs = result.bridgeNoteIDs
        #expect(noteIDs.legacy == noteIDs.package)
        #expect(noteIDs.legacy.count == result.layout.noteHeads.count)
        #expect(noteIDs.package.count == result.engraved.noteHeads.count)
        #expect(noteIDs.package == noteIDs.package.sorted())

        let controls = try result.bridgeControlIdentities()
        #expect(controls.legacy == controls.package)
        // stop-choke-damp carries exactly stop + choke + damp.
        #expect(controls.legacy.count == 3)
        #expect(controls.package.count == result.engraved.controls.count)
        #expect(Set(controls.package.map(\.kind)) == ["stop", "choke", "damp"])
        #expect(controls.package == controls.package.sorted())
    }
}
