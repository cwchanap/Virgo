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
    @StateObject private var sharedMetronome = MetronomeEngine()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Song.self,
            Chart.self,
            Note.self,
            ServerSong.self,
            ServerChart.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema, 
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If migration fails, try creating a new in-memory container and then recreate persistent store
            print("Migration failed, attempting to recreate database: \(error)")
            
            // Delete the existing database file to force recreation
            let storeURL = modelConfiguration.url
            try? FileManager.default.removeItem(at: storeURL)
            // Also remove any associated files
            let associatedFiles = [
                storeURL.appendingPathExtension("wal"),
                storeURL.appendingPathExtension("shm")
            ]
            for file in associatedFiles {
                try? FileManager.default.removeItem(at: file)
            }
            
            // Try creating the container again
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer even after cleanup: \(error)")
            }
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
                .environmentObject(sharedMetronome)
        }
        .modelContainer(sharedModelContainer)
    }
}
