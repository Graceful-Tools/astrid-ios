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
    /// The same six the iOS admin tab offers (task 545812e6). nil = all day, which is why the
    /// value is a String? rather than a sentinel string.
    static let dueTime: [(label: String, value: String?)] = [
        (NSLocalizedString("lists.all_day", comment: ""), nil),
        ("9:00 AM",  "09:00"),
        ("12:00 PM", "12:00"),
        ("2:00 PM",  "14:00"),
        ("5:00 PM",  "17:00"),
        ("6:00 PM",  "18:00"),
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
