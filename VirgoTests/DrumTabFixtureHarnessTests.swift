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
    /// identities named in the task are compared.
    @Test("old layout and package engraving agree on shared identities",
          arguments: DrumTabFixtureCatalog.all)
    func oldAndPackageOutputsBridge(_ fixture: DrumTabFixture) throws {
        let result = try DrumTabFixtureHarness.render(fixture)

        // Both routes consume the measured formatter; the formatted output
        // the engraving embedded must equal the one the old layout composed
        // from — one assertion that covers every column X, head-center X,
        // rest visual X, measure xOffset/width and row assignment at once.
        #expect(
            result.engraved.formatted == result.layout.formattedNotation,
            "\(fixture.name): package formatted output diverged from the layout's"
        )

        // Measure count/index and row packing.
        #expect(
            result.engraved.measures.map(\.index) == result.layout.measures.map(\.measureIndex),
            "\(fixture.name): measure index lists disagree"
        )
        #expect(
            result.engraved.measures.map(\.rowIndex) == result.layout.measures.map(\.row),
            "\(fixture.name): row packing disagrees"
        )
        #expect(
            result.engraved.measures.map(\.xOffset) == result.layout.measures.map(\.xOffset),
            "\(fixture.name): measure xOffsets disagree"
        )
        #expect(
            result.engraved.measures.map(\.width) == result.layout.measures.map(\.width),
            "\(fixture.name): measure widths disagree"
        )

        // Note event IDs survive the projection verbatim.
        #expect(
            Set(result.engraved.noteHeads.map(\.noteID))
                == Set(result.layout.noteHeads.map { Int($0.id) }),
            "\(fixture.name): note event ID sets disagree"
        )

        // Control kinds/IDs cross as the same resolved intent.
        #expect(
            result.engraved.controls.map(\.controlID).sorted()
                == result.layout.stopNotes.compactMap { $0.eventID?.rawValue }.sorted(),
            "\(fixture.name): control IDs disagree"
        )
        #expect(
            result.engraved.controls.map(\.kind.rawValue).sorted()
                == result.layout.stopNotes.map { $0.kind.rawValue }.sorted(),
            "\(fixture.name): control kinds disagree"
        )

        // formatted tick -> row/X: the playhead lookup must agree on both
        // surfaces for every resolved onset tick.
        for note in result.resolvedInput.notes {
            let oldPosition = result.layout.formattedNotation.position(
                measureIndex: note.position.measureIndex,
                localTick: Double(note.position.localTick)
            )
            let newPosition = result.engraved.position(
                measureIndex: note.position.measureIndex,
                localTick: Double(note.position.localTick)
            )
            #expect(
                oldPosition?.rowIndex == newPosition?.rowIndex,
                "\(fixture.name): tick \(note.position) row disagrees"
            )
            #expect(
                oldPosition?.x == newPosition?.x,
                "\(fixture.name): tick \(note.position) x disagrees"
            )
        }
    }
}
