struct NotationRhythmAnalyzer: Sendable {
    struct StreamKey: Hashable {
        let measureIndex: Int
        let voice: NotationVoice
        let beatGroupIndex: Int
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
        var warningCodes = metadataWarningCodes(measures: measures)
        let streams = groupedStreams(
            events: validEvents,
            measuresByIndex: measuresByIndex,
            warningCodes: &warningCodes
        )
        var resolutions: [EventResolution] = []
        var tuplets: [AnalyzedRhythmTuplet] = []
        var reservedTupletRests: [AnalyzedRhythmRest] = []

        for key in streams.keys.sorted(by: streamKeyComesBefore) {
            guard let measure = measuresByIndex[key.measureIndex] else { continue }
            var streamResolutions = resolveStream(
                streams[key, default: []],
                measure: measure,
                ticksPerWholeNote: ticksPerWholeNote
            )
            if case .supported = measure.engravingSupport {
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
                    warningCodes: &warningCodes
                )
            }
            finalizeIndeterminateDurations(
                resolutions: &streamResolutions,
                warningCodes: &warningCodes
            )
            resolutions.append(contentsOf: streamResolutions)
        }

        applyConservativeFallback(
            resolutions: &resolutions,
            tuplets: &tuplets,
            rests: &reservedTupletRests,
            warningCodes: warningCodes
        )
        var notes = analyzedNotes(from: resolutions)
        var effectiveMeasures = measuresWithFallback(measures, warningCodes: warningCodes)
        var restsOutput = analyzedRests(
            from: resolutions,
            measures: effectiveMeasures,
            reservedTupletRests: reservedTupletRests,
            ticksPerWholeNote: ticksPerWholeNote,
            warningCodes: &warningCodes
        )

        let newlyUnsupported = Set(warningCodes.keys).subtracting(
            Set(effectiveMeasures.compactMap { measure in
                if case .unsupported = measure.engravingSupport { return measure.measureIndex }
                return nil
            })
        )
        if !newlyUnsupported.isEmpty {
            applyConservativeFallback(
                resolutions: &resolutions,
                tuplets: &tuplets,
                rests: &reservedTupletRests,
                warningCodes: warningCodes
            )
            notes = analyzedNotes(from: resolutions)
            effectiveMeasures = measuresWithFallback(measures, warningCodes: warningCodes)
            restsOutput = analyzedRests(
                from: resolutions,
                measures: effectiveMeasures,
                reservedTupletRests: reservedTupletRests,
                ticksPerWholeNote: ticksPerWholeNote,
                warningCodes: &warningCodes
            )
        }

        let warnings = warningCodes.keys.sorted().map {
            RhythmMeasureWarning(measureIndex: $0, codes: warningCodes[$0, default: []])
        }
        return NotationRhythmAnalysis(
            notes: notes,
            rests: restsOutput.sorted(by: analyzedRestComesBefore),
            tuplets: tuplets.sorted(by: analyzedTupletComesBefore),
            warnings: warnings
        )
    }
}

private extension NotationRhythmAnalyzer {
    func metadataWarningCodes(measures: [RhythmMeasure]) -> [Int: Set<RhythmDiagnosticCode>] {
        var result: [Int: Set<RhythmDiagnosticCode>] = [:]
        for measure in measures {
            if case let .unsupported(codes) = measure.engravingSupport {
                result[measure.measureIndex, default: []].formUnion(codes)
            }
        }
        return result
    }

    func groupedStreams(
        events: [RhythmAnalysisEvent],
        measuresByIndex: [Int: RhythmMeasure],
        warningCodes: inout [Int: Set<RhythmDiagnosticCode>]
    ) -> [StreamKey: [LocatedEvent]] {
        var streams: [StreamKey: [LocatedEvent]] = [:]
        for event in events {
            guard let measure = measuresByIndex[event.position.measureIndex],
                  let group = measure.beatGroups.first(where: {
                      event.position.localTick >= $0.startTick && event.position.localTick < $0.endTick
                  }) else {
                warningCodes[event.position.measureIndex, default: []].insert(.ambiguousBeatGrouping)
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

    func resolveStream(
        _ locatedEvents: [LocatedEvent],
        measure: RhythmMeasure,
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
                ticksPerWholeNote: ticksPerWholeNote
            )
        }
    }

    func terminalDTXResolution(
        event: RhythmAnalysisEvent,
        beatGroup: RhythmBeatGroup,
        measure: RhythmMeasure,
        ticksPerWholeNote: Int
    ) -> EventResolution {
        let boundary = min(beatGroup.endTick, measure.durationTicks)
        if let interval = event.visualDurationCandidate,
           let duration = durationTicks(for: interval, ticksPerWholeNote: ticksPerWholeNote),
           event.position.localTick + duration <= boundary {
            return EventResolution(
                event: event,
                beatGroup: beatGroup,
                hasFollowingDTXOnset: false,
                durationTicks: duration,
                rhythm: NotationRhythm(baseInterval: interval),
                tupletID: nil
            )
        }
        if let interval = event.visualDurationCandidate,
           let baseDuration = durationTicks(for: interval, ticksPerWholeNote: ticksPerWholeNote),
           let compressedDuration = tripletPerformedTicks(baseTicks: baseDuration),
           event.position.localTick + compressedDuration <= boundary {
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
            durationTicks: max(boundary - event.position.localTick, 1),
            rhythm: NotationRhythm(
                baseInterval: event.visualDurationCandidate ?? event.storedInterval,
                support: .indeterminate(.indeterminateTerminalDuration)
            ),
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
        warningCodes: inout [Int: Set<RhythmDiagnosticCode>]
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
            warningCodes[measure.measureIndex, default: []].insert(.unsupportedTupletRatio)
        } else if unsupportedSpan {
            warningCodes[measure.measureIndex, default: []].insert(.incompleteTuplet)
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
                      ticksPerWholeNote: measure.durationTicks * 4 / max(measure.timeSignature.beatsPerMeasure, 1)
                  ), let performed = tripletPerformedTicks(baseTicks: baseTicks) else { return false }
            return performed > slot
        }
        if overlapping {
            warningCodes[measure.measureIndex, default: []].insert(.incompleteTuplet)
        }
    }

    func finalizeIndeterminateDurations(
        resolutions: inout [EventResolution],
        warningCodes: inout [Int: Set<RhythmDiagnosticCode>]
    ) {
        for index in resolutions.indices where resolutions[index].tupletID == nil {
            if case .indeterminate(.indeterminateTerminalDuration) = resolutions[index].rhythm.support {
                warningCodes[resolutions[index].event.position.measureIndex, default: []]
                    .insert(.indeterminateTerminalDuration)
            }
        }
    }

    func applyConservativeFallback(
        resolutions: inout [EventResolution],
        tuplets: inout [AnalyzedRhythmTuplet],
        rests: inout [AnalyzedRhythmRest],
        warningCodes: [Int: Set<RhythmDiagnosticCode>]
    ) {
        let unsupportedMeasures = Set(warningCodes.keys)
        guard !unsupportedMeasures.isEmpty else { return }
        for index in resolutions.indices {
            let measureIndex = resolutions[index].event.position.measureIndex
            guard unsupportedMeasures.contains(measureIndex) else { continue }
            let code = primaryCode(in: warningCodes[measureIndex, default: []])
            resolutions[index].rhythm = NotationRhythm(
                baseInterval: resolutions[index].rhythm.baseInterval,
                support: .unsupported(code)
            )
            resolutions[index].tupletID = nil
        }
        tuplets.removeAll { unsupportedMeasures.contains($0.id.measureIndex) }
        rests.removeAll { unsupportedMeasures.contains($0.measureIndex) }
    }

    func measuresWithFallback(
        _ measures: [RhythmMeasure],
        warningCodes: [Int: Set<RhythmDiagnosticCode>]
    ) -> [RhythmMeasure] {
        measures.map { measure in
            guard let codes = warningCodes[measure.measureIndex], !codes.isEmpty else { return measure }
            return RhythmMeasure(
                measureIndex: measure.measureIndex,
                startTick: measure.startTick,
                durationTicks: measure.durationTicks,
                timeSignature: measure.timeSignature,
                beatGroups: measure.beatGroups,
                engravingSupport: .unsupported(stableCodes(codes))
            )
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
        warningCodes: inout [Int: Set<RhythmDiagnosticCode>]
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
