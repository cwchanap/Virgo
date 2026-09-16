import Foundation
import SwiftData
import Testing
import DrumNotation
@testable import Virgo

/// The rendered output of one fixture, plus the inputs later assertions need.
///
/// Carries `chart` because the playhead tests drive a real `GameplayViewModel`,
/// and `snapshot` because beat groups and engraving support live on
/// `RhythmMeasure` rather than on `EngravedMeasure`.
///
/// `engraved` (the package `EngravedNotation`) is the sole production
/// geometry: `GameplayNotationPreparer.prepare` is the single preparation
/// route, so `prepared` is the same closed state the view model installs
/// (HPA-166 Task 7). `resolvedInput` is the projection output the engraving
/// consumed — rest/control ticks live there because the engraved primitives
/// carry only final geometry.
@MainActor
struct FixtureRenderResult {
    let chart: Chart
    let prepared: GameplayNotationPreparedState
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
    case notationNotReady(GameplayNotationPreparedState)
}

/// Runs a fixture through the production import and notation path.
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

        // HPA-166 Task 7: the package route is the one production
        // preparation path — snapshot → expansion → projection →
        // `NotationEngraver`. `prepared` is the same closed state the view
        // model installs.
        let prepared = GameplayNotationPreparer.prepare(GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: fixture.minimumMeasureCount,
            style: lockedStyle,
            notePositionOverrides: lockedOverrides
        ))

        let engraving = try engrave(
            snapshot: snapshot,
            minimumMeasureCount: fixture.minimumMeasureCount
        )

        return FixtureRenderResult(
            chart: chart,
            prepared: prepared,
            engraved: engraving.engraved,
            resolvedInput: engraving.input,
            snapshot: snapshot,
            timeline: timeline,
            style: lockedStyle,
            container: container
        )
    }

    /// The test-side package engraving seam: the same expanded measure list
    /// `GameplayNotationPreparer.prepare` builds, the app-site
    /// `VirgoNotationProjection` conversion, then the package engraver —
    /// sharing the harness's locked style and overrides so goldens stay
    /// pinned. `NotationSnapshotTestSupport` reuses this seam for synthetic
    /// snapshots so both entry points engrave identically.
    /// Nonisolated: every call below is a pure value-type function.
    nonisolated static func engrave(
        snapshot: RhythmLayoutSnapshot,
        minimumMeasureCount: Int,
        style: NotationLayoutStyle = lockedStyle,
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition] = lockedOverrides
    ) throws -> (input: ResolvedNotationInput, engraved: EngravedNotation) {
        let expandedMeasures = GameplayNotationPreparer.expandedRhythmMeasures(
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
            NotationEngraver.engrave(
                input,
                style: VirgoNotationProjection.engravingStyle(for: style)
            )
        )
    }

    /// The `.ready` engraving out of a prepared state; throws otherwise so
    /// fixture tests fail with the state rather than an optional unwrap.
    nonisolated static func requireEngraved(
        _ prepared: GameplayNotationPreparedState
    ) throws -> EngravedNotation {
        guard case let .ready(engraved, _) = prepared else {
            throw DrumTabFixtureHarnessError.notationNotReady(prepared)
        }
        return engraved
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
