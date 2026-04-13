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
        let numPackets = packetList.pointee.numPackets
        guard numPackets > 0 else { return result }
        result.reserveCapacity(Int(numPackets))

        // Locate the first packet by taking the address of the .packet field directly,
        // rather than using manual MemoryLayout byte-offset arithmetic.
        // UnsafeMutablePointer(mutating:) is required to form an inout reference;
        // the packet list itself is not mutated.
        let mutableList = UnsafeMutablePointer(mutating: packetList)
        withUnsafeMutablePointer(to: &mutableList.pointee.packet) { firstPacketPtr in
            var currentPacket: UnsafePointer<MIDIPacket> = UnsafePointer(firstPacketPtr)

            for _ in 0..<numPackets {
                let byteCount = min(Int(currentPacket.pointee.length), 256)

                var bytes: [UInt8] = []
                bytes.reserveCapacity(byteCount)
                withUnsafeBytes(of: currentPacket.pointee.data) { buffer in
                    if let baseAddress = buffer.baseAddress {
                        bytes = Array(UnsafeBufferPointer(
                            start: baseAddress.assumingMemoryBound(to: UInt8.self),
                            count: byteCount
                        ))
                    }
                }

                result.append(MIDIPacketBytes(timestamp: currentPacket.pointee.timeStamp, bytes: bytes))

                // UnsafeMutablePointer(mutating:) cast is only to satisfy the C API signature
                // and does not imply mutation — MIDIPacketNext only reads the packet's length.
                currentPacket = UnsafePointer(MIDIPacketNext(UnsafeMutablePointer(mutating: currentPacket)))
            }
        }

        return result
    }
}

/// Resolves a CoreMIDI endpoint unique-ID to a stable string identifier
/// suitable for use as a dictionary key or `MIDINoteEvent.sourceID`.
protocol MIDISourceIDResolving {
    func stableSourceID(for uniqueID: Int32) -> String
}
