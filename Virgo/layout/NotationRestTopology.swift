/// One notation time column: the measure, its local tick, and the absolute
/// tick on the layout timeline.
struct NotationTimeColumn: Hashable, Sendable {
    let measureIndex: Int
    let tickWithinMeasure: Int
    let absoluteLayoutTick: Int
}

struct RestTimelineNote: Hashable {
    let timeColumn: NotationTimeColumn
    let voice: NotationVoice
    let durationTicks: Int?
    let rhythm: NotationRhythm?
    let tupletID: RhythmTupletID?

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

struct NotationRestTopologyBuilder {}

private extension NotationRestTopologyBuilder {
    func eventComesBefore(_ lhs: RestTopologyEvent, _ rhs: RestTopologyEvent) -> Bool {
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

    struct ExactGapContext {
        let group: RhythmBeatGroup
        let measure: RhythmMeasure
        let voice: NotationVoice
        let ticksPerWholeNote: Int
        let terminalIndeterminateStarts: Set<Int>
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
        let terminalIndeterminateStarts = Set(spans.compactMap { span in
            span.isIndeterminate && span.end == measure.durationTicks ? span.start : nil
        })
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
            let groupGapContext = ExactGapContext(
                group: group,
                measure: measure,
                voice: voice,
                ticksPerWholeNote: ticksPerWholeNote,
                terminalIndeterminateStarts: terminalIndeterminateStarts
            )
            for range in clipped {
                appendExactGap(
                    start: cursor,
                    end: range.lowerBound,
                    context: groupGapContext,
                    events: &events,
                    warnings: &warnings
                )
                cursor = max(cursor, range.upperBound)
            }
            appendExactGap(
                start: cursor,
                end: group.endTick,
                context: groupGapContext,
                events: &events,
                warnings: &warnings
            )
        }
    }

    private func appendExactGap(
        start: Int,
        end: Int,
        context: ExactGapContext,
        events: inout [RestTopologyEvent],
        warnings: inout [Int: Set<RhythmDiagnosticCode>]
    ) {
        guard start < end else { return }
        guard !context.terminalIndeterminateStarts.contains(start),
              !context.terminalIndeterminateStarts.contains(end) else {
            events.append(RestTopologyEvent(
                measureIndex: context.measure.measureIndex,
                voice: context.voice,
                startTick: start,
                durationTicks: end - start,
                duration: .indeterminate,
                visibility: .hiddenSpacing,
                rhythm: NotationRhythm(
                    baseInterval: .quarter,
                    support: .indeterminate(.indeterminateTerminalDuration)
                )
            ))
            return
        }
        guard context.measure.engravingSupport.permitsEngraving,
              let path = solveRestPath(
                start: start,
                end: end,
                group: context.group,
                ticksPerWholeNote: context.ticksPerWholeNote
              ) else {
            events.append(RestTopologyEvent(
                measureIndex: context.measure.measureIndex,
                voice: context.voice,
                startTick: start,
                durationTicks: end - start,
                duration: .indeterminate,
                visibility: .hiddenSpacing,
                rhythm: NotationRhythm(
                    baseInterval: .quarter,
                    support: .unsupported(.ambiguousBeatGrouping)
                )
            ))
            warnings[context.measure.measureIndex, default: []].insert(.ambiguousBeatGrouping)
            return
        }
        var cursor = start
        for token in path.tokens {
            events.append(RestTopologyEvent(
                measureIndex: context.measure.measureIndex,
                voice: context.voice,
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
