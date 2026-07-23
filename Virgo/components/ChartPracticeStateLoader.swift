import SwiftData
import SwiftUI

@MainActor
final class ChartPracticeStateLoader: ObservableObject {
    typealias Resolver = @MainActor (Chart) -> ChartPracticeState

    @Published private(set) var state: ChartPracticeState

    private var loadedChartID: PersistentIdentifier?
    private let resolver: Resolver

    init(
        initialState: ChartPracticeState = .loading,
        resolver: @escaping Resolver = { ChartPracticeState.resolve(chart: $0) }
    ) {
        self.state = initialState
        self.resolver = resolver
    }

    func load(chart: Chart) async {
        let chartID = chart.persistentModelID
        guard loadedChartID != chartID else { return }

        let initialState = ChartPracticeState.initial(chart: chart)
        if initialState.isResolved {
            state = initialState
            loadedChartID = chartID
            return
        }

        state = .loading
        await Task.yield()
        guard !Task.isCancelled else { return }

        let resolvedState = resolver(chart)
        guard !Task.isCancelled else { return }

        state = resolvedState
        loadedChartID = chartID
    }
}
