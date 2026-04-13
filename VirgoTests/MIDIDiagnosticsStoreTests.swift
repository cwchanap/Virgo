import Testing
@testable import Virgo

@Suite("MIDIDiagnosticsStore Tests")
@MainActor
struct MIDIDiagnosticsStoreTests {
    @Test("recording a MIDI event updates diagnostics without gameplay state")
    func recordingAMIDIEventUpdatesDiagnosticsWithoutGameplayState() {
        let diagnostics = MIDIDiagnosticsStore()
        let event = MIDINoteEvent(sourceID: "source-2", channel: 9, note: 38, velocity: 120, hostTime: 100)

        diagnostics.record(event: event, mappedDrumType: .snare, sourceDisplayName: "TD-17")

        #expect(diagnostics.lastEvent?.sourceID == "source-2")
        #expect(diagnostics.lastEvent?.sourceDisplayName == "TD-17")
        #expect(diagnostics.lastEvent?.channel == 9)
        #expect(diagnostics.lastEvent?.note == 38)
        #expect(diagnostics.lastEvent?.velocity == 120)
        #expect(diagnostics.lastEvent?.mappedDrumType == .snare)
    }

    @Test("recording an unmapped MIDI event preserves a nil drum preview")
    func recordingAnUnmappedMIDIEventPreservesNilDrumPreview() {
        let diagnostics = MIDIDiagnosticsStore()
        let event = MIDINoteEvent(sourceID: "source-4", channel: 1, note: 99, velocity: 64, hostTime: 200)

        diagnostics.record(event: event, mappedDrumType: nil, sourceDisplayName: "Unknown Pad")

        #expect(diagnostics.lastEvent?.sourceID == "source-4")
        #expect(diagnostics.lastEvent?.sourceDisplayName == "Unknown Pad")
        #expect(diagnostics.lastEvent?.mappedDrumType == nil)
    }
}
