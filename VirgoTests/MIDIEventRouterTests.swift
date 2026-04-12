import Testing
@testable import Virgo

@Suite
struct MIDIEventRouterTests {
    @Test
    func decodeEventsEmitsEveryNoteOnEventFromEveryPacket() {
        let router = MIDIEventRouter()
        
        // Create multiple packets with note-on events
        let packets = [
            MIDIPacketBytes(
                timestamp: 1000,
                bytes: [0x90, 0x3C, 0x7F]  // Note-on, channel 0, note 60, velocity 127
            ),
            MIDIPacketBytes(
                timestamp: 2000,
                bytes: [0x91, 0x48, 0x64]  // Note-on, channel 1, note 72, velocity 100
            ),
            MIDIPacketBytes(
                timestamp: 3000,
                bytes: [0x9F, 0x24, 0x50]  // Note-on, channel 15, note 36, velocity 80
            ),
        ]
        
        let events = router.decodeEvents(from: packets, sourceID: "test-source")
        
        #expect(events.count == 3)
        #expect(events[0].sourceID == "test-source")
        #expect(events[0].channel == 0)
        #expect(events[0].note == 0x3C)
        #expect(events[0].velocity == 0x7F)
        #expect(events[0].hostTime == 1000)
        
        #expect(events[1].sourceID == "test-source")
        #expect(events[1].channel == 1)
        #expect(events[1].note == 0x48)
        #expect(events[1].velocity == 0x64)
        #expect(events[1].hostTime == 2000)
        
        #expect(events[2].sourceID == "test-source")
        #expect(events[2].channel == 15)
        #expect(events[2].note == 0x24)
        #expect(events[2].velocity == 0x50)
        #expect(events[2].hostTime == 3000)
    }
    
    @Test
    func decodeEventsIgnoresNoteOffZeroVelocityAndShortPackets() {
        let router = MIDIEventRouter()
        
        let packets = [
            // Valid note-on
            MIDIPacketBytes(
                timestamp: 1000,
                bytes: [0x90, 0x3C, 0x7F]
            ),
            // Note-off event (status 0x80)
            MIDIPacketBytes(
                timestamp: 2000,
                bytes: [0x80, 0x3C, 0x40]
            ),
            // Note-on with zero velocity
            MIDIPacketBytes(
                timestamp: 3000,
                bytes: [0x90, 0x48, 0x00]
            ),
            // Short packet (less than 3 bytes)
            MIDIPacketBytes(
                timestamp: 4000,
                bytes: [0x90, 0x3C]
            ),
            // Another valid note-on
            MIDIPacketBytes(
                timestamp: 5000,
                bytes: [0x91, 0x24, 0x60]
            ),
        ]
        
        let events = router.decodeEvents(from: packets, sourceID: "test-source")
        
        #expect(events.count == 2)
        #expect(events[0].note == 0x3C)
        #expect(events[0].hostTime == 1000)
        #expect(events[1].note == 0x24)
        #expect(events[1].hostTime == 5000)
    }
}
