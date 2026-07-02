//
//  VirgoApp.swift
//  Virgo
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

@main
struct VirgoApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacSingleWindowDelegate.self) private var appDelegate
    #endif

    @StateObject private var sharedMetronome = MetronomeEngine()
    @StateObject private var sharedPracticeSettings = PracticeSettingsService()
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode: AppearanceMode = .system

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Song.self,
            Chart.self,
            Note.self,
            ServerSong.self,
            ServerChart.self,
            ScoreRecord.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            Logger.debug("SwiftData container creation failed: \(error)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        AppFonts.registerAll()
        if VirgoAppLaunchBehavior.shouldDisableAnimations(arguments: ProcessInfo.processInfo.arguments) {
            #if canImport(UIKit)
            UIView.setAnimationsEnabled(false)
            #endif
        }
        #if os(macOS)
        // Must run before SwiftUI's WindowGroup sets up window restoration.
        // VirgoApp.init() runs during @main startup, before any scene or window
        // machinery, so the saved state is gone before restoration begins.
        if VirgoAppLaunchBehavior.shouldClearWindowRestorationState(
            arguments: ProcessInfo.processInfo.arguments
        ) {
            WindowRestorationStateClearer.clearSavedState()
        }
        #endif
    }

    @ViewBuilder
    private var rootView: some View {
        MainMenuView()
            .environmentObject(sharedMetronome)
            .environmentObject(sharedPracticeSettings)
            .appThemeRoot()
            .preferredColorScheme(appearanceMode.preferredColorScheme)
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            rootView
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        #else
        WindowGroup {
            rootView
        }
        .modelContainer(sharedModelContainer)
        #endif
    }
}

#if os(macOS)
final class MacSingleWindowDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            self.closeRestoredDuplicateMainWindows()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        closeRestoredDuplicateMainWindows()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            // Existing window present: activate it ourselves and tell AppKit we handled it.
            sender.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
        // When no windows are visible, defer to AppKit so SwiftUI's WindowGroup
        // creates a new one. File > New is intentionally disabled, so without this
        // the app would be left running with no window after the user closes the last one.
        return ReopenPolicy.shouldAppKitHandleReopen(hasVisibleWindows: flag)
    }

    private func closeRestoredDuplicateMainWindows() {
        let mainWindows = NSApp.windows.filter { window in
            window.canBecomeMain && window.isVisible && !(window is NSPanel)
        }

        for window in mainWindows.dropFirst() {
            window.close()
        }
    }
}

/// Clears macOS window state restoration data so the next launch creates a
/// fresh window instead of restoring (potentially corrupted) saved state.
enum WindowRestorationStateClearer {
    static func clearSavedState() {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        guard !bundleIdentifier.isEmpty else { return }

        let fileManager = FileManager.default
        // applicationSupportDirectory resolves to ~/Library/Application Support
        // (non-sandboxed) or the container equivalent (sandboxed). The Saved
        // Application State directory is a sibling under the same Library root.
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let libraryDir = appSupport.deletingLastPathComponent()
        let savedStateDir = libraryDir
            .appendingPathComponent("Saved Application State")
            .appendingPathComponent("\(bundleIdentifier).savedState")

        if fileManager.fileExists(atPath: savedStateDir.path) {
            try? fileManager.removeItem(at: savedStateDir)
        }
    }
}
#endif
