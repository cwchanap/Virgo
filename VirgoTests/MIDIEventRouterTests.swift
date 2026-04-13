import Testing
import CoreMIDI
@testable import Virgo

@Suite
struct MIDIEventRouterTests {
    @Test("Decode all note-on events from every packet")
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
    
    @Test("Ignore note-off, zero velocity, and short packets")
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
    
    @Test("Convert single packet list to MIDIPacketBytes")
    func convertPacketListExtractsPacketsFromMIDIPacketList() {
        // Create a single-packet MIDIPacketList with a note-on event
        var packet = MIDIPacket()
        packet.timeStamp = 12345
        packet.length = 3
        packet.data.0 = 0x90
        packet.data.1 = 0x3C
        packet.data.2 = 0x7F
        
        var packetList = MIDIPacketList()
        packetList.numPackets = 1
        packetList.packet = packet
        
        let result = withUnsafePointer(to: packetList) { ptr in
            MIDIEventRouter.convertPacketList(ptr)
        }
        
        #expect(result.count == 1)
        #expect(result[0].timestamp == 12345)
        #expect(result[0].bytes == [0x90, 0x3C, 0x7F])
    }
    
    @Test("Convert empty packet list")
    func convertPacketListHandlesEmptyPacketList() {
        var packetList = MIDIPacketList()
        packetList.numPackets = 0
        
        let result = withUnsafePointer(to: packetList) { ptr in
            MIDIEventRouter.convertPacketList(ptr)
        }
        
        #expect(result.isEmpty)
    }
    
    @Test("Convert multi-packet list with MIDIPacketNext")
    func convertPacketListHandlesMultiplePackets() {
        // Build a two-packet list using MIDIPacketList construction
        // First packet: timestamp 1000, note-on on channel 0
        var packet1 = MIDIPacket()
        packet1.timeStamp = 1000
        packet1.length = 3
        packet1.data.0 = 0x90  // Note-on, channel 0
        packet1.data.1 = 0x3C  // Note 60
        packet1.data.2 = 0x7F  // Velocity 127
        
        var packetList = MIDIPacketList()
        packetList.numPackets = 1
        packetList.packet = packet1
        
        // Advance to next packet slot and add second packet
        let nextPacketPtr = UnsafeMutablePointer(mutating: UnsafePointer(MIDIPacketNext(
            withUnsafeMutablePointer(to: &packetList.packet) { $0 }
        )))
        
        var packet2 = MIDIPacket()
        packet2.timeStamp = 2000
        packet2.length = 3
        packet2.data.0 = 0x91  // Note-on, channel 1
        packet2.data.1 = 0x48  // Note 72
        packet2.data.2 = 0x64  // Velocity 100
        
        nextPacketPtr.pointee = packet2
        packetList.numPackets = 2
        
        let result = withUnsafePointer(to: packetList) { ptr in
            MIDIEventRouter.convertPacketList(ptr)
        }
        
        #expect(result.count == 2)
        #expect(result[0].timestamp == 1000)
        #expect(result[0].bytes == [0x90, 0x3C, 0x7F])
        #expect(result[1].timestamp == 2000)
        #expect(result[1].bytes == [0x91, 0x48, 0x64])
    }
}
