import Testing
import CoreGraphics
import DrumNotation
@testable import Virgo

/// Adapter/preparer integration for note-position overrides: an override
/// must reach the staff step (Y placement, ledger lines) through
/// `VirgoNotationProjection.resolvedNotation` and the package engraver, not
/// just the rendered head.
///
/// Y is asserted row-relative: the engraver normalizes the whole sheet by
/// one shift, so `head.position.y - rows[rowIndex].staffCenterY` is the
/// stable quantity. A `GameplayLayout.NotePosition.yOffset` of `n` half
/// staff-spaces below the bottom line maps to pitch-ascending staff step
/// `-yOffset / (staffSpace / 2)`; the middle line is step 4, so the
/// row-relative head Y is `-(staffStep - 4) * staffSpace / 2`.
@Suite("Notation Layout Note Position Override Tests")
struct NotationLayoutNotePositionOverrideTests {
    private let support = NotationSnapshotTestSupport()

    /// Row-relative head Y for `position` under the package convention.
    /// Subpixel normalization leaves a floating-point residue, so callers
    /// compare with `tolerance`.
    private func expectedRowRelativeY(
        _ position: GameplayLayout.NotePosition,
        engraved: EngravedNotation
    ) -> CGFloat {
        let halfStaffSpace = engraved.style.formatting.staffSpace / 2
        let staffStep = -(position.yOffset / halfStaffSpace).rounded()
        return -(staffStep - 4) * halfStaffSpace
    }

    private let tolerance: CGFloat = 0.001

    @Test("Override changes the note head Y to match the custom position")
    func overrideChangesNoteHeadY() throws {
        let snareNote = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)

        let defaultEngraved = try support.requireEngraved(support.prepare(notes: [snareNote]))
        let defaultHead = try #require(defaultEngraved.noteHeads.first)
        let defaultCenterY = defaultEngraved.rows[defaultHead.rowIndex].staffCenterY
        #expect(
            abs(defaultHead.position.y - defaultCenterY
                - expectedRowRelativeY(DrumType.snare.notePosition, engraved: defaultEngraved))
                < tolerance
        )

        let overriddenEngraved = try support.requireEngraved(support.prepare(
            notes: [snareNote],
            notePositionOverrides: [.snare: .aboveLine6]
        ))
        let head = try #require(overriddenEngraved.noteHeads.first)
        let centerY = overriddenEngraved.rows[head.rowIndex].staffCenterY
        #expect(
            abs(head.position.y - centerY
                - expectedRowRelativeY(.aboveLine6, engraved: overriddenEngraved))
                < tolerance
        )
    }

    @Test("Override updates staffStep so ledger lines render at the custom position")
    func overrideUpdatesStaffStepAndLedgerLines() throws {
        let snareNote = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)

        // Default snare sits on line 3 — no ledger lines.
        let defaultEngraved = try support.requireEngraved(support.prepare(notes: [snareNote]))
        #expect(defaultEngraved.ledgerLines.isEmpty)

        // Forcing the snare far above the staff must produce ledger lines.
        let overriddenEngraved = try support.requireEngraved(support.prepare(
            notes: [snareNote],
            notePositionOverrides: [.snare: .aboveLine9]
        ))
        #expect(!overriddenEngraved.ledgerLines.isEmpty)
        #expect(
            overriddenEngraved.ledgerLines.allSatisfy {
                $0.noteID == overriddenEngraved.noteHeads.first?.noteID
            }
        )
    }

    @Test("Position override preserves canonical upper-voice stem direction")
    func positionOverridePreservesCanonicalStemDirection() throws {
        let snare = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        let defaultEngraved = try support.requireEngraved(support.prepare(notes: [snare]))
        let overriddenEngraved = try support.requireEngraved(support.prepare(
            notes: [snare],
            notePositionOverrides: [.snare: .aboveLine9]
        ))
        let defaultHead = try #require(defaultEngraved.noteHeads.first)
        let head = try #require(overriddenEngraved.noteHeads.first)

        #expect(head.noteID == defaultHead.noteID)
        #expect(head.position.x == defaultHead.position.x)
        // The staff step moved; the canonical voice/stem identity did not.
        #expect(head.staffStep != defaultHead.staffStep)
        #expect(head.noteheadStyle == defaultHead.noteheadStyle)
        #expect(head.voice == .upper)
        #expect(head.voice == defaultHead.voice)
        #expect(head.stemDirection == .up)
        #expect(head.stemDirection == defaultHead.stemDirection)
        #expect(head.duration == defaultHead.duration)

        let centerY = overriddenEngraved.rows[head.rowIndex].staffCenterY
        #expect(
            abs(head.position.y - centerY
                - expectedRowRelativeY(.aboveLine9, engraved: overriddenEngraved))
                < tolerance
        )
    }

    @Test("Drums without overrides keep their default note position")
    func nonOverriddenDrumsKeepDefaults() throws {
        let kickNote = Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0)

        let engraved = try support.requireEngraved(support.prepare(
            notes: [kickNote],
            notePositionOverrides: [.snare: .aboveLine9] // unrelated drum
        ))

        let head = try #require(engraved.noteHeads.first)
        let centerY = engraved.rows[head.rowIndex].staffCenterY
        #expect(
            abs(head.position.y - centerY
                - expectedRowRelativeY(DrumType.kick.notePosition, engraved: engraved))
                < tolerance
        )
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
