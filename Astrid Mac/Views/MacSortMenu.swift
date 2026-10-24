//  MacSortMenu.swift
//  Astrid for Mac — the sort menu in a list's header (AITD-522).
//
//  It was `MacRootView.sortMenu`, a toolbar item shown only where no sheet sorted (AITD-509).
//  Moving sort into the header made it the one sort control for every list-mode selection, which
//  added My Tasks to what it writes — and that file is on the AITD-346 ratchet, so the menu came
//  out here rather than growing it.

#if os(macOS)
import SwiftUI

/// Sort control. On a REAL list a pick is saved to the list (`sortBy`) through the canonical
/// service, so it persists and syncs to iOS/web — iOS behaves the same way. Previously every pick
/// was a window-local override that never left the Mac (task 2b886104). My Tasks writes its
/// synced preference, as its filter sheet did before sort moved to the header (AITD-467) — the
/// rows ignore the window override there. Virtual/saved selections own no list, so those keep
/// the local override.
///
/// The override and a list's sort no longer touch each other (AITD-389): clearing the override on
/// a list pick was only needed while it outranked the list, and it threw away your My Tasks sort.
struct MacSortMenu: View {
    let list: TaskList?
    let isMyTasks: Bool
    @Binding var override: String
    @ObservedObject private var myTasksPreferences = MyTasksPreferencesService.shared

    var body: some View {
        Menu {
            if let list {
                Picker(NSLocalizedString("actions.sort", comment: ""), selection: Binding(
                    get: { list.sortBy ?? "auto" },
                    set: { newValue in
                        AppActions.perform("Update sort") {
                            _ = try await ListService.shared.updateListAdvanced(
                                listId: list.id, updates: MacSortMenu.listUpdates(sortBy: newValue))
                        }
                    }
                )) {
                    ForEach(MacListFilter.sort) { Text($0.label).tag($0.value) }
                }
            } else if isMyTasks {
                Picker(NSLocalizedString("actions.sort", comment: ""), selection: Binding(
                    get: { myTasksPreferences.preferences.sortBy ?? "auto" },
                    set: { newValue in
                        var updated = myTasksPreferences.preferences
                        updated.sortBy = newValue
                        _Concurrency.Task { await myTasksPreferences.updatePreferences(updated) }
                    }
                )) {
                    ForEach(MacListFilter.sort) { Text($0.label).tag($0.value) }
                }
            } else {
                Picker(NSLocalizedString("actions.sort", comment: ""), selection: $override) {
                    Text(NSLocalizedString("mac.list_default", comment: "")).tag("")
                    ForEach(MacListFilter.sort) { Text($0.label).tag($0.value) }
                }
            }
        } label: {
            Label(NSLocalizedString("actions.sort", comment: ""), systemImage: "arrow.up.arrow.down")
        }
        .fixedSize()
        .help(NSLocalizedString("mac.sort_tasks", comment: ""))
        .accessibilityIdentifier("list.sortMenu")
    }

    /// What picking a sort writes to a list: its `sortBy` and nothing else — the same key and
    /// value `ListSettingsPayload` sends from the settings sheet (AITD-540). Sort is a per-user
    /// view field (AITD-394), so carrying anything more would revert someone's other choices.
    static func listUpdates(sortBy value: String) -> [String: Any] {
        ["sortBy": value]
    }
}
#endif
