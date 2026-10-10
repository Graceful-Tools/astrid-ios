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
    @State private var tab: Tab

    enum Tab: Hashable { case sortFilters, membership, admin }

    /// Tall enough that the Filters tab shows every row at the default text size. The content
    /// must still FIT whatever this is — it was 560 with 667 of content, and what does not fit
    /// is centred, so the title came off the top and Done off the bottom (AITD-483).
    static let size = CGSize(width: 460, height: 680)

    init(list: TaskList, initialTab: Tab = .sortFilters) {
        self.list = list
        _tab = State(initialValue: initialTab)
    }

    private var currentList: TaskList {
        listService.lists.first { $0.id == list.id } ?? list
    }

    /// Admin is offered only to those who can use it — the same rule the menu and Web use, asked
    /// of `ListPermissions` rather than restated.
    private var canEditSettings: Bool {
        ListPermissions.canEditSettings(currentList, userId: AuthManager.shared.userId)
    }

    var body: some View {
        content
            .frame(width: Self.size.width, height: Self.size.height)
            .background(Theme.bgPrimary)
            .onChange(of: canEditSettings) {
                // A demotion while the window is open must not strand you on a tab you may no
                // longer use — the same correction iOS makes.
                if !canEditSettings, tab == .admin { tab = .sortFilters }
            }
    }

    /// Everything inside the window's frame. The title, the tabs and Done take what they need
    /// and the tab's own content takes the rest, scrolling inside it — never the reverse.
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: NSLocalizedString("mac.list_settings_title", comment: ""),
                        currentList.name))
                .macFont(.headline).foregroundStyle(Theme.textPrimary)

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
                        // Said out loud, because a window called List Settings suggests
                        // otherwise: since AITD-394 these are the VIEWER's, stored per-user on
                        // the server, so changing them disturbs nobody else. The exception the
                        // copy names is manualSortOrder — choosing manual sort is yours, the
                        // arrangement it orders by is everyone's.
                        Text(NSLocalizedString("lists.sort_filters_personal_note", comment: ""))
                            .macFont(.caption).foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        MacListSortFiltersContent(list: currentList, fillsHeight: true)
                    }
                case .membership:
                    MacListMembershipTab(list: currentList)
                case .admin:
                    MacListAdminTab(list: currentList)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Spacer()
                Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.return)
            }
        }
        .padding(20)
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
        // Scrolls: a list with an image, task defaults and an AI model is taller than the
        // window, and a plain stack pushed the window's title and Done out of it (AITD-483).
        ScrollView {
            MacListEditSheet(existing: list, embedded: true)
        }
    }
}
#endif
