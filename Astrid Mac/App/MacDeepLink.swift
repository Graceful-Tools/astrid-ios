//  MacDeepLink.swift
//  Astrid for Mac — parse astrid:// and https://astrid.cc deep links to a navigation target
//  (Task 84993a68). Pure/testable. Mirrors DeepLinkManager (iOS) for tasks & lists.
//
//  NOTE: receiving astrid:// requires the scheme to be registered (CFBundleURLTypes) and
//  https://astrid.cc requires the associated-domains entitlement — both are added in Xcode
//  (see docs/MAC_LOGIN.md), same constraint as passkey. The routing below is ready for that.

#if os(macOS)
import Foundation

enum MacDeepLink: Equatable {
    case task(String)
    case list(String)

    /// Parse a URL to a navigation target, or nil if unrecognized.
    static func parse(_ url: URL) -> MacDeepLink? {
        if url.scheme == "astrid" {
            guard let host = url.host else { return nil }
            let id = url.lastPathComponent
            guard id != host, !id.isEmpty, id != "/" else { return nil }
            switch host {
            case "tasks": return .task(id)
            case "lists": return .list(id)
            default: return nil
            }
        }
        if url.host == "astrid.cc" || url.host == "www.astrid.cc" {
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count >= 2 else { return nil }
            switch parts[0] {
            case "tasks": return .task(parts[1])
            case "lists": return .list(parts[1])
            default: return nil
            }
        }
        return nil
    }
}
#endif
