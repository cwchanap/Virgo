import Testing
import CoreMIDI
@testable import Virgo

@Suite
struct MIDIEventRouterTests {
    let router = MIDIEventRouter()
    
    @Test("Decode all note-on events from every packet")
    func decodeEventsEmitsEveryNoteOnEventFromEveryPacket() {
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
            )
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
            )
        ]
        
        let events = router.decodeEvents(from: packets, sourceID: "test-source")
        
        #expect(events.count == 2)
        #expect(events[0].note == 0x3C)
        #expect(events[0].hostTime == 1000)
        #expect(events[1].note == 0x24)
        #expect(events[1].hostTime == 5000)
    }

    @Test("Decode multiple note-on triplets from a single packet")
    func decodeEventsEmitsEveryCompleteTripletWithinOnePacket() {
        let packets = [
            MIDIPacketBytes(
                timestamp: 4000,
                bytes: [0x99, 38, 127, 0x99, 42, 100]
            )
        ]

        let events = router.decodeEvents(from: packets, sourceID: "test-source")

        #expect(events.count == 2)
        #expect(events[0] == MIDINoteEvent(sourceID: "test-source", channel: 9, note: 38, velocity: 127, hostTime: 4000))
        #expect(events[1] == MIDINoteEvent(sourceID: "test-source", channel: 9, note: 42, velocity: 100, hostTime: 4000))
    }

    @Test("Decode note-on events that use running status")
    func decodeEventsHandlesRunningStatusPackets() {
        let packets = [
            MIDIPacketBytes(
                timestamp: 5000,
                bytes: [0x99, 38, 127, 42, 100]
            )
        ]

        let events = router.decodeEvents(from: packets, sourceID: "test-source")

        #expect(events.count == 2)
        #expect(events[0] == MIDINoteEvent(sourceID: "test-source", channel: 9, note: 38, velocity: 127, hostTime: 5000))
        #expect(events[1] == MIDINoteEvent(sourceID: "test-source", channel: 9, note: 42, velocity: 100, hostTime: 5000))
    }
    
    @Test("Decode note-on events when a message spans packet boundaries")
    func decodeEventsHandlesSplitNoteOnAcrossPackets() {
        let packets = [
            MIDIPacketBytes(
                timestamp: 6000,
                bytes: [0x99, 38]
            ),
            MIDIPacketBytes(
                timestamp: 7000,
                bytes: [127]
            )
        ]

        let events = router.decodeEvents(from: packets, sourceID: "test-source")

        #expect(events.count == 1)
        #expect(events[0] == MIDINoteEvent(sourceID: "test-source", channel: 9, note: 38, velocity: 127, hostTime: 6000))
    }

    @Test("Decode running-status note-on events across packet boundaries")
    func decodeEventsHandlesRunningStatusAcrossPackets() {
        let packets = [
            MIDIPacketBytes(
                timestamp: 8000,
                bytes: [0x99, 38, 127]
            ),
            MIDIPacketBytes(
                timestamp: 9000,
                bytes: [42, 100]
            )
        ]

        let events = router.decodeEvents(from: packets, sourceID: "test-source")

        #expect(events.count == 2)
        #expect(events[0] == MIDINoteEvent(sourceID: "test-source", channel: 9, note: 38, velocity: 127, hostTime: 8000))
        #expect(events[1] == MIDINoteEvent(sourceID: "test-source", channel: 9, note: 42, velocity: 100, hostTime: 9000))
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
            router.convertPacketList(ptr)
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
            router.convertPacketList(ptr)
        }
        
        #expect(result.isEmpty)
    }
    
    @Test("Convert multi-packet list with MIDIPacketNext")
    func convertPacketListHandlesMultiplePackets() {
        // Allocate a heap buffer large enough for a two-packet MIDIPacketList.
        // MIDIPacketList embeds one MIDIPacket; each additional packet needs one more slot.
        let bufferSize = MemoryLayout<MIDIPacketList>.size + MemoryLayout<MIDIPacket>.size
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize,
            alignment: MemoryLayout<MIDIPacketList>.alignment
        )
        defer { buffer.deallocate() }

        let packetListPtr = buffer.bindMemory(to: MIDIPacketList.self, capacity: 1)

        // Use CoreMIDI's safe packet-list API to populate the buffer.
        var currentPacket = MIDIPacketListInit(packetListPtr)

        var bytes1: [UInt8] = [0x90, 0x3C, 0x7F]  // Note-on, channel 0, note 60, velocity 127
        currentPacket = MIDIPacketListAdd(packetListPtr, bufferSize, currentPacket, 1000, 3, &bytes1)

        var bytes2: [UInt8] = [0x91, 0x48, 0x64]  // Note-on, channel 1, note 72, velocity 100
        _ = MIDIPacketListAdd(packetListPtr, bufferSize, currentPacket, 2000, 3, &bytes2)

        let result = MIDIEventRouter().convertPacketList(UnsafePointer(packetListPtr))

        #expect(result.count == 2)
        #expect(result[0].timestamp == 1000)
        #expect(result[0].bytes == [0x90, 0x3C, 0x7F])
        #expect(result[1].timestamp == 2000)
        #expect(result[1].bytes == [0x91, 0x48, 0x64])
    }
}
