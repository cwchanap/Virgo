import Foundation
import SwiftData

@MainActor
class ServerSongService: ObservableObject {
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    
    private let apiClient = DTXAPIClient()
    private var modelContext: ModelContext?
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Public API
    
    func loadServerSongs() async -> [ServerSong] {
        guard let modelContext = modelContext else { return [] }
        
        // First load from cache
        let descriptor = FetchDescriptor<ServerSong>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        
        do {
            let cachedSongs = try modelContext.fetch(descriptor)
            
            // If cache is empty or stale (older than 1 hour), refresh from server
            let oneHourAgo = Date().addingTimeInterval(-3600)
            let shouldRefresh = cachedSongs.isEmpty || 
                               cachedSongs.first?.lastUpdated ?? Date.distantPast < oneHourAgo
            
            if shouldRefresh {
                await refreshServerSongs()
                return try modelContext.fetch(descriptor)
            }
            
            return cachedSongs
        } catch {
            print("Failed to load server songs from cache: \(error)")
            return []
        }
    }
    
    func refreshServerSongs() async {
        guard let modelContext = modelContext else { return }
        
        isRefreshing = true
        errorMessage = nil
        
        do {
            // Fetch file list from server
            let serverFiles = try await apiClient.listDTXFiles()
            
            // Get metadata for each file
            var updatedSongs: [ServerSong] = []
            
            for file in serverFiles {
                do {
                    let metadata = try await apiClient.getDTXMetadata(filename: file.filename)
                    
                    let serverSong = ServerSong(
                        filename: file.filename,
                        title: metadata.title ?? file.filename.replacingOccurrences(of: ".dtx", with: ""),
                        artist: metadata.artist ?? "Unknown Artist",
                        bpm: metadata.bpm ?? 120.0,
                        difficultyLevel: metadata.level ?? 50,
                        size: file.size
                    )
                    
                    updatedSongs.append(serverSong)
                } catch {
                    print("Failed to get metadata for \(file.filename): \(error)")
                    // Create song with filename only
                    let serverSong = ServerSong(
                        filename: file.filename,
                        title: file.filename.replacingOccurrences(of: ".dtx", with: ""),
                        artist: "Unknown Artist",
                        bpm: 120.0,
                        difficultyLevel: 50,
                        size: file.size
                    )
                    updatedSongs.append(serverSong)
                }
            }
            
            // Clear existing cache and save new data
            let existingDescriptor = FetchDescriptor<ServerSong>()
            let existingSongs = try modelContext.fetch(existingDescriptor)
            
            for song in existingSongs {
                modelContext.delete(song)
            }
            
            for song in updatedSongs {
                modelContext.insert(song)
            }
            
            try modelContext.save()
            
        } catch {
            errorMessage = "Failed to refresh server songs: \(error.localizedDescription)"
            print("Failed to refresh server songs: \(error)")
        }
        
        isRefreshing = false
    }
    
    func downloadAndImportSong(_ serverSong: ServerSong) async -> Bool {
        guard let modelContext = modelContext else { return false }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Download the file
            let fileData = try await apiClient.downloadDTXFile(filename: serverSong.filename)
            
            // Convert data to string with Shift-JIS encoding
            guard let dtxContent = String(data: fileData, encoding: .shiftJIS) else {
                throw DTXAPIError.decodingError
            }
            
            // Parse the DTX content
            let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)
            
            // Create Song and Chart objects
            let song = Song(
                title: chartData.title,
                artist: chartData.artist,
                bpm: Int(chartData.bpm),
                duration: formatDuration(calculateDuration(from: chartData.notes)),
                genre: "DTX Import",
                timeSignature: chartData.toTimeSignature()
            )
            
            let chart = Chart(
                difficulty: chartData.toDifficulty(),
                song: song
            )
            
            // Add notes to the chart
            let notes = chartData.toNotes(for: chart)
            notes.forEach { note in
                chart.notes.append(note)
            }
            
            // Save to SwiftData
            modelContext.insert(song)
            modelContext.insert(chart)
            
            // Update ServerSong to mark as downloaded
            serverSong.isDownloaded = true
            
            try modelContext.save()
            isLoading = false
            return true
            
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateDuration(from notes: [DTXNote]) -> TimeInterval {
        guard !notes.isEmpty else { return 60.0 }
        
        let maxMeasure = notes.map(\.measureNumber).max() ?? 0
        let estimatedMeasures = maxMeasure + 1
        
        // Estimate duration based on 4/4 time signature and average BPM
        let measuresPerMinute = 30.0 // Assuming ~120 BPM average
        return Double(estimatedMeasures) / measuresPerMinute * 60.0
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
