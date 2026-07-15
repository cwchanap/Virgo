struct RestTimelineNote: Hashable {
    let timeColumn: NotationTimeColumn
    let voice: NotationVoice
    let durationTicks: Int?
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
}

enum NotationRestVisibility: String, Hashable {
    case printed
    case hiddenSpacing
    case hiddenDuplicate
}

struct RestTopologyEvent: Hashable {
    let measureIndex: Int
    let voice: NotationVoice
    let startTick: Int
    let durationTicks: Int
    let duration: NotationRestDuration
    let visibility: NotationRestVisibility

    var isPrinted: Bool { visibility == .printed }
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
        let lhsDuration = durationOrder(lhs.duration)
        let rhsDuration = durationOrder(rhs.duration)
        if lhsDuration != rhsDuration { return lhsDuration < rhsDuration }
        return visibilityOrder(lhs.visibility) < visibilityOrder(rhs.visibility)
    }

    private func durationOrder(_ duration: NotationRestDuration) -> Int {
        switch duration {
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

    private func visibilityOrder(_ visibility: NotationRestVisibility) -> Int {
        switch visibility {
        case .printed: return 0
        case .hiddenSpacing: return 1
        case .hiddenDuplicate: return 2
        }
    }
}
