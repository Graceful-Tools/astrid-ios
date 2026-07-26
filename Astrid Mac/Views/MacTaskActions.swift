//  MacTaskActions.swift
//  Astrid for Mac — the task actions iOS offers (share / copy / duplicate / delete), in one place
//  so the detail menu and the row context menu expose the SAME set (task ea0527ef).
//
//  Everything here goes through the SHARED services — RemoteResourceService.createShortcode for
//  the share link (identical to iOS ShareTaskView) and TaskService for writes — so Mac cannot
//  drift from iOS behaviour. Only the presentation is Mac-native: NSSharingServicePicker in place
//  of UIActivityViewController, and NSPasteboard in place of UIPasteboard.

#if os(macOS)
import SwiftUI
import AppKit

enum MacTaskActions {

    /// Plain-text form of a task for "Copy" — title plus the share URL when there is one.
    /// Pure so it is testable without a pasteboard.
    static func clipboardText(title: String, shareURL: URL?) -> String {
        guard let shareURL else { return title }
        return "\(title)\n\(shareURL.absoluteString)"
    }

    /// Whether the share sheet can be offered yet (a link must exist to share).
    static func canPresentShareSheet(shareURL: URL?) -> Bool { shareURL != nil }

    static func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// Native share sheet — the Mac counterpart of iOS's UIActivityViewController: Mail, Messages,
    /// AirDrop, Notes, and anything else the user has enabled.
    @MainActor
    static func presentShareSheet(url: URL, relativeTo view: NSView?) {
        let picker = NSSharingServicePicker(items: [url])
        let anchor = view ?? NSApp.keyWindow?.contentView
        guard let anchor else { return }
        picker.show(relativeTo: .zero, of: anchor, preferredEdge: .minY)
    }

    /// Create the share link through the SAME service iOS uses, then hand back the URL.
    static func makeShareURL(taskId: String) async throws -> URL? {
        let response = try await RemoteResourceService.shared.createShortcode(targetType: "task",
                                                                             targetId: taskId)
        return URL(string: response.url)
    }

    // NOTE: copying deliberately has NO helper here — TaskService.copyTask(id:targetListId:
    // includeComments:) already exists and is what iOS uses; it also brings the comments across,
    // which a hand-rolled createTask duplicate would silently drop.
}
#endif
