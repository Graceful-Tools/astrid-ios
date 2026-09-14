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

    /// LABELS ARE LOCALIZED, VALUES ARE NOT (AITD-403). The `value` is the wire string
    /// `updateListAdvanced` stores and iOS reads back, so it stays English forever; the `label` is
    /// what a person reads, and it was English here while iOS's ListDefaultsView already used
    /// `time.today`. Same list, two languages, depending on which app you opened it in.
    static let dueDate: [Option] = [
        .init("none", NSLocalizedString("priority.none", comment: "")), .init("today", NSLocalizedString("time.today", comment: "")),
        .init("tomorrow", NSLocalizedString("time.tomorrow", comment: "")), .init("next_week", NSLocalizedString("time.next_week", comment: "")),
        .init("next_month", NSLocalizedString("time.next_month", comment: "")),
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
        .init("never", NSLocalizedString("repeating.never", comment: "")), .init("daily", NSLocalizedString("repeating.daily", comment: "")),
        .init("weekly", NSLocalizedString("repeating.weekly", comment: "")), .init("monthly", NSLocalizedString("repeating.monthly", comment: "")),
        .init("yearly", NSLocalizedString("repeating.yearly", comment: "")),
    ]

    /// The updateListAdvanced payload for the default-task settings.
    static func updates(priority: Int, dueDate: String, repeating: String) -> [String: Any] {
        ["defaultPriority": priority, "defaultDueDate": dueDate, "defaultRepeating": repeating]
    }
}
#endif
