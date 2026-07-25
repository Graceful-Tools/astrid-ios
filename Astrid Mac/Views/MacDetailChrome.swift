//  MacDetailChrome.swift
//  Astrid for Mac — the task-details surface is a WHITE card (like Astrid Web), except when the
//  EFFECTIVE appearance is dark: explicit Dark theme, or Auto theme on a dark system. Previously
//  Auto+dark kept the white card while Theme.textPrimary resolved white → unreadable
//  white-on-white detail (Task 98c6c6d5).

#if os(macOS)
import SwiftUI
import AppKit

enum MacDetailChrome {
    /// Pure resolution: white card unless the effective appearance is dark.
    /// `systemIsDark` only matters for the "auto" mode (mirrors Theme.themed's auto branch).
    static func background(mode: String, systemIsDark: Bool) -> Color {
        switch mode {
        case "dark":            return Theme.Dark.bgSecondary
        case "ocean", "light":  return .white
        default:                return systemIsDark ? Theme.Dark.bgSecondary : .white   // auto
        }
    }

    static var background: Color {
        background(mode: UserDefaults.standard.string(forKey: "themeMode") ?? "ocean",
                   systemIsDark: NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
}
#endif
