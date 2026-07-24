import Testing
@testable import Virgo

@Suite("Notation Rhythm Analyzer Tests")
struct NotationRhythmAnalyzerTests {
    private let analyzer = NotationRhythmAnalyzer()

    private func measure(
        index: Int = 0,
        startTick: Int = 0,
        duration: Int = 960,
        timeSignature: TimeSignature = .fourFour,
        groups: [RhythmBeatGroup]? = nil
    ) -> RhythmMeasure {
        RhythmMeasure(
            measureIndex: index,
            startTick: startTick,
            durationTicks: duration,
            timeSignature: timeSignature,
            beatGroups: groups ?? (0..<4).map {
                RhythmBeatGroup(groupIndex: $0, startTick: $0 * 240, durationTicks: 240, isResidual: false)
            },
            engravingSupport: .supported
        )
    }

    private func event(
        _ id: Int,
        tick: Int,
        measureIndex: Int = 0,
        measureStartTick: Int = 0,
        voice: NotationVoice = .upper,
        origin: ResolvedRhythmEventOrigin = .manual,
        interval: NoteInterval = .eighth,
        candidate: NoteInterval? = nil
    ) -> RhythmAnalysisEvent {
        RhythmAnalysisEvent(
            eventID: RhythmEventID(rawValue: id),
            origin: origin,
            position: RhythmEventPosition(
                measureIndex: measureIndex,
                localTick: tick,
                absoluteTick: measureStartTick + tick
            ),
            voice: voice,
            storedInterval: interval,
            visualDurationCandidate: candidate
        )
    }

    private func analyze(
        _ events: [RhythmAnalysisEvent],
        feel: RhythmicFeel = .straight,
        rhythmMeasure: RhythmMeasure? = nil,
        measures: [RhythmMeasure]? = nil
    ) -> NotationRhythmAnalysis {
        analyzer.analyze(
            events: events,
            measures: measures ?? [rhythmMeasure ?? measure()],
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

    @Test("ordinary eighths in a compound beat are not inferred as triplets")
    func compoundBeatOrdinaryEighths() {
        let compoundMeasure = measure(
            duration: 720,
            timeSignature: .sixEight,
            groups: [
                RhythmBeatGroup(groupIndex: 0, startTick: 0, durationTicks: 360, isResidual: false),
                RhythmBeatGroup(groupIndex: 1, startTick: 360, durationTicks: 360, isResidual: false)
            ]
        )
        let analysis = analyze([
            event(1, tick: 0),
            event(2, tick: 120),
            event(3, tick: 240)
        ], rhythmMeasure: compoundMeasure)

        #expect(analysis.tuplets.isEmpty)
        #expect(analysis.warnings.isEmpty)
        #expect(analysis.notes.allSatisfy {
            $0.durationTicks == 120
                && $0.rhythm == NotationRhythm(baseInterval: .eighth)
                && $0.tupletID == nil
        })
    }

    @Test("four ordinary sixteenths do not produce an unsupported tuplet warning")
    func ordinarySixteenthsRemainBinary() {
        let analysis = analyze([
            event(1, tick: 0, interval: .sixteenth),
            event(2, tick: 60, interval: .sixteenth),
            event(3, tick: 120, interval: .sixteenth),
            event(4, tick: 180, interval: .sixteenth)
        ])

        #expect(analysis.tuplets.isEmpty)
        #expect(analysis.warnings.isEmpty)
        #expect(analysis.notes.allSatisfy {
            $0.durationTicks == 60 && $0.rhythm == NotationRhythm(baseInterval: .sixteenth)
        })
    }

    @Test("a true triplet subgroup is recognized inside a compound beat")
    func compoundBeatTripletSubgroup() {
        let compoundMeasure = measure(
            duration: 720,
            timeSignature: .sixEight,
            groups: [
                RhythmBeatGroup(groupIndex: 0, startTick: 0, durationTicks: 360, isResidual: false),
                RhythmBeatGroup(groupIndex: 1, startTick: 360, durationTicks: 360, isResidual: false)
            ]
        )
        let analysis = analyze([
            event(1, tick: 0, interval: .eighth),
            event(2, tick: 80, interval: .eighth),
            event(3, tick: 160, interval: .eighth),
            event(4, tick: 240, interval: .eighth)
        ], rhythmMeasure: compoundMeasure)

        #expect(analysis.tuplets.count == 1)
        #expect(analysis.notes.filter { $0.tupletID != nil }.map(\.position.localTick) == [0, 80, 160])
        #expect(analysis.notes.first { $0.position.localTick == 240 }?.tupletID == nil)
        #expect(analysis.notes.first { $0.position.localTick == 240 }?.rhythm == NotationRhythm(baseInterval: .eighth))
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

        let absentAnalysis = analyze([
            event(2, tick: 120, origin: .dtx, interval: .sixtyfourth)
        ])
        let absent = try #require(absentAnalysis.notes.first)
        #expect(absent.durationTicks == 120)
        #expect(absent.rhythm.baseInterval == .quarter)
        #expect(absent.rhythm.support == .indeterminate(.indeterminateTerminalDuration))
        #expect(absentAnalysis.rests.contains {
            $0.voice == .upper && $0.visibility == .hiddenSpacing
        })
        #expect(absentAnalysis.rests.allSatisfy {
            $0.voice != .upper || $0.visibility != .printed
        })

        let crossing = try #require(analyze([
            event(3, tick: 120, origin: .dtx, candidate: .quarter)
        ]).notes.first)
        #expect(crossing.rhythm.support == .indeterminate(.indeterminateTerminalDuration))
    }

    @Test("a later manual onset is never used as DTX duration evidence")
    func laterManualOnsetDoesNotResolveDTXDuration() throws {
        let trusted = analyze([
            event(1, tick: 0, origin: .dtx, interval: .sixtyfourth, candidate: .eighth),
            event(2, tick: 60, origin: .manual, interval: .sixteenth)
        ])
        let trustedDTX = try #require(trusted.notes.first { $0.eventID.rawValue == 1 })
        #expect(trustedDTX.durationTicks == 120)
        #expect(trustedDTX.rhythm == NotationRhythm(baseInterval: .eighth))

        let absent = analyze([
            event(3, tick: 0, origin: .dtx, interval: .sixtyfourth),
            event(4, tick: 120, origin: .manual, interval: .eighth)
        ])
        let absentDTX = try #require(absent.notes.first { $0.eventID.rawValue == 3 })
        #expect(absentDTX.durationTicks == 240)
        #expect(absentDTX.rhythm.baseInterval == .quarter)
        #expect(absentDTX.rhythm.support == .indeterminate(.indeterminateTerminalDuration))
        #expect(absent.rests.allSatisfy {
            $0.voice != .upper || $0.visibility != .printed
        })
    }

    @Test("DTX onset inference never crosses a simple-meter beat-group boundary")
    func simpleMeterDTXBoundary() throws {
        let analysis = analyze([
            event(1, tick: 120, origin: .dtx, interval: .sixtyfourth, candidate: .eighth),
            event(2, tick: 300, origin: .dtx, interval: .sixtyfourth, candidate: .eighth)
        ])
        let first = try #require(analysis.notes.first { $0.eventID.rawValue == 1 })

        #expect(first.beatGroupIndex == 0)
        #expect(first.durationTicks == 120)
        #expect(first.rhythm == NotationRhythm(baseInterval: .eighth))
        #expect(analysis.warnings.isEmpty)
    }

    @Test("DTX onset inference never crosses a compound-meter beat-group boundary")
    func compoundMeterDTXBoundary() throws {
        let compoundMeasure = measure(
            duration: 720,
            timeSignature: .sixEight,
            groups: [
                RhythmBeatGroup(groupIndex: 0, startTick: 0, durationTicks: 360, isResidual: false),
                RhythmBeatGroup(groupIndex: 1, startTick: 360, durationTicks: 360, isResidual: false)
            ]
        )
        let analysis = analyze([
            event(1, tick: 240, origin: .dtx, interval: .sixtyfourth, candidate: .eighth),
            event(2, tick: 420, origin: .dtx, interval: .sixtyfourth, candidate: .eighth)
        ], rhythmMeasure: compoundMeasure)
        let first = try #require(analysis.notes.first { $0.eventID.rawValue == 1 })

        #expect(first.beatGroupIndex == 0)
        #expect(first.durationTicks == 120)
        #expect(first.rhythm == NotationRhythm(baseInterval: .eighth))
        #expect(analysis.warnings.isEmpty)
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

    @Test("manual chord members retain their own notated durations")
    func mixedDurationManualChord() throws {
        let analysis = analyze([
            event(1, tick: 0, interval: .quarter),
            event(2, tick: 0, interval: .eighth)
        ])
        let quarter = try #require(analysis.notes.first { $0.eventID.rawValue == 1 })
        let eighth = try #require(analysis.notes.first { $0.eventID.rawValue == 2 })

        #expect(quarter.durationTicks == 240)
        #expect(quarter.rhythm == NotationRhythm(baseInterval: .quarter))
        #expect(eighth.durationTicks == 120)
        #expect(eighth.rhythm == NotationRhythm(baseInterval: .eighth))
        #expect(analysis.warnings.isEmpty)
    }

    @Test("a DTX chord member uses only DTX onset evidence while a manual member keeps its interval")
    func mixedManualAndDTXChord() throws {
        let analysis = analyze([
            event(1, tick: 0, origin: .manual, interval: .quarter),
            event(2, tick: 0, origin: .dtx, interval: .sixtyfourth),
            event(3, tick: 120, origin: .dtx, interval: .sixtyfourth, candidate: .eighth)
        ])
        let manual = try #require(analysis.notes.first { $0.eventID.rawValue == 1 })
        let dtx = try #require(analysis.notes.first { $0.eventID.rawValue == 2 })

        #expect(manual.durationTicks == 240)
        #expect(manual.rhythm == NotationRhythm(baseInterval: .quarter))
        #expect(dtx.durationTicks == 120)
        #expect(dtx.rhythm == NotationRhythm(baseInterval: .eighth))
        #expect(analysis.warnings.isEmpty)
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

    @Test("one unsupported group forces conservative rhythm fallback for its whole measure")
    func analyzerFailureFallsBackForWholeMeasure() {
        let analysis = analyze([
            event(1, tick: 0, origin: .dtx),
            event(2, tick: 48, origin: .dtx),
            event(3, tick: 96, origin: .dtx),
            event(4, tick: 144, origin: .dtx),
            event(5, tick: 192, origin: .dtx, candidate: .sixtyfourth),
            event(6, tick: 240, interval: .eighth),
            event(7, tick: 320, interval: .eighth),
            event(8, tick: 400, interval: .eighth),
            event(9, tick: 480, origin: .dtx),
            event(10, tick: 660, origin: .dtx, candidate: .sixteenth)
        ])

        #expect(analysis.notes.map(\.position.localTick) == [0, 48, 96, 144, 192, 240, 320, 400, 480, 660])
        #expect(analysis.notes.allSatisfy {
            if case .unsupported = $0.rhythm.support {
                return $0.rhythm.dotCount == 0 && $0.rhythm.tuplet == nil && $0.tupletID == nil
            }
            return false
        })
        #expect(analysis.tuplets.isEmpty)
        #expect(analysis.rests.filter { $0.voice == .upper && $0.visibility == .printed }.isEmpty)
        #expect(analysis.warnings.count == 1)
        #expect(analysis.warnings.first?.codes.contains(.unsupportedTupletRatio) == true)
    }

    @Test("tuplet ordering and identity are stable across measures, voices, equal starts, and shuffled input")
    func deterministicTupletOrdering() {
        let source = [
            event(31, tick: 0, measureIndex: 1, measureStartTick: 240, voice: .upper),
            event(11, tick: 0, voice: .upper),
            event(23, tick: 160, voice: .lower),
            event(33, tick: 160, measureIndex: 1, measureStartTick: 240, voice: .upper),
            event(21, tick: 0, voice: .lower),
            event(13, tick: 160, voice: .upper),
            event(22, tick: 80, voice: .lower),
            event(32, tick: 80, measureIndex: 1, measureStartTick: 240, voice: .upper),
            event(12, tick: 80, voice: .upper)
        ]
        let rhythmMeasures = [
            measure(
                index: 0,
                duration: 240,
                groups: [RhythmBeatGroup(groupIndex: 0, startTick: 0, durationTicks: 240, isResidual: false)]
            ),
            measure(
                index: 1,
                startTick: 240,
                duration: 240,
                groups: [RhythmBeatGroup(groupIndex: 0, startTick: 0, durationTicks: 240, isResidual: false)]
            )
        ]
        let forward = analyze(source, measures: rhythmMeasures)
        let shuffled = analyze(source.reversed(), measures: rhythmMeasures)

        #expect(forward.tuplets == shuffled.tuplets)
        #expect(forward.notes == shuffled.notes)
        #expect(forward.tuplets.map {
            "\($0.id.measureIndex):\($0.id.startTick):\($0.id.voice)"
        } == [
            "0:0:lower",
            "0:0:upper",
            "1:0:upper"
        ])
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

    @Test("compound overlap diagnosis uses the analyzer whole-note resolution")
    func compoundOverlapUsesActualWholeNoteResolution() {
        let compoundMeasure = measure(
            duration: 720,
            timeSignature: .sixEight,
            groups: [
                RhythmBeatGroup(groupIndex: 0, startTick: 0, durationTicks: 360, isResidual: false),
                RhythmBeatGroup(groupIndex: 1, startTick: 360, durationTicks: 360, isResidual: false)
            ]
        )
        let analysis = analyze([
            event(1, tick: 0, interval: .quarter),
            event(2, tick: 120, interval: .quarter),
            event(3, tick: 240, interval: .quarter)
        ], rhythmMeasure: compoundMeasure)

        #expect(analysis.notes.map(\.position.localTick) == [0, 120, 240])
        #expect(analysis.notes.allSatisfy {
            $0.rhythm.support == .unsupported(.incompleteTuplet)
                && $0.rhythm.dotCount == 0
                && $0.tupletID == nil
        })
        #expect(analysis.tuplets.isEmpty)
        #expect(analysis.warnings == [RhythmMeasureWarning(
            measureIndex: 0,
            codes: [.incompleteTuplet]
        )])
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
