import SwiftData
import SwiftUI

@MainActor
final class ChartPracticeStateLoader: ObservableObject {
    typealias Resolver = @MainActor (Chart) -> ChartPracticeState

    @Published private(set) var state: ChartPracticeState

    private var loadedChartID: PersistentIdentifier?
    private let resolver: Resolver

    init(
        initialState: ChartPracticeState? = nil,
        resolver: Resolver? = nil
    ) {
        // Resolve defaults inside the initializer body rather than as default
        // argument expressions. Under Swift 6, default arguments are evaluated
        // in the caller's isolation context, so defaults that reference
        // `@MainActor`-isolated symbols (`.loading`, `ChartPracticeState.resolve`)
        // would warn or error. Materializing them here keeps the access on the
        // `@MainActor` initializer context. `resolver` is an optional closure,
        // which is implicitly escaping, so no `@escaping` annotation is needed.
        self.state = initialState ?? .loading
        self.resolver = resolver ?? { ChartPracticeState.resolve(chart: $0) }
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
