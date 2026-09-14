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
    let formatted: FormattedNotation

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
/// `VirgoNotationProjection.resolvedNotation`, maps the style through
/// `VirgoNotationProjection.formattingStyle`, runs the measured
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
            let input = try VirgoNotationProjection.resolvedNotation(
                snapshot: request.snapshot,
                expandedMeasures: expandedMeasures,
                notePositionOverrides: request.notePositionOverrides
            )
            let style = VirgoNotationProjection.formattingStyle(
                rowWidth: request.style.rowWidth,
                style: request.style
            )
            let formatted = try NotationFormatter.format(input, style: style)
            return GameplayNotationPreparedState(
                layout: composeVirgoLayout(
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

// MARK: - Package geometry composition (HPA-164 Tasks 5–6)

/// App-only marks and derived artifacts rebuilt from positioned primitives
/// (they consume the composed geometry but never alter package spacing).
private struct RebuiltArtifacts {
    let derived: NotationLayoutEngine.BuiltDerivedArtifacts
    let articulations: [RenderedArticulation]
    let rhythmDots: [RenderedRhythmDot]
    let tuplets: [RenderedTuplet]
    let feelMarks: [RenderedFeelMark]
    let rhythmWarnings: [RenderedRhythmWarning]
}

/// Everything composed from the measured formatter output before the
/// app-only marks are rebuilt: measures, the three X lookups, and the
/// positioned primitives. Groups what used to be seven loose parameters.
private struct ComposedNotation {
    let measures: [RenderedMeasure]
    let columnXByKey: [MeasureTickKey: CGFloat]
    let headCenterXByID: [UInt64: CGFloat]
    let visualXByRestID: [Int: CGFloat]
    let noteHeads: [RenderedNoteHead]
    let rests: [RenderedRest]
    let stopNotes: [RenderedStopNote]
    let unsupportedMeasureIndexes: Set<Int>
}

/// Composes Virgo's rendered layout directly from the measured
/// `FormattedNotation`: measure rows/bounds and every primitive X come from
/// the package, while Y stays Virgo (row + staff position). Stems, beams,
/// flags and every X-dependent mark are rebuilt from the positioned heads, so
/// the shared stem axis remains on the undisplaced stem-side representative —
/// the package's pinned VexFlow displacement never moves that head. No
/// post-format X transform and no grid geometry.
private extension GameplayNotationPreparer {
    static func composeVirgoLayout(
        formatted: FormattedNotation,
        expandedMeasures: [RhythmMeasure],
        request: GameplayNotationPreparationRequest
    ) -> NotationLayout {
        let engine = NotationLayoutEngine()
        let composed = composedNotation(
            engine: engine,
            formatted: formatted,
            expandedMeasures: expandedMeasures,
            request: request
        )
        let rebuilt = rebuiltArtifacts(
            engine: engine,
            request: request,
            expandedMeasures: expandedMeasures,
            composed: composed
        )
        var layout = engine.finalizedLayout(
            finalizationInput(request: request, composed: composed, rebuilt: rebuilt)
        )
        // The immutable formatter output rides on the installed layout for
        // the live playhead lookup; no extra view-model caches are derived.
        layout.formattedNotation = formatted
        return layout
    }

    /// Composes measures, the X lookups and the positioned primitives from
    /// the measured formatter output (package X, Virgo staff Y).
    static func composedNotation(
        engine: NotationLayoutEngine,
        formatted: FormattedNotation,
        expandedMeasures: [RhythmMeasure],
        request: GameplayNotationPreparationRequest
    ) -> ComposedNotation {
        let measures = composedMeasures(expandedMeasures: expandedMeasures, formatted: formatted)
        let columnXByKey = columnLookup(formatted: formatted) { $0.logicalColumnX }
        let headCenterXByID = headCenterLookup(formatted: formatted)
        let visualXByRestID = restVisualLookup(formatted: formatted)
        // Unsupported measures suppress duration-bearing engraving; their
        // rests are dropped and the measure's warning is carried by
        // `buildRhythmWarnings`.
        let unsupportedMeasureIndexes = Set(
            expandedMeasures.lazy.filter { !$0.engravingSupport.permitsEngraving }.map(\.measureIndex)
        )
        let noteHeads = engine.buildNoteHeads(
            notes: request.snapshot.notes,
            measures: measures,
            headCenterXByID: headCenterXByID,
            columnXByKey: columnXByKey,
            style: request.style,
            notePositionOverrides: request.notePositionOverrides
        )
        let rests = engine.buildRests(
            rests: request.snapshot.rests.filter {
                !unsupportedMeasureIndexes.contains($0.position.measureIndex)
            },
            measures: measures,
            visualXByRestID: visualXByRestID,
            columnXByKey: columnXByKey,
            style: request.style
        )
        let stopNotes = engine.buildStopNotes(
            controls: request.snapshot.controls,
            measures: measures,
            columnXByKey: columnXByKey,
            style: request.style,
            notePositionOverrides: request.notePositionOverrides
        )
        return ComposedNotation(
            measures: measures,
            columnXByKey: columnXByKey,
            headCenterXByID: headCenterXByID,
            visualXByRestID: visualXByRestID,
            noteHeads: noteHeads,
            rests: rests,
            stopNotes: stopNotes,
            unsupportedMeasureIndexes: unsupportedMeasureIndexes
        )
    }

    /// Measures pair the timeline's tick semantics with the package's
    /// row packing and sheet-local bounds verbatim.
    static func composedMeasures(
        expandedMeasures: [RhythmMeasure],
        formatted: FormattedNotation
    ) -> [RenderedMeasure] {
        let byIndex = Dictionary(uniqueKeysWithValues: formatted.measures.map { ($0.index, $0) })
        return expandedMeasures.compactMap { rhythmMeasure in
            guard let packageMeasure = byIndex[rhythmMeasure.measureIndex] else {
                // The formatter emits one formatted measure per input
                // measure; a gap means the input projection drifted.
                assertionFailure("Formatter omitted measure \(rhythmMeasure.measureIndex)")
                return nil
            }
            return RenderedMeasure(
                id: rhythmMeasure.measureIndex,
                measureIndex: rhythmMeasure.measureIndex,
                row: packageMeasure.rowIndex,
                xOffset: packageMeasure.xOffset,
                width: packageMeasure.width,
                startTick: rhythmMeasure.startTick,
                durationTicks: rhythmMeasure.durationTicks
            )
        }
    }

    /// Logical onset X for every formatted column (the timing anchor notes,
    /// rests and controls share).
    private static func columnLookup(
        formatted: FormattedNotation,
        x: (FormattedColumn) -> CGFloat
    ) -> [MeasureTickKey: CGFloat] {
        var lookup: [MeasureTickKey: CGFloat] = [:]
        for measure in formatted.measures {
            for column in measure.columns {
                lookup[MeasureTickKey(
                    measureIndex: measure.index,
                    tick: column.localTick
                )] = x(column)
            }
        }
        return lookup
    }

    /// Package head-center X per note ID (a displaced staff second rides on
    /// the head itself).
    private static func headCenterLookup(
        formatted: FormattedNotation
    ) -> [UInt64: CGFloat] {
        var lookup: [UInt64: CGFloat] = [:]
        for measure in formatted.measures {
            for column in measure.columns {
                for head in column.noteHeads {
                    lookup[UInt64(head.noteID)] = head.headCenterX
                }
            }
        }
        return lookup
    }

    /// Package visual X per printed rest (keyed by `FormattedRest.restID` —
    /// the rest's ordinal in the projection's printed order). Same-tick rests
    /// keep distinct X: full-measure rests center in the content span while
    /// interval rests sit on the column anchor.
    private static func restVisualLookup(
        formatted: FormattedNotation
    ) -> [Int: CGFloat] {
        var lookup: [Int: CGFloat] = [:]
        for measure in formatted.measures {
            for column in measure.columns {
                for rest in column.rests {
                    lookup[rest.restID] = rest.visualX
                }
            }
        }
        return lookup
    }

    /// Rebuilds beams/stems/flags/ledger/bars plus the app-only marks from
    /// the positioned primitives (the marks consume the composed geometry
    /// but never alter package spacing).
    static func rebuiltArtifacts(
        engine: NotationLayoutEngine,
        request: GameplayNotationPreparationRequest,
        expandedMeasures: [RhythmMeasure],
        composed: ComposedNotation
    ) -> RebuiltArtifacts {
        let style = request.style
        let beamBuild = engine.buildBeams(noteHeads: composed.noteHeads, measures: expandedMeasures, style: style)
        let stems = engine.buildStems(noteHeads: composed.noteHeads, beams: beamBuild.beams, style: style)
        let derived = NotationLayoutEngine.BuiltDerivedArtifacts(
            beams: beamBuild.beams,
            stems: stems,
            flags: engine.buildFlags(
                noteHeads: composed.noteHeads.filter {
                    !composed.unsupportedMeasureIndexes.contains($0.measureIndex)
                },
                beamBuild: beamBuild,
                stems: stems,
                style: style
            ),
            ledgerLines: engine.buildLedgerLines(noteHeads: composed.noteHeads, style: style),
            measureBars: engine.buildMeasureBars(measures: composed.measures)
        )
        let tupletContext = TupletRenderingContext(
            beams: derived.beams,
            feel: request.snapshot.feel,
            rhythmMeasures: expandedMeasures,
            unsupportedMeasureIndexes: composed.unsupportedMeasureIndexes,
            style: style
        )
        return RebuiltArtifacts(
            derived: derived,
            articulations: engine.buildArticulations(noteHeads: composed.noteHeads, style: style),
            rhythmDots: engine.buildRhythmDots(
                noteHeads: composed.noteHeads,
                rests: composed.rests,
                unsupportedMeasureIndexes: composed.unsupportedMeasureIndexes,
                style: style
            ),
            tuplets: engine.buildTuplets(
                noteHeads: composed.noteHeads,
                rests: composed.rests,
                context: tupletContext
            ),
            feelMarks: engine.buildFeelMarks(
                feel: request.snapshot.feel,
                measures: composed.measures,
                style: style
            ),
            rhythmWarnings: engine.buildRhythmWarnings(
                rhythmMeasures: expandedMeasures,
                renderedMeasures: composed.measures,
                style: style
            )
        )
    }

    /// Bundles the composed and rebuilt artifacts for the engine's finalizer.
    static func finalizationInput(
        request: GameplayNotationPreparationRequest,
        composed: ComposedNotation,
        rebuilt: RebuiltArtifacts
    ) -> NotationLayoutFinalizationInput {
        NotationLayoutFinalizationInput(
            measures: composed.measures,
            noteHeads: composed.noteHeads,
            rests: composed.rests,
            stopNotes: composed.stopNotes,
            articulations: rebuilt.articulations,
            derived: rebuilt.derived,
            rhythmDots: rebuilt.rhythmDots,
            tuplets: rebuilt.tuplets,
            feelMarks: rebuilt.feelMarks,
            rhythmWarnings: rebuilt.rhythmWarnings,
            style: request.style
        )
    }
}
