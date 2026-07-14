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
}
