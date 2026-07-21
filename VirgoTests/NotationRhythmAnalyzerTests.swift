import Testing
@testable import Virgo

@Suite("Notation Rhythm Analyzer Tests")
struct NotationRhythmAnalyzerTests {
    private let analyzer = NotationRhythmAnalyzer()

    private func measure(
        duration: Int = 960,
        groups: [RhythmBeatGroup]? = nil
    ) -> RhythmMeasure {
        RhythmMeasure(
            measureIndex: 0,
            startTick: 0,
            durationTicks: duration,
            timeSignature: .fourFour,
            beatGroups: groups ?? (0..<4).map {
                RhythmBeatGroup(groupIndex: $0, startTick: $0 * 240, durationTicks: 240, isResidual: false)
            },
            engravingSupport: .supported
        )
    }

    private func event(
        _ id: Int,
        tick: Int,
        voice: NotationVoice = .upper,
        origin: ResolvedRhythmEventOrigin = .manual,
        interval: NoteInterval = .eighth,
        candidate: NoteInterval? = nil
    ) -> RhythmAnalysisEvent {
        RhythmAnalysisEvent(
            eventID: RhythmEventID(rawValue: id),
            origin: origin,
            position: RhythmEventPosition(measureIndex: 0, localTick: tick, absoluteTick: tick),
            voice: voice,
            storedInterval: interval,
            visualDurationCandidate: candidate
        )
    }

    private func analyze(
        _ events: [RhythmAnalysisEvent],
        feel: RhythmicFeel = .straight,
        rhythmMeasure: RhythmMeasure? = nil
    ) -> NotationRhythmAnalysis {
        analyzer.analyze(
            events: events,
            measures: [rhythmMeasure ?? measure()],
            ticksPerWholeNote: 960,
            feel: feel
        )
    }

    @Test(
        "binary spans classify from whole through sixty-fourth",
        arguments: zip(
            [960, 480, 240, 120, 60, 30, 15],
            NoteInterval.allCases
        ).map { ($0, $1) }
    )
    func binarySpanMatrix(ticks: Int, interval: NoteInterval) {
        #expect(analyzer.classify(spanTicks: ticks, ticksPerWholeNote: 960) == NotationRhythm(
            baseInterval: interval,
            dotCount: 0,
            tuplet: nil,
            support: .supported
        ))
    }

    @Test(
        "single-dotted spans classify exactly when integral",
        arguments: [
            (ticks: 2_880, interval: NoteInterval.full),
            (ticks: 1_440, interval: .half),
            (ticks: 720, interval: .quarter),
            (ticks: 360, interval: .eighth),
            (ticks: 180, interval: .sixteenth),
            (ticks: 90, interval: .thirtysecond),
            (ticks: 45, interval: .sixtyfourth)
        ]
    )
    func dottedSpanMatrix(ticks: Int, interval: NoteInterval) {
        #expect(analyzer.classify(spanTicks: ticks, ticksPerWholeNote: 1_920) == NotationRhythm(
            baseInterval: interval,
            dotCount: 1,
            tuplet: nil,
            support: .supported
        ))
    }

    @Test("three equal slots form one explicit 3:2 triplet")
    func completeTriplet() {
        let analysis = analyze([
            event(1, tick: 0), event(2, tick: 80), event(3, tick: 160)
        ])

        #expect(analysis.tuplets.count == 1)
        #expect(analysis.tuplets.first?.bracketVisibility == .shown)
        #expect(analysis.notes.filter { $0.tupletID != nil }.count == 3)
        #expect(analysis.notes.filter { $0.tupletID != nil }.allSatisfy {
            $0.durationTicks == 80
                && $0.rhythm.tuplet == TupletRatio(actual: 3, normal: 2)
        })
    }

    @Test("analysis includes an exact dotted rest complement")
    func dottedRestComplement() throws {
        let oneGroup = measure(
            duration: 360,
            groups: [RhythmBeatGroup(
                groupIndex: 0,
                startTick: 0,
                durationTicks: 360,
                isResidual: false
            )]
        )
        let analysis = analyze([
            event(1, tick: 180, interval: .eighth)
        ], rhythmMeasure: oneGroup)
        let rest = try #require(analysis.rests.first {
            $0.voice == .upper && $0.startTick == 0
        })

        #expect(rest.durationTicks == 180)
        #expect(rest.rhythm == NotationRhythm(baseInterval: .eighth, dotCount: 1))
    }

    @Test(
        "each silent triplet slot remains explicitly reserved",
        arguments: [[80, 160], [0, 160], [0, 80]]
    )
    func tripletWithOneSilentSlot(onsets: [Int]) throws {
        let analysis = analyze(onsets.enumerated().map {
            event($0.offset + 1, tick: $0.element)
        })
        let tuplet = try #require(analysis.tuplets.first)
        let rest = try #require(analysis.rests.first { $0.tupletID == tuplet.id })

        #expect(analysis.tuplets.count == 1)
        #expect(rest.durationTicks == 80)
        #expect(rest.rhythm.tuplet == TupletRatio(actual: 3, normal: 2))
        #expect(Set(onsets + [rest.startTick]) == [0, 80, 160])
    }

    @Test("straight shows a 2:1 pair while swing and shuffle suppress only its bracket")
    func declaredFeelPair() throws {
        let source = [
            event(1, tick: 0, origin: .dtx),
            event(2, tick: 160, origin: .dtx, candidate: .eighth)
        ]
        #expect(analyze(source, feel: .straight).tuplets.first?.bracketVisibility == .shown)
        #expect(analyze(source, feel: .swing).tuplets.first?.bracketVisibility == .suppressedForFeel)
        #expect(analyze(source, feel: .shuffle).tuplets.first?.bracketVisibility == .suppressedForFeel)

        let equalSlots = analyze([
            event(3, tick: 0, origin: .dtx),
            event(4, tick: 80, origin: .dtx),
            event(5, tick: 160, origin: .dtx, candidate: .eighth)
        ], feel: .swing)
        #expect(equalSlots.tuplets.first?.bracketVisibility == .shown)
        #expect(equalSlots.warnings.allSatisfy {
            !$0.codes.contains(.indeterminateTerminalDuration)
        })
    }

    @Test("terminal DTX duration is trusted only when evidence fits its resolved group")
    func terminalDTXCandidateBoundary() throws {
        let fitting = try #require(analyze([
            event(1, tick: 120, origin: .dtx, interval: .sixtyfourth, candidate: .eighth)
        ]).notes.first)
        #expect(fitting.durationTicks == 120)
        #expect(fitting.rhythm.baseInterval == .eighth)
        #expect(fitting.rhythm.support == .supported)

        let absent = try #require(analyze([
            event(2, tick: 120, origin: .dtx, interval: .sixtyfourth)
        ]).notes.first)
        #expect(absent.durationTicks == 840)
        #expect(absent.rhythm.support == .indeterminate(.indeterminateTerminalDuration))

        let crossing = try #require(analyze([
            event(3, tick: 120, origin: .dtx, candidate: .quarter)
        ]).notes.first)
        #expect(crossing.rhythm.support == .indeterminate(.indeterminateTerminalDuration))
    }

    @Test("same-time same-voice events share one chord rhythm")
    func sameVoiceChordOnset() {
        let analysis = analyze([
            event(1, tick: 0, interval: .quarter),
            event(2, tick: 0, interval: .quarter),
            event(3, tick: 240, interval: .quarter)
        ])

        #expect(analysis.notes.filter { $0.position.localTick == 0 }.count == 2)
        #expect(Set(analysis.notes.filter { $0.position.localTick == 0 }.map(\.rhythm)).count == 1)
    }

    @Test("another voice never shortens a manual note")
    func voiceIsolation() throws {
        let analysis = analyze([
            event(1, tick: 0, voice: .upper, interval: .half),
            event(2, tick: 120, voice: .lower, interval: .eighth)
        ])
        let upper = try #require(analysis.notes.first { $0.voice == .upper })

        #expect(upper.durationTicks == 480)
        #expect(upper.rhythm.baseInterval == .half)
    }

    @Test("incomplete and non-3:2 structures keep positions and warn")
    func unsupportedTupletStructures() {
        let incomplete = analyze([
            event(1, tick: 0, origin: .dtx),
            event(2, tick: 80, origin: .dtx)
        ])
        #expect(incomplete.notes.map(\.position.localTick) == [0, 80])
        #expect(incomplete.warnings.first?.codes.contains(.incompleteTuplet) == true)

        let quintuplet = analyze((0..<5).map {
            event($0, tick: $0 * 48, origin: .dtx, candidate: $0 == 4 ? .sixtyfourth : nil)
        })
        #expect(quintuplet.notes.map(\.position.localTick) == [0, 48, 96, 144, 192])
        #expect(quintuplet.warnings.first?.codes.contains(.unsupportedTupletRatio) == true)
    }

    @Test("overlapping triplet members remain engraving-unsupported")
    func overlappingTripletMembers() {
        let analysis = analyze([
            event(1, tick: 0, interval: .quarter),
            event(2, tick: 80, interval: .quarter),
            event(3, tick: 160, interval: .quarter)
        ])

        #expect(analysis.notes.map(\.position.localTick) == [0, 80, 160])
        #expect(analysis.tuplets.isEmpty)
        #expect(analysis.warnings.first?.codes.contains(.incompleteTuplet) == true)
    }

    @Test("engraving-unsupported measure keeps exact onsets but emits no tuplet claim")
    func unsupportedMeasureSuppressesTupletClaim() {
        let unsupported = RhythmMeasure(
            measureIndex: 0,
            startTick: 0,
            durationTicks: 240,
            timeSignature: .fourFour,
            beatGroups: [RhythmBeatGroup(
                groupIndex: 0,
                startTick: 0,
                durationTicks: 240,
                isResidual: false
            )],
            engravingSupport: .unsupported([.unsupportedTupletRatio])
        )
        let analysis = analyze([
            event(1, tick: 0), event(2, tick: 80), event(3, tick: 160)
        ], rhythmMeasure: unsupported)

        #expect(analysis.notes.map(\.position.localTick) == [0, 80, 160])
        #expect(analysis.tuplets.isEmpty)
        #expect(analysis.warnings == [RhythmMeasureWarning(
            measureIndex: 0,
            codes: [.unsupportedTupletRatio]
        )])
    }
}
