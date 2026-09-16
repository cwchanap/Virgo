import CoreGraphics

extension NotationLayoutEngine {
    /// Builds rests from snapshot rests. Each printed rest takes its own
    /// visual X from the package output (`visualXByRestID`, which includes
    /// the centered full-measure position the formatter finalized); hidden
    /// spacing/double rests never paint, so they anchor deterministically at
    /// the formatted logical column (or the measure's leading inset) without
    /// reserving ink.
    func buildRests(
        rests: [RhythmLayoutRest],
        measures: [RenderedMeasure],
        visualXByRestID: [Int: CGFloat],
        columnXByKey: [MeasureTickKey: CGFloat],
        style: NotationLayoutStyle
    ) -> [RenderedRest] {
        let measuresByIndex = Dictionary(uniqueKeysWithValues: measures.map { ($0.measureIndex, $0) })
        let candidates = rests.compactMap { rest -> (RhythmLayoutRest, RenderedMeasure)? in
            guard let measure = measuresByIndex[rest.position.measureIndex],
                  rest.position.localTick >= 0,
                  rest.position.localTick < measure.durationTicks,
                  rest.position.absoluteTick == measure.startTick + rest.position.localTick,
                  rest.durationTicks > 0,
                  rest.position.localTick + rest.durationTicks <= measure.durationTicks else {
                return nil
            }
            return (rest, measure)
        }.sorted {
            if $0.0.position.absoluteTick != $1.0.position.absoluteTick {
                return $0.0.position.absoluteTick < $1.0.position.absoluteTick
            }
            if $0.0.voice != $1.0.voice { return $0.0.voice == .upper }
            return $0.0.durationTicks > $1.0.durationTicks
        }
        var duplicateCounts: [String: Int] = [:]
        // The projection assigns each printed rest a `ResolvedRest.id` equal
        // to its ordinal in this same sorted candidate order, so a printed
        // rest's rank among the printed candidates here is its package ID.
        var printedOrdinal = 0
        return candidates.map { rest, measure in
            let duration = legacyRestDuration(
                rhythm: rest.rhythm,
                fillsMeasure: rest.position.localTick == 0
                    && rest.durationTicks == measure.durationTicks
            )
            let baseID = "rest-m\(rest.position.measureIndex)-v\(rest.voice.rawValue)"
                + "-t\(rest.position.localTick)-n\(rest.durationTicks)"
                + "-d\(duration.rawValue)-x\(rest.visibility.rawValue)"
            let ordinal = duplicateCounts[baseID, default: 0]
            duplicateCounts[baseID] = ordinal + 1
            let x: CGFloat
            if rest.visibility == .printed {
                let resolvedRestID = printedOrdinal
                printedOrdinal += 1
                if let visualX = visualXByRestID[resolvedRestID] {
                    x = visualX
                } else {
                    // Drift guard (HPA-164): the adapter projects exactly
                    // these printed rests, so a printed rest without a
                    // package entry means the projection guards drifted.
                    // Keep it deterministic.
                    assertionFailure("No formatted visual X for printed rest \(baseID)")
                    Logger.warning("Printed rest \(baseID) missing from formatter output; using column anchor")
                    x = Self.columnX(
                        measureIndex: rest.position.measureIndex,
                        localTick: rest.position.localTick,
                        columnXByKey: columnXByKey,
                        fallbackMeasure: measure
                    )
                }
            } else {
                x = Self.columnX(
                    measureIndex: rest.position.measureIndex,
                    localTick: rest.position.localTick,
                    columnXByKey: columnXByKey,
                    fallbackMeasure: measure
                )
            }
            let voiceOffset = rest.voice == .upper
                ? style.upperVoiceRestOffset
                : style.lowerVoiceRestOffset
            return RenderedRest(
                id: "\(baseID)-duplicate-\(ordinal)",
                timeColumn: NotationTimeColumn(
                    measureIndex: rest.position.measureIndex,
                    tickWithinMeasure: rest.position.localTick,
                    absoluteLayoutTick: rest.position.absoluteTick
                ),
                measureIndex: rest.position.measureIndex,
                row: measure.row,
                voice: rest.voice,
                durationTicks: rest.durationTicks,
                duration: duration,
                visibility: rest.visibility,
                position: CGPoint(
                    x: x,
                    y: GameplayLayout.StaffLinePosition.line3.absoluteY(for: measure.row) + voiceOffset
                ),
                rhythmPosition: rest.position,
                rhythm: rest.rhythm,
                tupletID: rest.tupletID
            )
        }
    }
}
