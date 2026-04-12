import Testing
import AVFoundation
@testable import Virgo

@Suite
struct MIDIHostTimeConverterTests {
    @Test
    func elapsedSecondsConvertsHostTimeIntoPositiveElapsedDuration() {
        let converter = MIDIHostTimeConverter()
        
        // Use arbitrary host times - the converter should compute the elapsed seconds
        let startHostTime: UInt64 = 1_000_000
        let eventHostTime: UInt64 = 2_000_000
        
        let elapsed = converter.elapsedSeconds(from: startHostTime, to: eventHostTime)
        
        // The result should be positive and represent the time difference
        #expect(elapsed > 0)
        #expect(elapsed > 0.0)
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
