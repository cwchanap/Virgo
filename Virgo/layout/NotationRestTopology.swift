struct RestTimelineNote: Hashable {
    let timeColumn: NotationTimeColumn
    let voice: NotationVoice
    let durationTicks: Int?
    let rhythm: NotationRhythm?
    let tupletID: RhythmTupletID?

    init(
        timeColumn: NotationTimeColumn,
        voice: NotationVoice,
        durationTicks: Int?
    ) {
        self.timeColumn = timeColumn
        self.voice = voice
        self.durationTicks = durationTicks
        rhythm = nil
        tupletID = nil
    }

    init(
        position: RhythmEventPosition,
        voice: NotationVoice,
        durationTicks: Int?,
        rhythm: NotationRhythm?,
        tupletID: RhythmTupletID?
    ) {
        timeColumn = NotationTimeColumn(
            measureIndex: position.measureIndex,
            tickWithinMeasure: position.localTick,
            absoluteLayoutTick: position.absoluteTick
        )
        self.voice = voice
        self.durationTicks = durationTicks
        self.rhythm = rhythm
        self.tupletID = tupletID
    }
}

/// Rest duration vocabulary.
///
/// The seven printed cases (`fullMeasure` … `sixtyFourth`) form the closed
/// rest vocabulary specified in the implementation plan. `indeterminate` is
/// an internal-only sentinel for hidden spacing spans that do not align to
/// any vocabulary case; it is never paired with `.printed` visibility and
/// is never rendered as a rest symbol.
enum NotationRestDuration: String, CaseIterable, Hashable {
    case fullMeasure
    case half
    case quarter
    case eighth
    case sixteenth
    case thirtySecond
    case sixtyFourth
    case indeterminate

    /// Stable ordering used by rest sort comparators.
    var sortOrder: Int {
        switch self {
        case .fullMeasure: return 0
        case .half: return 1
        case .quarter: return 2
        case .eighth: return 3
        case .sixteenth: return 4
        case .thirtySecond: return 5
        case .sixtyFourth: return 6
        case .indeterminate: return 7
        }
    }
}

enum NotationRestVisibility: String, Hashable {
    case printed
    case hiddenSpacing
    case hiddenDuplicate

    /// Stable ordering used by rest sort comparators.
    var sortOrder: Int {
        switch self {
        case .printed: return 0
        case .hiddenSpacing: return 1
        case .hiddenDuplicate: return 2
        }
    }
}

struct RestTopologyEvent: Hashable {
    let measureIndex: Int
    let voice: NotationVoice
    let startTick: Int
    let durationTicks: Int
    let duration: NotationRestDuration
    let visibility: NotationRestVisibility
    let rhythm: NotationRhythm?
    let tupletID: RhythmTupletID?

    init(
        measureIndex: Int,
        voice: NotationVoice,
        startTick: Int,
        durationTicks: Int,
        duration: NotationRestDuration,
        visibility: NotationRestVisibility,
        rhythm: NotationRhythm? = nil,
        tupletID: RhythmTupletID? = nil
    ) {
        self.measureIndex = measureIndex
        self.voice = voice
        self.startTick = startTick
        self.durationTicks = durationTicks
        self.duration = duration
        self.visibility = visibility
        self.rhythm = rhythm
        self.tupletID = tupletID
    }

    var isPrinted: Bool { visibility == .printed }
}

struct RestTopologyResult: Hashable {
    let events: [RestTopologyEvent]
    let warnings: [RhythmMeasureWarning]
}

struct NotationRestTopologyBuilder {
    private struct GroupKey: Hashable {
        let measureIndex: Int
        let voice: NotationVoice
    }

    private struct OnsetKey: Hashable {
        let measureIndex: Int
        let voice: NotationVoice
        let startTick: Int
    }

    private struct Onset {
        let startTick: Int
        let durationTicks: Int?
    }

    private struct Span {
        let startTick: Int
        let endTick: Int
        let isUncertain: Bool
    }

    private struct MeasureContext {
        let measureIndex: Int
        let ticksPerMeasure: Int
        let timeSignature: TimeSignature
    }

    private struct VoiceContext {
        let measure: MeasureContext
        let voice: NotationVoice
    }

    private let decompositionOrder: [NotationRestDuration] = [
        .half, .quarter, .eighth, .sixteenth, .thirtySecond, .sixtyFourth
    ]

    func noteDurationTicks(
        for interval: NoteInterval,
        ticksPerMeasure: Int,
        timeSignature: TimeSignature
    ) -> Int? {
        let ratio: (numerator: Int, denominator: Int)
        switch interval {
        case .full: ratio = (4, 1)
        case .half: ratio = (2, 1)
        case .quarter: ratio = (1, 1)
        case .eighth: ratio = (1, 2)
        case .sixteenth: ratio = (1, 4)
        case .thirtysecond: ratio = (1, 8)
        case .sixtyfourth: ratio = (1, 16)
        }
        return exactDurationTicks(
            ratio: ratio,
            ticksPerMeasure: ticksPerMeasure,
            timeSignature: timeSignature
        )
    }

    func restDurationTicks(
        for duration: NotationRestDuration,
        ticksPerMeasure: Int,
        timeSignature: TimeSignature
    ) -> Int? {
        let ratio: (numerator: Int, denominator: Int)
        switch duration {
        case .fullMeasure, .indeterminate:
            return nil
        case .half: ratio = (2, 1)
        case .quarter: ratio = (1, 1)
        case .eighth: ratio = (1, 2)
        case .sixteenth: ratio = (1, 4)
        case .thirtySecond: ratio = (1, 8)
        case .sixtyFourth: ratio = (1, 16)
        }
        return exactDurationTicks(
            ratio: ratio,
            ticksPerMeasure: ticksPerMeasure,
            timeSignature: timeSignature
        )
    }

    func build(
        notes: [RestTimelineNote],
        totalMeasureCount: Int,
        ticksPerMeasure: Int,
        timeSignature: TimeSignature
    ) -> [RestTopologyEvent] {
        guard totalMeasureCount > 0, ticksPerMeasure > 0 else { return [] }

        let groupedOnsets = normalizeAndGroup(
            notes: notes,
            totalMeasureCount: totalMeasureCount,
            ticksPerMeasure: ticksPerMeasure
        )
        var events: [RestTopologyEvent] = []

        for measureIndex in 0..<totalMeasureCount {
            let upper = groupedOnsets[GroupKey(measureIndex: measureIndex, voice: .upper), default: []]
            let lower = groupedOnsets[GroupKey(measureIndex: measureIndex, voice: .lower), default: []]
            let context = MeasureContext(
                measureIndex: measureIndex,
                ticksPerMeasure: ticksPerMeasure,
                timeSignature: timeSignature
            )
            appendMeasureEvents(
                context: context,
                upperOnsets: upper,
                lowerOnsets: lower,
                events: &events
            )
        }

        return events.sorted(by: eventComesBefore)
    }

    private func exactDurationTicks(
        ratio: (numerator: Int, denominator: Int),
        ticksPerMeasure: Int,
        timeSignature: TimeSignature
    ) -> Int? {
        guard ticksPerMeasure > 0, timeSignature.noteValue == 4 else { return nil }
        let divisor = timeSignature.beatsPerMeasure * ratio.denominator
        let (product, overflow) = ticksPerMeasure.multipliedReportingOverflow(by: ratio.numerator)
        guard !overflow, divisor > 0, product.isMultiple(of: divisor) else { return nil }
        return product / divisor
    }
}

private extension NotationRestTopologyBuilder {
    private func normalizeAndGroup(
        notes: [RestTimelineNote],
        totalMeasureCount: Int,
        ticksPerMeasure: Int
    ) -> [GroupKey: [Onset]] {
        var chordMembers: [OnsetKey: [Int?]] = [:]
        for note in notes {
            let measure = note.timeColumn.measureIndex
            let tick = note.timeColumn.tickWithinMeasure
            guard (0..<totalMeasureCount).contains(measure), (0..<ticksPerMeasure).contains(tick) else {
                continue
            }
            let key = OnsetKey(measureIndex: measure, voice: note.voice, startTick: tick)
            chordMembers[key, default: []].append(note.durationTicks)
        }

        var result: [GroupKey: [Onset]] = [:]
        for (key, durations) in chordMembers {
            let duration = durations.contains(where: { $0 == nil })
                ? nil
                : durations.compactMap { $0 }.max()
            let group = GroupKey(measureIndex: key.measureIndex, voice: key.voice)
            result[group, default: []].append(Onset(startTick: key.startTick, durationTicks: duration))
        }
        for key in result.keys {
            result[key]?.sort { $0.startTick < $1.startTick }
        }
        return result
    }

    private func appendMeasureEvents(
        context: MeasureContext,
        upperOnsets: [Onset],
        lowerOnsets: [Onset],
        events: inout [RestTopologyEvent]
    ) {
        if upperOnsets.isEmpty {
            events.append(fullMeasureEvent(
                context: context,
                voice: .upper,
                visibility: .printed
            ))
        }
        if lowerOnsets.isEmpty {
            events.append(fullMeasureEvent(
                context: context,
                voice: .lower,
                visibility: upperOnsets.isEmpty ? .hiddenDuplicate : .printed
            ))
        }
        if !upperOnsets.isEmpty {
            appendActiveVoiceEvents(
                context: VoiceContext(measure: context, voice: .upper),
                onsets: upperOnsets,
                events: &events
            )
        }
        if !lowerOnsets.isEmpty {
            appendActiveVoiceEvents(
                context: VoiceContext(measure: context, voice: .lower),
                onsets: lowerOnsets,
                events: &events
            )
        }
    }

    private func fullMeasureEvent(
        context: MeasureContext,
        voice: NotationVoice,
        visibility: NotationRestVisibility
    ) -> RestTopologyEvent {
        RestTopologyEvent(
            measureIndex: context.measureIndex,
            voice: voice,
            startTick: 0,
            durationTicks: context.ticksPerMeasure,
            duration: .fullMeasure,
            visibility: visibility
        )
    }

    private func appendActiveVoiceEvents(
        context: VoiceContext,
        onsets: [Onset],
        events: inout [RestTopologyEvent]
    ) {
        let measure = context.measure
        let spans = clippedSpans(onsets: onsets, measureEnd: measure.ticksPerMeasure)
        let uncertainSpans = spans.filter(\.isUncertain)
        for span in uncertainSpans {
            events.append(hiddenEvent(
                context: context,
                span: span,
                timeSignature: measure.timeSignature
            ))
        }

        let occupiedSpans = mergeSpans(spans)
        var cursor = 0
        for span in occupiedSpans {
            appendGap(
                context: context,
                startTick: cursor,
                endTick: span.startTick,
                events: &events
            )
            cursor = max(cursor, span.endTick)
        }
        appendGap(
            context: context,
            startTick: cursor,
            endTick: measure.ticksPerMeasure,
            events: &events
        )
    }
}

private extension NotationRestTopologyBuilder {
    private func clippedSpans(onsets: [Onset], measureEnd: Int) -> [Span] {
        onsets.indices.compactMap { index in
            let onset = onsets[index]
            let nextOnset = index + 1 < onsets.count ? onsets[index + 1].startTick : measureEnd
            let endTick: Int
            if let duration = onset.durationTicks {
                endTick = onset.startTick + min(max(duration, 0), nextOnset - onset.startTick)
            } else {
                endTick = nextOnset
            }
            guard endTick > onset.startTick else { return nil }
            return Span(
                startTick: onset.startTick,
                endTick: endTick,
                isUncertain: onset.durationTicks == nil
            )
        }
    }

    private func mergeSpans(_ spans: [Span]) -> [Span] {
        let sorted = spans.sorted {
            $0.startTick == $1.startTick
                ? $0.endTick < $1.endTick
                : $0.startTick < $1.startTick
        }
        var merged: [Span] = []
        for span in sorted {
            guard let last = merged.last, span.startTick <= last.endTick else {
                merged.append(span)
                continue
            }
            merged[merged.count - 1] = Span(
                startTick: last.startTick,
                endTick: max(last.endTick, span.endTick),
                isUncertain: last.isUncertain || span.isUncertain
            )
        }
        return merged
    }

    private func appendGap(
        context: VoiceContext,
        startTick: Int,
        endTick: Int,
        events: inout [RestTopologyEvent]
    ) {
        guard startTick < endTick else { return }
        let measure = context.measure
        if measure.timeSignature.noteValue == 8 {
            events.append(hiddenEvent(
                context: context,
                span: Span(startTick: startTick, endTick: endTick, isUncertain: false),
                timeSignature: measure.timeSignature
            ))
            return
        }

        var cursor = startTick
        while cursor < endTick {
            var candidateTicks: Int?
            let candidate = decompositionOrder.first { duration in
                guard let ticks = restDurationTicks(
                    for: duration,
                    ticksPerMeasure: measure.ticksPerMeasure,
                    timeSignature: measure.timeSignature
                ) else { return false }
                guard ticks > 0, ticks <= endTick - cursor, cursor.isMultiple(of: ticks) else { return false }
                candidateTicks = ticks
                return true
            }
            guard let candidate, let ticks = candidateTicks else {
                events.append(RestTopologyEvent(
                    measureIndex: measure.measureIndex,
                    voice: context.voice,
                    startTick: cursor,
                    durationTicks: endTick - cursor,
                    duration: .indeterminate,
                    visibility: .hiddenSpacing
                ))
                break
            }

            events.append(RestTopologyEvent(
                measureIndex: measure.measureIndex,
                voice: context.voice,
                startTick: cursor,
                durationTicks: ticks,
                duration: candidate,
                visibility: .printed
            ))
            cursor += ticks
        }
    }

    private func hiddenEvent(
        context: VoiceContext,
        span: Span,
        timeSignature: TimeSignature
    ) -> RestTopologyEvent {
        let measure = context.measure
        let ticks = span.endTick - span.startTick
        let exactDuration = decompositionOrder.first {
            restDurationTicks(
                for: $0,
                ticksPerMeasure: measure.ticksPerMeasure,
                timeSignature: timeSignature
            ) == ticks
        }
        return RestTopologyEvent(
            measureIndex: measure.measureIndex,
            voice: context.voice,
            startTick: span.startTick,
            durationTicks: ticks,
            duration: exactDuration ?? .indeterminate,
            visibility: .hiddenSpacing
        )
    }

    private func eventComesBefore(_ lhs: RestTopologyEvent, _ rhs: RestTopologyEvent) -> Bool {
        if lhs.measureIndex != rhs.measureIndex { return lhs.measureIndex < rhs.measureIndex }
        let lhsVoice = lhs.voice == .upper ? 0 : 1
        let rhsVoice = rhs.voice == .upper ? 0 : 1
        if lhsVoice != rhsVoice { return lhsVoice < rhsVoice }
        if lhs.startTick != rhs.startTick { return lhs.startTick < rhs.startTick }
        if lhs.duration.sortOrder != rhs.duration.sortOrder {
            return lhs.duration.sortOrder < rhs.duration.sortOrder
        }
        return lhs.visibility.sortOrder < rhs.visibility.sortOrder
    }
}

extension NotationRestTopologyBuilder {
    struct ExactSpan {
        let start: Int
        let end: Int
        let isIndeterminate: Bool
    }

    struct RestToken {
        let ticks: Int
        let baseTicks: Int
        let rhythm: NotationRhythm
        let legacyDuration: NotationRestDuration
    }

    struct RestPath {
        let tokens: [RestToken]
    }

    /// Timeline-native rest synthesis. Tuplet slots are reserved before the
    /// bounded binary/dotted solver and every complement is scoped to one
    /// resolved beat group.
    func buildExact(
        notes: [RestTimelineNote],
        measures: [RhythmMeasure],
        reservedTupletRests: [AnalyzedRhythmRest],
        ticksPerWholeNote: Int
    ) -> RestTopologyResult {
        guard ticksPerWholeNote > 0,
              !measures.isEmpty,
              Set(measures.map(\.measureIndex)).count == measures.count else {
            return RestTopologyResult(events: [], warnings: [])
        }
        var events: [RestTopologyEvent] = []
        var warnings: [Int: Set<RhythmDiagnosticCode>] = [:]

        for measure in measures.sorted(by: { $0.measureIndex < $1.measureIndex }) {
            guard measure.durationTicks > 0, validGroups(in: measure) else {
                warnings[measure.measureIndex, default: []].insert(.ambiguousBeatGrouping)
                continue
            }
            let measureNotes = notes.filter {
                $0.timeColumn.measureIndex == measure.measureIndex
                    && (0..<measure.durationTicks).contains($0.timeColumn.tickWithinMeasure)
            }
            let hasUpper = measureNotes.contains { $0.voice == .upper }
            let hasLower = measureNotes.contains { $0.voice == .lower }
            if !hasUpper {
                events.append(exactFullMeasureEvent(
                    measure: measure,
                    voice: .upper,
                    visibility: .printed
                ))
            }
            if !hasLower {
                events.append(exactFullMeasureEvent(
                    measure: measure,
                    voice: .lower,
                    visibility: hasUpper ? .printed : .hiddenDuplicate
                ))
            }
            for voice in [NotationVoice.upper, .lower] where measureNotes.contains(where: { $0.voice == voice }) {
                appendExactVoice(
                    voice: voice,
                    notes: measureNotes.filter { $0.voice == voice },
                    measure: measure,
                    reservedTupletRests: reservedTupletRests.filter {
                        $0.measureIndex == measure.measureIndex && $0.voice == voice
                    },
                    ticksPerWholeNote: ticksPerWholeNote,
                    events: &events,
                    warnings: &warnings
                )
            }
        }

        return RestTopologyResult(
            events: events.sorted(by: eventComesBefore),
            warnings: warnings.keys.sorted().map {
                RhythmMeasureWarning(measureIndex: $0, codes: warnings[$0, default: []])
            }
        )
    }

    private func appendExactVoice(
        voice: NotationVoice,
        notes: [RestTimelineNote],
        measure: RhythmMeasure,
        reservedTupletRests: [AnalyzedRhythmRest],
        ticksPerWholeNote: Int,
        events: inout [RestTopologyEvent],
        warnings: inout [Int: Set<RhythmDiagnosticCode>]
    ) {
        let spans = exactSpans(notes: notes, measureEnd: measure.durationTicks)
        for span in spans where span.isIndeterminate {
            events.append(RestTopologyEvent(
                measureIndex: measure.measureIndex,
                voice: voice,
                startTick: span.start,
                durationTicks: span.end - span.start,
                duration: .indeterminate,
                visibility: .hiddenSpacing,
                rhythm: NotationRhythm(
                    baseInterval: .quarter,
                    support: .indeterminate(.indeterminateTerminalDuration)
                )
            ))
        }
        let occupied = mergedExactSpans(spans)
        let reservedEvents = reservedTupletRests.map {
            RestTopologyEvent(
                measureIndex: $0.measureIndex,
                voice: $0.voice,
                startTick: $0.startTick,
                durationTicks: $0.durationTicks,
                duration: legacyDuration(for: $0.rhythm.baseInterval),
                visibility: $0.visibility,
                rhythm: $0.rhythm,
                tupletID: $0.tupletID
            )
        }
        events.append(contentsOf: reservedEvents)

        for group in measure.beatGroups {
            let blockers = occupied.map { $0.start..<$0.end }
                + reservedEvents.map { $0.startTick..<($0.startTick + $0.durationTicks) }
            let clipped = blockers.compactMap { range -> Range<Int>? in
                let lower = max(range.lowerBound, group.startTick)
                let upper = min(range.upperBound, group.endTick)
                return lower < upper ? lower..<upper : nil
            }.sorted { $0.lowerBound < $1.lowerBound }
            var cursor = group.startTick
            for range in clipped {
                appendExactGap(
                    start: cursor,
                    end: range.lowerBound,
                    group: group,
                    measure: measure,
                    voice: voice,
                    ticksPerWholeNote: ticksPerWholeNote,
                    events: &events,
                    warnings: &warnings
                )
                cursor = max(cursor, range.upperBound)
            }
            appendExactGap(
                start: cursor,
                end: group.endTick,
                group: group,
                measure: measure,
                voice: voice,
                ticksPerWholeNote: ticksPerWholeNote,
                events: &events,
                warnings: &warnings
            )
        }
    }

    private func appendExactGap(
        start: Int,
        end: Int,
        group: RhythmBeatGroup,
        measure: RhythmMeasure,
        voice: NotationVoice,
        ticksPerWholeNote: Int,
        events: inout [RestTopologyEvent],
        warnings: inout [Int: Set<RhythmDiagnosticCode>]
    ) {
        guard start < end else { return }
        guard case .supported = measure.engravingSupport,
              let path = solveRestPath(
                start: start,
                end: end,
                group: group,
                ticksPerWholeNote: ticksPerWholeNote
              ) else {
            events.append(RestTopologyEvent(
                measureIndex: measure.measureIndex,
                voice: voice,
                startTick: start,
                durationTicks: end - start,
                duration: .indeterminate,
                visibility: .hiddenSpacing,
                rhythm: NotationRhythm(
                    baseInterval: .quarter,
                    support: .unsupported(.ambiguousBeatGrouping)
                )
            ))
            warnings[measure.measureIndex, default: []].insert(.ambiguousBeatGrouping)
            return
        }
        var cursor = start
        for token in path.tokens {
            events.append(RestTopologyEvent(
                measureIndex: measure.measureIndex,
                voice: voice,
                startTick: cursor,
                durationTicks: token.ticks,
                duration: token.legacyDuration,
                visibility: .printed,
                rhythm: token.rhythm
            ))
            cursor += token.ticks
        }
    }
}

private extension NotationRestTopologyBuilder {
    func solveRestPath(
        start: Int,
        end: Int,
        group: RhythmBeatGroup,
        ticksPerWholeNote: Int
    ) -> RestPath? {
        let tokens = exactTokens(ticksPerWholeNote: ticksPerWholeNote)
        var best: [Int: RestPath] = [end: RestPath(tokens: [])]
        guard start >= group.startTick,
              end <= group.endTick,
              end - start <= RhythmLimits.maximumMaterializedRhythmUnitCount else { return nil }
        for cursor in stride(from: end - 1, through: start, by: -1) {
            for token in tokens where cursor + token.ticks <= end {
                let relativeStart = cursor - group.startTick
                guard relativeStart.isMultiple(of: token.baseTicks),
                      let suffix = best[cursor + token.ticks] else { continue }
                let candidate = RestPath(tokens: [token] + suffix.tokens)
                if let current = best[cursor] {
                    if restPath(candidate, isBetterThan: current) { best[cursor] = candidate }
                } else {
                    best[cursor] = candidate
                }
            }
        }
        return best[start]
    }

    func exactTokens(ticksPerWholeNote: Int) -> [RestToken] {
        let intervals: [(NoteInterval, Int)] = [
            (.full, 1), (.half, 2), (.quarter, 4), (.eighth, 8),
            (.sixteenth, 16), (.thirtysecond, 32), (.sixtyfourth, 64)
        ]
        return intervals.flatMap { interval, divisor -> [RestToken] in
            guard ticksPerWholeNote.isMultiple(of: divisor) else { return [] }
            let base = ticksPerWholeNote / divisor
            var result = [RestToken(
                ticks: base,
                baseTicks: base,
                rhythm: NotationRhythm(baseInterval: interval),
                legacyDuration: legacyDuration(for: interval)
            )]
            let dotted = base.multipliedReportingOverflow(by: 3)
            if !dotted.overflow, dotted.partialValue.isMultiple(of: 2) {
                result.append(RestToken(
                    ticks: dotted.partialValue / 2,
                    baseTicks: base,
                    rhythm: NotationRhythm(baseInterval: interval, dotCount: 1),
                    legacyDuration: legacyDuration(for: interval)
                ))
            }
            return result
        }.sorted {
            $0.ticks != $1.ticks ? $0.ticks > $1.ticks : $0.rhythm.dotCount < $1.rhythm.dotCount
        }
    }

    func restPath(_ lhs: RestPath, isBetterThan rhs: RestPath) -> Bool {
        if lhs.tokens.count != rhs.tokens.count { return lhs.tokens.count < rhs.tokens.count }
        let leftDurations = lhs.tokens.map(\.ticks).sorted(by: >)
        let rightDurations = rhs.tokens.map(\.ticks).sorted(by: >)
        if leftDurations != rightDurations {
            return leftDurations.lexicographicallyPrecedes(rightDurations, by: >)
        }
        return lhs.tokens.reduce(0) { $0 + $1.rhythm.dotCount }
            < rhs.tokens.reduce(0) { $0 + $1.rhythm.dotCount }
    }

    func exactSpans(notes: [RestTimelineNote], measureEnd: Int) -> [ExactSpan] {
        let byOnset = Dictionary(grouping: notes, by: { $0.timeColumn.tickWithinMeasure })
        return byOnset.keys.sorted().compactMap { start in
            let members = byOnset[start, default: []]
            let isIndeterminate = members.contains {
                $0.durationTicks == nil || $0.rhythm?.support != .supported
            }
            let next = byOnset.keys.filter { $0 > start }.min() ?? measureEnd
            let duration = isIndeterminate
                ? next - start
                : members.compactMap(\.durationTicks).max() ?? 0
            guard duration > 0 else { return nil }
            let candidateEnd = start.addingReportingOverflow(duration)
            guard !candidateEnd.overflow else { return nil }
            return ExactSpan(
                start: start,
                end: min(candidateEnd.partialValue, measureEnd),
                isIndeterminate: isIndeterminate
            )
        }
    }

    func mergedExactSpans(_ spans: [ExactSpan]) -> [ExactSpan] {
        var result: [ExactSpan] = []
        for span in spans.sorted(by: { $0.start < $1.start }) {
            guard let last = result.last, span.start <= last.end else {
                result.append(span)
                continue
            }
            result[result.count - 1] = ExactSpan(
                start: last.start,
                end: max(last.end, span.end),
                isIndeterminate: last.isIndeterminate || span.isIndeterminate
            )
        }
        return result
    }

    func exactFullMeasureEvent(
        measure: RhythmMeasure,
        voice: NotationVoice,
        visibility: NotationRestVisibility
    ) -> RestTopologyEvent {
        RestTopologyEvent(
            measureIndex: measure.measureIndex,
            voice: voice,
            startTick: 0,
            durationTicks: measure.durationTicks,
            duration: .fullMeasure,
            visibility: visibility,
            rhythm: NotationRhythm(baseInterval: .full)
        )
    }

    func legacyDuration(for interval: NoteInterval) -> NotationRestDuration {
        switch interval {
        case .full: return .fullMeasure
        case .half: return .half
        case .quarter: return .quarter
        case .eighth: return .eighth
        case .sixteenth: return .sixteenth
        case .thirtysecond: return .thirtySecond
        case .sixtyfourth: return .sixtyFourth
        }
    }

    func validGroups(in measure: RhythmMeasure) -> Bool {
        guard !measure.beatGroups.isEmpty else { return false }
        var cursor = 0
        for group in measure.beatGroups {
            guard group.durationTicks > 0,
                  group.startTick == cursor,
                  group.endTick <= measure.durationTicks else { return false }
            cursor = group.endTick
        }
        return cursor == measure.durationTicks
    }
}
