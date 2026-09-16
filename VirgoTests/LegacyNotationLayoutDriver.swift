import CoreGraphics
import Testing
import DrumNotation
@testable import Virgo

/// The disconnected legacy layout result: the composed `NotationLayout` plus
/// the measured formatter output it was built from (the old
/// `GameplayNotationPreparedState` shape).
///
/// Test-only bridge for the restored pure model/engine tests — production
/// preparation ends in `EngravedNotation` and never produces this. Task 8
/// deletes this driver with the legacy model it feeds.
struct LegacyPreparedNotation {
    let layout: NotationLayout
    let formatted: FormattedNotation
}

/// Reproduces the pre-cutover preparation route for the restored legacy
/// model's pure tests: snapshot → expansion → `VirgoNotationProjection` →
/// `NotationFormatter.format` → `NotationLayoutEngine` composition. This is
/// a test seam only — no production code calls it.
func legacyPreparedNotation(
    _ request: GameplayNotationPreparationRequest
) -> LegacyPreparedNotation {
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
        return LegacyPreparedNotation(
            layout: LegacyNotationComposition.composeVirgoLayout(
                formatted: formatted,
                expandedMeasures: expandedMeasures,
                request: request
            ),
            formatted: formatted
        )
    } catch {
        return LegacyPreparedNotation(
            layout: .empty,
            formatted: FormattedNotation(measures: [])
        )
    }
}

/// App-only marks and derived artifacts rebuilt from positioned primitives.
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
/// positioned primitives.
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

/// The pre-cutover composition helpers, verbatim from the old
/// `GameplayNotationPreparer`: measure rows/bounds and every primitive X come
/// from the package formatter output, Y stays Virgo (row + staff position),
/// and stems/beams/flags are rebuilt from the positioned heads.
private enum LegacyNotationComposition {
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

extension NotationSnapshotTestSupport {
    /// Runs the specs through the disconnected legacy preparation route and
    /// returns the composed `NotationLayout` + formatter output — the shape
    /// the restored model/engine tests assert against.
    func legacyPrepare(
        notes: [Note] = [],
        controls: [NotationControlEvent] = [],
        rests: [RhythmLayoutRest] = [],
        minimumMeasureCount: Int = 1,
        style: NotationLayoutStyle = .gameplayDefault,
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition] = [:]
    ) -> LegacyPreparedNotation {
        guard let snapshot = try? snapshot(
            notes: notes,
            controls: controls,
            rests: rests,
            minimumMeasureCount: minimumMeasureCount
        ) else {
            Issue.record("Snapshot construction failed for test notes")
            return LegacyPreparedNotation(
                layout: .empty,
                formatted: FormattedNotation(measures: [])
            )
        }
        return legacyPreparedNotation(GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: minimumMeasureCount,
            style: style,
            notePositionOverrides: notePositionOverrides
        ))
    }
}
