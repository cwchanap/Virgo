//
//  RhythmInputTimingTests.swift
//  VirgoTests
//

import Foundation
import Testing
@testable import Virgo

private final class TimingResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: NoteMatchResult?

    func store(_ result: NoteMatchResult?) {
        lock.lock()
        storage = result
        lock.unlock()
    }

    func load() -> NoteMatchResult? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@Suite("Rhythm input timing", .serialized)
@MainActor
struct RhythmInputTimingTests {
    @Test("Live speed transition exposes one atomic matcher and host-origin snapshot")
    func liveSpeedTransitionIsAtomicForConcurrentMIDICallback() {
        let transitionEntered = DispatchSemaphore(value: 0)
        let releaseTransition = DispatchSemaphore(value: 0)
        let transitionFinished = DispatchSemaphore(value: 0)
        let callbackStarted = DispatchSemaphore(value: 0)
        let callbackFinished = DispatchSemaphore(value: 0)
        let resultBox = TimingResultBox()
        let converter = MIDIHostTimeConverter()
        let manager = InputManager(timingTransitionCriticalSection: {
            transitionEntered.signal()
            releaseTransition.wait()
        })
        manager.setMIDIMapping([38: .snare])
        let position = RhythmEventPosition(measureIndex: 0, localTick: 2, absoluteTick: 2)
        let target = RhythmNoteTarget(
            eventID: .init(rawValue: 91),
            drumType: .snare,
            position: position,
            targetSecondsAtOneX: 1
        )
        let timeline = makeTimeline(measureDurations: [4])
        let oldHostOrigin = mach_absolute_time()
        manager.configure(.timeline(targets: [target], timeline: timeline, speed: 1))
        manager.startListening(songStartTime: Date(), capturedHostTime: oldHostOrigin)
        let newHostOrigin = converter.hostTimeByAdding(seconds: 10, to: oldHostOrigin)

        DispatchQueue.global().async {
            manager.configureAndStartListening(
                .timeline(targets: [target], timeline: timeline, speed: 0.5),
                songStartTime: Date(),
                elapsedOffset: 0.5,
                capturedHostTime: newHostOrigin
            )
            transitionFinished.signal()
        }

        let didEnterTransition = transitionEntered.wait(timeout: .now() + 1) == .success
        DispatchQueue.global().async {
            callbackStarted.signal()
            let eventHostTime = converter.hostTimeByAdding(seconds: 1.5, to: newHostOrigin)
            resultBox.store(manager.handleMIDINoteEvent(MIDINoteEvent(
                sourceID: "atomic-transition",
                channel: 9,
                note: 38,
                velocity: 100,
                hostTime: eventHostTime
            )))
            callbackFinished.signal()
        }
        let didStartCallback = callbackStarted.wait(timeout: .now() + 1) == .success
        let callbackEscapedTransaction = callbackFinished.wait(timeout: .now()) == .success

        releaseTransition.signal()
        let didFinishTransition = transitionFinished.wait(timeout: .now() + 1) == .success
        let didFinishCallback = callbackEscapedTransaction
            || callbackFinished.wait(timeout: .now() + 1) == .success

        #expect(didEnterTransition)
        #expect(didStartCallback)
        #expect(!callbackEscapedTransaction)
        #expect(didFinishTransition)
        #expect(didFinishCallback)
        #expect(resultBox.load()?.matchedEventID == target.eventID)
        #expect(resultBox.load()?.matchedTargetSeconds == 2)
        #expect(resultBox.load()?.hitSongSeconds == 2)
    }

    @Test("A target after a shortened bar uses cumulative timeline seconds")
    func shortenedBarUsesCumulativeTargetTime() throws {
        let timeline = makeTimeline(
            measureDurations: [3, 4],
            eventPositions: [sourceID(0): .init(measureIndex: 1, localTick: 1, absoluteTick: 4)]
        )
        let eventID = RhythmEventID(rawValue: 41)
        let target = RhythmNoteTarget(
            eventID: eventID,
            drumType: .snare,
            position: .init(measureIndex: 1, localTick: 1, absoluteTick: 4),
            targetSecondsAtOneX: 2.0
        )
        let matcher = InputTimingMatcher(configuration: .timeline(
            targets: [target],
            timeline: timeline,
            speed: 1.0
        ))

        let result = matcher.calculateNoteMatch(for: hit(.snare), elapsedTime: 2.01)

        #expect(result.matchedNote == nil)
        #expect(result.matchedEventID == eventID)
        #expect(result.matchedTargetPosition == target.position)
        #expect(abs(try #require(result.matchedTargetSeconds) - 2.0) < 0.000_001)
        #expect(abs(try #require(result.hitSongSeconds) - 2.01) < 0.000_001)
        #expect(result.hitPosition == target.position)
        #expect(result.timingAccuracy == .perfect)
        #expect(abs(try #require(result.timingError) - 10.0) < 0.001)
    }

    @Test("Same-time targets for different drums retain distinct event identity")
    func sameTimeTargetsRemainDistinct() {
        let position = RhythmEventPosition(measureIndex: 0, localTick: 2, absoluteTick: 2)
        let timeline = makeTimeline(measureDurations: [4])
        let kickID = RhythmEventID(rawValue: 1)
        let snareID = RhythmEventID(rawValue: 2)
        let matcher = InputTimingMatcher(configuration: .timeline(
            targets: [
                .init(eventID: snareID, drumType: .snare, position: position, targetSecondsAtOneX: 1.0),
                .init(eventID: kickID, drumType: .kick, position: position, targetSecondsAtOneX: 1.0)
            ],
            timeline: timeline,
            speed: 1.0
        ))

        #expect(matcher.calculateNoteMatch(for: hit(.kick), elapsedTime: 1.0).matchedEventID == kickID)
        #expect(matcher.calculateNoteMatch(for: hit(.snare), elapsedTime: 1.0).matchedEventID == snareID)
    }

    @Test("Timeline matching treats an exact zero-origin 100 millisecond late hit as good")
    func exactHundredMillisecondsLateIsGood() {
        let position = RhythmEventPosition(measureIndex: 0, localTick: 0, absoluteTick: 0)
        let matcher = InputTimingMatcher(configuration: .timeline(
            targets: [
                .init(
                    eventID: .init(rawValue: 1),
                    drumType: .kick,
                    position: position,
                    targetSecondsAtOneX: 0
                )
            ],
            timeline: makeTimeline(measureDurations: [4]),
            speed: 1.0
        ))

        #expect(matcher.calculateNoteMatch(for: hit(.kick), elapsedTime: 0.1).timingAccuracy == .good)
    }

    @Test("Legacy matching treats an exact zero-origin 100 millisecond late hit as good")
    func legacyExactHundredMillisecondsLateIsGood() {
        let note = Note(
            interval: .quarter,
            noteType: .bass,
            measureNumber: 1,
            measureOffset: 0
        )
        let matcher = InputTimingMatcher(bpm: 120, timeSignature: .fourFour, notes: [note])

        let result = matcher.calculateNoteMatch(for: hit(.kick), elapsedTime: 0.1)

        #expect(result.matchedNote === note)
        #expect(result.timingAccuracy == .good)
        #expect(result.timingError == 100)
    }

    @Test("Timeline inverse mapping remains nil when only tick-zero targets exist")
    func tickZeroOnlyTargetsHaveNoInventedHitPosition() {
        let position = RhythmEventPosition(measureIndex: 0, localTick: 0, absoluteTick: 0)
        let eventID = RhythmEventID(rawValue: 8)
        let matcher = InputTimingMatcher(configuration: .timeline(
            targets: [
                .init(eventID: eventID, drumType: .snare, position: position, targetSecondsAtOneX: 0)
            ],
            timeline: makeTimeline(measureDurations: [4]),
            speed: 1.0
        ))

        let result = matcher.calculateNoteMatch(for: hit(.snare), elapsedTime: 0.01)

        #expect(result.matchedEventID == eventID)
        #expect(result.hitPosition == nil)
    }

    @Test("Inconsistent one-X target scales do not invent a hit position")
    func inconsistentTargetScalesHaveNoHitPosition() {
        let matcher = InputTimingMatcher(configuration: .timeline(
            targets: [
                .init(
                    eventID: .init(rawValue: 1),
                    drumType: .kick,
                    position: .init(measureIndex: 0, localTick: 1, absoluteTick: 1),
                    targetSecondsAtOneX: 0
                ),
                .init(
                    eventID: .init(rawValue: 2),
                    drumType: .snare,
                    position: .init(measureIndex: 0, localTick: 2, absoluteTick: 2),
                    targetSecondsAtOneX: 1
                )
            ],
            timeline: makeTimeline(measureDurations: [4]),
            speed: 1
        ))

        let result = matcher.calculateNoteMatch(for: hit(.snare), elapsedTime: 1)

        #expect(result.matchedEventID == .init(rawValue: 2))
        #expect(result.hitPosition == nil)
    }

    @Test("InputManager timeline callbacks retain no SwiftData note objects")
    func inputManagerTimelineCallbackUsesOnlySnapshots() throws {
        let converter = MIDIHostTimeConverter()
        let manager = InputManager(hostTimeConverter: converter)
        let position = RhythmEventPosition(measureIndex: 0, localTick: 2, absoluteTick: 2)
        let target = RhythmNoteTarget(
            eventID: .init(rawValue: 77),
            drumType: .snare,
            position: position,
            targetSecondsAtOneX: 1
        )
        weak var releasedNote: Note?
        do {
            let note = Note(
                interval: .quarter,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: 0.5
            )
            releasedNote = note
            manager.configure(.timeline(
                targets: [target],
                timeline: makeTimeline(measureDurations: [4]),
                speed: 1
            ))
        }
        #expect(releasedNote == nil)

        manager.setMIDIMapping([38: .snare])
        let startHostTime = mach_absolute_time()
        manager.startListening(songStartTime: Date(), capturedHostTime: startHostTime)
        let result = manager.handleMIDINoteEvent(MIDINoteEvent(
            sourceID: "test-source",
            channel: 9,
            note: 38,
            velocity: 100,
            hostTime: converter.hostTimeByAdding(seconds: 1, to: startHostTime)
        ))

        #expect(try #require(result).matchedEventID == target.eventID)
        #expect(result?.matchedNote == nil)
    }

    private func hit(_ drumType: DrumType) -> InputHit {
        InputHit(
            drumType: drumType,
            velocity: 1.0,
            timestamp: Date(timeIntervalSinceReferenceDate: 1_000)
        )
    }

    private func sourceID(_ ordinal: Int) -> RhythmSourceEventID {
        RhythmSourceEventID(kind: .note, stableOrdinal: ordinal)
    }

    private func makeTimeline(
        measureDurations: [Int],
        eventPositions: [RhythmSourceEventID: RhythmEventPosition] = [:]
    ) -> RhythmTimeline {
        var startTick = 0
        let measures = measureDurations.enumerated().map { index, duration in
            defer { startTick += duration }
            return RhythmMeasure(
                measureIndex: index,
                startTick: startTick,
                durationTicks: duration,
                timeSignature: .fourFour,
                beatGroups: [
                    .init(groupIndex: 0, startTick: 0, durationTicks: duration, isResidual: false)
                ],
                engravingSupport: .supported
            )
        }
        return RhythmTimeline(
            ticksPerWholeNote: 4,
            measures: measures,
            eventPositions: eventPositions,
            bgmStartPosition: nil
        )
    }
}
