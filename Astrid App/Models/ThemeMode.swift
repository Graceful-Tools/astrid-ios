//  ThemeMode.swift
//  Moved out of Views/Settings/AppearanceSettingsView.swift so the shared Theme can
//  use it on macOS (it's a theme model, not a view).

import SwiftUI

enum ThemeMode: String, CaseIterable, Codable {
    case ocean, light, dark, auto

    var displayName: String {
        switch self {
        case .ocean: return NSLocalizedString("theme.ocean", comment: "")
        case .light: return NSLocalizedString("theme.light", comment: "")
        case .dark: return NSLocalizedString("theme.dark", comment: "")
        case .auto: return NSLocalizedString("theme.auto", comment: "")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .ocean: return .light  // Ocean uses light theme with cyan background
        case .light: return .light  // Light always uses light appearance
        case .dark: return .dark    // Dark always uses dark appearance
        case .auto: return nil      // Auto follows system (sunrise/sunset)
        }
    }

    /// The theme actually on screen: `auto` becomes light or dark from the system appearance,
    /// every other mode is itself. The one place Auto is resolved (AITD-611) — views used to
    /// carried their own dark-scheme ternary for this.
    func resolved(for systemScheme: ColorScheme) -> ThemeMode {
        guard self == .auto else { return self }
        switch systemScheme {
        case .dark: return .dark
        default: return .light
        }
    }

    /// The same, for views that keep the setting as its raw `@AppStorage` string. An unknown
    /// value passes through unchanged.
    static func resolvedName(_ raw: String, colorScheme: ColorScheme) -> String {
        ThemeMode(rawValue: raw)?.resolved(for: colorScheme).rawValue ?? raw
    }
}
