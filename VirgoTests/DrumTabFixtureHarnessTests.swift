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
}
