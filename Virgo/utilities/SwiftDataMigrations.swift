//
//  SwiftDataMigrations.swift
//  Virgo
//
//  Created by Claude Code on 4/8/2025.
//

import SwiftData
import Foundation

// MARK: - Migration from v1.0 to v2.0
// Adds ServerSong and ServerChart models
struct MigrateV1toV2: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }
    
    static var stages: [any MigrationStage.Type] {
        [MigrateV1toV2Stage.self]
    }
}

struct MigrateV1toV2Stage: MigrationStage {
    static var originalVersion = SchemaV1.self
    static var migratedVersion = SchemaV2.self
    
    static func willMigrate(context: ModelContext) throws {
        print("Starting migration from v1.0 to v2.0 - adding server models")
    }
    
    static func didMigrate(context: ModelContext) throws {
        print("Completed migration from v1.0 to v2.0")
    }
}

// MARK: - Migration from v2.0 to v2.1
// Adds BGM and preview audio support
struct MigrateV2toV21: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV2.self, SchemaV21.self]
    }
    
    static var stages: [any MigrationStage.Type] {
        [MigrateV2toV21Stage.self]
    }
}

struct MigrateV2toV21Stage: MigrationStage {
    static var originalVersion = SchemaV2.self
    static var migratedVersion = SchemaV21.self
    
    static func willMigrate(context: ModelContext) throws {
        print("Starting migration from v2.0 to v2.1 - adding BGM and preview support")
    }
    
    static func didMigrate(context: ModelContext) throws {
        print("Completed migration from v2.0 to v2.1 - BGM and preview fields added")
        
        // Initialize new BGM/preview fields to default values for existing records
        let songs = try context.fetch(FetchDescriptor<SchemaV21.Song>())
        for song in songs {
            if song.bgmFilePath == nil {
                song.bgmFilePath = nil // Explicitly set to nil for clarity
            }
            if song.previewFilePath == nil {
                song.previewFilePath = nil
            }
        }
        
        let serverSongs = try context.fetch(FetchDescriptor<SchemaV21.ServerSong>())
        for serverSong in serverSongs {
            if !serverSong.hasBGM {
                serverSong.hasBGM = false
                serverSong.bgmDownloaded = false
            }
            if !serverSong.hasPreview {
                serverSong.hasPreview = false
                serverSong.previewDownloaded = false
            }
        }
        
        try context.save()
    }
}

// MARK: - Schema Versions

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [Song.self, Chart.self, Note.self]
    }
    
    @Model
    final class Song {
        var title: String
        var artist: String
        var bpm: Int
        var duration: String
        var genre: String
        private var _timeSignature: TimeSignature?
        var isPlaying: Bool
        var dateAdded: Date
        var playCount: Int
        var isSaved: Bool = false
        @Relationship(deleteRule: .cascade, inverse: \Chart.song)
        var charts: [Chart]
        
        var timeSignature: TimeSignature {
            get { _timeSignature ?? .fourFour }
            set { _timeSignature = newValue }
        }
        
        init(title: String, artist: String, bpm: Int, duration: String, genre: String, 
             timeSignature: TimeSignature = .fourFour, charts: [Chart] = [], 
             isPlaying: Bool = false, playCount: Int = 0, isSaved: Bool = false) {
            self.title = title
            self.artist = artist
            self.bpm = bpm
            self.duration = duration
            self.genre = genre
            self._timeSignature = timeSignature
            self.charts = charts
            self.isPlaying = isPlaying
            self.dateAdded = Date()
            self.playCount = playCount
            self.isSaved = isSaved
        }
    }
    
    @Model
    final class Chart {
        var difficulty: Difficulty
        var level: Int = 50
        private var _timeSignature: TimeSignature?
        var song: Song?
        @Relationship(deleteRule: .cascade, inverse: \Note.chart)
        var notes: [Note]
        
        var timeSignature: TimeSignature {
            get { _timeSignature ?? (song?.timeSignature) ?? .fourFour }
            set { _timeSignature = newValue }
        }
        
        init(difficulty: Difficulty, level: Int? = nil, timeSignature: TimeSignature? = nil, 
             notes: [Note] = [], song: Song? = nil) {
            self.difficulty = difficulty
            self.level = level ?? difficulty.defaultLevel
            self._timeSignature = timeSignature
            self.notes = notes
            self.song = song
        }
    }
    
    @Model
    final class Note {
        var interval: NoteInterval
        var noteType: NoteType
        var measureNumber: Int
        var measureOffset: Double
        var chart: Chart?
        
        init(interval: NoteInterval, noteType: NoteType, measureNumber: Int, measureOffset: Double, chart: Chart? = nil) {
            self.interval = interval
            self.noteType = noteType
            self.measureNumber = measureNumber
            self.measureOffset = measureOffset
            self.chart = chart
        }
    }
}

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [Song.self, Chart.self, Note.self, ServerSong.self, ServerChart.self]
    }
    
    @Model
    final class Song {
        var title: String
        var artist: String
        var bpm: Int
        var duration: String
        var genre: String
        private var _timeSignature: TimeSignature?
        var isPlaying: Bool
        var dateAdded: Date
        var playCount: Int
        var isSaved: Bool = false
        @Relationship(deleteRule: .cascade, inverse: \Chart.song)
        var charts: [Chart]
        
        var timeSignature: TimeSignature {
            get { _timeSignature ?? .fourFour }
            set { _timeSignature = newValue }
        }
        
        init(title: String, artist: String, bpm: Int, duration: String, genre: String, 
             timeSignature: TimeSignature = .fourFour, charts: [Chart] = [], 
             isPlaying: Bool = false, playCount: Int = 0, isSaved: Bool = false) {
            self.title = title
            self.artist = artist
            self.bpm = bpm
            self.duration = duration
            self.genre = genre
            self._timeSignature = timeSignature
            self.charts = charts
            self.isPlaying = isPlaying
            self.dateAdded = Date()
            self.playCount = playCount
            self.isSaved = isSaved
        }
    }
    
    @Model
    final class Chart {
        var difficulty: Difficulty
        var level: Int = 50
        private var _timeSignature: TimeSignature?
        var song: Song?
        @Relationship(deleteRule: .cascade, inverse: \Note.chart)
        var notes: [Note]
        
        var timeSignature: TimeSignature {
            get { _timeSignature ?? (song?.timeSignature) ?? .fourFour }
            set { _timeSignature = newValue }
        }
        
        init(difficulty: Difficulty, level: Int? = nil, timeSignature: TimeSignature? = nil, 
             notes: [Note] = [], song: Song? = nil) {
            self.difficulty = difficulty
            self.level = level ?? difficulty.defaultLevel
            self._timeSignature = timeSignature
            self.notes = notes
            self.song = song
        }
    }
    
    @Model
    final class Note {
        var interval: NoteInterval
        var noteType: NoteType
        var measureNumber: Int
        var measureOffset: Double
        var chart: Chart?
        
        init(interval: NoteInterval, noteType: NoteType, measureNumber: Int, measureOffset: Double, chart: Chart? = nil) {
            self.interval = interval
            self.noteType = noteType
            self.measureNumber = measureNumber
            self.measureOffset = measureOffset
            self.chart = chart
        }
    }
    
    @Model
    final class ServerSong {
        var songId: String
        var title: String
        var artist: String
        var bpm: Double
        @Relationship(deleteRule: .cascade) var charts: [ServerChart]
        var lastUpdated: Date
        var isDownloaded: Bool
        
        init(songId: String, title: String, artist: String, bpm: Double, 
             charts: [ServerChart] = [], isDownloaded: Bool = false) {
            self.songId = songId
            self.title = title
            self.artist = artist
            self.bpm = bpm
            self.charts = charts
            self.lastUpdated = Date()
            self.isDownloaded = isDownloaded
        }
    }
    
    @Model
    final class ServerChart {
        var difficulty: String
        var difficultyLabel: String
        var level: Int
        var filename: String
        var size: Int
        var serverSong: ServerSong?
        
        init(difficulty: String, difficultyLabel: String, level: Int, 
             filename: String, size: Int, serverSong: ServerSong? = nil) {
            self.difficulty = difficulty
            self.difficultyLabel = difficultyLabel
            self.level = level
            self.filename = filename
            self.size = size
            self.serverSong = serverSong
        }
    }
}

enum SchemaV21: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 1, 0)
    
    static var models: [any PersistentModel.Type] {
        [Song.self, Chart.self, Note.self, ServerSong.self, ServerChart.self]
    }
    
    @Model
    final class Song {
        var title: String
        var artist: String
        var bpm: Int
        var duration: String
        var genre: String
        private var _timeSignature: TimeSignature?
        var isPlaying: Bool
        var dateAdded: Date
        var playCount: Int
        var isSaved: Bool = false
        var bgmFilePath: String?
        var previewFilePath: String?
        @Relationship(deleteRule: .cascade, inverse: \Chart.song)
        var charts: [Chart]
        
        var timeSignature: TimeSignature {
            get { _timeSignature ?? .fourFour }
            set { _timeSignature = newValue }
        }
        
        init(title: String, artist: String, bpm: Int, duration: String, genre: String, 
             timeSignature: TimeSignature = .fourFour, charts: [Chart] = [], 
             isPlaying: Bool = false, playCount: Int = 0, isSaved: Bool = false,
             bgmFilePath: String? = nil, previewFilePath: String? = nil) {
            self.title = title
            self.artist = artist
            self.bpm = bpm
            self.duration = duration
            self.genre = genre
            self._timeSignature = timeSignature
            self.charts = charts
            self.isPlaying = isPlaying
            self.dateAdded = Date()
            self.playCount = playCount
            self.isSaved = isSaved
            self.bgmFilePath = bgmFilePath
            self.previewFilePath = previewFilePath
        }
    }
    
    @Model
    final class Chart {
        var difficulty: Difficulty
        var level: Int = 50
        private var _timeSignature: TimeSignature?
        var song: Song?
        @Relationship(deleteRule: .cascade, inverse: \Note.chart)
        var notes: [Note]
        
        var timeSignature: TimeSignature {
            get { _timeSignature ?? (song?.timeSignature) ?? .fourFour }
            set { _timeSignature = newValue }
        }
        
        init(difficulty: Difficulty, level: Int? = nil, timeSignature: TimeSignature? = nil, 
             notes: [Note] = [], song: Song? = nil) {
            self.difficulty = difficulty
            self.level = level ?? difficulty.defaultLevel
            self._timeSignature = timeSignature
            self.notes = notes
            self.song = song
        }
    }
    
    @Model
    final class Note {
        var interval: NoteInterval
        var noteType: NoteType
        var measureNumber: Int
        var measureOffset: Double
        var chart: Chart?
        
        init(interval: NoteInterval, noteType: NoteType, measureNumber: Int, measureOffset: Double, chart: Chart? = nil) {
            self.interval = interval
            self.noteType = noteType
            self.measureNumber = measureNumber
            self.measureOffset = measureOffset
            self.chart = chart
        }
    }
    
    @Model
    final class ServerSong {
        var songId: String
        var title: String
        var artist: String
        var bpm: Double
        @Relationship(deleteRule: .cascade) var charts: [ServerChart]
        var lastUpdated: Date
        var isDownloaded: Bool
        var hasBGM: Bool = false
        var bgmDownloaded: Bool = false
        var hasPreview: Bool = false
        var previewDownloaded: Bool = false
        
        init(songId: String, title: String, artist: String, bpm: Double, 
             charts: [ServerChart] = [], isDownloaded: Bool = false,
             hasBGM: Bool = false, bgmDownloaded: Bool = false,
             hasPreview: Bool = false, previewDownloaded: Bool = false) {
            self.songId = songId
            self.title = title
            self.artist = artist
            self.bpm = bpm
            self.charts = charts
            self.lastUpdated = Date()
            self.isDownloaded = isDownloaded
            self.hasBGM = hasBGM
            self.bgmDownloaded = bgmDownloaded
            self.hasPreview = hasPreview
            self.previewDownloaded = previewDownloaded
        }
    }
    
    @Model
    final class ServerChart {
        var difficulty: String
        var difficultyLabel: String
        var level: Int
        var filename: String
        var size: Int
        var serverSong: ServerSong?
        
        init(difficulty: String, difficultyLabel: String, level: Int, 
             filename: String, size: Int, serverSong: ServerSong? = nil) {
            self.difficulty = difficulty
            self.difficultyLabel = difficultyLabel
            self.level = level
            self.filename = filename
            self.size = size
            self.serverSong = serverSong
        }
    }
}