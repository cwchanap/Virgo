// Virgo/design/FontRegistration.swift
import CoreText
import Foundation

/// Registers bundled `.ttf` fonts at runtime so they resolve on both iOS and
/// macOS without relying on Info.plist paths. Idempotent.
enum AppFonts {
    private static var didRegister = false

    static func registerAll() {
        guard !didRegister else { return }

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
                // Releases the owned CFError. "Already registered" and
                // "duplicated name" (two files registering the same PostScript
                // name) are both benign on re-runs and ignored.
                let code = CFErrorGetCode(err)
                let benignCodes: Set<CFIndex> = [
                    CTFontManagerError.alreadyRegistered.rawValue,
                    CTFontManagerError.duplicatedName.rawValue
                ]
                if !benignCodes.contains(code) {
                    Logger.debug("Font registration failed for \(url.lastPathComponent): \(err)")
                }
            }
        }

        // Set after the scan so a partially-failed registration can be retried
        // rather than permanently short-circuiting subsequent calls.
        didRegister = true
    }
}
