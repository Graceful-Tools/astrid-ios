//  MacServiceProvider.swift
//  Astrid for Mac — Services menu "Add to Astrid" quick-create (Task 3b9883d0).
//
//  The macOS equivalent of the iOS Share Extension: select text in any app → Services → "Add to
//  Astrid" creates a task via the shared TaskService (offline-first Outbox). Registered as the
//  app's servicesProvider at launch; the NSServices Info.plist entry (build setting) exposes the
//  menu item. Also usable from a share flow that hands us plain text.

#if os(macOS)
import AppKit

/// Pure parsing of the shared text into a task (title + notes). Testable without AppKit.
enum MacServiceInput {
    struct Parsed: Equatable { let title: String; let notes: String }

    /// First non-empty line → title (trimmed, capped at 200 chars); the remainder → notes.
    static func parse(_ text: String) -> Parsed? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let firstIdx = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return nil
        }
        let title = String(lines[firstIdx].trimmingCharacters(in: .whitespaces).prefix(200))
        let notes = lines[(firstIdx + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return Parsed(title: title, notes: notes)
    }
}

final class MacServiceProvider: NSObject {
    static let shared = MacServiceProvider()

    /// Register so the Services menu "Add to Astrid" item routes here.
    @MainActor static func register() {
        NSApp.servicesProvider = shared
        NSUpdateDynamicServices()
    }

    /// NSMessage handler named in the NSServices Info.plist entry ("addToAstrid").
    @objc func addToAstrid(_ pboard: NSPasteboard, userData: String?,
                           error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pboard.string(forType: .string),
              let parsed = MacServiceInput.parse(text) else { return }
        MacActions.perform("Add to \(Brand.appName)") {
            let listIds = ListService.shared.lists.first(where: { $0.isVirtual != true }).map { [$0.id] } ?? []
            _ = try await TaskService.shared.createTask(
                listIds: listIds, title: parsed.title,
                description: parsed.notes.isEmpty ? nil : parsed.notes)
        }
    }
}
#endif
