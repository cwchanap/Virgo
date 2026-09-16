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
