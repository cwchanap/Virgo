//
//  SecondWaveCoverageTests.swift
//  VirgoTests
//
//  Created by Copilot on wave-2 coverage pass.
//

import Testing
import SwiftUI
import SwiftData
import Foundation
#if os(macOS)
import AppKit
#endif
@testable import Virgo

@Suite("Second Wave Coverage Tests", .serialized)
@MainActor
struct SecondWaveCoverageTests {

    // MARK: - DownloadedSongsView

    @Test("DownloadedSongsView renders empty state when no downloaded songs exist")
    func testDownloadedSongsViewEmptyState() async throws {
        try await TestSetup.withTestSetup {
            let serverSongService = ServerSongService()
            let audioPlaybackService = AudioPlaybackService(startPlayback: { _ in false })

            let view = DownloadedSongsView(
                songs: [],
                serverSongService: serverSongService,
                currentlyPlaying: .constant(nil),
                expandedSongId: .constant(nil),
                selectedChart: .constant(nil),
                navigateToGameplay: .constant(false),
                audioPlaybackService: audioPlaybackService,
                onPlayTap: { _ in },
                onSaveTap: { _ in }
            )

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1024, height: 768)
            )
        }
    }

    @Test("DownloadedSongsView renders populated state with DTX Import songs")
    func testDownloadedSongsViewPopulatedState() async throws {
        try await TestSetup.withTestSetup {
            let song1 = makeDownloadedSong(title: "Wave 2 Song A")
            let song2 = makeDownloadedSong(title: "Wave 2 Song B")
            let serverSongService = ServerSongService()
            let audioPlaybackService = AudioPlaybackService(startPlayback: { _ in false })

            let view = DownloadedSongsView(
                songs: [song1, song2],
                serverSongService: serverSongService,
                currentlyPlaying: .constant(nil),
                expandedSongId: .constant(nil),
                selectedChart: .constant(nil),
                navigateToGameplay: .constant(false),
                audioPlaybackService: audioPlaybackService,
                onPlayTap: { _ in },
                onSaveTap: { _ in }
            )

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1024, height: 768)
            )
        }
    }

    @Test("DownloadedSongsView.rowViewID stays stable across SwiftData reloads")
    func testDownloadedSongsViewRowViewIDStableAcrossReloads() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let song = makeDownloadedSong(title: "Stable Row ID")
            context.insert(song)
            try context.save()

            let originalRowViewID = DownloadedSongsView.rowViewID(for: song)

            let verificationContext = ModelContext(TestContainer.shared.container)
            let reloadedSong = try #require(
                verificationContext.fetch(FetchDescriptor<Song>()).first
            )

            #expect(song.persistentModelID == reloadedSong.persistentModelID)
            #expect(ObjectIdentifier(song) != ObjectIdentifier(reloadedSong))
            #expect(
                DownloadedSongsView.rowViewID(for: reloadedSong) == originalRowViewID,
                "Row view IDs should stay stable for the same SwiftData model across reloads"
            )
        }
    }

    @Test("DownloadedSongsView.downloadedSongs filters to DTX Import genre only")
    func testDownloadedSongsViewFiltersNonDTXSongs() async throws {
        try await TestSetup.withTestSetup {
            let downloadedSong = makeDownloadedSong(title: "DTX Track")
            let nonDownloadedSong = Song(
                title: "Rock Track",
                artist: "Rock Artist",
                bpm: 120,
                duration: "3:00",
                genre: "Rock",
                timeSignature: .fourFour
            )
            let serverSongService = ServerSongService()
            let audioPlaybackService = AudioPlaybackService(startPlayback: { _ in false })

            let view = DownloadedSongsView(
                songs: [downloadedSong, nonDownloadedSong],
                serverSongService: serverSongService,
                currentlyPlaying: .constant(nil),
                expandedSongId: .constant(nil),
                selectedChart: .constant(nil),
                navigateToGameplay: .constant(false),
                audioPlaybackService: audioPlaybackService,
                onPlayTap: { _ in },
                onSaveTap: { _ in }
            )

            // Assert real filtering behaviour: only the DTX Import song passes the predicate
            #expect(view.downloadedSongs.count == 1)
            #expect(view.downloadedSongs.first?.title == "DTX Track")

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1024, height: 768)
            )
        }
    }

    @Test("DownloadedSongsView renders with currently playing song highlighted")
    func testDownloadedSongsViewWithPlayingState() async throws {
        try await TestSetup.withTestSetup {
            let song = makeDownloadedSong(title: "Playing Song")
            let serverSongService = ServerSongService()
            let audioPlaybackService = AudioPlaybackService(startPlayback: { _ in false })

            let view = DownloadedSongsView(
                songs: [song],
                serverSongService: serverSongService,
                currentlyPlaying: .constant(song.persistentModelID),
                expandedSongId: .constant(nil),
                selectedChart: .constant(nil),
                navigateToGameplay: .constant(false),
                audioPlaybackService: audioPlaybackService,
                onPlayTap: { _ in },
                onSaveTap: { _ in }
            )

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1024, height: 768)
            )
        }
    }

    // MARK: - KeyCapturingOverlay

    @Test("InputSettingsView.keyCapturingOverlay renders without a drum selection")
    func testKeyCapturingOverlayRendersWithoutDrumSelection() async throws {
        try await TestSetup.withTestSetup {
            let keyCaptureState = InputKeyCaptureState()
            keyCaptureState.isCapturingKey = true

            SwiftUITestUtilities.assertViewWithEnvironment(
                InputSettingsView(keyCaptureState: keyCaptureState),
                size: CGSize(width: 1024, height: 768)
            )
        }
    }

    @Test("InputSettingsView.keyCapturingOverlay renders for each drum type")
    func testKeyCapturingOverlayRendersForAllDrumTypes() async throws {
        try await TestSetup.withTestSetup {
            #if os(macOS)
            for drumType in DrumType.allCases {
                let keyCaptureState = InputKeyCaptureState()
                keyCaptureState.selectedDrumType = drumType
                keyCaptureState.isCapturingKey = true
                let mountedView = SwiftUITestUtilities.assertViewWithEnvironment(
                    InputSettingsView(keyCaptureState: keyCaptureState),
                    size: CGSize(width: 800, height: 600)
                )
                let renderedTexts = SwiftUITestUtilities.renderedTexts(from: mountedView.root)
                let hasTypeText = renderedTexts.contains("for \(drumType.description)")
                #expect(
                    hasTypeText,
                    "Expected overlay text for \(drumType); got \(renderedTexts)"
                )
            }
            #endif
        }
    }

    // MARK: - ContentView

    @Test("ContentView renders with MetronomeEngine environment object")
    func testContentViewRendersWithMetronomeEngine() async throws {
        try await TestSetup.withTestSetup {
            let view = ContentView()
                .modelContainer(TestContainer.shared.container)
                .environmentObject(MetronomeEngine(audioDriver: RecordingAudioDriver()))
                .environmentObject(PracticeSettingsService())

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    @Test("ContentView renders with songs inserted into the shared container")
    func testContentViewRendersWithSongsInContainer() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let song = makeDownloadedSong(title: "Container Song")
            context.insert(song)
            try context.save()

            let view = ContentView()
                .modelContainer(TestContainer.shared.container)
                .environmentObject(MetronomeEngine(audioDriver: RecordingAudioDriver()))
                .environmentObject(PracticeSettingsService())

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    // MARK: - Private Helpers

    private func makeDownloadedSong(title: String) -> Song {
        let chart = SwiftUICoverageFixtures.makeChart(
            difficulty: .medium,
            notes: [
                SwiftUICoverageFixtures.makeNote(
                    interval: .quarter,
                    noteType: .bass,
                    measureNumber: 1,
                    measureOffset: 0.0
                )
            ]
        )
        let song = SwiftUICoverageFixtures.makeSong(
            title: title,
            genre: "DTX Import",
            charts: [chart]
        )
        return song
    }
}
