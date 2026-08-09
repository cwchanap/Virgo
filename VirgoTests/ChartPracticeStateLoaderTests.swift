import SwiftData
import Testing
@testable import Virgo

@Suite("Chart Practice State Loader Tests")
@MainActor
struct ChartPracticeStateLoaderTests {
    @Test("loader starts unresolved and disables practice")
    func initialStateIsLoading() {
        let loader = ChartPracticeStateLoader()

        #expect(loader.state == .loading)
        #expect(loader.state.isResolved == false)
        #expect(loader.state.isPracticeEnabled == false)
    }

    @Test("loading the same chart resolves only once")
    func repeatedLoadUsesCachedState() async throws {
        let context = TestContainer.isolatedContainer().context
        let chart = Chart(difficulty: .easy)
        context.insert(chart)
        try context.save()
        var resolutionCount = 0
        let loader = ChartPracticeStateLoader { chart in
            resolutionCount += 1
            return ChartPracticeState.resolve(chart: chart)
        }

        await loader.load(chart: chart)
        await loader.load(chart: chart)

        #expect(resolutionCount == 1)
        #expect(loader.state.isResolved)
        #expect(loader.state.isPracticeEnabled)
    }

    @Test("loading a different chart invalidates the cached identity")
    func differentChartResolvesAgain() async throws {
        let context = TestContainer.isolatedContainer().context
        let first = Chart(difficulty: .easy)
        let second = Chart(difficulty: .hard)
        context.insert(first)
        context.insert(second)
        try context.save()
        var resolutionCount = 0
        let loader = ChartPracticeStateLoader { chart in
            resolutionCount += 1
            return ChartPracticeState.resolve(chart: chart)
        }

        await loader.load(chart: first)
        await loader.load(chart: second)

        #expect(resolutionCount == 2)
        #expect(loader.state.isResolved)
    }

    @Test("in-place timing mutation re-resolves even when the persistent ID is unchanged")
    func timingFingerprintChangeReResolves() async throws {
        let context = TestContainer.isolatedContainer().context
        let chart = Chart(difficulty: .easy)
        context.insert(chart)
        try context.save()
        var resolutionCount = 0
        let loader = ChartPracticeStateLoader { chart in
            resolutionCount += 1
            return ChartPracticeState.resolve(chart: chart)
        }

        await loader.load(chart: chart)
        #expect(resolutionCount == 1)

        // Simulate an in-place timing mutation: change a timing-affecting field
        // without changing the chart's persistent identity.
        chart.timeSignature = .threeFour

        await loader.load(chart: chart)
        #expect(resolutionCount == 2, "Fingerprint change must trigger re-resolution")
    }

    @Test("notes mutation re-resolves via timingRevision bump")
    func notesMutationReResolves() async throws {
        let context = TestContainer.isolatedContainer().context
        let chart = Chart(difficulty: .easy)
        context.insert(chart)
        try context.save()
        var resolutionCount = 0
        let loader = ChartPracticeStateLoader { chart in
            resolutionCount += 1
            return ChartPracticeState.resolve(chart: chart)
        }

        await loader.load(chart: chart)
        #expect(resolutionCount == 1)

        // Simulate an in-place note mutation: append a note and bump the revision.
        chart.notes.append(Note(
            interval: .quarter,
            noteType: .bass,
            measureNumber: 1,
            measureOffset: 0.0
        ))
        chart.bumpTimingRevision()

        await loader.load(chart: chart)
        #expect(resolutionCount == 2, "Notes mutation must trigger re-resolution")
    }

    @Test("timingFingerprint is relationship-free and does not fault the Song")
    func timingFingerprintIsRelationshipFree() async throws {
        // A chart with no song must produce a valid fingerprint without crashing.
        // The fingerprint must depend only on the chart-owned timingRevision
        // scalar, never on the Song relationship (which can fault during view
        // rendering). See P1: the old fingerprint read chart.timeSignature,
        // which falls back to song?.timeSignature.
        let context = TestContainer.isolatedContainer().context
        let chart = Chart(difficulty: .easy)
        context.insert(chart)
        try context.save()

        let initialFingerprint = chart.timingFingerprint
        #expect(initialFingerprint.timingRevision == 0)

        chart.bumpTimingRevision()
        let bumpedFingerprint = chart.timingFingerprint
        #expect(bumpedFingerprint.timingRevision == 1)
        #expect(initialFingerprint != bumpedFingerprint)

        // Strengthen relationship-independence: create a Song whose
        // timeSignature the chart falls back to (chart has no own
        // _timeSignature), persist both, then mutate the Song's timeSignature.
        // If the fingerprint traversed the Song relationship (as the old
        // chart.timeSignature-based fingerprint did), it would change. Since
        // it reads only the chart-owned timingRevision scalar, it must not.
        let song = Song(
            title: "Fingerprint Probe",
            artist: "Test",
            bpm: 120.0,
            duration: "1:00",
            genre: "Test",
            timeSignature: .fourFour
        )
        let relationshipChart = Chart(difficulty: .easy, song: song)
        song.charts = [relationshipChart]
        context.insert(song)
        context.insert(relationshipChart)
        try context.save()

        // Sanity: the chart falls back to the song's timeSignature because
        // the chart's own _timeSignature is nil.
        #expect(relationshipChart.timeSignature == .fourFour)

        let beforeSongMutation = relationshipChart.timingFingerprint

        // Mutate the Song's timeSignature. This changes
        // relationshipChart.timeSignature (the fallback) but must NOT change
        // the fingerprint, which reads only timingRevision.
        song.timeSignature = .threeFour
        try context.save()

        #expect(relationshipChart.timeSignature == .threeFour,
                "chart.timeSignature must reflect the mutated song timeSignature")
        let afterSongMutation = relationshipChart.timingFingerprint
        #expect(afterSongMutation == beforeSongMutation,
                "Fingerprint must not change when only the Song relationship changes")
    }
}
