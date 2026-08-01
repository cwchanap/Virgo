struct NotationRhythmAnalyzer: Sendable {
    struct StreamKey: Hashable {
        let measureIndex: Int
        let voice: NotationVoice
        let beatGroupIndex: Int
    }

    struct MeasureVoiceKey: Hashable {
        let measureIndex: Int
        let voice: NotationVoice
    }

    struct LocatedEvent {
        let event: RhythmAnalysisEvent
        let beatGroup: RhythmBeatGroup
    }

    struct EventResolution {
        let event: RhythmAnalysisEvent
        let beatGroup: RhythmBeatGroup
        let hasFollowingDTXOnset: Bool
        var durationTicks: Int
        var rhythm: NotationRhythm
        var tupletID: RhythmTupletID?
    }

    struct TupletCandidate {
        let startTick: Int
        let slotTicks: Int
        let memberIndices: [Int]
        let occupiedSlots: Set<Int>
        let isFeelPair: Bool

        var durationTicks: Int { slotTicks * 3 }
    }

    /// Explicit musical order. Never derive semantic fallback from Set iteration.
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
        let lastVoiceOnsetTicks = lastOnsetTicksByMeasureAndVoice(events: validEvents)
        let measureDTXOnsets = dtxOnsetTicksByMeasureAndVoice(events: validEvents)
        var diagnosticCodes = metadataDiagnosticCodes(measures: measures)
        let streams = groupedStreams(
            events: validEvents,
            measuresByIndex: measuresByIndex,
            diagnosticCodes: &diagnosticCodes
        )
        var resolutions: [EventResolution] = []
        var tuplets: [AnalyzedRhythmTuplet] = []
        var reservedTupletRests: [AnalyzedRhythmRest] = []

        for key in streams.keys.sorted(by: streamKeyComesBefore) {
            guard let measure = measuresByIndex[key.measureIndex] else { continue }
            let voiceKey = MeasureVoiceKey(measureIndex: key.measureIndex, voice: key.voice)
            var streamResolutions = resolveStream(
                streams[key, default: []],
                measure: measure,
                lastVoiceOnsetTick: lastVoiceOnsetTicks[voiceKey],
                measureDTXOnsets: measureDTXOnsets[voiceKey] ?? [],
                ticksPerWholeNote: ticksPerWholeNote
            )
            if measure.engravingSupport.permitsEngraving {
                recognizeTuplets(
                    resolutions: &streamResolutions,
                    measure: measure,
                    ticksPerWholeNote: ticksPerWholeNote,
                    feel: feel,
                    tuplets: &tuplets,
                    rests: &reservedTupletRests
                )
                diagnoseUnrecognizedStructure(
                    resolutions: streamResolutions,
                    measure: measure,
                    ticksPerWholeNote: ticksPerWholeNote,
                    diagnosticCodes: &diagnosticCodes
                )
            }
            finalizeIndeterminateDurations(
                resolutions: &streamResolutions,
                diagnosticCodes: &diagnosticCodes
            )
            resolutions.append(contentsOf: streamResolutions)
        }

        var effectiveMeasures = measuresWithFallback(measures, diagnosticCodes: diagnosticCodes)
        let fallbackDiagnosticCodesByMeasure = fallbackDiagnosticCodes(
            for: effectiveMeasures,
            diagnosticCodes: diagnosticCodes
        )
        applyConservativeFallback(
            resolutions: &resolutions,
            tuplets: &tuplets,
            rests: &reservedTupletRests,
            fallbackDiagnosticCodesByMeasure: fallbackDiagnosticCodesByMeasure
        )
        var notes = analyzedNotes(from: resolutions)
        let preRestMeasures = effectiveMeasures
        var restsOutput = analyzedRests(
            from: resolutions, measures: effectiveMeasures, reservedTupletRests: reservedTupletRests,
            ticksPerWholeNote: ticksPerWholeNote, diagnosticCodes: &diagnosticCodes
        )

        let postRestState = postRestState(
            from: measures,
            preRestMeasures: preRestMeasures,
            diagnosticCodes: diagnosticCodes
        )
        effectiveMeasures = postRestState.measures
        if !postRestState.newlyNonPermitting.isEmpty {
            let newlyNonPermittingDiagnosticCodesByMeasure = fallbackDiagnosticCodes(
                for: effectiveMeasures,
                diagnosticCodes: diagnosticCodes,
                restrictedTo: postRestState.newlyNonPermitting
            )
            applyConservativeFallback(
                resolutions: &resolutions,
                tuplets: &tuplets,
                rests: &reservedTupletRests,
                fallbackDiagnosticCodesByMeasure: newlyNonPermittingDiagnosticCodesByMeasure
            )
            notes = analyzedNotes(from: resolutions)
            restsOutput = analyzedRests(
                from: resolutions, measures: effectiveMeasures, reservedTupletRests: reservedTupletRests,
                ticksPerWholeNote: ticksPerWholeNote, diagnosticCodes: &diagnosticCodes
            )
            effectiveMeasures = measuresWithFallback(measures, diagnosticCodes: diagnosticCodes)
        }

        let warnings = rhythmWarnings(from: diagnosticCodes)
        return NotationRhythmAnalysis(
            notes: notes,
            rests: restsOutput.sorted(by: analyzedRestComesBefore),
            tuplets: tuplets.sorted(by: analyzedTupletComesBefore),
            warnings: warnings
        )
    }
}

private extension NotationRhythmAnalyzer {
    func metadataDiagnosticCodes(measures: [RhythmMeasure]) -> [Int: Set<RhythmDiagnosticCode>] {
        var result: [Int: Set<RhythmDiagnosticCode>] = [:]
        for measure in measures {
            switch measure.engravingSupport {
            case .supported:
                continue
            case let .warning(codes), let .unsupported(codes):
                result[measure.measureIndex, default: []].formUnion(codes)
            }
        }
        return result
    }

    func groupedStreams(
        events: [RhythmAnalysisEvent],
        measuresByIndex: [Int: RhythmMeasure],
        diagnosticCodes: inout [Int: Set<RhythmDiagnosticCode>]
    ) -> [StreamKey: [LocatedEvent]] {
        var streams: [StreamKey: [LocatedEvent]] = [:]
        for event in events {
            guard let measure = measuresByIndex[event.position.measureIndex],
                  let group = measure.beatGroups.first(where: {
                      event.position.localTick >= $0.startTick && event.position.localTick < $0.endTick
                  }) else {
                diagnosticCodes[event.position.measureIndex, default: []].insert(.ambiguousBeatGrouping)
                continue
            }
            let key = StreamKey(
                measureIndex: event.position.measureIndex,
                voice: event.voice,
                beatGroupIndex: group.groupIndex
            )
            streams[key, default: []].append(LocatedEvent(event: event, beatGroup: group))
        }
        return streams.mapValues {
            $0.sorted {
                $0.event.position.localTick != $1.event.position.localTick
                    ? $0.event.position.localTick < $1.event.position.localTick
                    : $0.event.eventID.rawValue < $1.event.eventID.rawValue
            }
        }
    }

    func lastOnsetTicksByMeasureAndVoice(
        events: [RhythmAnalysisEvent]
    ) -> [MeasureVoiceKey: Int] {
        Dictionary(grouping: events) {
            MeasureVoiceKey(
                measureIndex: $0.position.measureIndex,
                voice: $0.voice
            )
        }.mapValues { events in
            events.map(\.position.localTick).max() ?? 0
        }
    }

    /// Sorted same-voice DTX onset ticks per measure, used to cap candidate
    /// evidence in `terminalDTXResolution` so an upward-rounded visual
    /// candidate cannot overrun a later same-voice onset in a different beat
    /// group.
    func dtxOnsetTicksByMeasureAndVoice(
        events: [RhythmAnalysisEvent]
    ) -> [MeasureVoiceKey: [Int]] {
        Dictionary(grouping: events.filter { $0.origin == .dtx }) {
            MeasureVoiceKey(
                measureIndex: $0.position.measureIndex,
                voice: $0.voice
            )
        }.mapValues { events in
            events.map(\.position.localTick).sorted()
        }
    }

    func resolveStream(
        _ locatedEvents: [LocatedEvent],
        measure: RhythmMeasure,
        lastVoiceOnsetTick: Int?,
        measureDTXOnsets: [Int],
        ticksPerWholeNote: Int
    ) -> [EventResolution] {
        let dtxOnsets = Set(locatedEvents.compactMap {
            $0.event.origin == .dtx ? $0.event.position.localTick : nil
        }).sorted()
        return locatedEvents.map { located in
            let event = located.event
            if event.origin == .manual {
                let duration = durationTicks(
                    for: event.storedInterval,
                    ticksPerWholeNote: ticksPerWholeNote
                ) ?? 1
                return EventResolution(
                    event: event,
                    beatGroup: located.beatGroup,
                    hasFollowingDTXOnset: false,
                    durationTicks: duration,
                    rhythm: NotationRhythm(baseInterval: event.storedInterval),
                    tupletID: nil
                )
            }
            let nextDTXOnset = dtxOnsets.first { $0 > event.position.localTick }
            if let nextDTXOnset {
                let span = max(nextDTXOnset - event.position.localTick, 1)
                return EventResolution(
                    event: event,
                    beatGroup: located.beatGroup,
                    hasFollowingDTXOnset: true,
                    durationTicks: span,
                    rhythm: classify(spanTicks: span, ticksPerWholeNote: ticksPerWholeNote),
                    tupletID: nil
                )
            }
            return terminalDTXResolution(
                event: event,
                beatGroup: located.beatGroup,
                measure: measure,
                mayUseMeasureRemainder: event.position.localTick == lastVoiceOnsetTick,
                measureDTXOnsets: measureDTXOnsets,
                ticksPerWholeNote: ticksPerWholeNote
            )
        }
    }

    func terminalDTXResolution(
        event: RhythmAnalysisEvent,
        beatGroup: RhythmBeatGroup,
        measure: RhythmMeasure,
        mayUseMeasureRemainder: Bool,
        measureDTXOnsets: [Int],
        ticksPerWholeNote: Int
    ) -> EventResolution {
        let measureBoundary = measure.durationTicks
        let beatGroupBoundary = min(beatGroup.endTick, measureBoundary)
        let nextMeasureDTXOnset = measureDTXOnsets.first { $0 > event.position.localTick }

        // When a later same-voice DTX onset exists elsewhere in the measure
        // (typically in a following beat group), cap candidate evidence at
        // that onset so an upward-rounded visual candidate cannot overrun it.
        // `VisualDurationLookup` derives candidates chart-wide and snaps to
        // the closest base interval, rounding up on ties, so the candidate
        // can exceed the actual span to the next onset.
        if let nextTick = nextMeasureDTXOnset {
            let span = nextTick - event.position.localTick
            if let interval = event.visualDurationCandidate,
               let duration = durationTicks(for: interval, ticksPerWholeNote: ticksPerWholeNote),
               duration <= span,
               event.position.localTick + duration <= measureBoundary {
                return EventResolution(
                    event: event,
                    beatGroup: beatGroup,
                    hasFollowingDTXOnset: false,
                    durationTicks: duration,
                    rhythm: NotationRhythm(baseInterval: interval),
                    tupletID: nil
                )
            }
            let spanRhythm = classify(spanTicks: span, ticksPerWholeNote: ticksPerWholeNote)
            if spanRhythm.support == .supported {
                return EventResolution(
                    event: event,
                    beatGroup: beatGroup,
                    hasFollowingDTXOnset: false,
                    durationTicks: span,
                    rhythm: spanRhythm,
                    tupletID: nil
                )
            }
            return EventResolution(
                event: event,
                beatGroup: beatGroup,
                hasFollowingDTXOnset: false,
                durationTicks: max(min(beatGroupBoundary - event.position.localTick, span), 1),
                rhythm: NotationRhythm(
                    baseInterval: event.visualDurationCandidate ?? .quarter,
                    support: .indeterminate(.indeterminateTerminalDuration)
                ),
                tupletID: nil
            )
        }

        // No later same-voice DTX onset in the measure — truly terminal.
        if let interval = event.visualDurationCandidate,
           let duration = durationTicks(for: interval, ticksPerWholeNote: ticksPerWholeNote),
           event.position.localTick + duration <= measureBoundary {
            return EventResolution(
                event: event,
                beatGroup: beatGroup,
                hasFollowingDTXOnset: false,
                durationTicks: duration,
                rhythm: NotationRhythm(baseInterval: interval),
                tupletID: nil
            )
        }
        // Try the exact measure remainder before the compressed-triplet
        // fallback so a supported dotted remainder is not masked by an
        // indeterminate compression that merely fits the beat group.
        if mayUseMeasureRemainder,
           let resolution = exactMeasureRemainderResolution(
               event: event,
               beatGroup: beatGroup,
               measureBoundary: measureBoundary,
               ticksPerWholeNote: ticksPerWholeNote
           ) {
            return resolution
        }
        if let interval = event.visualDurationCandidate,
           let baseDuration = durationTicks(for: interval, ticksPerWholeNote: ticksPerWholeNote),
           let compressedDuration = tripletPerformedTicks(baseTicks: baseDuration),
           event.position.localTick + compressedDuration <= beatGroupBoundary {
            return EventResolution(
                event: event,
                beatGroup: beatGroup,
                hasFollowingDTXOnset: false,
                durationTicks: compressedDuration,
                rhythm: NotationRhythm(
                    baseInterval: interval,
                    support: .indeterminate(.indeterminateTerminalDuration)
                ),
                tupletID: nil
            )
        }
        return EventResolution(
            event: event,
            beatGroup: beatGroup,
            hasFollowingDTXOnset: false,
            durationTicks: max(beatGroupBoundary - event.position.localTick, 1),
            rhythm: NotationRhythm(
                baseInterval: event.visualDurationCandidate ?? .quarter,
                support: .indeterminate(.indeterminateTerminalDuration)
            ),
            tupletID: nil
        )
    }

    func exactMeasureRemainderResolution(
        event: RhythmAnalysisEvent,
        beatGroup: RhythmBeatGroup,
        measureBoundary: Int,
        ticksPerWholeNote: Int
    ) -> EventResolution? {
        let remainingDuration = measureBoundary - event.position.localTick
        let remainingRhythm = classify(
            spanTicks: remainingDuration,
            ticksPerWholeNote: ticksPerWholeNote
        )
        guard remainingRhythm.support == .supported else { return nil }
        return EventResolution(
            event: event,
            beatGroup: beatGroup,
            hasFollowingDTXOnset: false,
            durationTicks: remainingDuration,
            rhythm: remainingRhythm,
            tupletID: nil
        )
    }
}

private extension NotationRhythmAnalyzer {
    func recognizeTuplets(
        resolutions: inout [EventResolution],
        measure: RhythmMeasure,
        ticksPerWholeNote: Int,
        feel: RhythmicFeel,
        tuplets: inout [AnalyzedRhythmTuplet],
        rests: inout [AnalyzedRhythmRest]
    ) {
        guard let group = resolutions.first?.beatGroup else { return }
        let candidates = tripletCandidates(
            resolutions: resolutions,
            group: group,
            ticksPerWholeNote: ticksPerWholeNote
        )
        var claimedMembers: Set<Int> = []
        var claimedRanges: [Range<Int>] = []
        for candidate in candidates {
            let range = candidate.startTick..<(candidate.startTick + candidate.durationTicks)
            guard candidate.memberIndices.allSatisfy({ !claimedMembers.contains($0) }),
                  claimedRanges.allSatisfy({ $0.overlaps(range) == false }) else { continue }
            let memberIDs = candidate.memberIndices.map { resolutions[$0].event.eventID }
            guard let stableMemberID = memberIDs.min(by: { $0.rawValue < $1.rawValue }) else { continue }
            let voice = resolutions[candidate.memberIndices[0]].event.voice
            let tupletID = RhythmTupletID(
                measureIndex: measure.measureIndex,
                voice: voice,
                beatGroupIndex: group.groupIndex,
                startTick: candidate.startTick,
                durationTicks: candidate.durationTicks,
                stableMemberEventID: stableMemberID
            )
            tuplets.append(AnalyzedRhythmTuplet(
                id: tupletID,
                ratio: TupletRatio(actual: 3, normal: 2),
                bracketVisibility: feel != .straight && candidate.isFeelPair
                    ? .suppressedForFeel : .shown
            ))
            for index in candidate.memberIndices {
                guard let interval = tripletBaseInterval(
                    for: resolutions[index],
                    ticksPerWholeNote: ticksPerWholeNote
                ), let baseTicks = durationTicks(for: interval, ticksPerWholeNote: ticksPerWholeNote),
                      let performedTicks = tripletPerformedTicks(baseTicks: baseTicks) else { continue }
                resolutions[index].durationTicks = performedTicks
                resolutions[index].rhythm = NotationRhythm(
                    baseInterval: interval,
                    tuplet: TupletRatio(actual: 3, normal: 2)
                )
                resolutions[index].tupletID = tupletID
                claimedMembers.insert(index)
            }
            claimedRanges.append(range)
            appendSilentTupletRests(
                candidate: candidate,
                tupletID: tupletID,
                measureIndex: measure.measureIndex,
                voice: voice,
                ticksPerWholeNote: ticksPerWholeNote,
                rests: &rests
            )
        }
    }

    func tripletCandidates(
        resolutions: [EventResolution],
        group: RhythmBeatGroup,
        ticksPerWholeNote: Int
    ) -> [TupletCandidate] {
        let performedByIndex = Dictionary(uniqueKeysWithValues: resolutions.indices.compactMap { index in
            tripletPerformedDuration(for: resolutions[index], ticksPerWholeNote: ticksPerWholeNote)
                .map { (index, $0) }
        })
        let slotTicks = Set(performedByIndex.values).sorted()
        var candidates: [TupletCandidate] = []
        for slot in slotTicks where slot > 0 {
            let subgroupDuration = slot.multipliedReportingOverflow(by: 3)
            guard !subgroupDuration.overflow, subgroupDuration.partialValue <= group.durationTicks else { continue }
            let starts = Set(resolutions.flatMap { resolution in
                (0..<3).map { resolution.event.position.localTick - $0 * slot }
            }).sorted()
            for start in starts where start >= group.startTick
                && start + subgroupDuration.partialValue <= group.endTick
                && (start - group.startTick).isMultiple(of: slot) {
                if let candidate = tripletCandidate(
                    startTick: start,
                    slotTicks: slot,
                    resolutions: resolutions,
                    performedByIndex: performedByIndex
                ) {
                    candidates.append(candidate)
                }
            }
        }
        return candidates.sorted {
            if $0.memberIndices.count != $1.memberIndices.count {
                return $0.memberIndices.count > $1.memberIndices.count
            }
            if $0.occupiedSlots.count != $1.occupiedSlots.count {
                return $0.occupiedSlots.count > $1.occupiedSlots.count
            }
            if $0.startTick != $1.startTick { return $0.startTick < $1.startTick }
            return $0.slotTicks > $1.slotTicks
        }
    }

    func tripletCandidate(
        startTick: Int,
        slotTicks: Int,
        resolutions: [EventResolution],
        performedByIndex: [Int: Int]
    ) -> TupletCandidate? {
        let endTick = startTick + slotTicks * 3
        let indicesInRange = resolutions.indices.filter {
            let tick = resolutions[$0].event.position.localTick
            return tick >= startTick && tick < endTick
        }
        guard !indicesInRange.isEmpty, indicesInRange.allSatisfy({ index in
            (resolutions[index].event.position.localTick - startTick).isMultiple(of: slotTicks)
        }) else { return nil }

        let equalMembers = indicesInRange.filter { performedByIndex[$0] == slotTicks }
        let equalSlots = Set(equalMembers.map {
            (resolutions[$0].event.position.localTick - startTick) / slotTicks
        })
        let allOnsetSlots = Set(indicesInRange.map {
            (resolutions[$0].event.position.localTick - startTick) / slotTicks
        })
        if equalSlots.count >= 2, equalSlots == allOnsetSlots {
            return TupletCandidate(
                startTick: startTick,
                slotTicks: slotTicks,
                memberIndices: equalMembers,
                occupiedSlots: equalSlots,
                isFeelPair: false
            )
        }

        guard allOnsetSlots == [0, 2] else { return nil }
        let feelMembers = indicesInRange.filter { index in
            let slot = (resolutions[index].event.position.localTick - startTick) / slotTicks
            return slot == 0 ? performedByIndex[index] == slotTicks * 2
                : performedByIndex[index] == slotTicks
        }
        let feelSlots = Set(feelMembers.map {
            (resolutions[$0].event.position.localTick - startTick) / slotTicks
        })
        guard feelSlots == [0, 2] else { return nil }
        return TupletCandidate(
            startTick: startTick,
            slotTicks: slotTicks,
            memberIndices: feelMembers,
            occupiedSlots: feelSlots,
            isFeelPair: true
        )
    }

    func appendSilentTupletRests(
        candidate: TupletCandidate,
        tupletID: RhythmTupletID,
        measureIndex: Int,
        voice: NotationVoice,
        ticksPerWholeNote: Int,
        rests: inout [AnalyzedRhythmRest]
    ) {
        guard !candidate.isFeelPair,
              let baseInterval = tripletBaseInterval(
                  performedTicks: candidate.slotTicks,
                  ticksPerWholeNote: ticksPerWholeNote
              ) else { return }
        for slot in 0..<3 where !candidate.occupiedSlots.contains(slot) {
            rests.append(AnalyzedRhythmRest(
                measureIndex: measureIndex,
                voice: voice,
                startTick: candidate.startTick + slot * candidate.slotTicks,
                durationTicks: candidate.slotTicks,
                rhythm: NotationRhythm(
                    baseInterval: baseInterval,
                    tuplet: TupletRatio(actual: 3, normal: 2)
                ),
                tupletID: tupletID,
                visibility: .printed
            ))
        }
    }
}

private extension NotationRhythmAnalyzer {
    func diagnoseUnrecognizedStructure(
        resolutions: [EventResolution],
        measure: RhythmMeasure,
        ticksPerWholeNote: Int,
        diagnosticCodes: inout [Int: Set<RhythmDiagnosticCode>]
    ) {
        let unresolved = resolutions.filter { $0.tupletID == nil }
        let unsupportedSpan = unresolved.contains {
            if case .unsupported = $0.rhythm.support { return true }
            return false
        }
        let onsetTicks = Set(unresolved.map { $0.event.position.localTick }).sorted()
        let distances = zip(onsetTicks, onsetTicks.dropFirst()).map { $1 - $0 }
        if unsupportedSpan, onsetTicks.count >= 4,
           let distance = distances.first, distance > 0,
           distances.allSatisfy({ $0 == distance }) {
            diagnosticCodes[measure.measureIndex, default: []].insert(.unsupportedTupletRatio)
        } else if unsupportedSpan {
            diagnosticCodes[measure.measureIndex, default: []].insert(.incompleteTuplet)
        }

        guard let group = resolutions.first?.beatGroup,
              group.durationTicks.isMultiple(of: 3) else { return }
        let slot = group.durationTicks / 3
        let exactThirdOnsets = [group.startTick, group.startTick + slot, group.startTick + slot * 2]
        guard exactThirdOnsets.allSatisfy(onsetTicks.contains) else { return }
        let overlapping = unresolved.contains { resolution in
            guard exactThirdOnsets.contains(resolution.event.position.localTick),
                  resolution.event.origin == .manual,
                  let baseTicks = durationTicks(
                      for: resolution.event.storedInterval,
                      ticksPerWholeNote: ticksPerWholeNote
                  ), let performed = tripletPerformedTicks(baseTicks: baseTicks) else { return false }
            return performed > slot
        }
        if overlapping {
            diagnosticCodes[measure.measureIndex, default: []].insert(.incompleteTuplet)
        }
    }

    func finalizeIndeterminateDurations(
        resolutions: inout [EventResolution],
        diagnosticCodes: inout [Int: Set<RhythmDiagnosticCode>]
    ) {
        for index in resolutions.indices where resolutions[index].tupletID == nil {
            if case .indeterminate(.indeterminateTerminalDuration) = resolutions[index].rhythm.support {
                diagnosticCodes[resolutions[index].event.position.measureIndex, default: []]
                    .insert(.indeterminateTerminalDuration)
            }
        }
    }

    func applyConservativeFallback(
        resolutions: inout [EventResolution],
        tuplets: inout [AnalyzedRhythmTuplet],
        rests: inout [AnalyzedRhythmRest],
        fallbackDiagnosticCodesByMeasure: [Int: Set<RhythmDiagnosticCode>]
    ) {
        let unsupportedMeasures = Set(fallbackDiagnosticCodesByMeasure.keys)
        guard !unsupportedMeasures.isEmpty else { return }
        for index in resolutions.indices {
            let measureIndex = resolutions[index].event.position.measureIndex
            guard unsupportedMeasures.contains(measureIndex) else { continue }
            let code = primaryCode(in: fallbackDiagnosticCodesByMeasure[measureIndex, default: []])
            let fallbackSupport: RhythmSemanticSupport
            switch resolutions[index].rhythm.support {
            case let .indeterminate(indeterminateCode):
                fallbackSupport = .indeterminate(indeterminateCode)
            case .supported, .unsupported:
                fallbackSupport = .unsupported(code)
            }
            resolutions[index].rhythm = NotationRhythm(
                baseInterval: resolutions[index].rhythm.baseInterval,
                support: fallbackSupport
            )
            resolutions[index].tupletID = nil
        }
        tuplets.removeAll { unsupportedMeasures.contains($0.id.measureIndex) }
        rests.removeAll { unsupportedMeasures.contains($0.measureIndex) }
    }

    func measuresWithFallback(
        _ measures: [RhythmMeasure],
        diagnosticCodes: [Int: Set<RhythmDiagnosticCode>]
    ) -> [RhythmMeasure] {
        measures.map { measure in
            let codes = diagnosticCodes[measure.measureIndex, default: []]
            return RhythmMeasure(
                measureIndex: measure.measureIndex,
                startTick: measure.startTick,
                durationTicks: measure.durationTicks,
                timeSignature: measure.timeSignature,
                beatGroups: measure.beatGroups,
                engravingSupport: measure.engravingSupport.applyingRuntimeWarnings(codes)
            )
        }
    }

    func fallbackDiagnosticCodes(
        for measures: [RhythmMeasure],
        diagnosticCodes: [Int: Set<RhythmDiagnosticCode>],
        restrictedTo measureIndexes: Set<Int>? = nil
    ) -> [Int: Set<RhythmDiagnosticCode>] {
        Dictionary(uniqueKeysWithValues: measures.compactMap { measure in
            guard !measure.engravingSupport.permitsEngraving,
                  measureIndexes?.contains(measure.measureIndex) ?? true,
                  let codes = diagnosticCodes[measure.measureIndex],
                  !codes.isEmpty else {
                return nil
            }
            return (measure.measureIndex, codes)
        })
    }

    func postRestState(
        from measures: [RhythmMeasure],
        preRestMeasures: [RhythmMeasure],
        diagnosticCodes: [Int: Set<RhythmDiagnosticCode>]
    ) -> (measures: [RhythmMeasure], newlyNonPermitting: Set<Int>) {
        let measures = measuresWithFallback(measures, diagnosticCodes: diagnosticCodes)
        let preRestMeasuresByIndex = Dictionary(uniqueKeysWithValues: preRestMeasures.map {
            ($0.measureIndex, $0)
        })
        let newlyNonPermitting: Set<Int> = Set(measures.compactMap { measure in
            guard !measure.engravingSupport.permitsEngraving,
                  preRestMeasuresByIndex[measure.measureIndex]?.engravingSupport.permitsEngraving == true else {
                return nil
            }
            return measure.measureIndex
        })
        return (measures, newlyNonPermitting)
    }

    func rhythmWarnings(
        from diagnosticCodes: [Int: Set<RhythmDiagnosticCode>]
    ) -> [RhythmMeasureWarning] {
        diagnosticCodes.keys.sorted().map {
            RhythmMeasureWarning(measureIndex: $0, codes: diagnosticCodes[$0, default: []])
        }
    }
}

private extension NotationRhythmAnalyzer {
    func analyzedNotes(from resolutions: [EventResolution]) -> [AnalyzedRhythmNote] {
        resolutions.map { resolution in
            AnalyzedRhythmNote(
                eventID: resolution.event.eventID,
                position: resolution.event.position,
                voice: resolution.event.voice,
                beatGroupIndex: resolution.beatGroup.groupIndex,
                durationTicks: resolution.durationTicks,
                rhythm: resolution.rhythm,
                tupletID: resolution.tupletID
            )
        }.sorted(by: analyzedNoteComesBefore)
    }

    func analyzedRests(
        from resolutions: [EventResolution],
        measures: [RhythmMeasure],
        reservedTupletRests: [AnalyzedRhythmRest],
        ticksPerWholeNote: Int,
        diagnosticCodes: inout [Int: Set<RhythmDiagnosticCode>]
    ) -> [AnalyzedRhythmRest] {
        let restNotes = resolutions.map { resolution in
            RestTimelineNote(
                position: resolution.event.position,
                voice: resolution.event.voice,
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
            diagnosticCodes[warning.measureIndex, default: []].formUnion(warning.codes)
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
}

private extension NotationRhythmAnalyzer {
    func tripletPerformedDuration(
        for resolution: EventResolution,
        ticksPerWholeNote: Int
    ) -> Int? {
        guard let interval = tripletBaseInterval(
            for: resolution,
            ticksPerWholeNote: ticksPerWholeNote
        ), let baseTicks = durationTicks(for: interval, ticksPerWholeNote: ticksPerWholeNote) else {
            return nil
        }
        return tripletPerformedTicks(baseTicks: baseTicks)
    }

    func tripletBaseInterval(
        for resolution: EventResolution,
        ticksPerWholeNote: Int
    ) -> NoteInterval? {
        if resolution.event.origin == .manual {
            return resolution.event.storedInterval
        }
        if !resolution.hasFollowingDTXOnset {
            return resolution.event.visualDurationCandidate
        }
        return tripletBaseInterval(
            performedTicks: resolution.durationTicks,
            ticksPerWholeNote: ticksPerWholeNote
        )
    }

    func tripletBaseInterval(performedTicks: Int, ticksPerWholeNote: Int) -> NoteInterval? {
        let product = performedTicks.multipliedReportingOverflow(by: 3)
        guard !product.overflow, product.partialValue.isMultiple(of: 2) else { return nil }
        return binaryInterval(for: product.partialValue / 2, ticksPerWholeNote: ticksPerWholeNote)
    }

    func tripletPerformedTicks(baseTicks: Int) -> Int? {
        let product = baseTicks.multipliedReportingOverflow(by: 2)
        guard !product.overflow, product.partialValue.isMultiple(of: 3) else { return nil }
        return product.partialValue / 3
    }

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

    func stableCodes(_ codes: Set<RhythmDiagnosticCode>) -> [RhythmDiagnosticCode] {
        RhythmDiagnosticCode.allCases.filter(codes.contains)
    }

    func primaryCode(in codes: Set<RhythmDiagnosticCode>) -> RhythmDiagnosticCode {
        stableCodes(codes).first ?? .ambiguousBeatGrouping
    }
}

private extension NotationRhythmAnalyzer {
    func streamKeyComesBefore(_ lhs: StreamKey, _ rhs: StreamKey) -> Bool {
        if lhs.measureIndex != rhs.measureIndex { return lhs.measureIndex < rhs.measureIndex }
        if lhs.voice != rhs.voice { return lhs.voice.rawValue < rhs.voice.rawValue }
        return lhs.beatGroupIndex < rhs.beatGroupIndex
    }

    func analyzedNoteComesBefore(_ lhs: AnalyzedRhythmNote, _ rhs: AnalyzedRhythmNote) -> Bool {
        lhs.position.absoluteTick != rhs.position.absoluteTick
            ? lhs.position.absoluteTick < rhs.position.absoluteTick
            : lhs.eventID.rawValue < rhs.eventID.rawValue
    }

    func analyzedRestComesBefore(_ lhs: AnalyzedRhythmRest, _ rhs: AnalyzedRhythmRest) -> Bool {
        if lhs.measureIndex != rhs.measureIndex { return lhs.measureIndex < rhs.measureIndex }
        if lhs.voice != rhs.voice { return lhs.voice == .upper }
        if lhs.startTick != rhs.startTick { return lhs.startTick < rhs.startTick }
        return lhs.durationTicks > rhs.durationTicks
    }

    func analyzedTupletComesBefore(_ lhs: AnalyzedRhythmTuplet, _ rhs: AnalyzedRhythmTuplet) -> Bool {
        if lhs.id.measureIndex != rhs.id.measureIndex { return lhs.id.measureIndex < rhs.id.measureIndex }
        if lhs.id.startTick != rhs.id.startTick { return lhs.id.startTick < rhs.id.startTick }
        if lhs.id.voice != rhs.id.voice { return lhs.id.voice.rawValue < rhs.id.voice.rawValue }
        if lhs.id.stableMemberEventID != rhs.id.stableMemberEventID {
            return lhs.id.stableMemberEventID.rawValue < rhs.id.stableMemberEventID.rawValue
        }
        if lhs.id.beatGroupIndex != rhs.id.beatGroupIndex {
            return lhs.id.beatGroupIndex < rhs.id.beatGroupIndex
        }
        return lhs.id.durationTicks < rhs.id.durationTicks
    }
}
