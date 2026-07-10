import Testing
import CoreGraphics
@testable import Virgo

@Suite("Notation Layout Note Position Override Tests")
struct NotationLayoutNotePositionOverrideTests {

    @Test("Override changes the note head Y to match the custom position")
    func overrideChangesNoteHeadY() {
        let snareNote = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
        let baseY = GameplayLayout.StaffLinePosition.line1.absoluteY(for: 0)

        let defaultLayout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [snareNote], timeSignature: .fourFour)
        )
        #expect(defaultLayout.noteHeads.count == 1)
        #expect(defaultLayout.noteHeads[0].position.y == baseY + DrumType.snare.notePosition.yOffset)

        let overriddenLayout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                notes: [snareNote],
                timeSignature: .fourFour,
                notePositionOverrides: [.snare: .aboveLine6]
            )
        )
        #expect(overriddenLayout.noteHeads.count == 1)
        #expect(overriddenLayout.noteHeads[0].position.y == baseY + GameplayLayout.NotePosition.aboveLine6.yOffset)
    }

    @Test("Override updates staffStep so ledger lines render at the custom position")
    func overrideUpdatesStaffStepAndLedgerLines() {
        let snareNote = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)

        // Default snare sits on line 3 — no ledger lines.
        let defaultLayout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [snareNote], timeSignature: .fourFour)
        )
        #expect(defaultLayout.ledgerLines.isEmpty)

        // Forcing the snare far above the staff must produce ledger lines.
        let overriddenLayout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                notes: [snareNote],
                timeSignature: .fourFour,
                notePositionOverrides: [.snare: .aboveLine9]
            )
        )
        #expect(!overriddenLayout.ledgerLines.isEmpty)
    }

    @Test("Position override preserves canonical upper-voice stem direction")
    func positionOverridePreservesCanonicalStemDirection() throws {
        let snare = Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: 0
        )
        let defaultLayout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [snare], timeSignature: .fourFour)
        )
        let overriddenLayout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                notes: [snare],
                timeSignature: .fourFour,
                notePositionOverrides: [.snare: .aboveLine9]
            )
        )
        let defaultHead = try #require(defaultLayout.noteHeads.first)
        let head = try #require(overriddenLayout.noteHeads.first)

        #expect(head.position.y != defaultHead.position.y)
        #expect(head.position.x == defaultHead.position.x)
        #expect(head.sourceObjectID == defaultHead.sourceObjectID)
        #expect(head.sourceLaneID == defaultHead.sourceLaneID)
        #expect(head.sourceChipID == defaultHead.sourceChipID)
        #expect(head.noteType == defaultHead.noteType)
        #expect(head.drumType == defaultHead.drumType)
        #expect(head.glyph == defaultHead.glyph)
        #expect(head.variant == defaultHead.variant)
        #expect(head.voice == .upper)
        #expect(head.voice == defaultHead.voice)
        #expect(head.stemDirection == .up)
        #expect(head.stemDirection == defaultHead.stemDirection)
        #expect(head.position.y == GameplayLayout.NotePosition.aboveLine9.absoluteY(for: 0))
    }

    @Test("Drums without overrides keep their default note position")
    func nonOverriddenDrumsKeepDefaults() {
        let kickNote = Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0)
        let baseY = GameplayLayout.StaffLinePosition.line1.absoluteY(for: 0)

        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                notes: [kickNote],
                timeSignature: .fourFour,
                notePositionOverrides: [.snare: .aboveLine9] // unrelated drum
            )
        )

        #expect(layout.noteHeads.count == 1)
        #expect(layout.noteHeads[0].position.y == baseY + DrumType.kick.notePosition.yOffset)
    }
}

@Suite("DrumNotationSettingsManager Static Loader Tests")
struct DrumNotationSettingsManagerLoaderTests {

    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("loadPositions returns full default mapping when nothing persisted")
    func loadDefaultsWhenEmpty() {
        let defaults = makeSuite("loader-defaults-\(UUID().uuidString)")
        let positions = DrumNotationSettingsManager.loadPositions(from: defaults)

        #expect(positions.count == DrumType.allCases.count)
        for drumType in DrumType.allCases {
            #expect(positions[drumType] == drumType.notePosition)
        }
    }

    @Test("loadPositions reflects values written via the settings manager")
    func loadReflectsPersistedValues() {
        let defaults = makeSuite("loader-persisted-\(UUID().uuidString)")
        let manager = DrumNotationSettingsManager(userDefaults: defaults)
        manager.setNotePosition(.aboveLine7, for: .snare)
        manager.setNotePosition(.belowLine5, for: .kick)

        let positions = DrumNotationSettingsManager.loadPositions(from: defaults)
        #expect(positions[.snare] == .aboveLine7)
        #expect(positions[.kick] == .belowLine5)
        // Untouched drums fall back to defaults.
        #expect(positions[.crash] == DrumType.crash.notePosition)
    }
}
