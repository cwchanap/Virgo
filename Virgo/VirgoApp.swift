//
//  VirgoApp.swift
//  Virgo
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

@main
struct VirgoApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DrumTrack.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        if ProcessInfo.processInfo.arguments.contains("UITesting") {
            #if canImport(UIKit)
            UIView.setAnimationsEnabled(false)
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            MainMenuView()
        }
        .modelContainer(sharedModelContainer)
    }
}
