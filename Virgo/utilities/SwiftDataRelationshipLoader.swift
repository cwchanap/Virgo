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
        // Avoid scheduling async work that captures a deallocating instance.
        // Synchronously cancel any in-flight task during teardown.
        loadingTask?.cancel()
        loadingTask = nil
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

    static let empty = SongRelationshipData(
        chartCount: 0,
        measureCount: 1,
        charts: [],
        availableDifficulties: []
    )
}

@MainActor
class SongRelationshipLoader: BaseSwiftDataRelationshipLoader<Song, SongRelationshipData> {
    convenience init(song: Song) {
        self.init(
            model: song,
            defaultData: .empty,
            dataLoader: { song in
                await Self.loadSongData(song)
            }
        )
    }

    private static func loadSongData(_ song: Song) async -> SongRelationshipData {
        // Access SwiftData relationships on MainActor to prevent data races
        await MainActor.run {
            relationshipData(for: song)
        }
    }

    static func relationshipData(for song: Song) -> SongRelationshipData {
        guard isModelAvailable(song) else { return .empty }

        let validCharts = song.charts.filter { isModelAvailable($0) }
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

    static func isModelAvailable(_ song: Song) -> Bool {
        guard !isDetachedPersistentModel(song), !song.isDeleted else { return false }
        return true
    }

    static func isModelAvailable(_ chart: Chart) -> Bool {
        guard !isDetachedPersistentModel(chart), !chart.isDeleted else { return false }
        return true
    }

    static func isModelAvailable(_ note: Note) -> Bool {
        guard !isDetachedPersistentModel(note), !note.isDeleted else { return false }
        return true
    }

    static func isModelAvailable(_ serverSong: ServerSong) -> Bool {
        guard !isDetachedPersistentModel(serverSong), !serverSong.isDeleted else { return false }
        return true
    }

    static func isModelAvailable(_ serverChart: ServerChart) -> Bool {
        guard !isDetachedPersistentModel(serverChart), !serverChart.isDeleted else { return false }
        return true
    }

    private static func calculateMeasureCount(from charts: [Chart]) -> Int {
        // Access notes relationships safely - charts are already loaded on main thread
        let allNotes = charts.flatMap { chart in
            chart.notes.filter { isModelAvailable($0) }
        }
        return allNotes.map(\.measureNumber).max() ?? 1
    }

    private static func isDetachedPersistentModel<T: PersistentModel>(_ model: T) -> Bool {
        model.modelContext == nil && !isTemporaryIdentifier(model.persistentModelID)
    }

    private static func isTemporaryIdentifier(_ identifier: PersistentIdentifier) -> Bool {
        guard let data = try? JSONEncoder().encode(identifier),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return true
        }

        return findIsTemporary(in: object) ?? true
    }

    private static func findIsTemporary(in object: Any) -> Bool? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                if key == "isTemporary", let isTemporary = value as? Bool {
                    return isTemporary
                }
                if let nested = findIsTemporary(in: value) {
                    return nested
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let nested = findIsTemporary(in: value) {
                    return nested
                }
            }
        }

        return nil
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
            guard SongRelationshipLoader.isModelAvailable(chart) else {
                return ChartRelationshipData(
                    notesCount: 0,
                    notes: [],
                    measureCount: 1
                )
            }

            let validNotes = chart.notes.filter { SongRelationshipLoader.isModelAvailable($0) }
            let measureCount = validNotes.map(\.measureNumber).max() ?? 1

            return ChartRelationshipData(
                notesCount: validNotes.count,
                notes: validNotes,
                measureCount: measureCount
            )
        }
    }
}

// MARK: - Server Song Relationship Loader
struct ServerSongRelationshipData {
    let totalSize: Int
    let levelText: String?
    let difficultyChips: [DifficultyChip]

    static let empty = ServerSongRelationshipData(
        totalSize: 0,
        levelText: nil,
        difficultyChips: []
    )
}

@MainActor
class ServerSongRelationshipLoader: BaseSwiftDataRelationshipLoader<ServerSong, ServerSongRelationshipData> {
    convenience init(serverSong: ServerSong) {
        // Compute the initial snapshot synchronously so the first render
        // already carries level/size/chip data (avoids an empty-state flash
        // and lets synchronous test harnesses observe the populated values).
        // `relationshipData(for:)` is a MainActor-safe synchronous call.
        let initial = Self.relationshipData(for: serverSong)
        self.init(
            model: serverSong,
            defaultData: initial,
            dataLoader: { serverSong in
                await Self.loadServerSongData(serverSong)
            }
        )
    }

    private static func loadServerSongData(_ serverSong: ServerSong) async -> ServerSongRelationshipData {
        await MainActor.run {
            relationshipData(for: serverSong)
        }
    }

    static func relationshipData(for serverSong: ServerSong) -> ServerSongRelationshipData {
        guard SongRelationshipLoader.isModelAvailable(serverSong) else { return .empty }

        let charts = serverSong.charts.filter { SongRelationshipLoader.isModelAvailable($0) }
        let totalSize = charts.reduce(0) { $0 + $1.size }
        let levelText: String?
        if charts.count > 1 {
            let levels = charts.map { String($0.level) }.joined(separator: ", ")
            levelText = "Levels \(levels)"
        } else if let chart = charts.first {
            levelText = "Level \(chart.level)"
        } else {
            levelText = nil
        }
        let difficultyChips: [DifficultyChip] = charts.count > 1
            ? charts.map { DifficultyChip(label: $0.difficultyLabel, level: $0.level) }
            : []

        return ServerSongRelationshipData(
            totalSize: totalSize,
            levelText: levelText,
            difficultyChips: difficultyChips
        )
    }
}

// MARK: - View Modifier for Relationship Loading
struct SwiftDataRelationshipModifier<
    Model: PersistentModel,
    Data,
    Loader: BaseSwiftDataRelationshipLoader<Model, Data>
>: ViewModifier {
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

    func loadServerSongRelationships(
        for serverSong: ServerSong,
        onDataLoaded: @escaping (ServerSongRelationshipData) -> Void
    ) -> some View {
        modifier(SwiftDataRelationshipModifier(
            loader: ServerSongRelationshipLoader(serverSong: serverSong),
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
