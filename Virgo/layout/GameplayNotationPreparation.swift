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

/// Composes Virgo's rendered layout directly from the measured
/// `FormattedNotation`: measure rows/bounds and every primitive X come from
/// the package, while Y stays Virgo (row + staff position). Stems, beams,
/// flags and every X-dependent mark are rebuilt from the positioned heads, so
/// the shared stem axis remains on the undisplaced stem-side representative —
/// the package's pinned VexFlow displacement never moves that head. No
/// post-format X transform and no grid geometry.
private extension GameplayNotationPreparer {
    static func composeVirgoLayout(
        snapshot: RhythmLayoutSnapshot,
        formatted: FormattedNotation,
        expandedMeasures: [RhythmMeasure],
        request: GameplayNotationPreparationRequest
    ) -> NotationLayout {
        let measures = composedMeasures(
            expandedMeasures: expandedMeasures,
            formatted: formatted
        )
        let columnXByKey = columnLookup(formatted: formatted) { $0.logicalColumnX }
        let headCenterXByID = headCenterLookup(formatted: formatted)
        let visualXByKey = restVisualLookup(formatted: formatted)
        let unsupportedMeasureIndexes = Set(expandedMeasures.compactMap { measure -> Int? in
            measure.engravingSupport.permitsEngraving ? nil : measure.measureIndex
        })
        let engine = NotationLayoutEngine()
        let noteHeads = engine.buildNoteHeads(
            notes: snapshot.notes,
            measures: measures,
            headCenterXByID: headCenterXByID,
            columnXByKey: columnXByKey,
            style: request.style,
            notePositionOverrides: request.notePositionOverrides
        )
        let rests = engine.buildRests(
            rests: snapshot.rests.filter {
                // Unsupported measures suppress duration-bearing engraving;
                // their rests are dropped and the measure's warning is
                // carried by `buildRhythmWarnings`.
                !unsupportedMeasureIndexes.contains($0.position.measureIndex)
            },
            measures: measures,
            visualXByKey: visualXByKey,
            columnXByKey: columnXByKey,
            style: request.style
        )
        let stopNotes = engine.buildStopNotes(
            controls: snapshot.controls,
            measures: measures,
            columnXByKey: columnXByKey,
            style: request.style,
            notePositionOverrides: request.notePositionOverrides
        )
        let rebuilt = rebuiltArtifacts(
            snapshot: snapshot,
            request: request,
            expandedMeasures: expandedMeasures,
            measures: measures,
            noteHeads: noteHeads,
            rests: rests,
            unsupportedMeasureIndexes: unsupportedMeasureIndexes
        )
        var layout = engine.finalizedLayout(NotationLayoutFinalizationInput(
            measures: measures,
            noteHeads: noteHeads,
            rests: rests,
            stopNotes: stopNotes,
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

    /// Package visual X for printed rests (only rest-bearing columns map).
    private static func restVisualLookup(
        formatted: FormattedNotation
    ) -> [MeasureTickKey: CGFloat] {
        var lookup: [MeasureTickKey: CGFloat] = [:]
        for measure in formatted.measures {
            for column in measure.columns {
                guard let rest = column.rest else { continue }
                lookup[MeasureTickKey(
                    measureIndex: measure.index,
                    tick: column.localTick
                )] = rest.visualX
            }
        }
        return lookup
    }

    /// Rebuilds beams/stems/flags/ledger/bars plus the app-only marks from
    /// the positioned primitives (the marks consume the composed geometry
    /// but never alter package spacing).
    static func rebuiltArtifacts(
        snapshot: RhythmLayoutSnapshot,
        request: GameplayNotationPreparationRequest,
        expandedMeasures: [RhythmMeasure],
        measures: [RenderedMeasure],
        noteHeads: [RenderedNoteHead],
        rests: [RenderedRest],
        unsupportedMeasureIndexes: Set<Int>
    ) -> RebuiltArtifacts {
        let engine = NotationLayoutEngine()
        let style = request.style
        let beamBuild = engine.buildBeams(noteHeads: noteHeads, measures: expandedMeasures, style: style)
        let stems = engine.buildStems(noteHeads: noteHeads, beams: beamBuild.beams, style: style)
        let derived = NotationLayoutEngine.BuiltDerivedArtifacts(
            beams: beamBuild.beams,
            stems: stems,
            flags: engine.buildFlags(
                noteHeads: noteHeads.filter { !unsupportedMeasureIndexes.contains($0.measureIndex) },
                beamBuild: beamBuild,
                stems: stems,
                style: style
            ),
            ledgerLines: engine.buildLedgerLines(noteHeads: noteHeads, style: style),
            measureBars: engine.buildMeasureBars(measures: measures)
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
            articulations: engine.buildArticulations(noteHeads: noteHeads, style: style),
            rhythmDots: engine.buildRhythmDots(
                noteHeads: noteHeads,
                rests: rests,
                unsupportedMeasureIndexes: unsupportedMeasureIndexes,
                style: style
            ),
            tuplets: engine.buildTuplets(
                noteHeads: noteHeads,
                rests: rests,
                context: tupletContext
            ),
            feelMarks: engine.buildFeelMarks(
                feel: snapshot.feel,
                measures: measures,
                style: style
            ),
            rhythmWarnings: engine.buildRhythmWarnings(
                rhythmMeasures: expandedMeasures,
                renderedMeasures: measures,
                style: style
            )
        )
    }
}
