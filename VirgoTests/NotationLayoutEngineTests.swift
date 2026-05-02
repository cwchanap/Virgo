import Testing
import SwiftUI
@testable import Virgo

@Suite("Notation Layout Engine Tests")
struct NotationLayoutEngineTests {
    @Test("default gameplay style preserves current low-density quarter spacing")
    func defaultStylePreservesQuarterSpacing() {
        let style = NotationLayoutStyle.gameplayDefault

        #expect(style.minimumNoteColumnGap == 28)
        #expect(style.minimumQuarterBeatGap == GameplayLayout.uniformSpacing)
        #expect(style.noteHeadWidth == GameplayLayout.beatColumnWidth)
    }

    @Test("drum types map to gameplay voices")
    func drumTypesMapToGameplayVoices() {
        #expect(NotationVoice.voice(for: .kick) == .lower)
        #expect(NotationVoice.voice(for: .hiHatPedal) == .lower)
        #expect(NotationVoice.voice(for: .snare) == .upper)
        #expect(NotationVoice.voice(for: .crash) == .upper)
    }

    @Test("layout input accepts notes and time signature")
    func layoutInputAcceptsNotesAndTimeSignature() {
        let note = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        let input = NotationLayoutInput(notes: [note], timeSignature: .fourFour)

        #expect(input.notes.count == 1)
        #expect(input.timeSignature.beatsPerMeasure == 4)
        #expect(input.style.minimumNoteColumnGap == 28)
    }
}
