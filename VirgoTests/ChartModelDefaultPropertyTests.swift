//
//  ChartModelDefaultPropertyTests.swift
//  VirgoTests
//
//  Tests for Chart and Song model computed properties, default values,
//  explicit level initialisation, timeSignature setter, difficultyColor,
//  ServerSong legacy convenience init, and static sampleData properties.
//

import Testing
import SwiftUI
import SwiftData
@testable import Virgo

// MARK: - Chart Computed Properties

@Suite("Chart Computed Property Tests")
struct ChartComputedPropertyTests {

    // A shared in-memory container so we can insert models when needed.
    static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: Song.self, Chart.self, Note.self,
                                   ServerSong.self, ServerChart.self,
                                   configurations: config)
    }()

    // MARK: - Defaults when song == nil

    @Test("Chart.title returns 'Unknown Song' when song is nil")
    func testTitleDefaultWhenSongIsNil() {
        let chart = Chart(difficulty: .medium)
        #expect(chart.title == "Unknown Song")
    }

    @Test("Chart.artist returns 'Unknown Artist' when song is nil")
    func testArtistDefaultWhenSongIsNil() {
        let chart = Chart(difficulty: .easy)
        #expect(chart.artist == "Unknown Artist")
    }

    @Test("Chart.bpm returns 120.0 when song is nil")
    func testBPMDefaultWhenSongIsNil() {
        let chart = Chart(difficulty: .hard)
        #expect(chart.bpm == 120.0)
    }

    @Test("Chart.duration returns '0:00' when song is nil")
    func testDurationDefaultWhenSongIsNil() {
        let chart = Chart(difficulty: .expert)
        #expect(chart.duration == "0:00")
    }

    @Test("Chart.genre returns 'Unknown' when song is nil")
    func testGenreDefaultWhenSongIsNil() {
        let chart = Chart(difficulty: .medium)
        #expect(chart.genre == "Unknown")
    }

    // MARK: - Properties delegate to song when present

    @Test("Chart convenience properties delegate to its song")
    func testChartPropertiesDelegateToSong() {
        let song = Song(
            title: "Delegate Test",
            artist: "Delegation Artist",
            bpm: 160.0,
            duration: "5:00",
            genre: "Progressive"
        )
        let chart = Chart(difficulty: .hard, song: song)
        #expect(chart.title == "Delegate Test")
        #expect(chart.artist == "Delegation Artist")
        #expect(chart.bpm == 160.0)
        #expect(chart.duration == "5:00")
        #expect(chart.genre == "Progressive")
    }

    // MARK: - level initialisation

    @Test("Chart level uses difficulty.defaultLevel when nil is passed")
    func testChartLevelUsesDefaultLevelWhenNil() {
        #expect(Chart(difficulty: .easy).level == 30)   // easy.defaultLevel
        #expect(Chart(difficulty: .medium).level == 50) // medium.defaultLevel
        #expect(Chart(difficulty: .hard).level == 70)   // hard.defaultLevel
        #expect(Chart(difficulty: .expert).level == 90) // expert.defaultLevel
    }

    @Test("Chart level uses explicit value when provided")
    func testChartLevelUsesExplicitValue() {
        let chart = Chart(difficulty: .medium, level: 65)
        #expect(chart.level == 65)
    }

    @Test("Chart level accepts 0 as explicit override")
    func testChartLevelZeroOverride() {
        let chart = Chart(difficulty: .easy, level: 0)
        #expect(chart.level == 0)
    }

    @Test("Chart level accepts maximum value")
    func testChartLevelMaximum() {
        let chart = Chart(difficulty: .expert, level: 99)
        #expect(chart.level == 99)
    }

    // MARK: - timeSignature getter and setter

    @Test("Chart.timeSignature falls back to .fourFour when no song and no explicit signature")
    func testTimeSignatureFallbackToFourFour() {
        let chart = Chart(difficulty: .medium)
        // _timeSignature is nil and song is nil → default .fourFour
        #expect(chart.timeSignature == .fourFour)
    }

    @Test("Chart.timeSignature returns explicit value when set via init")
    func testTimeSignatureFromInit() {
        let chart = Chart(difficulty: .medium, timeSignature: .threeFour)
        #expect(chart.timeSignature == .threeFour)
    }

    @Test("Chart.timeSignature setter stores the new value")
    func testTimeSignatureSetter() {
        let chart = Chart(difficulty: .medium)
        chart.timeSignature = .sixEight
        #expect(chart.timeSignature == .sixEight)
    }

    @Test("Chart.timeSignature setter can overwrite a previously set value")
    func testTimeSignatureSetterOverwrite() {
        let chart = Chart(difficulty: .medium, timeSignature: .threeFour)
        chart.timeSignature = .fiveFour
        #expect(chart.timeSignature == .fiveFour)
    }

    @Test("Chart.timeSignature reads song's timeSignature when chart has none")
    func testTimeSignatureInheritedFromSong() {
        let song = Song(
            title: "T", artist: "A", bpm: 120,
            duration: "3:00", genre: "Rock",
            timeSignature: .sixEight
        )
        let chart = Chart(difficulty: .medium, song: song)
        // chart._timeSignature is nil → falls through to song?.timeSignature
        #expect(chart.timeSignature == .sixEight)
    }

    // MARK: - difficultyColor

    @Test("Chart.difficultyColor matches its Difficulty.color")
    func testDifficultyColor() {
        #expect(Chart(difficulty: .easy).difficultyColor == Color.green)
        #expect(Chart(difficulty: .medium).difficultyColor == Color.orange)
        #expect(Chart(difficulty: .hard).difficultyColor == Color.red)
        #expect(Chart(difficulty: .expert).difficultyColor == Color.purple)
    }

    // MARK: - notesCount and safeNotes

    @Test("Chart.notesCount counts non-deleted notes")
    func testNotesCountWithNotes() {
        let note1 = Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0)
        let note2 = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.25)
        let chart = Chart(difficulty: .medium, notes: [note1, note2])
        #expect(chart.notesCount == 2)
    }

    @Test("Chart.notesCount returns 0 for empty notes")
    func testNotesCountEmpty() {
        let chart = Chart(difficulty: .medium)
        #expect(chart.notesCount == 0)
    }

    @Test("Chart.safeNotes returns all notes when none are deleted")
    func testSafeNotesNoDeleted() {
        let note1 = Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.0)
        let note2 = Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.125)
        let chart = Chart(difficulty: .easy, notes: [note1, note2])
        #expect(chart.safeNotes.count == 2)
    }

    @Test("Chart.safeNotes returns empty array for chart with no notes")
    func testSafeNotesEmpty() {
        let chart = Chart(difficulty: .easy)
        #expect(chart.safeNotes.isEmpty)
    }
}

// MARK: - Song Computed Properties

@Suite("Song Computed Property Tests")
struct SongComputedPropertyTests {

    // MARK: - timeSignature

    @Test("Song.timeSignature defaults to .fourFour when not explicitly provided")
    func testTimeSignatureDefaultsFourFour() {
        let song = Song(title: "T", artist: "A", bpm: 120, duration: "3:00", genre: "Rock")
        #expect(song.timeSignature == .fourFour)
    }

    @Test("Song.timeSignature stores explicit value from init")
    func testTimeSignatureExplicitFromInit() {
        let song = Song(
            title: "T", artist: "A", bpm: 120, duration: "3:00",
            genre: "Rock", timeSignature: .sevenEight
        )
        #expect(song.timeSignature == .sevenEight)
    }

    @Test("Song.timeSignature setter can update value after init")
    func testTimeSignatureSetter() {
        let song = Song(title: "T", artist: "A", bpm: 120, duration: "3:00", genre: "Rock")
        song.timeSignature = .nineEight
        #expect(song.timeSignature == .nineEight)
    }

    // MARK: - Song.chart(for:)

    @Test("Song.chart(for:) returns chart matching requested difficulty")
    func testChartForDifficulty() {
        let song = Song(title: "T", artist: "A", bpm: 120, duration: "3:00", genre: "Rock")
        let easy = Chart(difficulty: .easy, song: song)
        let hard = Chart(difficulty: .hard, song: song)
        song.charts = [easy, hard]

        #expect(song.chart(for: .easy) === easy)
        #expect(song.chart(for: .hard) === hard)
        #expect(song.chart(for: .expert) == nil)
        #expect(song.chart(for: .medium) == nil)
    }

    @Test("Song.chart(for:) returns nil when charts array is empty")
    func testChartForDifficultyEmptyCharts() {
        let song = Song(title: "T", artist: "A", bpm: 120, duration: "3:00", genre: "Rock")
        #expect(song.chart(for: .easy) == nil)
    }

    // MARK: - Song.sampleData

    @Test("Song.sampleData returns 7 songs")
    func testSampleDataCount() {
        let samples = Song.sampleData
        #expect(samples.count == 7)
    }

    @Test("Song.sampleData first song is Thunder Beat with expected properties")
    func testSampleDataFirstSong() {
        let first = Song.sampleData[0]
        #expect(first.title == "Thunder Beat")
        #expect(first.artist == "Rock Masters")
        #expect(first.bpm == 140.0)
        #expect(first.genre == "Rock")
    }

    @Test("Song.sampleData all songs have at least one chart")
    func testSampleDataAllSongsHaveCharts() {
        for song in Song.sampleData {
            #expect(!song.charts.isEmpty, "Song \(song.title) has no charts")
        }
    }

    @Test("Song.sampleData progressive song uses 5/4 time signature")
    func testSampleDataProgressiveSongTimeSignature() {
        let progressive = Song.sampleData.first { $0.genre == "Progressive" }
        #expect(progressive != nil)
        #expect(progressive?.timeSignature == .fiveFour)
    }

    // MARK: - DrumTrack.sampleData

    @Test("DrumTrack.sampleData contains one track per chart")
    func testDrumTrackSampleDataCount() {
        let totalCharts = Song.sampleData.reduce(0) { $0 + $1.charts.count }
        let tracks = DrumTrack.sampleData
        #expect(tracks.count == totalCharts)
    }

    @Test("DrumTrack.sampleData tracks delegate properties to their charts and songs")
    func testDrumTrackSampleDataProperties() {
        let track = DrumTrack.sampleData[0]
        #expect(!track.title.isEmpty)
        #expect(!track.artist.isEmpty)
        #expect(track.bpm > 0)
    }
}

// MARK: - ServerSong Legacy Convenience Initializer

@Suite("ServerSong Legacy Init Tests")
struct ServerSongLegacyInitTests {

    @Test("Legacy init strips .dtx extension to derive songId")
    func testSongIdStripsExtension() {
        let song = ServerSong(
            filename: "track.dtx",
            title: "Track",
            artist: "Artist",
            bpm: 120.0,
            difficultyLevel: 50,
            size: 1024
        )
        #expect(song.songId == "track")
    }

    @Test("Legacy init creates exactly one chart")
    func testCreatesOneChart() {
        let song = ServerSong(
            filename: "song.dtx",
            title: "T",
            artist: "A",
            bpm: 120.0,
            difficultyLevel: 60,
            size: 2048
        )
        #expect(song.charts.count == 1)
    }

    @Test("Legacy init chart has difficulty 'medium' and label 'STANDARD'")
    func testChartDifficultyAndLabel() {
        let song = ServerSong(
            filename: "song.dtx",
            title: "T",
            artist: "A",
            bpm: 120.0,
            difficultyLevel: 55,
            size: 512
        )
        let chart = song.charts[0]
        #expect(chart.difficulty == "medium")
        #expect(chart.difficultyLabel == "STANDARD")
    }

    @Test("Legacy init chart stores provided difficultyLevel and size")
    func testChartLevelAndSize() {
        let song = ServerSong(
            filename: "extreme.dtx",
            title: "T",
            artist: "A",
            bpm: 200.0,
            difficultyLevel: 95,
            size: 8192
        )
        let chart = song.charts[0]
        #expect(chart.level == 95)
        #expect(chart.size == 8192)
    }

    @Test("Legacy init chart filename matches original filename")
    func testChartFilenameMatchesOriginal() {
        let filename = "mytrack.dtx"
        let song = ServerSong(
            filename: filename,
            title: "T",
            artist: "A",
            bpm: 120.0,
            difficultyLevel: 40,
            size: 256
        )
        #expect(song.charts[0].filename == filename)
    }

    @Test("Legacy init isDownloaded defaults to false")
    func testIsDownloadedDefaultsFalse() {
        let song = ServerSong(
            filename: "song.dtx",
            title: "T",
            artist: "A",
            bpm: 120.0,
            difficultyLevel: 50,
            size: 1024
        )
        #expect(song.isDownloaded == false)
    }

    @Test("Legacy init isDownloaded can be set to true")
    func testIsDownloadedCanBeTrue() {
        let song = ServerSong(
            filename: "song.dtx",
            title: "T",
            artist: "A",
            bpm: 120.0,
            difficultyLevel: 50,
            size: 1024,
            isDownloaded: true
        )
        #expect(song.isDownloaded == true)
    }

    @Test("Legacy init stores title, artist, and bpm on song")
    func testSongProperties() {
        let song = ServerSong(
            filename: "jazz.dtx",
            title: "Jazz Piece",
            artist: "Jazz Trio",
            bpm: 95.0,
            difficultyLevel: 35,
            size: 4096
        )
        #expect(song.title == "Jazz Piece")
        #expect(song.artist == "Jazz Trio")
        #expect(song.bpm == 95.0)
    }
}
