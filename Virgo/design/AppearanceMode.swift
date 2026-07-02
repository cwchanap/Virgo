//
//  AppearanceMode.swift
//  Virgo
//
//  User-selectable app appearance. Drives `.preferredColorScheme` at the app
//  root; every follow-mode screen resolves its world from the resulting
//  color scheme via `.appSurface()`.
//

import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// UserDefaults key shared by the app root and the Appearance setting.
    static let storageKey = "appearanceMode"

    /// `nil` means "follow the OS appearance".
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}
