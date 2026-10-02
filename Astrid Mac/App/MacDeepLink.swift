//  MacDeepLink.swift
//  Astrid for Mac — parse astrid:// and https://astrid.cc deep links to a navigation target
//  (Task 84993a68). Pure/testable. Mirrors DeepLinkManager (iOS) for tasks & lists.
//
//  NOTE: receiving astrid:// requires the scheme to be registered (CFBundleURLTypes) and
//  https://astrid.cc requires the associated-domains entitlement — both are added in Xcode
//  (see docs/MAC_SIGNING.md), same constraint as passkey. The routing below is ready for that.

#if os(macOS)
import SwiftUI

/// A settings page a link can open. Named as the web routes them (`/settings/<page>`).
enum MacSettingsPage: String, Equatable {
    case agents
}

enum MacDeepLink: Equatable {
    case task(String)
    case list(String)
    /// `/settings/agents` — the target of Astrid's "set up a model" chat reply (AITD-452).
    case settings(MacSettingsPage)

    /// Parse a link tapped inside rendered chat or comment text. Server-written copy uses
    /// root-relative links (`/settings/agents`) the way the web does; those resolve against the
    /// brand origin first, by the same rule iOS uses (AppRelativeLink).
    static func parse(chatLink url: URL) -> MacDeepLink? {
        parse(AppRelativeLink.resolve(url) ?? url)
    }

    /// Parse a URL to a navigation target, or nil if unrecognized.
    ///
    /// Identifiers are validated (security audit 2026-07-25): a deep link is attacker-supplied
    /// input — any web page or message can open one — and its id flowed straight into
    /// `/api/v1/tasks/<id>`, where a percent-encoded separator became path traversal.
    static func parse(_ url: URL) -> MacDeepLink? {
        if url.scheme == "astrid" {
            guard let host = url.host else { return nil }
            let id = url.lastPathComponent
            guard id != host, APIPathSafety.isValidIdentifier(id) else { return nil }
            if host == "settings" { return MacSettingsPage(rawValue: id).map { .settings($0) } }
            switch host {
            case "tasks": return .task(id)
            case "lists": return .list(id)
            default: return nil
            }
        }
        // Only real web links count — `http://astrid.cc/...`, or any other scheme claiming this
        // host, must not be routed as a trusted universal link.
        if url.scheme == "https", let host = url.host, Brand.webHosts.contains(host) {
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count >= 2, APIPathSafety.isValidIdentifier(parts[1]) else { return nil }
            if parts[0] == "settings" { return MacSettingsPage(rawValue: parts[1]).map { .settings($0) } }
            switch parts[0] {
            case "tasks": return .task(parts[1])
            case "lists": return .list(parts[1])
            default: return nil
            }
        }
        return nil
    }
}

/// Where a deep link goes, in one place for both entry points: a URL the system hands the app
/// (`onOpenURL`) and a link tapped in rendered chat text (MacMarkdownText).
@MainActor
enum MacDeepLinkRouter {
    static func route(_ link: MacDeepLink, openSettings: OpenSettingsAction) {
        switch link {
        case .task(let id): MacAppModel.shared.openTask(listId: nil, taskId: id)
        case .list(let id): MacAppModel.shared.openList(id)
        case .settings(let page):
            // Select the tab first: the Settings window reads it through @AppStorage, so this
            // also switches a window that is already open.
            UserDefaults.standard.set(MacSettingsTab(page: page).rawValue, forKey: MacSettingsTab.defaultsKey)
            openSettings()
        }
    }
}
#endif
