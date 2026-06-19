//
//  LocalDTXFixtureImporterTests.swift
//  VirgoTests
//

import Foundation
import SwiftData
import Testing
@testable import Virgo

@Suite("Local DTX Fixture Importer Tests", .serialized)
@MainActor
struct LocalDTXFixtureImporterTests {
    @Test("imports Soukyuu fixture with four playable charts")
    func importsSoukyuuFixtureWithFourPlayableCharts() throws {
        let store = try makeStore()
        let context = store.context
        let fixtureURL = try soukyuuFixtureURL()

        let song = try LocalDTXFixtureImporter.importSong(from: fixtureURL, into: context)

        #expect(song.title == "蒼穹への翔歌")
        #expect(song.artist == "hapadona feat. Suno AI")
        #expect(song.bpm == 165.55)
        #expect(song.genre == "DTX Import")
        #expect(song.isServerImported)
        #expect(song.serverSongId == "soukyuu_e_no_shouka")
        #expect(song.bgmFilePath?.hasSuffix("bgm.m4a") == true)
        #expect(song.previewFilePath?.hasSuffix("preview.mp3") == true)
        #expect((song.bgmStartOffsetSeconds ?? 0) > 0)

        let charts = song.charts.sorted { $0.difficulty.sortOrder < $1.difficulty.sortOrder }
        #expect(charts.map(\.difficulty) == [.easy, .medium, .hard, .expert])
        #expect(charts.map(\.level) == [36, 60, 74, 87])
        #expect(charts.allSatisfy { $0.notesCount > 0 })
    }

    @Test("does not duplicate Soukyuu fixture when already imported")
    func doesNotDuplicateSoukyuuFixtureWhenAlreadyImported() throws {
        let store = try makeStore()
        let context = store.context
        let fixtureURL = try soukyuuFixtureURL()

        _ = try LocalDTXFixtureImporter.importSong(from: fixtureURL, into: context)
        _ = try LocalDTXFixtureImporter.importSong(from: fixtureURL, into: context)

        let songs = try context.fetch(FetchDescriptor<Song>())
        #expect(songs.count == 1)
    }

    @Test("refreshes stale Soukyuu audio paths when already imported")
    func refreshesStaleSoukyuuAudioPathsWhenAlreadyImported() throws {
        let store = try makeStore()
        let context = store.context
        let fixtureURL = try soukyuuFixtureURL()
        let staleSong = Song(
            title: "蒼穹への翔歌",
            artist: "hapadona feat. Suno AI",
            bpm: 165.55,
            duration: "3:50",
            genre: "DTX Import",
            timeSignature: .fourFour,
            isServerImported: true,
            serverSongId: LocalDTXFixtureImporter.soukyuuSongId,
            bgmFilePath: fixtureURL.appendingPathComponent("bgm.ogg").path,
            previewFilePath: nil
        )
        context.insert(staleSong)
        try context.save()

        let song = try LocalDTXFixtureImporter.importSong(from: fixtureURL, into: context)

        #expect(song.bgmFilePath?.hasSuffix("bgm.m4a") == true)
        #expect(song.previewFilePath?.hasSuffix("preview.mp3") == true)
    }

    private struct TestStore {
        let container: ModelContainer
        let context: ModelContext
    }

    private func makeStore() throws -> TestStore {
        let schema = Schema([
            Song.self,
            Chart.self,
            Note.self,
            ServerSong.self,
            ServerChart.self,
            ScoreRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return TestStore(container: container, context: container.mainContext)
    }

    private func soukyuuFixtureURL() throws -> URL {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Virgo/Fixtures/soukyuu_e_no_shouka", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: url.path))
        return url
    }
}
