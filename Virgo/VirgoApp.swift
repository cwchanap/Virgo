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
        if VirgoAppLaunchBehavior.shouldDisableAnimations(arguments: ProcessInfo.processInfo.arguments) {
            #if canImport(UIKit)
            UIView.setAnimationsEnabled(false)
            #endif
        }
    }

    @ViewBuilder
    private var rootView: some View {
        MainMenuView()
            .environmentObject(sharedMetronome)
            .environmentObject(sharedPracticeSettings)
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
#endif
