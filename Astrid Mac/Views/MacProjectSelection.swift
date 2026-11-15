//  MacProjectSelection.swift
//  Astrid for Mac — the Projects sidebar section's selection and gate (AITD-674, web AWTD-1660).
//
//  A project shares the sidebar's one selection with the lists, tagged `project:<id>` so it can
//  never collide with a list id. The shell asks this before anything list-shaped.

#if os(macOS)
import Foundation

enum MacProjectSelection {
    static let prefix = "project:"

    static func tag(projectId: String) -> String { prefix + projectId }

    /// The project a sidebar selection names, or nil for a list, My Tasks or Search.
    static func projectId(from selection: String?) -> String? {
        guard let selection, selection.hasPrefix(prefix) else { return nil }
        let id = String(selection.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }

    /// Projects show only when the deployment ships Project Mode AND this person has the
    /// `project_mode` flag (PRODUCT_CONTRACT.md §9).
    static func isOffered(deploymentShips: Bool, flagEnabled: Bool) -> Bool {
        deploymentShips && flagEnabled
    }

    /// The lists under a project in the sidebar: its own domain lists, in the order they arrive.
    static func lists(of projectId: String, in lists: [TaskList]) -> [TaskList] {
        lists.filter { $0.projectId == projectId && $0.isDomainList && $0.isVirtual != true }
    }

    /// Projects in the sidebar, sorted by name.
    static func sorted(_ projects: [Project]) -> [Project] {
        projects.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}
#endif

#if os(macOS)
import SwiftUI

/// A sidebar list row as a drag source for a project board (AITD-674). Off, the row is unchanged:
/// no drag gesture competes with its click or its task drop.
struct MacListRowDrag: ViewModifier {
    let listId: String
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.draggable(ProjectBoardListDrag.payload(listId: listId))
        } else {
            content
        }
    }
}
#endif
