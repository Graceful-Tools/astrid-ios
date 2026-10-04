//  SettingsPage.swift
//  A settings page a link can name, as the web routes them (`/settings/<page>`). Shared by the
//  iOS DeepLinkManager and the Mac's MacDeepLink, so the two apps answer the same links
//  (AITD-458; the Mac knew only `agents` before).

import Foundation

enum SettingsPage: String, Hashable, Identifiable, CaseIterable {
    case account
    case profile
    case reminders
    case agents
    /// Retired name kept for old deep links; opens Connections.
    case apiAccess = "api-access"
    case connections
    case chatgpt
    case contacts
    case appearance
    case debug
    case language
    case about

    var id: String { rawValue }
}
