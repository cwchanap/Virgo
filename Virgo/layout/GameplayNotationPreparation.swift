import CoreGraphics
import DrumNotation

/// Immutable timeline inputs needed to prepare gameplay notation.
struct GameplayNotationPreparationRequest: Sendable {
    let snapshot: RhythmLayoutSnapshot
    let minimumMeasureCount: Int
    let style: NotationLayoutStyle
    let notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
}

/// Layout produced from one notation preparation request.
struct GameplayNotationPreparedState: Sendable {
    let layout: NotationLayout
    /// The measured formatter output the layout was composed from (HPA-164
    /// Task 5). Also embedded on `layout` for the live playhead lookup.
    var formatted: FormattedNotation = FormattedNotation(measures: [])

    init(layout: NotationLayout, formatted: FormattedNotation = FormattedNotation(measures: [])) {
        self.layout = layout
        self.formatted = formatted
    }
}

/// Pure value boundary for timeline-native gameplay notation preparation.
/// Cancellation is best-effort resource cleanup only: the dominant work is
/// notation layout, which has no cooperative cancellation points, so an
/// abandoned worker may still run to completion. Correctness rests on the
/// caller's generation checks — a stale result is discarded regardless of
/// whether the worker finished or was cancelled.
///
/// The single preparation route (HPA-164 Task 4): both the detached initial
/// worker and the synchronous `cacheNotationLayout()` relayout run through
/// ``prepare(_:)``, which projects the snapshot through
/// `VirgoNotationAdapter.resolvedNotation`, maps the style through
/// `VirgoNotationAdapter.formattingStyle`, runs the measured
/// `NotationFormatter`, and composes the rendered layout. There is no second
/// style/formatting path.
struct GameplayNotationPreparer {
    static func prepare(_ request: GameplayNotationPreparationRequest) -> GameplayNotationPreparedState {
        // Trailing-measure expansion happens before package conversion so the
        // formatter sees the complete requested measure list.
        let expandedMeasures = NotationLayoutEngine().expandedRhythmMeasures(
            request.snapshot,
            minimumMeasureCount: request.minimumMeasureCount
        )
        do {
            let input = try VirgoNotationAdapter.resolvedNotation(
                snapshot: request.snapshot,
                expandedMeasures: expandedMeasures,
                notePositionOverrides: request.notePositionOverrides
            )
            let style = VirgoNotationAdapter.formattingStyle(
                rowWidth: request.style.rowWidth,
                style: request.style
            )
            let formatted = try NotationFormatter.format(input, style: style)
            return GameplayNotationPreparedState(
                layout: composeVirgoLayout(
                    snapshot: request.snapshot,
                    formatted: formatted,
                    expandedMeasures: expandedMeasures,
                    request: request
                ),
                formatted: formatted
            )
        } catch {
            Logger.error("Measured notation preparation failed: \(error)")
            return GameplayNotationPreparedState(layout: .empty)
        }
    }
}

// MARK: - Package geometry composition (HPA-164 Task 5)

/// Repositioned primitives plus the base composition they derive from.
private struct ComposedPrimitives {
    let base: NotationLayout
    let measures: [RenderedMeasure]
    let noteHeads: [RenderedNoteHead]
    let rests: [RenderedRest]
    let stopNotes: [RenderedStopNote]
}

private struct MeasureTickKey: Hashable {
    let measureIndex: Int
    let tick: Int
}

/// App-only marks and derived artifacts rebuilt from positioned primitives
/// (Task 5 Step 4: they consume the composed geometry but never alter
/// package spacing).
private struct RebuiltArtifacts {
    let derived: NotationLayoutEngine.BuiltDerivedArtifacts
    let articulations: [RenderedArticulation]
    let rhythmDots: [RenderedRhythmDot]
    let tuplets: [RenderedTuplet]
    let feelMarks: [RenderedFeelMark]
    let rhythmWarnings: [RenderedRhythmWarning]
}

/// Task 5 composition (closes Ruling P1): copies package geometry from the
/// measured `FormattedNotation` straight onto Virgo's rendered primitives.
/// Measure rows/bounds, head centers, rest and control X and measure bars
/// come from the package; Y stays Virgo (row + staff position). Stems, beams,
/// flags and every X-dependent mark are rebuilt from the repositioned heads,
/// so the shared stem axis remains on the undisplaced stem-side
/// representative — the package's pinned VexFlow displacement never moves
/// that head. No `contentStartX`, `tickWidth` or `leftMargin` post-transform.
private extension GameplayNotationPreparer {
    static func composeVirgoLayout(
        snapshot: RhythmLayoutSnapshot,
        formatted: FormattedNotation,
        expandedMeasures: [RhythmMeasure],
        request: GameplayNotationPreparationRequest
    ) -> NotationLayout {
        // Base pass: Virgo Y, staff positions and the app-only semantics
        // (voice grouping, rests, controls, tuplets, warnings) with the
        // legacy grid X that the repositioning below replaces.
        let input = NotationLayoutInput(
            timing: .timeline(snapshot),
            minimumMeasureCount: request.minimumMeasureCount,
            style: request.style,
            notePositionOverrides: request.notePositionOverrides
        )
        let base = NotationLayoutEngine().layout(input: input)
        let primitives = ComposedPrimitives(
            base: base,
            measures: composedMeasures(from: base.measures, formatted: formatted),
            noteHeads: composedNoteHeads(from: base.noteHeads, formatted: formatted),
            rests: composedRests(from: base.rests, formatted: formatted),
            stopNotes: composedStopNotes(from: base.stopNotes, formatted: formatted)
        )
        return finalizedComposition(
            snapshot: snapshot,
            request: request,
            expandedMeasures: expandedMeasures,
            primitives: primitives,
            formatted: formatted
        )
    }

    /// Measures copy the package's row packing and sheet-local bounds
    /// verbatim; timeline start/duration ticks stay with the rhythm measures.
    static func composedMeasures(
        from base: [RenderedMeasure],
        formatted: FormattedNotation
    ) -> [RenderedMeasure] {
        let byIndex = Dictionary(uniqueKeysWithValues: formatted.measures.map { ($0.index, $0) })
        return base.map { measure in
            guard let packageMeasure = byIndex[measure.measureIndex] else { return measure }
            return RenderedMeasure(
                id: measure.id,
                measureIndex: measure.measureIndex,
                row: packageMeasure.rowIndex,
                xOffset: packageMeasure.xOffset,
                width: packageMeasure.width,
                startTick: measure.startTick,
                durationTicks: measure.durationTicks
            )
        }
    }

    /// Heads copy their package `headCenterX` (a displaced staff second rides
    /// on the head itself) while Y stays Virgo. Head IDs are the package note
    /// IDs, so the mapping is direct.
    static func composedNoteHeads(
        from base: [RenderedNoteHead],
        formatted: FormattedNotation
    ) -> [RenderedNoteHead] {
        var centerXByID: [UInt64: CGFloat] = [:]
        for measure in formatted.measures {
            for column in measure.columns {
                for head in column.noteHeads {
                    centerXByID[UInt64(head.noteID)] = head.headCenterX
                }
            }
        }
        return base.map { head in
            guard let centerX = centerXByID[head.id] else { return head }
            return RenderedNoteHead(
                id: head.id,
                sourceLaneID: head.sourceLaneID,
                sourceChipID: head.sourceChipID,
                noteType: head.noteType,
                drumType: head.drumType,
                variant: head.variant,
                voice: head.voice,
                stemDirection: head.stemDirection,
                timeColumn: head.timeColumn,
                timePosition: head.timePosition,
                row: head.row,
                position: CGPoint(x: centerX, y: head.position.y),
                staffStep: head.staffStep,
                interval: head.interval,
                catalogOrder: head.catalogOrder,
                eventID: head.eventID,
                rhythmPosition: head.rhythmPosition,
                rhythmDurationTicks: head.rhythmDurationTicks,
                rhythm: head.rhythm,
                tupletID: head.tupletID
            )
        }
    }

    /// Rests take the package visual X: the column's `logicalColumnX`, or the
    /// centered full-measure rest position the formatter finalized.
    static func composedRests(
        from base: [RenderedRest],
        formatted: FormattedNotation
    ) -> [RenderedRest] {
        var visualXByKey: [MeasureTickKey: CGFloat] = [:]
        for measure in formatted.measures {
            for column in measure.columns {
                if let rest = column.rest {
                    visualXByKey[MeasureTickKey(
                        measureIndex: measure.index,
                        tick: column.localTick
                    )] = rest.visualX
                }
            }
        }
        return base.map { rest in
            guard let x = visualXByKey[MeasureTickKey(
                measureIndex: rest.measureIndex,
                tick: rest.timeColumn.tickWithinMeasure
            )] else { return rest }
            return RenderedRest(
                id: rest.id,
                timeColumn: rest.timeColumn,
                measureIndex: rest.measureIndex,
                row: rest.row,
                voice: rest.voice,
                durationTicks: rest.durationTicks,
                duration: rest.duration,
                visibility: rest.visibility,
                position: CGPoint(x: x, y: rest.position.y),
                rhythmPosition: rest.rhythmPosition,
                rhythm: rest.rhythm,
                tupletID: rest.tupletID
            )
        }
    }

    /// Controls anchor at the logical column X of their tick (the package
    /// gives every control tick an exact column; controls carry zero ink).
    static func composedStopNotes(
        from base: [RenderedStopNote],
        formatted: FormattedNotation
    ) -> [RenderedStopNote] {
        var columnXByKey: [MeasureTickKey: CGFloat] = [:]
        for measure in formatted.measures {
            for column in measure.columns {
                columnXByKey[MeasureTickKey(
                    measureIndex: measure.index,
                    tick: column.localTick
                )] = column.logicalColumnX
            }
        }
        return base.map { stop in
            guard let x = columnXByKey[MeasureTickKey(
                measureIndex: stop.timeColumn.measureIndex,
                tick: stop.timeColumn.tickWithinMeasure
            )] else { return stop }
            return RenderedStopNote(
                id: stop.id,
                kind: stop.kind,
                sourceLaneID: stop.sourceLaneID,
                sourceNoteID: stop.sourceNoteID,
                targetLaneID: stop.targetLaneID,
                targetDisplayName: stop.targetDisplayName,
                timeColumn: stop.timeColumn,
                row: stop.row,
                position: CGPoint(x: x, y: stop.position.y),
                eventID: stop.eventID,
                rhythmPosition: stop.rhythmPosition
            )
        }
    }

    /// Rebuilds every X-dependent artifact from the repositioned primitives
    /// and finalizes. Beam topology stays X-independent (it builds from the
    /// same rhythm measures); stems pick the stem-side representative by Y,
    /// which the package never displaces.
    static func finalizedComposition(
        snapshot: RhythmLayoutSnapshot,
        request: GameplayNotationPreparationRequest,
        expandedMeasures: [RhythmMeasure],
        primitives: ComposedPrimitives,
        formatted: FormattedNotation
    ) -> NotationLayout {
        let engine = NotationLayoutEngine()
        let rebuilt = rebuiltArtifacts(
            snapshot: snapshot,
            request: request,
            primitives: primitives,
            expandedMeasures: expandedMeasures
        )
        var layout = engine.finalizedLayout(NotationLayoutFinalizationInput(
            tabGrid: primitives.base.tabGrid,
            measures: primitives.measures,
            noteHeads: primitives.noteHeads,
            rests: primitives.rests,
            stopNotes: primitives.stopNotes,
            articulations: rebuilt.articulations,
            derived: rebuilt.derived,
            rhythmDots: rebuilt.rhythmDots,
            tuplets: rebuilt.tuplets,
            feelMarks: rebuilt.feelMarks,
            rhythmWarnings: rebuilt.rhythmWarnings,
            style: request.style
        ))
        // The immutable formatter output rides on the installed layout for
        // the live playhead lookup; no extra view-model caches are derived.
        layout.formattedNotation = formatted
        return layout
    }

    /// Rebuilds beams/stems/flags/ledger/bars plus the app-only marks from
    /// the repositioned primitives (Task 5 Step 4: the marks consume the
    /// composed geometry but never alter package spacing).
    static func rebuiltArtifacts(
        snapshot: RhythmLayoutSnapshot,
        request: GameplayNotationPreparationRequest,
        primitives: ComposedPrimitives,
        expandedMeasures: [RhythmMeasure]
    ) -> RebuiltArtifacts {
        let engine = NotationLayoutEngine()
        let style = request.style
        let heads = primitives.noteHeads
        let unsupportedMeasureIndexes = Set(expandedMeasures.compactMap { measure -> Int? in
            measure.engravingSupport.permitsEngraving ? nil : measure.measureIndex
        })
        let derived = rebuiltDerivedArtifacts(
            heads: heads,
            measures: primitives.measures,
            expandedMeasures: expandedMeasures,
            style: style,
            unsupportedMeasureIndexes: unsupportedMeasureIndexes
        )
        let tupletContext = TupletRenderingContext(
            beams: derived.beams,
            feel: snapshot.feel,
            rhythmMeasures: expandedMeasures,
            unsupportedMeasureIndexes: unsupportedMeasureIndexes,
            style: style
        )
        return RebuiltArtifacts(
            derived: derived,
            articulations: engine.buildArticulations(noteHeads: heads, style: style),
            rhythmDots: engine.buildRhythmDots(
                noteHeads: heads,
                rests: primitives.rests,
                unsupportedMeasureIndexes: unsupportedMeasureIndexes,
                style: style
            ),
            tuplets: engine.buildTuplets(
                noteHeads: heads,
                rests: primitives.rests,
                context: tupletContext
            ),
            feelMarks: engine.buildFeelMarks(
                feel: snapshot.feel,
                measures: primitives.measures,
                style: style
            ),
            rhythmWarnings: engine.buildRhythmWarnings(
                rhythmMeasures: expandedMeasures,
                renderedMeasures: primitives.measures,
                style: style
            )
        )
    }

    /// Stems pick the stem-side representative by Y (which the package never
    /// displaces); beam topology is X-independent and rebuilds from the same
    /// rhythm measures.
    static func rebuiltDerivedArtifacts(
        heads: [RenderedNoteHead],
        measures: [RenderedMeasure],
        expandedMeasures: [RhythmMeasure],
        style: NotationLayoutStyle,
        unsupportedMeasureIndexes: Set<Int>
    ) -> NotationLayoutEngine.BuiltDerivedArtifacts {
        let engine = NotationLayoutEngine()
        let beamBuild = engine.buildBeams(noteHeads: heads, measures: expandedMeasures, style: style)
        let stems = engine.buildStems(noteHeads: heads, beams: beamBuild.beams, style: style)
        return NotationLayoutEngine.BuiltDerivedArtifacts(
            beams: beamBuild.beams,
            stems: stems,
            flags: engine.buildFlags(
                noteHeads: heads.filter { !unsupportedMeasureIndexes.contains($0.measureIndex) },
                beamBuild: beamBuild,
                stems: stems,
                style: style
            ),
            ledgerLines: engine.buildLedgerLines(noteHeads: heads, style: style),
            measureBars: engine.buildMeasureBars(measures: measures)
        )
    }
}
