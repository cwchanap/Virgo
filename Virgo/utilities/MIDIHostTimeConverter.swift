import Foundation
import AVFoundation

struct MIDIHostTimeConverter {
    static func elapsedSeconds(from startHostTime: UInt64, to eventHostTime: UInt64) -> Double {
        AVAudioTime.seconds(forHostTime: eventHostTime) - AVAudioTime.seconds(forHostTime: startHostTime)
    }
}
