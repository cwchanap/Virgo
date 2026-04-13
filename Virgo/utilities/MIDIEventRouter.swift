import Foundation
import CoreMIDI

struct MIDIPacketBytes: Equatable {
    let timestamp: UInt64
    let bytes: [UInt8]
}

struct MIDINoteEvent: Equatable {
    let sourceID: String
    let channel: UInt8
    let note: UInt8
    let velocity: UInt8
    let hostTime: UInt64
}

final class MIDIEventRouter {
    /// Decode MIDI note-on events from packet bytes.
    /// Expects one MIDI message per packet. Filters for note-on status (0x9n) with velocity > 0.
    func decodeEvents(from packets: [MIDIPacketBytes], sourceID: String) -> [MIDINoteEvent] {
        packets.compactMap { packet in
            guard packet.bytes.count >= 3 else { return nil }
            let status = packet.bytes[0]
            let velocity = packet.bytes[2]
            guard (status & 0xF0) == 0x90, velocity > 0 else { return nil }

            return MIDINoteEvent(
                sourceID: sourceID,
                channel: status & 0x0F,
                note: packet.bytes[1],
                velocity: velocity,
                hostTime: packet.timestamp
            )
        }
    }
    
    static func convertPacketList(_ packetList: UnsafePointer<MIDIPacketList>) -> [MIDIPacketBytes] {
        var result: [MIDIPacketBytes] = []
        
        // Get the first packet by accessing the immutable packet field
        let firstPacketPtr = UnsafeRawPointer(packetList)
            .advanced(by: MemoryLayout<UInt32>.size)
            .assumingMemoryBound(to: MIDIPacket.self)
        
        var currentPacket = firstPacketPtr
        
        for _ in 0..<packetList.pointee.numPackets {
            let byteCount = min(Int(currentPacket.pointee.length), 256)
            
            // Extract bytes from the data field safely
            var bytes: [UInt8] = []
            bytes.reserveCapacity(byteCount)
            withUnsafeBytes(of: currentPacket.pointee.data) { buffer in
                if let baseAddress = buffer.baseAddress {
                    let dataPtr = baseAddress.assumingMemoryBound(to: UInt8.self)
                    bytes = Array(UnsafeBufferPointer(start: dataPtr, count: byteCount))
                }
            }
            
            result.append(MIDIPacketBytes(timestamp: currentPacket.pointee.timeStamp, bytes: bytes))
            
            // Advance to the next packet
            let mutablePtr = UnsafeMutablePointer(mutating: currentPacket)
            currentPacket = UnsafePointer(MIDIPacketNext(mutablePtr))
        }
        
        return result
    }
}

protocol MIDISourceIDResolving {
    func stableSourceID(for uniqueID: Int32) -> String
}
