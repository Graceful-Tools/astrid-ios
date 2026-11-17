//  SidebarProjectCollapse.swift
//  Hide or show a project's lists in the sidebar (ADEV-57) — iPhone, iPad and Mac.
//
//  Jon, 2026-11-16: "enable projects to hide/show the lists in project". A project's header
//  carries a chevron; tapping it folds the section to just its name. Lists show until hidden, and
//  what was hidden is remembered on this device, the way the sidebar's other view state is. Web's
//  `ProjectsSection` keeps the same choice per page view (`projectMode.showLists`/`hideLists`).

import Combine
import Foundation

@MainActor
final class SidebarProjectCollapse: ObservableObject {
    static let shared = SidebarProjectCollapse()

    static let defaultsKey = "sidebar.collapsedProjectIds"

    @Published private(set) var collapsed: Set<String>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        collapsed = Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    func isCollapsed(_ projectId: String) -> Bool {
        collapsed.contains(projectId)
    }

    func toggle(_ projectId: String) {
        if collapsed.remove(projectId) == nil { collapsed.insert(projectId) }
        save()
    }

    /// The lists a section draws: none while its project is folded.
    func visibleLists<Item>(_ lists: [Item], in projectId: String) -> [Item] {
        isCollapsed(projectId) ? [] : lists
    }

    /// The chevron's VoiceOver label — web's `projectMode.hideLists` / `showLists`.
    func toggleLabel(for projectId: String, name: String) -> String {
        let key = isCollapsed(projectId) ? "projects.show_lists" : "projects.hide_lists"
        return String(format: NSLocalizedString(key, comment: ""), name)
    }

    private func save() {
        defaults.set(collapsed.sorted(), forKey: Self.defaultsKey)
    }
}
