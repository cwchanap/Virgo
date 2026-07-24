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
    func repeatedLoadUsesCachedState() async {
        let chart = Chart(difficulty: .easy)
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
    func differentChartResolvesAgain() async {
        let first = Chart(difficulty: .easy)
        let second = Chart(difficulty: .hard)
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
    func timingFingerprintChangeReResolves() async {
        let chart = Chart(difficulty: .easy)
        var resolutionCount = 0
        let loader = ChartPracticeStateLoader { chart in
            resolutionCount += 1
            return ChartPracticeState.resolve(chart: chart)
        }

        await loader.load(chart: chart)
        #expect(resolutionCount == 1)

        // Simulate a rhythm backfill: mutate a timing-affecting field in place
        // without changing the chart's persistent identity.
        chart.timeSignature = .threeFour

        await loader.load(chart: chart)
        #expect(resolutionCount == 2, "Fingerprint change must trigger re-resolution")
    }

    @Test("notes mutation re-resolves via timingRevision bump")
    func notesMutationReResolves() async {
        let chart = Chart(difficulty: .easy)
        var resolutionCount = 0
        let loader = ChartPracticeStateLoader { chart in
            resolutionCount += 1
            return ChartPracticeState.resolve(chart: chart)
        }

        await loader.load(chart: chart)
        #expect(resolutionCount == 1)

        // Simulate a notes backfill: append a note and bump the revision.
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
    func timingFingerprintIsRelationshipFree() {
        // A chart with no song must produce a valid fingerprint without crashing.
        // The fingerprint must depend only on the chart-owned timingRevision
        // scalar, never on the Song relationship (which can fault during view
        // rendering). See P1: the old fingerprint read chart.timeSignature,
        // which falls back to song?.timeSignature.
        let chart = Chart(difficulty: .easy)
        let initialFingerprint = chart.timingFingerprint
        #expect(initialFingerprint.timingRevision == 0)

        chart.bumpTimingRevision()
        let bumpedFingerprint = chart.timingFingerprint
        #expect(bumpedFingerprint.timingRevision == 1)
        #expect(initialFingerprint != bumpedFingerprint)
    }
}
