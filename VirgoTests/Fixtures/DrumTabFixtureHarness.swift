import Foundation
import SwiftData
import Testing
import DrumNotation
@testable import Virgo

/// The rendered output of one fixture, plus the inputs later assertions need.
///
/// Carries `chart` because the playhead tests drive a real `GameplayViewModel`,
/// and `snapshot` because beat groups and engraving support live on
/// `RhythmMeasure` rather than on `RenderedMeasure`.
///
/// `layout` (the app-composed `NotationLayout`) and `engraved` (the package
/// `EngravedNotation`) are produced from the *same* snapshot by the two
/// parallel routes: `layout` is what production still mounts today, while
/// `engraved` is the regression net's geometry authority (HPA-166 Task 6).
/// `resolvedInput` is the projection output the engraving consumed — rest/
/// control ticks live there because the engraved primitives carry only
/// final geometry.
@MainActor
struct FixtureRenderResult {
    let chart: Chart
    let layout: NotationLayout
    let engraved: EngravedNotation
    let resolvedInput: ResolvedNotationInput
    let snapshot: RhythmLayoutSnapshot
    let timeline: RhythmTimeline
    let style: NotationLayoutStyle
    /// Retained so the chart's backing store outlives `render(...)`.
    let container: TestContainer
}

enum DrumTabFixtureHarnessError: Error {
    case rhythmUnavailable(RhythmTimelineAvailability)
    case missingTimeline
}

/// One control's bridge identity: event ID + kind kept as a pair, so a kind
/// swap between two controls or a dropped duplicate fails the comparison.
/// A concrete struct rather than a tuple so `[BridgeControlIdentity]`
/// conforms to `Equatable`/`Comparable` for direct `==` and `.sorted()`.
struct BridgeControlIdentity: Equatable, Comparable, Sendable {
    let id: Int
    let kind: String

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.id, lhs.kind) < (rhs.id, rhs.kind)
    }
}

/// Bridge-identity helpers (HPA-166 Task 6, review fix 1): the bridge test
/// compares only the identities named in the brief — measure count/index,
/// note event IDs, control (eventID, kind) pairs, and formatted
/// tick → row/X. These helpers keep each of those comparisons lossless
/// (sorted arrays/tuples preserve multiplicity and pairing; a nil legacy
/// control ID fails instead of being dropped) and make the probe set cover
/// every relevant tick without turning the test into a generalized
/// dual-renderer comparator.
extension FixtureRenderResult {
    /// Every tick the bridge's tick → row/X check must visit: all formatted
    /// logical columns on BOTH surfaces plus every resolved note/rest/control
    /// onset, deduplicated and sorted by (measureIndex, localTick).
    var bridgeProbeTicks: [NotationTickPosition] {
        Self.bridgeProbeTicks(
            legacyFormatted: layout.formattedNotation,
            packageFormatted: engraved.formatted,
            onsetTicks: resolvedInput.notes.map(\.position)
                + resolvedInput.rests.map(\.position)
                + resolvedInput.controls.map(\.position)
        )
    }

    /// The probe union: logical column ticks from BOTH formatted outputs —
    /// a column that exists on only one surface must still be probed, or a
    /// legacy-only tick could escape the tick → row/X comparison — plus all
    /// resolved event onsets. `nonisolated`: pure value-type work.
    nonisolated static func bridgeProbeTicks(
        legacyFormatted: FormattedNotation,
        packageFormatted: FormattedNotation,
        onsetTicks: [NotationTickPosition]
    ) -> [NotationTickPosition] {
        var seen = Set<NotationTickPosition>()
        return (
            columnTicks(legacyFormatted)
                + columnTicks(packageFormatted)
                + onsetTicks
        )
        .filter { seen.insert($0).inserted }
        .sorted { ($0.measureIndex, $0.localTick) < ($1.measureIndex, $1.localTick) }
    }

    private nonisolated static func columnTicks(
        _ formatted: FormattedNotation
    ) -> [NotationTickPosition] {
        formatted.measures.flatMap { measure in
            measure.columns.map {
                NotationTickPosition(measureIndex: measure.index, localTick: $0.localTick)
            }
        }
    }

    /// Sorted note event IDs on each surface — an array, not a Set, so a
    /// dropped or duplicated head changes the comparison.
    var bridgeNoteIDs: (legacy: [Int], package: [Int]) {
        (
            legacy: layout.noteHeads.map { Int($0.id) }.sorted(),
            package: engraved.noteHeads.map(\.noteID).sorted()
        )
    }

    /// Sorted (eventID, kind) control identities on each surface. Legacy
    /// stop notes must carry an event ID — `#require` fails the test rather
    /// than `compactMap` silently narrowing the comparison — and pairing ID
    /// with kind per element means a kind swap between two controls fails.
    func bridgeControlIdentities() throws
        -> (legacy: [BridgeControlIdentity], package: [BridgeControlIdentity]) {
        let legacy = try layout.stopNotes.map { stop in
            BridgeControlIdentity(
                id: try #require(
                    stop.eventID,
                    "bridge requires every legacy control to carry an eventID"
                ).rawValue,
                kind: stop.kind.rawValue
            )
        }
        let package = engraved.controls.map {
            BridgeControlIdentity(id: $0.controlID, kind: $0.kind.rawValue)
        }
        return (legacy: legacy.sorted(), package: package.sorted())
    }
}

/// Runs a fixture through the production import and layout path.
///
/// Deliberately mirrors `LocalDTXFixtureImporter` / `ServerSongDownloader`:
/// `persistenceProjection()` + `setRhythmMetadata` rather than
/// `toNotes`/`toControlEvents`, because the latter leaves
/// `rhythmMetadataState == .missing` (routing `resolve` through
/// `resolveMissing`) and stamps control ticks at each chip's native grid size
/// instead of the shared LCM timeline.
@MainActor
enum DrumTabFixtureHarness {
    /// Pinned so goldens cannot depend on window size or user settings.
    /// `nonisolated` (immutable + Sendable) so the pure `engrave` path can
    /// default to them without hopping onto the main actor.
    nonisolated static let lockedStyle = NotationLayoutStyle.gameplayDefault
        .with(rowWidth: GameplayLayout.maxRowWidth)

    nonisolated static let lockedOverrides: [DrumType: GameplayLayout.NotePosition] =
        Dictionary(uniqueKeysWithValues: DrumType.allCases.map { ($0, $0.notePosition) })

    static func render(
        _ fixture: DrumTabFixture,
        includeControls: Bool = true
    ) throws -> FixtureRenderResult {
        let chartData = try DTXFileParser.parseChartMetadata(
            from: fixture.source(includeControls: includeControls)
        )
        let projection = try chartData.persistenceProjection()

        let (chart, container) = try makePersistedChart(
            chartData: chartData,
            projection: projection
        )

        let resolved = RhythmTimelineResolver().resolve(chart: chart)
        guard resolved.availability == .valid else {
            throw DrumTabFixtureHarnessError.rhythmUnavailable(resolved.availability)
        }
        guard let timeline = resolved.timeline else {
            throw DrumTabFixtureHarnessError.missingTimeline
        }

        let snapshot = try RhythmLayoutSnapshotBuilder().build(
            resolvedRhythm: resolved,
            timeline: timeline,
            feel: RhythmLayoutSnapshotBuilder.feel(for: chart)
        )

        // HPA-164 Task 6: goldens exercise the one measured preparation route
        // production uses (snapshot → formatter → composed layout).
        let prepared = GameplayNotationPreparer.prepare(GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: fixture.minimumMeasureCount,
            style: lockedStyle,
            notePositionOverrides: lockedOverrides
        ))

        // HPA-166 Task 6: the package route shares the same snapshot and
        // expansion; the regression net reads `engraved`, not `layout`.
        let engraving = try engrave(
            snapshot: snapshot,
            minimumMeasureCount: fixture.minimumMeasureCount
        )

        return FixtureRenderResult(
            chart: chart,
            layout: prepared.layout,
            engraved: engraving.engraved,
            resolvedInput: engraving.input,
            snapshot: snapshot,
            timeline: timeline,
            style: lockedStyle,
            container: container
        )
    }

    /// The test-side package engraving path (HPA-166 Task 6): the same
    /// expanded measure list `GameplayNotationPreparer.prepare` builds, the
    /// app-site `VirgoNotationProjection` conversion, then the package
    /// engraver — sharing the harness's locked style and overrides so
    /// goldens stay pinned. `NotationSnapshotTestSupport` reuses this seam
    /// for synthetic snapshots so both entry points engrave identically.
    /// Nonisolated: every call below is a pure value-type function.
    nonisolated static func engrave(
        snapshot: RhythmLayoutSnapshot,
        minimumMeasureCount: Int,
        style: NotationLayoutStyle = lockedStyle,
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition] = lockedOverrides
    ) throws -> (input: ResolvedNotationInput, engraved: EngravedNotation) {
        let expandedMeasures = NotationLayoutEngine().expandedRhythmMeasures(
            snapshot,
            minimumMeasureCount: minimumMeasureCount
        )
        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: expandedMeasures,
            notePositionOverrides: notePositionOverrides
        )
        return try (
            input,
            NotationEngraver.engrave(input, style: engravingStyle(for: style))
        )
    }

    /// Maps the app layout style onto the package engraving style. The
    /// `formatting` half routes through `VirgoNotationProjection`'s single
    /// app-site mapper (the same call `GameplayNotationPreparer` makes); the
    /// engraving half spells out every app scalar explicitly — the values
    /// `NotationEngravingStyle`'s defaults happen to encode — so this seam
    /// fails loudly if either side's defaults ever drift.
    nonisolated static func engravingStyle(for style: NotationLayoutStyle) -> NotationEngravingStyle {
        NotationEngravingStyle(
            formatting: VirgoNotationProjection.formattingStyle(
                rowWidth: style.rowWidth,
                style: style
            ),
            rowHeight: GameplayLayout.rowHeight,
            rowVerticalSpacing: GameplayLayout.rowVerticalSpacing,
            stemLength: style.stemLength,
            minimumStemExtensionPastChord: style.minimumStemExtensionPastChord,
            beamThickness: style.beamThickness,
            beamLevelSpacing: style.beamLevelSpacing,
            beamHookLength: style.beamHookLength,
            flagVerticalSpacing: GameplayLayout.flagVerticalSpacing,
            ledgerLineOverhang: style.ledgerLineOverhang,
            upperVoiceRestOffset: style.upperVoiceRestOffset,
            lowerVoiceRestOffset: style.lowerVoiceRestOffset,
            stopMarkSize: style.stopMarkSize,
            stopMarkStrokeWidth: style.stopMarkStrokeWidth,
            stopMarkVerticalOffset: style.stopMarkVerticalOffset,
            articulationVerticalOffset: style.articulationVerticalOffset,
            tupletLineWidth: style.tupletLineWidth,
            tupletLabelSize: style.tupletLabelSize,
            tupletVerticalOffset: style.tupletVerticalOffset,
            tupletHookLength: style.tupletHookLength,
            barLineWidth: GameplayLayout.barLineWidth,
            doubleBarThinWidth: GameplayLayout.doubleBarLineWidths.thin,
            doubleBarThickWidth: GameplayLayout.doubleBarLineWidths.thick,
            doubleBarSpacing: GameplayLayout.doubleBarLineSpacing,
            clefWidth: GameplayLayout.clefWidth,
            meterWidth: GameplayLayout.timeSignatureWidth
        )
    }

    /// Builds the `Song`/`Chart` pair from a parsed projection, wires their
    /// relationships, applies rhythm metadata, and persists them into an
    /// ephemeral `TestContainer` (not registered in the global
    /// `isolatedContainers` dict — `FixtureRenderResult.container` retains
    /// it for the chart's lifetime, so global registration would leak).
    /// Returns the chart and the container so the caller can retain the
    /// backing store for the chart's lifetime.
    private static func makePersistedChart(
        chartData: DTXChartData,
        projection: DTXChartPersistenceProjection
    ) throws -> (chart: Chart, container: TestContainer) {
        let container = TestContainer.ephemeralContainer()
        let context = container.context
        let song = Song(
            title: chartData.title,
            artist: chartData.artist,
            bpm: chartData.bpm,
            duration: "0:10",
            genre: "DTX"
        )
        let chart = Chart(
            difficulty: .medium,
            level: chartData.difficultyLevel,
            timeSignature: projection.timeSignature,
            song: song
        )
        try chart.setRhythmMetadata(projection.chartMetadata)
        chart.notes = projection.notes.map { $0.makeNote(for: chart) }
        chart.controlEvents = projection.controls.map { $0.makeControl(for: chart) }
        song.charts = [chart]
        context.insert(song)
        try context.save()
        return (chart, container)
    }
}
