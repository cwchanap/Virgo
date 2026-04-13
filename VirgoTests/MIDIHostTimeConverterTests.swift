import Testing
import AVFoundation
@testable import Virgo

@Suite
struct MIDIHostTimeConverterTests {
    @Test
    func elapsedSecondsConvertsHostTimeIntoPositiveElapsedDuration() {
        let converter = MIDIHostTimeConverter()
        
        // Use AVAudioTime to generate realistic host times with known intervals
        let startHostTime = AVAudioTime.hostTime(forSeconds: 1.0)
        let endHostTime = AVAudioTime.hostTime(forSeconds: 1.125)
        
        let elapsed = converter.elapsedSeconds(from: startHostTime, to: endHostTime)
        
        // Validate that the elapsed time matches the expected 0.125 second difference
        #expect(abs(elapsed - 0.125) < 0.001)
    }
    
    @Test
    func elapsedSecondsHandlesMultipleTimePoints() {
        let converter = MIDIHostTimeConverter()
        
        let startHostTime: UInt64 = 100_000
        let midHostTime: UInt64 = 150_000
        let endHostTime: UInt64 = 300_000
        
        let elapsedToMid = converter.elapsedSeconds(from: startHostTime, to: midHostTime)
        let elapsedToEnd = converter.elapsedSeconds(from: startHostTime, to: endHostTime)
        
        // Elapsed time should increase with later timestamps
        #expect(elapsedToEnd > elapsedToMid)
        #expect(elapsedToEnd > 0)
        #expect(elapsedToMid > 0)
    }
}
