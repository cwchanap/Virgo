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
}
