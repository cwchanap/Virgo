import Testing
import AVFoundation
@testable import Virgo

@Suite
struct MIDIHostTimeConverterTests {
    let converter = MIDIHostTimeConverter()
    
    @Test("Convert host time to elapsed seconds correctly")
    func elapsedSecondsConvertsHostTimeIntoPositiveElapsedDuration() {
        // Use AVAudioTime to generate realistic host times with known intervals
        let startHostTime = AVAudioTime.hostTime(forSeconds: 1.0)
        let endHostTime = AVAudioTime.hostTime(forSeconds: 1.125)
        
        let elapsed = converter.elapsedSeconds(from: startHostTime, to: endHostTime)
        
        // Validate that the elapsed time matches the expected 0.125 second difference
        #expect(abs(elapsed - 0.125) < 0.001)
    }
    
    @Test("Handle multiple time points correctly")
    func elapsedSecondsHandlesMultipleTimePoints() {
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

    @Test("Return negative when end time precedes start time")
    func elapsedSecondsReturnsNegativeWhenEndPrecedesStart() {
        let earlierHostTime = AVAudioTime.hostTime(forSeconds: 1.0)
        let laterHostTime = AVAudioTime.hostTime(forSeconds: 1.125)

        // When the end time precedes the start time the result must be negative.
        let elapsed = converter.elapsedSeconds(from: laterHostTime, to: earlierHostTime)
        #expect(elapsed < 0)
    }
}
