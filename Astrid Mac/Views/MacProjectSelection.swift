//  MacProjectSelection.swift
//  Astrid for Mac — the project sidebar sections' selection and gate (AITD-674, web AWTD-1660).
//  Its sections and their lists are the core's sidebar rule, through `SidebarProjects` (ADEV-16).
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
/// Each project is its own sidebar section, headed by its name the way Favorites and Lists are, its
/// lists the section's ordinary rows — a project is a custom favorites, not another level (ADEV-51,
/// following iOS ADEV-47). Which projects, in what order, with which lists: the core's sidebar rule
/// (`SidebarProjects`, ADEV-16). The header carries what the project row did (AITD-674): a click
/// opens the board, right-click offers New List in Project…, Rename and Edit Project… for the owner or an admin
/// (ADEV-65) and, for the owner, Delete Project…,
/// and a sidebar list dropped on it moves into the project — each only where core or server allows.
struct MacProjectsSidebarSection<ListRow: View>: View {
    let offered: Bool
    /// The sidebar's selection: the header opens its board there, and a list made in a project
    /// opens at once (AITD-681).
    @Binding var selection: String?
    let lists: [TaskList]
    @ViewBuilder let listRow: (TaskList) -> ListRow
    @StateObject private var projectService = ProjectService.shared
    /// Which projects have their lists hidden (ADEV-57), shared with iPhone and iPad.
    @StateObject private var collapse = SidebarProjectCollapse.shared
    @State private var newListProject: Project?
    // New Project… is in Settings ▸ Projects, not here (ADEV-357).
    /// Delete Project…, confirmed first (ADEV-27).
    @State private var deletingProject: Project?
    /// Rename Project… and Edit Project… (ADEV-65), shared with iPhone and iPad.
    @State private var renamingProject: Project?
    @State private var editingProject: Project?

    var body: some View {
        let entries = SidebarProjects.entries(offered: offered, projects: projectService.projects, lists: lists)
        if MacProjectActions.showsSection(offered: offered) {
            // The sections, the header's name and its chevron are iOS's (ADEV-170).
            SidebarProjectSections(entries: entries, collapse: collapse, header: { project, name in
                HStack(spacing: 0) {
                    projectHeader(project, name: name)
                    // Beside the header, not in it: a click on the name still opens the board.
                    SidebarProjectCollapseToggle(projectId: project.id, name: name, collapse: collapse)
                        .padding(.trailing, MacLayout.sidebarHeaderAccessoryTrailingInset)   // in the counts' column (ADEV-77)
                }
            }, listRow: listRow)
        }
    }

    private func projectHeader(_ project: Project, name: String) -> some View {
        let tag = MacProjectSelection.tag(projectId: project.id)
        let isOpen = selection == tag
        return Button { selection = tag } label: {
            SidebarProjectHeaderTitle(name: name)
                .foregroundStyle(isOpen ? Theme.accent : Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .help(String(format: NSLocalizedString("project_mode.open_board", comment: ""), name))
        .accessibilityAddTraits(isOpen ? [.isHeader, .isSelected] : .isHeader)
        .accessibilityIdentifier("sidebar.project.\(project.id)")
        // One sheet and one dialog per header, bound to that project: a modifier on the ForEach
        // would fan out to every section.
        .sheet(isPresented: Binding(get: { newListProject?.id == project.id },
                                    set: { if !$0 { newListProject = nil } })) {
            MacNewListInProjectSheet(project: project) { list in selection = list.id }
        }
        .sheet(isPresented: Binding(get: { editingProject?.id == project.id },
                                    set: { if !$0 { editingProject = nil } })) {
            EditProjectSheet(project: project)
        }
        .renameProjectAlert($renamingProject, for: project)
        .contextMenu {
            if MacListProjectControl.offersNewList(in: project.id,
                                                   moves: ListService.shared.projectMoves(listId: nil)) {
                Button(NSLocalizedString("projects.new_list_in", comment: "")) { newListProject = project }
                    .accessibilityIdentifier("sidebar.project.newList")
            }
            // The owner or a project admin, the server's bar for an edit (ADEV-65).
            if ListProjectControl.offersEdit(of: project, userId: AuthManager.shared.userId,
                                             offered: MacListProjectControl.isOffered) {
                Button(NSLocalizedString("projects.rename_project", comment: "")) { renamingProject = project }
                    .accessibilityIdentifier("sidebar.project.rename")
                Button(NSLocalizedString("projects.edit_project", comment: "")) { editingProject = project }
                    .accessibilityIdentifier("sidebar.project.edit")
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
