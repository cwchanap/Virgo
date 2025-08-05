//
//  SwiftDataRelationshipLoader.swift
//  Virgo
//
//  Created by Claude Code on 4/8/2025.
//

import SwiftUI
import SwiftData

// MARK: - SwiftData Relationship Loading Protocol
protocol SwiftDataRelationshipLoader: ObservableObject {
    associatedtype ModelType: PersistentModel
    associatedtype RelationshipData
    
    var model: ModelType { get }
    var relationshipData: RelationshipData { get set }
    var isLoading: Bool { get set }
    
    func loadRelationshipData() async -> RelationshipData
    func startObserving()
    func stopObserving()
}

// MARK: - Base Relationship Loader
@MainActor
class BaseSwiftDataRelationshipLoader<Model: PersistentModel, Data>: ObservableObject {
    @Published var relationshipData: Data
    @Published var isLoading: Bool = false
    
    let model: Model
    private let dataLoader: (Model) async -> Data
    private let defaultData: Data
    
    private var loadingTask: Task<Void, Never>?
    
    init(
        model: Model,
        defaultData: Data,
        dataLoader: @escaping (Model) async -> Data
    ) {
        self.model = model
        self.defaultData = defaultData
        self.relationshipData = defaultData
        self.dataLoader = dataLoader
        
        startObserving()
    }
    
    deinit {
        Task { @MainActor in
            self.stopObserving()
        }
    }
    
    func startObserving() {
        // Load initial data
        Task {
            await loadRelationshipData()
        }
    }
    
    func stopObserving() {
        loadingTask?.cancel()
        loadingTask = nil
    }
    
    func loadRelationshipData() async {
        // Cancel any existing loading task
        loadingTask?.cancel()
        
        loadingTask = Task {
            await MainActor.run {
                isLoading = true
            }
            
            // Perform the data loading operation
            let newData = await dataLoader(model)
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.relationshipData = newData
                self.isLoading = false
            }
        }
        
        await loadingTask?.value
    }
    
    func refresh() {
        Task {
            await loadRelationshipData()
        }
    }
}

// MARK: - Song Relationship Loader
struct SongRelationshipData {
    let chartCount: Int
    let measureCount: Int
    let charts: [Chart]
    let availableDifficulties: [Difficulty]
}

@MainActor
class SongRelationshipLoader: BaseSwiftDataRelationshipLoader<Song, SongRelationshipData> {
    convenience init(song: Song) {
        self.init(
            model: song,
            defaultData: SongRelationshipData(
                chartCount: 0,
                measureCount: 1,
                charts: [],
                availableDifficulties: []
            ),
            dataLoader: { song in
                await Self.loadSongData(song)
            }
        )
    }
    
    private static func loadSongData(_ song: Song) async -> SongRelationshipData {
        // Access SwiftData relationships on MainActor to prevent data races
        return await MainActor.run {
            let validCharts = song.charts.filter { !$0.isDeleted }
            let measureCount = calculateMeasureCount(from: validCharts)
            let difficulties = validCharts.compactMap { $0.difficulty }
                .removingDuplicates()
                .sorted { $0.sortOrder < $1.sortOrder }
            
            return SongRelationshipData(
                chartCount: validCharts.count,
                measureCount: measureCount,
                charts: validCharts,
                availableDifficulties: difficulties
            )
        }
    }
    
    private static func calculateMeasureCount(from charts: [Chart]) -> Int {
        // Access notes relationships safely - charts are already loaded on main thread
        let allNotes = charts.flatMap { chart in
            chart.notes.filter { !$0.isDeleted }
        }
        return allNotes.map(\.measureNumber).max() ?? 1
    }
}

// MARK: - Chart Relationship Loader
struct ChartRelationshipData {
    let notesCount: Int
    let notes: [Note]
    let measureCount: Int
}

@MainActor
class ChartRelationshipLoader: BaseSwiftDataRelationshipLoader<Chart, ChartRelationshipData> {
    convenience init(chart: Chart) {
        self.init(
            model: chart,
            defaultData: ChartRelationshipData(
                notesCount: 0,
                notes: [],
                measureCount: 1
            ),
            dataLoader: { chart in
                await Self.loadChartData(chart)
            }
        )
    }
    
    private static func loadChartData(_ chart: Chart) async -> ChartRelationshipData {
        // Access SwiftData relationships on MainActor to prevent data races
        return await MainActor.run {
            let validNotes = chart.notes.filter { !$0.isDeleted }
            let measureCount = validNotes.map(\.measureNumber).max() ?? 1
            
            return ChartRelationshipData(
                notesCount: validNotes.count,
                notes: validNotes,
                measureCount: measureCount
            )
        }
    }
}

// MARK: - View Modifier for Relationship Loading
struct SwiftDataRelationshipModifier<Model: PersistentModel, Data, Loader: BaseSwiftDataRelationshipLoader<Model, Data>>: ViewModifier {
    @StateObject private var loader: Loader
    let onDataLoaded: (Data) -> Void
    
    init(
        loader: @autoclosure @escaping () -> Loader,
        onDataLoaded: @escaping (Data) -> Void
    ) {
        self._loader = StateObject(wrappedValue: loader())
        self.onDataLoaded = onDataLoaded
    }
    
    func body(content: Content) -> some View {
        content
            .onReceive(loader.$relationshipData) { data in
                onDataLoaded(data)
            }
            .onAppear {
                Task {
                    await loader.loadRelationshipData()
                }
            }
    }
}

// MARK: - View Extensions
extension View {
    func loadSongRelationships(
        for song: Song,
        onDataLoaded: @escaping (SongRelationshipData) -> Void
    ) -> some View {
        modifier(SwiftDataRelationshipModifier(
            loader: SongRelationshipLoader(song: song),
            onDataLoaded: onDataLoaded
        ))
    }
    
    func loadChartRelationships(
        for chart: Chart,
        onDataLoaded: @escaping (ChartRelationshipData) -> Void
    ) -> some View {
        modifier(SwiftDataRelationshipModifier(
            loader: ChartRelationshipLoader(chart: chart),
            onDataLoaded: onDataLoaded
        ))
    }
}

// MARK: - Helper Extensions
extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}