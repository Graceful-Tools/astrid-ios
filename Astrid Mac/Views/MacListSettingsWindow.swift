//  MacListSettingsWindow.swift
//  Astrid for Mac — one List Settings window, in tabs (AITD-388).
//
//  WHY TABS, AND WHY THESE. iOS (`ListSettingsModal`) and Web (`list-settings-popover.tsx`) have
//  had one modal with Sort & Filters / Membership / Admin for a long time. Mac scattered the same
//  material across three unrelated entry points — a filter sheet on the toolbar, "Sharing" in the
//  list menu, "Edit" in the same menu — so there was no single place that answered "what is true
//  about this list", and no visible line between the settings that are yours and the settings
//  that are everyone's.
//
//  THAT LINE IS THE POINT, and it is drawn honestly. Sort & Filters LOOKS like a personal view
//  and is not one: sort, the six filters, "saved filter" and "show subtasks" are all columns on
//  the shared list row, on every platform, so changing one changes it for every member. The tab
//  says so rather than implying a private view that does not exist. Making them genuinely
//  per-user is a backend change and is filed separately; until then the honest thing is to label
//  what is actually happening.

#if os(macOS)
import SwiftUI

struct MacListSettingsWindow: View {
    let list: TaskList
    @Environment(\.dismiss) private var dismiss
    @StateObject private var listService = ListService.shared
    @State private var tab: Tab = .sortFilters

    enum Tab: Hashable { case sortFilters, membership, admin }

    private var currentList: TaskList {
        listService.lists.first { $0.id == list.id } ?? list
    }

    /// Admin is offered only to those who can use it — the same rule the menu and Web use, asked
    /// of `ListPermissions` rather than restated.
    private var canEditSettings: Bool {
        ListPermissions.canEditSettings(currentList, userId: AuthManager.shared.userId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: NSLocalizedString("mac.list_settings_title", comment: ""),
                        currentList.name))
                .font(.headline).foregroundStyle(Theme.textPrimary)

            Picker("", selection: $tab) {
                Text(NSLocalizedString("lists.filters", comment: "")).tag(Tab.sortFilters)
                Text(NSLocalizedString("lists.members", comment: "")).tag(Tab.membership)
                if canEditSettings {
                    Text(NSLocalizedString("lists.admin", comment: "")).tag(Tab.admin)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch tab {
                case .sortFilters:
                    VStack(alignment: .leading, spacing: 8) {
                        // Said out loud, because the tab's name suggests otherwise.
                        Text(NSLocalizedString("lists.sort_filters_shared_note", comment: ""))
                            .font(.caption).foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        MacListSortFiltersContent(list: currentList)
                    }
                case .membership:
                    MacListMembershipTab(list: currentList)
                case .admin:
                    MacListAdminTab(list: currentList)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 460, height: 560)
        .background(Theme.bgPrimary)
        .onChange(of: canEditSettings) {
            // A demotion while the window is open must not strand you on a tab you may no longer
            // use — the same correction iOS makes.
            if !canEditSettings, tab == .admin { tab = .sortFilters }
        }
    }
}

/// The all-users settings: everything that changes the list itself.
///
/// A thin host over the existing editor rather than a second copy of it (ASTRID.md rule 8).
/// `MacListEditSheet` already owns name, description, colour, image, task defaults, the
/// recently-completed window and the per-list AI model, and it is still the sheet that CREATES a
/// list — so it is embedded here with its own chrome suppressed instead of being reimplemented.
struct MacListAdminTab: View {
    let list: TaskList

    var body: some View {
        MacListEditSheet(existing: list, embedded: true)
    }
}
#endif
