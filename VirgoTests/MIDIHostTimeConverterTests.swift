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

    @Test("hostTimeByAdding round-trips through elapsedSeconds")
    func hostTimeByAddingRoundTripsCorrectly() {
        // Use AVAudioTime.hostTime to get a known baseline, then verify that
        // adding N seconds via hostTimeByAdding produces a host time whose
        // elapsed from the baseline is exactly N seconds.  This independently
        // validates the nanoseconds-to-ticks conversion without relying on the
        // same helper for both sides of the comparison.
        let baseHostTime = AVAudioTime.hostTime(forSeconds: 1.0)
        let offsetSeconds = 0.25

        let projectedHostTime = converter.hostTimeByAdding(seconds: offsetSeconds, to: baseHostTime)
        let elapsed = converter.elapsedSeconds(from: baseHostTime, to: projectedHostTime)

        // The round-trip must be within 1 ms (generous tolerance for Mach tick granularity)
        #expect(abs(elapsed - offsetSeconds) < 0.001,
                "hostTimeByAdding(\(offsetSeconds)) produced \(elapsed)s elapsed, expected \(offsetSeconds)s")
    }

    @Test("hostTimeByAdding is consistent with AVAudioTime.hostTime")
    func hostTimeByAddingMatchesAVAudioTime() {
        // Cross-validate against AVAudioTime.hostTime(forSeconds:) which uses
        // the system's own conversion.  Both approaches should agree.
        let baseHostTime = mach_absolute_time()
        let offset = 0.1

        let viaConverter = converter.hostTimeByAdding(seconds: offset, to: baseHostTime)
        let viaAVAudioTime = AVAudioTime.hostTime(forSeconds: AVAudioTime.seconds(forHostTime: baseHostTime) + offset)

        let diff = AVAudioTime.seconds(forHostTime: viaConverter) - AVAudioTime.seconds(forHostTime: viaAVAudioTime)
        #expect(abs(diff) < 0.001,
                "Converter and AVAudioTime disagree by \(diff)s")
    }
}
