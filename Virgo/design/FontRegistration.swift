// Virgo/design/FontRegistration.swift
import CoreText
import Foundation

/// Registers bundled `.ttf` fonts at runtime so they resolve on both iOS and
/// macOS without relying on Info.plist paths. Idempotent.
enum AppFonts {
    private static var didRegister = false

    static func registerAll() {
        guard !didRegister else { return }
        didRegister = true

        // Primary: scan Bundle.main (works at app runtime)
        var urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []

        // Fallback: scan all loaded bundles (covers the XCTest host where
        // Bundle.main is the test runner, not the app bundle).
        if urls.isEmpty {
            for bundle in Bundle.allBundles {
                let found = bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
                if !found.isEmpty {
                    urls = found
                    break
                }
            }
        }

        for url in urls {
            var cfError: Unmanaged<CFError>?
            // .process scope = process-wide; "already registered" errors are safe to ignore.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &cfError)
            if let err = cfError?.takeRetainedValue() {
                // Releases the owned CFError. "Already registered" on re-runs is benign and ignored.
                let code = CFErrorGetCode(err)
                if code != CTFontManagerError.alreadyRegistered.rawValue {
                    Logger.debug("Font registration failed for \(url.lastPathComponent): \(err)")
                }
            }
        }
    }
}
