import Foundation
import SwiftUI
import SafariServices

/**
 * DeepLinkManager
 *
 * Parses and routes incoming URLs to the appropriate presenters.
 * Supports both custom scheme (astrid://) and Universal Links (https://astrid.cc).
 * Falls back to in-app browser for web pages not available natively.
 */
@MainActor
class DeepLinkManager {
    static let shared = DeepLinkManager()

    private let api = AstridAPIClient.shared

    private init() {}

    /// Opens a URL in an in-app browser (SFSafariViewController)
    func openInAppBrowser(url: URL) {
        print("🌐 [DeepLinkManager] Opening in-app browser: \(url.absoluteString)")

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("⚠️ [DeepLinkManager] No root view controller found, falling back to external browser")
            UIApplication.shared.open(url)
            return
        }

        // Find the topmost presented view controller
        var topController = rootViewController
        while let presented = topController.presentedViewController {
            topController = presented
        }

        let safariVC = SFSafariViewController(url: url)
        safariVC.preferredControlTintColor = UIColor(Theme.accent)
        topController.present(safariVC, animated: true)
    }
    
    /// Entry point for handling incoming URLs
    func handleURL(_ url: URL) {
        print("🔗 [DeepLinkManager] Handling URL: \(url.absoluteString)")
        
        // Handle custom scheme: astrid://...
        if url.scheme == "astrid" {
            handleCustomScheme(url)
            return
        }
        
        // Handle Universal Links: https://<brand host>/...
        if let host = url.host, Brand.webHosts.contains(host) {
            handleUniversalLink(url)
            return
        }
        
        print("⚠️ [DeepLinkManager] Unrecognized URL scheme or host")
    }
    
    private func handleCustomScheme(_ url: URL) {
        guard let host = url.host else { return }

        switch host {
        // Deep links are attacker-supplied input (any page or message can open one), and these
        // ids flow into `/api/v1/<collection>/<id>`. Validate them before routing on them
        // (security audit 2026-07-25) — a percent-encoded separator was path traversal.
        case "tasks":
            let taskId = url.lastPathComponent
            if taskId != "tasks", APIPathSafety.isValidIdentifier(taskId) {
                TaskPresenter.shared.showTask(taskId: taskId)
            }
        case "lists":
            let listId = url.lastPathComponent
            if listId != "lists", APIPathSafety.isValidIdentifier(listId) {
                ListPresenter.shared.showList(listId: listId)
            }
        case "users":
            let userId = url.lastPathComponent
            if userId != "users", APIPathSafety.isValidIdentifier(userId) {
                // Navigate to profile in main content area
                NotificationCenter.default.post(name: .openProfile, object: userId)
            }
        case "settings":
            let page = url.lastPathComponent
            if page != "settings", let settingsPage = SettingsPresenter.SettingsPage(rawValue: page) {
                SettingsPresenter.shared.navigateTo(page: settingsPage)
            } else {
                SettingsPresenter.shared.openSettings()
            }
        case "s":
            let code = url.lastPathComponent
            if code != "s", APIPathSafety.isValidIdentifier(code) {
                resolveAndRoute(code: code)
            }
        default:
            // Convert custom scheme to https URL and open in in-app browser
            print("ℹ️ [DeepLinkManager] Unknown custom scheme host '\(host)' - opening in in-app browser")
            if let httpsURL = URL(string: "\(Brand.productionBaseURL)/\(host)\(url.path)") {
                openInAppBrowser(url: httpsURL)
            }
        }
    }
    
    private func handleUniversalLink(_ url: URL) {
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        // Empty path (just the domain) - nothing to do
        guard !pathComponents.isEmpty else { return }

        let first = pathComponents[0]

        switch first {
        case "tasks":
            if pathComponents.count > 1, APIPathSafety.isValidIdentifier(pathComponents[1]) {
                TaskPresenter.shared.showTask(taskId: pathComponents[1])
            }
        case "lists":
            if pathComponents.count > 1, APIPathSafety.isValidIdentifier(pathComponents[1]) {
                ListPresenter.shared.showList(listId: pathComponents[1])
            }
        case "settings":
            if pathComponents.count > 1 {
                if let settingsPage = SettingsPresenter.SettingsPage(rawValue: pathComponents[1]) {
                    SettingsPresenter.shared.navigateTo(page: settingsPage)
                } else {
                    // Unknown settings page - open in-app browser
                    print("ℹ️ [DeepLinkManager] Unknown settings page '\(pathComponents[1])' - opening in browser")
                    openInAppBrowser(url: url)
                }
            } else {
                SettingsPresenter.shared.openSettings()
            }
        case "s":
            if pathComponents.count > 1 {
                resolveAndRoute(code: pathComponents[1])
            }
        default:
            // Unknown path - open in in-app browser
            // This handles pages like /help, /pricing, /blog, etc. that don't have native views
            print("ℹ️ [DeepLinkManager] Unknown path '\(first)' - opening in in-app browser")
            openInAppBrowser(url: url)
        }
    }
    
    private func resolveAndRoute(code: String) {
        _Concurrency.Task {
            do {
                let resolution = try await api.resolveShortcode(code)
                print("✅ [DeepLinkManager] Resolved shortcode \(code) to \(resolution.targetType) \(resolution.targetId)")
                
                await MainActor.run {
                    if resolution.targetType == "task" {
                        TaskPresenter.shared.showTask(taskId: resolution.targetId)
                    } else if resolution.targetType == "list" {
                        ListPresenter.shared.showList(listId: resolution.targetId)
                    }
                }
            } catch {
                print("❌ [DeepLinkManager] Failed to resolve shortcode \(code): \(error)")
                // Fallback to web if resolution fails
                if let url = URL(string: "\(Brand.productionBaseURL)/s/\(code)") {
                    await MainActor.run {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }
}
