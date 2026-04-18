import Foundation
import AVFoundation

struct MIDIHostTimeConverter {
    func elapsedSeconds(from startHostTime: UInt64, to eventHostTime: UInt64) -> Double {
        AVAudioTime.seconds(forHostTime: eventHostTime) - AVAudioTime.seconds(forHostTime: startHostTime)
    }

    /// Returns a new host time offset by the given number of seconds.
    /// Used to project a captured `mach_absolute_time()` forward to match a
    /// scheduled (future) audio start time.
    func hostTimeByAdding(seconds: Double, to hostTime: UInt64) -> UInt64 {
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        // Convert seconds → nanoseconds → Mach ticks
        let nanosToAdd = seconds * 1_000_000_000.0
        let ticksToAdd = UInt64(nanosToAdd * Double(info.numer) / Double(info.denom))
        return hostTime + ticksToAdd
    }
}
