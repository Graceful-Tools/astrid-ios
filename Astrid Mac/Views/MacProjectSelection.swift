//  MacProjectSelection.swift
//  Astrid for Mac — the Projects sidebar section's selection and gate (AITD-674, web AWTD-1660).
//  Its rows and their lists are the core's sidebar rule, through `SidebarProjects` (ADEV-16).
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

#if os(macOS)
/// The sidebar's Projects section, like Favorites (AITD-674): each project opens its board, and its
/// chevron expands it to its lists, drawn with the sidebar's own list row.
struct MacProjectsSidebarSection<ListRow: View>: View {
    let offered: Bool
    @Binding var expanded: Set<String>
    /// The sidebar's selection, so a list made in a project opens at once (AITD-681).
    @Binding var selection: String?
    let lists: [TaskList]
    @ViewBuilder let listRow: (TaskList) -> ListRow
    @StateObject private var projectService = ProjectService.shared
    @State private var newListProject: Project?
    /// New Project… (ADEV-27): the section is where a project is made, even the first one.
    @State private var creatingProject = false
    /// Delete Project…, confirmed first (ADEV-27).
    @State private var deletingProject: Project?

    var body: some View {
        // Which projects, in what order, with which lists: the core's sidebar rule (ADEV-16).
        let entries = SidebarProjects.entries(offered: offered, projects: projectService.projects, lists: lists)
        if MacProjectActions.showsSection(offered: offered) {
            Section(NSLocalizedString("project_mode.projects_heading", comment: "")) {
                newProjectRow
                ForEach(entries) { entry in
                    projectRow(entry.project, name: entry.name)
                    if expanded.contains(entry.id) {
                        ForEach(entry.lists) { list in
                            listRow(list).padding(.leading, AstridTokens.Space.s16)
                        }
                    }
                }
            }
        }
    }

    private var newProjectRow: some View {
        Button { creatingProject = true } label: {
            Label(NSLocalizedString("projects.new_project", comment: ""), systemImage: "plus")
                .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.newProject")
        .sheet(isPresented: $creatingProject) {
            MacNewProjectSheet { project in selection = MacProjectSelection.tag(projectId: project.id) }
        }
    }

    private func projectRow(_ project: Project, name: String) -> some View {
        let isExpanded = expanded.contains(project.id)
        let toggleKey = isExpanded ? "project_mode.hide_lists" : "project_mode.show_lists"
        return HStack(spacing: AstridTokens.Space.s4) {
            Button {
                if isExpanded { expanded.remove(project.id) } else { expanded.insert(project.id) }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right").macFont(.caption2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(format: NSLocalizedString(toggleKey, comment: ""), name))
            Label(name, systemImage: "rectangle.split.3x1")
                .help(String(format: NSLocalizedString("project_mode.open_board", comment: ""), name))
        }
        .tag(Optional(MacProjectSelection.tag(projectId: project.id)))
        .accessibilityIdentifier("sidebar.project.\(project.id)")
        // One sheet per row, bound to that row: a Section's modifiers fan out to every row, so a
        // single `sheet(item:)` there would be presented by each of them.
        .sheet(isPresented: Binding(get: { newListProject?.id == project.id },
                                    set: { if !$0 { newListProject = nil } })) {
            MacNewListInProjectSheet(project: project) { list in
                expanded.insert(project.id)
                selection = list.id
            }
        }
        .contextMenu {
            if MacListProjectControl.offersNewList(in: project.id,
                                                   moves: ListService.shared.projectMoves(listId: nil)) {
                Button(NSLocalizedString("projects.new_list_in", comment: "")) { newListProject = project }
                    .accessibilityIdentifier("sidebar.project.newList")
            }
            // Owner only, the server's rule (ADEV-46).
            if MacListProjectControl.offersDelete(of: project, userId: AuthManager.shared.userId,
                                                  offered: MacListProjectControl.isOffered) {
                Divider()
                Button(NSLocalizedString("projects.delete_project", comment: ""), role: .destructive) {
                    deletingProject = project
                }
                .accessibilityIdentifier("sidebar.project.delete")
            }
        }
        .confirmationDialog(
            String(format: NSLocalizedString("projects.delete_confirm", comment: ""), name),
            isPresented: Binding(get: { deletingProject?.id == project.id },
                                 set: { if !$0 { deletingProject = nil } })) {
            Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) {
                MacProjectActions.delete(projectId: project.id) {
                    selection = MacProjectActions.selection(afterDeleting: project.id, current: selection)
                    expanded.remove(project.id)
                }
            }
            Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("projects.delete_confirm_detail", comment: ""))
        }
        // Drop a sidebar list here to move it into this project (AITD-681) — only where the
        // core allows; anything else is refused and the list stays where it was.
        .dropDestination(for: String.self) { payloads, _ in
            let moved = payloads.compactMap(ProjectBoardListDrag.listId(from:)).filter { id in
                guard let list = lists.first(where: { $0.id == id }) else { return false }
                return MacListProjectControl.acceptsDrop(
                    of: list, onto: project.id, moves: ListService.shared.projectMoves(listId: id))
            }
            moved.forEach { MacListProjectControl.move(listId: $0, to: project.id) }
            return !moved.isEmpty
        }
    }
}
#endif
