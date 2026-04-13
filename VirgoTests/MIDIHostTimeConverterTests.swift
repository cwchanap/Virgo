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
        
        // Use AVAudioTime to generate realistic host times with known intervals
        let startHostTime = AVAudioTime.hostTime(forSeconds: 0.0)
        let midHostTime = AVAudioTime.hostTime(forSeconds: 0.25)
        let endHostTime = AVAudioTime.hostTime(forSeconds: 0.5)
        
        let elapsedToMid = converter.elapsedSeconds(from: startHostTime, to: midHostTime)
        let elapsedToEnd = converter.elapsedSeconds(from: startHostTime, to: endHostTime)
        
        // Validate exact elapsed times with small tolerance for timing precision
        #expect(abs(elapsedToMid - 0.25) < 0.001)
        #expect(abs(elapsedToEnd - 0.5) < 0.001)
        #expect(elapsedToEnd > elapsedToMid)
    }
}
