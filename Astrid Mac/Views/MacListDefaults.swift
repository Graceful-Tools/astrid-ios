//  MacListDefaults.swift
//  Astrid for Mac — pure model for a list's default-task settings (Task c82173ff). Values match the
//  strings iOS ListAdminTab writes, so updateListAdvanced applies them identically.

#if os(macOS)
import Foundation

enum MacListDefaults {
    struct Option: Identifiable, Equatable {
        let value: String; let label: String; var id: String { value }
        init(_ value: String, _ label: String) { self.value = value; self.label = label }
    }

    static let dueDate: [Option] = [
        .init("none", "None"), .init("today", "Today"), .init("tomorrow", "Tomorrow"),
        .init("next_week", "Next week"), .init("next_month", "Next month"),
    ]
    static let repeating: [Option] = [
        .init("never", "Never"), .init("daily", "Daily"), .init("weekly", "Weekly"),
        .init("monthly", "Monthly"), .init("yearly", "Yearly"),
    ]

    /// The updateListAdvanced payload for the default-task settings.
    static func updates(priority: Int, dueDate: String, repeating: String) -> [String: Any] {
        ["defaultPriority": priority, "defaultDueDate": dueDate, "defaultRepeating": repeating]
    }
}
#endif
