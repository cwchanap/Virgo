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

struct MIDIEventRouter {
    /// Decode MIDI note-on events from packet bytes.
    /// Filters for note-on status (0x9n) with velocity > 0.
    func decodeEvents(from packets: [MIDIPacketBytes], sourceID: String) -> [MIDINoteEvent] {
        var events: [MIDINoteEvent] = []
        var runningStatus: UInt8?
        var dataBytes: [UInt8] = []
        var currentMessageTimestamp: UInt64?
        dataBytes.reserveCapacity(2)

        for packet in packets {
            for byte in packet.bytes {
                if byte >= 0xF8 {
                    continue
                }

                if byte & 0x80 != 0 {
                    runningStatus = byte < 0xF0 ? byte : nil
                    dataBytes.removeAll(keepingCapacity: true)
                    currentMessageTimestamp = byte < 0xF0 ? packet.timestamp : nil
                    continue
                }

                guard let status = runningStatus,
                      let expectedDataByteCount = Self.expectedDataByteCount(for: status) else {
                    continue
                }

                if dataBytes.isEmpty, currentMessageTimestamp == nil {
                    currentMessageTimestamp = packet.timestamp
                }

                dataBytes.append(byte)
                guard dataBytes.count == expectedDataByteCount else { continue }

                if expectedDataByteCount == 2 {
                    let note = dataBytes[0]
                    let velocity = dataBytes[1]
                    if (status & 0xF0) == 0x90, velocity > 0 {
                        events.append(
                            MIDINoteEvent(
                                sourceID: sourceID,
                                channel: status & 0x0F,
                                note: note,
                                velocity: velocity,
                                hostTime: currentMessageTimestamp ?? packet.timestamp
                            )
                        )
                    }
                }

                dataBytes.removeAll(keepingCapacity: true)
                currentMessageTimestamp = nil
            }
        }

        return events
    }

    private static func expectedDataByteCount(for status: UInt8) -> Int? {
        switch status & 0xF0 {
        case 0x80, 0x90, 0xA0, 0xB0, 0xE0:
            return 2
        case 0xC0, 0xD0:
            return 1
        default:
            return nil
        }
    }
    
    func convertPacketList(_ packetList: UnsafePointer<MIDIPacketList>) -> [MIDIPacketBytes] {
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
                // Clamp to 256 bytes to match CoreMIDI's fixed MIDIPacket.data buffer size
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
///
/// This protocol is used by later tasks (Task 5+) to map MIDI source unique IDs
/// to stable human-readable identifiers across multiple input events.
protocol MIDISourceIDResolving {
    func stableSourceID(for uniqueID: Int32) -> String
}
