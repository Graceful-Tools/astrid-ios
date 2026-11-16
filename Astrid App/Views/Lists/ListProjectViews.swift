//  ListProjectViews.swift
//  iPhone/iPad: moving a list into and out of a project, and creating a list inside one
//  (AITD-682; Mac AITD-681, core AITD-680 / D68, server AWTD-1702).
//
//  Every offer is the core's `listProjectMoves`, read through `ListProjectControl` — shared with
//  the Mac — so these views only draw it.

import SwiftUI

// MARK: - List Settings ▸ Admin ▸ Project

/// The Project row: None · the core's destinations · New Project… Read-only, naming the project,
/// when the list may not leave it; choosing None asks first.
struct ListProjectSettingsRow: View {
    let list: TaskList
    @ThemedPalette private var palette
    @StateObject private var projectService = ProjectService.shared
    @StateObject private var listService = ListService.shared
    @State private var confirmingLeave = false

    var body: some View {
        let picker = ListProjectControl.picker(
            list: list,
            moves: listService.projectMoves(listId: list.id),
            projects: projectService.projects,
            canEditSettings: ListPermissions.canEditSettings(list, userId: AuthManager.shared.userId))
        if ListProjectControl.isOffered, picker.readOnly || !picker.options.isEmpty {
            Group {
                if picker.readOnly {
                    LabeledContent(NSLocalizedString("projects.project", comment: ""),
                                   value: label(picker.current))
                } else {
                    Picker(NSLocalizedString("projects.project", comment: ""), selection: Binding(
                        get: { picker.current },
                        set: { choose($0, current: picker.current) })) {
                        ForEach(picker.options, id: \.self) { option in
                            Text(label(option)).tag(option)
                        }
                    }
                    .foregroundColor(palette.textPrimary)
                }
            }
            .accessibilityIdentifier("listSettings.project")
            .confirmationDialog(
                String(format: NSLocalizedString("projects.leave_confirm", comment: ""),
                       list.name, label(picker.current)),
                isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button(NSLocalizedString("projects.remove_from", comment: ""), role: .destructive) {
                    ListProjectControl.move(listId: list.id, to: nil)
                }
                Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("projects.leave_confirm_detail", comment: ""))
            }
        }
    }

    private func label(_ option: ListProjectControl.Option) -> String {
        switch option {
        case .none: return NSLocalizedString("projects.none", comment: "")
        case let .project(_, name): return name
        case .newProject: return NSLocalizedString("projects.new_project", comment: "")
        }
    }

    private func choose(_ option: ListProjectControl.Option, current: ListProjectControl.Option) {
        switch ListProjectControl.action(choosing: option, current: current) {
        case .nothing: break
        case let .move(projectId): ListProjectControl.move(listId: list.id, to: projectId)
        case .confirmLeave: confirmingLeave = true
        case .createProject:
            let list = list
            AppActions.perform("Create board") {
                _ = try await ProjectService.shared.createBoardForList(list)
            }
        }
    }
}

// MARK: - New List in Project…

struct NewListInProjectSheet: View {
    let project: Project
    var onCreated: (TaskList) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField(NSLocalizedString("lists.list_name", comment: ""), text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(create)
                    .accessibilityIdentifier("projects.newListName")
            }
            .navigationTitle(String(format: NSLocalizedString("projects.new_list_in_title", comment: ""),
                                    project.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("actions.cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("actions.create", comment: ""), action: create)
                        .disabled(trimmed.isEmpty)
                        .accessibilityIdentifier("projects.newListCreate")
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func create() {
        guard !trimmed.isEmpty else { return }
        ListProjectControl.createList(named: trimmed, in: project.id, then: onCreated)
        dismiss()
    }
}

// MARK: - The sidebar's Projects section

/// Projects, like Favorites: each project row expands to its lists (the core's sidebar rule,
/// `SidebarProjects`). Long-press a project for New List in Project… and, for its owner, Delete
/// Project… (ADEV-46); on iPad, drop a sidebar list on a project row to move it there — each only
/// where the core or server allows.
struct SidebarProjectsSection<ListRow: View>: View {
    let lists: [TaskList]
    /// Opens a list (the sidebar's own tap), so a list made in a project opens at once.
    let open: (TaskList) -> Void
    @ViewBuilder let listRow: (TaskList) -> ListRow
    @ThemedPalette private var palette
    @StateObject private var projectService = ProjectService.shared
    @StateObject private var listService = ListService.shared
    @State private var expanded: Set<String> = []
    @State private var newListProject: Project?
    @State private var deletingProject: Project?

    var body: some View {
        let entries = SidebarProjects.entries(offered: ListProjectControl.isOffered,
                                              projects: projectService.projects, lists: lists)
        if !entries.isEmpty {
            Section(NSLocalizedString("project_mode.projects_heading", comment: "")) {
                ForEach(entries) { entry in
                    projectRow(entry.project, name: entry.name)
                    if expanded.contains(entry.id) {
                        ForEach(entry.lists) { list in
                            listRow(list).padding(.leading, AstridTokens.Space.s16)
                        }
                    }
                }
            }
            .sheet(item: $newListProject) { project in
                NewListInProjectSheet(project: project) { list in
                    expanded.insert(project.id)
                    open(list)
                }
            }
        }
    }

    private func projectRow(_ project: Project, name: String) -> some View {
        let isExpanded = expanded.contains(project.id)
        let toggleKey = isExpanded ? "project_mode.hide_lists" : "project_mode.show_lists"
        return Button {
            if isExpanded { expanded.remove(project.id) } else { expanded.insert(project.id) }
        } label: {
            HStack(spacing: SidebarBrandHeader.spacing) {
                Image(systemName: "rectangle.split.3x1")
                    .foregroundColor(Theme.accent)
                    .frame(width: SidebarBrandHeader.logoSize)
                Text(name)
                    .font(Theme.Typography.body())
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(Theme.Typography.caption1())
                    .foregroundColor(palette.textMuted)
            }
            .padding(.vertical, Theme.spacing8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityHint(String(format: NSLocalizedString(toggleKey, comment: ""), name))
        .accessibilityIdentifier("sidebar.project.\(project.id)")
        .contextMenu {
            if ListProjectControl.offersNewList(in: project.id, moves: listService.projectMoves(listId: nil)) {
                Button {
                    newListProject = project
                } label: {
                    Label(NSLocalizedString("projects.new_list_in", comment: ""), systemImage: "plus")
                }
                .accessibilityIdentifier("sidebar.project.newList")
            }
            if ListProjectControl.offersDelete(of: project, userId: AuthManager.shared.userId,
                                               offered: ListProjectControl.isOffered) {
                Button(role: .destructive) {
                    deletingProject = project
                } label: {
                    Label(NSLocalizedString("projects.delete_project", comment: ""), systemImage: "trash")
                }
                .accessibilityIdentifier("sidebar.project.delete")
            }
        }
        // One dialog per row, bound to that row (a Section's modifiers fan out to every row).
        .confirmationDialog(
            String(format: NSLocalizedString("projects.delete_confirm", comment: ""), name),
            isPresented: Binding(get: { deletingProject?.id == project.id },
                                 set: { if !$0 { deletingProject = nil } }),
            titleVisibility: .visible) {
            Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) {
                ListProjectControl.deleteProject(id: project.id) {
                    expanded.remove(project.id)
                }
            }
            .accessibilityIdentifier("sidebar.project.deleteConfirm")
            Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("projects.delete_confirm_detail", comment: ""))
        }
        // iPad: drop a sidebar list here to move it into this project (AITD-682).
        .dropDestination(for: String.self) { payloads, _ in
            let moved = payloads.compactMap(ProjectBoardListDrag.listId(from:)).filter { id in
                guard let list = lists.first(where: { $0.id == id }) else { return false }
                return ListProjectControl.acceptsDrop(of: list, onto: project.id,
                                                      moves: listService.projectMoves(listId: id))
            }
            moved.forEach { ListProjectControl.move(listId: $0, to: project.id) }
            return !moved.isEmpty
        }
    }
}
