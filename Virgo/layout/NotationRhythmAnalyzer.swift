struct NotationRhythmAnalyzer: Sendable {
    struct VoiceKey: Hashable {
        let measureIndex: Int
        let voice: NotationVoice
    }

    struct Chord {
        let position: RhythmEventPosition
        let voice: NotationVoice
        let events: [RhythmAnalysisEvent]
    }

    struct ChordResolution {
        let chord: Chord
        let beatGroup: RhythmBeatGroup
        var durationTicks: Int
        var rhythm: NotationRhythm
        var tupletID: RhythmTupletID?
    }

    private static let intervalsByDescendingDuration: [NoteInterval] = [
        .full, .half, .quarter, .eighth, .sixteenth, .thirtysecond, .sixtyfourth
    ]

    func classify(spanTicks: Int, ticksPerWholeNote: Int) -> NotationRhythm {
        guard spanTicks > 0, ticksPerWholeNote > 0 else {
            return unsupportedRhythm(.ambiguousBeatGrouping)
        }
        for interval in Self.intervalsByDescendingDuration {
            guard let baseTicks = durationTicks(for: interval, ticksPerWholeNote: ticksPerWholeNote) else {
                continue
            }
            if spanTicks == baseTicks {
                return NotationRhythm(baseInterval: interval)
            }
            let dotted = baseTicks.multipliedReportingOverflow(by: 3)
            if !dotted.overflow, dotted.partialValue.isMultiple(of: 2), spanTicks == dotted.partialValue / 2 {
                return NotationRhythm(baseInterval: interval, dotCount: 1)
            }
        }
        return unsupportedRhythm(.ambiguousBeatGrouping)
    }

    func analyze(
        events: [RhythmAnalysisEvent],
        measures: [RhythmMeasure],
        ticksPerWholeNote: Int,
        feel: RhythmicFeel
    ) -> NotationRhythmAnalysis {
        guard ticksPerWholeNote > 0, !measures.isEmpty else { return .empty }
        let measuresByIndex = Dictionary(uniqueKeysWithValues: measures.map { ($0.measureIndex, $0) })
        let validEvents = events.filter { event in
            guard let measure = measuresByIndex[event.position.measureIndex] else { return false }
            return event.position.localTick >= 0
                && event.position.localTick < measure.durationTicks
                && event.position.absoluteTick == measure.startTick + event.position.localTick
        }
        let chordsByVoice = groupedChords(events: validEvents)
        var resolutions: [ChordResolution] = []
        var tuplets: [AnalyzedRhythmTuplet] = []
        var tupletRests: [AnalyzedRhythmRest] = []
        var warningCodes: [Int: Set<RhythmDiagnosticCode>] = [:]

        for key in chordsByVoice.keys.sorted(by: voiceKeyComesBefore) {
            guard let measure = measuresByIndex[key.measureIndex] else { continue }
            let chords = chordsByVoice[key, default: []]
            var voiceResolutions = resolveChords(
                chords,
                measure: measure,
                ticksPerWholeNote: ticksPerWholeNote,
                warningCodes: &warningCodes
            )
            switch measure.engravingSupport {
            case .supported:
                recognizeTuplets(
                    resolutions: &voiceResolutions,
                    measure: measure,
                    ticksPerWholeNote: ticksPerWholeNote,
                    feel: feel,
                    tuplets: &tuplets,
                    rests: &tupletRests,
                    warningCodes: &warningCodes
                )
            case let .unsupported(codes):
                let code = codes.first ?? .ambiguousBeatGrouping
                warningCodes[measure.measureIndex, default: []].formUnion(codes)
                for index in voiceResolutions.indices {
                    let rhythm = voiceResolutions[index].rhythm
                    voiceResolutions[index].rhythm = NotationRhythm(
                        baseInterval: rhythm.baseInterval,
                        dotCount: rhythm.dotCount,
                        support: .unsupported(code)
                    )
                }
            }
            for index in voiceResolutions.indices
            where voiceResolutions[index].rhythm.support
                == .indeterminate(.indeterminateTerminalDuration) {
                let start = voiceResolutions[index].chord.position.localTick
                voiceResolutions[index].durationTicks = max(measure.durationTicks - start, 1)
                warningCodes[measure.measureIndex, default: []].insert(.indeterminateTerminalDuration)
            }
            resolutions.append(contentsOf: voiceResolutions)
        }

        let notes = analyzedNotes(from: resolutions)
        let analyzedRests = analyzedRests(
            from: resolutions,
            measures: measures,
            reservedTupletRests: tupletRests,
            ticksPerWholeNote: ticksPerWholeNote,
            warningCodes: &warningCodes
        )
        let warnings = warningCodes.keys.sorted().map {
            RhythmMeasureWarning(measureIndex: $0, codes: warningCodes[$0, default: []])
        }
        return NotationRhythmAnalysis(
            notes: notes,
            rests: analyzedRests.sorted(by: analyzedRestComesBefore),
            tuplets: tuplets.sorted { $0.id.startTick < $1.id.startTick },
            warnings: warnings
        )
    }
}

private extension NotationRhythmAnalyzer {
    func analyzedNotes(from resolutions: [ChordResolution]) -> [AnalyzedRhythmNote] {
        resolutions.flatMap { resolution in
            resolution.chord.events.map { event in
                AnalyzedRhythmNote(
                    eventID: event.eventID,
                    position: event.position,
                    voice: event.voice,
                    beatGroupIndex: resolution.beatGroup.groupIndex,
                    durationTicks: resolution.durationTicks,
                    rhythm: resolution.rhythm,
                    tupletID: resolution.tupletID
                )
            }
        }.sorted(by: analyzedNoteComesBefore)
    }

    func analyzedRests(
        from resolutions: [ChordResolution],
        measures: [RhythmMeasure],
        reservedTupletRests: [AnalyzedRhythmRest],
        ticksPerWholeNote: Int,
        warningCodes: inout [Int: Set<RhythmDiagnosticCode>]
    ) -> [AnalyzedRhythmRest] {
        let restNotes = resolutions.map { resolution in
            RestTimelineNote(
                position: resolution.chord.position,
                voice: resolution.chord.voice,
                durationTicks: resolution.rhythm.support == .supported
                    ? resolution.durationTicks : nil,
                rhythm: resolution.rhythm,
                tupletID: resolution.tupletID
            )
        }
        let topology = NotationRestTopologyBuilder().buildExact(
            notes: restNotes,
            measures: measures,
            reservedTupletRests: reservedTupletRests,
            ticksPerWholeNote: ticksPerWholeNote
        )
        for warning in topology.warnings {
            warningCodes[warning.measureIndex, default: []].formUnion(warning.codes)
        }
        return topology.events.map { event in
            AnalyzedRhythmRest(
                measureIndex: event.measureIndex,
                voice: event.voice,
                startTick: event.startTick,
                durationTicks: event.durationTicks,
                rhythm: event.rhythm ?? unsupportedRhythm(.ambiguousBeatGrouping),
                tupletID: event.tupletID,
                visibility: event.visibility
            )
        }
    }

    func groupedChords(events: [RhythmAnalysisEvent]) -> [VoiceKey: [Chord]] {
        let byVoice = Dictionary(grouping: events) {
            VoiceKey(measureIndex: $0.position.measureIndex, voice: $0.voice)
        }
        return byVoice.mapValues { voiceEvents in
            Dictionary(grouping: voiceEvents, by: { $0.position.localTick })
                .keys.sorted()
                .map { tick in
                    let members = voiceEvents.filter { $0.position.localTick == tick }.sorted {
                        $0.eventID.rawValue < $1.eventID.rawValue
                    }
                    return Chord(position: members[0].position, voice: members[0].voice, events: members)
                }
        }
    }

    func resolveChords(
        _ chords: [Chord],
        measure: RhythmMeasure,
        ticksPerWholeNote: Int,
        warningCodes: inout [Int: Set<RhythmDiagnosticCode>]
    ) -> [ChordResolution] {
        chords.indices.compactMap { index in
            let chord = chords[index]
            guard let beatGroup = measure.beatGroups.first(where: {
                chord.position.localTick >= $0.startTick && chord.position.localTick < $0.endTick
            }) else {
                warningCodes[measure.measureIndex, default: []].insert(.ambiguousBeatGrouping)
                return nil
            }
            let allManual = chord.events.allSatisfy { $0.origin == .manual }
            if allManual {
                let intervals = Set(chord.events.map(\.storedInterval))
                guard intervals.count == 1, let interval = intervals.first,
                      let duration = durationTicks(for: interval, ticksPerWholeNote: ticksPerWholeNote) else {
                    warningCodes[measure.measureIndex, default: []].insert(.ambiguousBeatGrouping)
                    return ChordResolution(
                        chord: chord,
                        beatGroup: beatGroup,
                        durationTicks: max(measure.durationTicks - chord.position.localTick, 1),
                        rhythm: unsupportedRhythm(.ambiguousBeatGrouping),
                        tupletID: nil
                    )
                }
                return ChordResolution(
                    chord: chord,
                    beatGroup: beatGroup,
                    durationTicks: duration,
                    rhythm: NotationRhythm(baseInterval: interval),
                    tupletID: nil
                )
            }

            if index + 1 < chords.count {
                let span = chords[index + 1].position.localTick - chord.position.localTick
                let rhythm = classify(spanTicks: span, ticksPerWholeNote: ticksPerWholeNote)
                if rhythm.support != .supported {
                    warningCodes[measure.measureIndex, default: []].insert(.ambiguousBeatGrouping)
                }
                return ChordResolution(
                    chord: chord,
                    beatGroup: beatGroup,
                    durationTicks: max(span, 1),
                    rhythm: rhythm,
                    tupletID: nil
                )
            }

            let candidates = Set(chord.events.compactMap(\.visualDurationCandidate))
            if candidates.count == 1, let interval = candidates.first,
               let duration = durationTicks(for: interval, ticksPerWholeNote: ticksPerWholeNote),
               chord.position.localTick + duration <= min(beatGroup.endTick, measure.durationTicks) {
                return ChordResolution(
                    chord: chord,
                    beatGroup: beatGroup,
                    durationTicks: duration,
                    rhythm: NotationRhythm(baseInterval: interval),
                    tupletID: nil
                )
            }

            if candidates.count == 1, let interval = candidates.first,
               let duration = durationTicks(for: interval, ticksPerWholeNote: ticksPerWholeNote) {
                let compressed = duration.multipliedReportingOverflow(by: 2)
                if !compressed.overflow, compressed.partialValue.isMultiple(of: 3) {
                    let compressedDuration = compressed.partialValue / 3
                    if chord.position.localTick + compressedDuration
                        <= min(beatGroup.endTick, measure.durationTicks) {
                        return ChordResolution(
                            chord: chord,
                            beatGroup: beatGroup,
                            durationTicks: compressedDuration,
                            rhythm: NotationRhythm(
                                baseInterval: interval,
                                support: .indeterminate(.indeterminateTerminalDuration)
                            ),
                            tupletID: nil
                        )
                    }
                }
            }

            warningCodes[measure.measureIndex, default: []].insert(.indeterminateTerminalDuration)
            return ChordResolution(
                chord: chord,
                beatGroup: beatGroup,
                durationTicks: max(measure.durationTicks - chord.position.localTick, 1),
                rhythm: NotationRhythm(
                    baseInterval: candidates.first ?? .quarter,
                    support: .indeterminate(.indeterminateTerminalDuration)
                ),
                tupletID: nil
            )
        }
    }
}

private extension NotationRhythmAnalyzer {
    func recognizeTuplets(
        resolutions: inout [ChordResolution],
        measure: RhythmMeasure,
        ticksPerWholeNote: Int,
        feel: RhythmicFeel,
        tuplets: inout [AnalyzedRhythmTuplet],
        rests: inout [AnalyzedRhythmRest],
        warningCodes: inout [Int: Set<RhythmDiagnosticCode>]
    ) {
        for group in measure.beatGroups where group.durationTicks > 0 && group.durationTicks.isMultiple(of: 3) {
            let indices = resolutions.indices.filter { resolutions[$0].beatGroup.groupIndex == group.groupIndex }
            guard !indices.isEmpty else { continue }
            let slotTicks = group.durationTicks / 3
            let slotByIndex = Dictionary(uniqueKeysWithValues: indices.compactMap { index -> (Int, Int)? in
                let offset = resolutions[index].chord.position.localTick - group.startTick
                guard offset >= 0, offset.isMultiple(of: slotTicks), offset / slotTicks < 3 else { return nil }
                return (index, offset / slotTicks)
            })

            if indices.count >= 4, equallyDivides(group: group, resolutions: resolutions, indices: indices) {
                warningCodes[measure.measureIndex, default: []].insert(.unsupportedTupletRatio)
                continue
            }
            guard slotByIndex.count == indices.count, Set(slotByIndex.values).count >= 2 else { continue }

            guard let tripletRhythms = tripletRhythms(
                resolutions: resolutions,
                indices: indices,
                group: group,
                ticksPerWholeNote: ticksPerWholeNote
            ) else {
                warningCodes[measure.measureIndex, default: []].insert(.incompleteTuplet)
                continue
            }

            let firstVoice = resolutions[indices[0]].chord.voice
            let tupletID = RhythmTupletID(
                measureIndex: measure.measureIndex,
                voice: firstVoice,
                beatGroupIndex: group.groupIndex,
                startTick: group.startTick,
                durationTicks: group.durationTicks
            )
            let occupiedSlots = Set(slotByIndex.values)
            let durations = indices.compactMap { index -> Int? in
                guard let interval = tripletRhythms[index]?.baseInterval,
                      let baseTicks = durationTicks(
                        for: interval,
                        ticksPerWholeNote: ticksPerWholeNote
                      ) else { return nil }
                return baseTicks * 2 / 3
            }
            let isFeelPair = indices.count == 2
                && occupiedSlots == [0, 2]
                && durations.count == 2
                && durations[0] == durations[1] * 2
            let visibility: TupletBracketVisibility = feel != .straight && isFeelPair
                ? .suppressedForFeel : .shown
            tuplets.append(AnalyzedRhythmTuplet(
                id: tupletID,
                ratio: TupletRatio(actual: 3, normal: 2),
                bracketVisibility: visibility
            ))

            for index in indices {
                guard let rhythm = tripletRhythms[index],
                      let baseTicks = durationTicks(
                        for: rhythm.baseInterval,
                        ticksPerWholeNote: ticksPerWholeNote
                      ) else {
                    continue
                }
                resolutions[index].rhythm = rhythm
                resolutions[index].durationTicks = baseTicks * 2 / 3
                resolutions[index].tupletID = tupletID
            }
            if !isFeelPair, let noteRhythm = tripletRhythms[indices[0]] {
                for slot in 0..<3 where !occupiedSlots.contains(slot) {
                    rests.append(AnalyzedRhythmRest(
                        measureIndex: measure.measureIndex,
                        voice: firstVoice,
                        startTick: group.startTick + slot * slotTicks,
                        durationTicks: slotTicks,
                        rhythm: NotationRhythm(
                            baseInterval: noteRhythm.baseInterval,
                            tuplet: TupletRatio(actual: 3, normal: 2)
                        ),
                        tupletID: tupletID,
                        visibility: .printed
                    ))
                }
            }
        }
    }

    func tripletRhythms(
        resolutions: [ChordResolution],
        indices: [Int],
        group: RhythmBeatGroup,
        ticksPerWholeNote: Int
    ) -> [Int: NotationRhythm]? {
        var result: [Int: NotationRhythm] = [:]
        let ordered = indices.sorted {
            resolutions[$0].chord.position.localTick < resolutions[$1].chord.position.localTick
        }
        for (position, index) in ordered.enumerated() {
            let resolution = resolutions[index]
            let baseInterval: NoteInterval?
            if resolution.chord.events.allSatisfy({ $0.origin == .manual }) {
                let intervals = Set(resolution.chord.events.map(\.storedInterval))
                baseInterval = intervals.count == 1 ? intervals.first : nil
            } else {
                baseInterval = tripletBaseInterval(
                    resolution: resolution,
                    ticksPerWholeNote: ticksPerWholeNote
                )
            }
            guard let baseInterval,
                  let baseTicks = durationTicks(
                    for: baseInterval,
                    ticksPerWholeNote: ticksPerWholeNote
                  ) else { return nil }
            let compressed = baseTicks.multipliedReportingOverflow(by: 2)
            guard !compressed.overflow, compressed.partialValue.isMultiple(of: 3) else { return nil }
            let duration = compressed.partialValue / 3
            let nextStart = position + 1 < ordered.count
                ? resolutions[ordered[position + 1]].chord.position.localTick
                : group.endTick
            guard duration <= nextStart - resolution.chord.position.localTick else { return nil }
            result[index] = NotationRhythm(
                baseInterval: baseInterval,
                tuplet: TupletRatio(actual: 3, normal: 2)
            )
        }
        return result
    }

    func tripletBaseInterval(
        resolution: ChordResolution,
        ticksPerWholeNote: Int
    ) -> NoteInterval? {
        let terminalCandidates = Set(
            resolution.chord.events.compactMap(\.visualDurationCandidate)
        )
        if terminalCandidates.count == 1 { return terminalCandidates.first }
        let tripletBase = resolution.durationTicks.multipliedReportingOverflow(by: 3)
        guard !tripletBase.overflow, tripletBase.partialValue.isMultiple(of: 2) else { return nil }
        return binaryInterval(
            for: tripletBase.partialValue / 2,
            ticksPerWholeNote: ticksPerWholeNote
        )
    }

    func equallyDivides(
        group: RhythmBeatGroup,
        resolutions: [ChordResolution],
        indices: [Int]
    ) -> Bool {
        let ticks = indices.map { resolutions[$0].chord.position.localTick }.sorted()
        guard ticks.count > 3 else { return false }
        let distances = zip(ticks, ticks.dropFirst()).map { $1 - $0 }
        guard let first = distances.first, first > 0, distances.allSatisfy({ $0 == first }) else {
            return false
        }
        return group.durationTicks.isMultiple(of: first)
    }
}

private extension NotationRhythmAnalyzer {
    func durationTicks(for interval: NoteInterval, ticksPerWholeNote: Int) -> Int? {
        let divisor: Int
        switch interval {
        case .full: divisor = 1
        case .half: divisor = 2
        case .quarter: divisor = 4
        case .eighth: divisor = 8
        case .sixteenth: divisor = 16
        case .thirtysecond: divisor = 32
        case .sixtyfourth: divisor = 64
        }
        guard ticksPerWholeNote > 0, ticksPerWholeNote.isMultiple(of: divisor) else { return nil }
        return ticksPerWholeNote / divisor
    }

    func binaryInterval(for ticks: Int, ticksPerWholeNote: Int) -> NoteInterval? {
        Self.intervalsByDescendingDuration.first {
            durationTicks(for: $0, ticksPerWholeNote: ticksPerWholeNote) == ticks
        }
    }

    func unsupportedRhythm(_ code: RhythmDiagnosticCode) -> NotationRhythm {
        NotationRhythm(baseInterval: .quarter, support: .unsupported(code))
    }

    func voiceKeyComesBefore(_ lhs: VoiceKey, _ rhs: VoiceKey) -> Bool {
        lhs.measureIndex != rhs.measureIndex
            ? lhs.measureIndex < rhs.measureIndex
            : lhs.voice.rawValue < rhs.voice.rawValue
    }

    func analyzedNoteComesBefore(_ lhs: AnalyzedRhythmNote, _ rhs: AnalyzedRhythmNote) -> Bool {
        lhs.position.absoluteTick != rhs.position.absoluteTick
            ? lhs.position.absoluteTick < rhs.position.absoluteTick
            : lhs.eventID.rawValue < rhs.eventID.rawValue
    }

    func analyzedRestComesBefore(_ lhs: AnalyzedRhythmRest, _ rhs: AnalyzedRhythmRest) -> Bool {
        if lhs.measureIndex != rhs.measureIndex { return lhs.measureIndex < rhs.measureIndex }
        if lhs.voice != rhs.voice { return lhs.voice == .upper }
        return lhs.startTick < rhs.startTick
    }
}
