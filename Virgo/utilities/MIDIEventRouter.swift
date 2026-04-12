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
    
    func convertPacketList(_ packetList: UnsafeMutablePointer<MIDIPacketList>) -> [MIDIPacketBytes] {
        var result: [MIDIPacketBytes] = []
        var packet: UnsafeMutablePointer<MIDIPacket> = UnsafeMutablePointer(&packetList.pointee.packet)
        
        for _ in 0..<packetList.pointee.numPackets {
            let byteCount = Int(packet.pointee.length)
            let bytes = [UInt8](UnsafeBufferPointer(start: &packet.pointee.data.0, count: byteCount))
            result.append(MIDIPacketBytes(timestamp: packet.pointee.timeStamp, bytes: bytes))
            packet = UnsafeMutablePointer(MIDIPacketNext(packet))
        }
        
        return result
    }
}

protocol MIDISourceIDResolving {
    func stableSourceID(for uniqueID: Int32) -> String
}
