import Foundation
import SwiftData
import Testing
@testable import Virgo

/// The rendered output of one fixture, plus the inputs later assertions need.
///
/// Carries `chart` because the playhead tests drive a real `GameplayViewModel`,
/// and `snapshot` because beat groups and engraving support live on
/// `RhythmMeasure` rather than on `RenderedMeasure`.
@MainActor
struct FixtureRenderResult {
    let chart: Chart
    let layout: NotationLayout
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
    static let lockedStyle = NotationLayoutStyle.gameplayDefault
        .with(rowWidth: GameplayLayout.maxRowWidth)

    static let lockedOverrides: [DrumType: GameplayLayout.NotePosition] =
        Dictionary(uniqueKeysWithValues: DrumType.allCases.map { ($0, $0.notePosition) })

    static func render(
        _ fixture: DrumTabFixture,
        includeControls: Bool = true
    ) throws -> FixtureRenderResult {
        let chartData = try DTXFileParser.parseChartMetadata(
            from: fixture.source(includeControls: includeControls)
        )
        let projection = try chartData.persistenceProjection()

        let container = TestContainer.isolatedContainer()
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

        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                timing: .timeline(snapshot),
                minimumMeasureCount: fixture.minimumMeasureCount,
                style: lockedStyle,
                notePositionOverrides: lockedOverrides
            )
        )

        return FixtureRenderResult(
            chart: chart,
            layout: layout,
            snapshot: snapshot,
            timeline: timeline,
            style: lockedStyle,
            container: container
        )
    }
}
