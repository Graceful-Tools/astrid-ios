//  MacListProjectControls.swift
//  Astrid for Mac — moving a list into and out of a project, and creating a list inside one
//  (AITD-681; core AITD-680 / D68, server AWTD-1702).
//
//  Jon, 2026-11-15: "How can I move lists into / out of projects or create a new list in a
//  project? Cannot figure it out." The only control was Create Board, which always makes a NEW
//  project. Every decision here is astrid-core's `listProjectMoves` (owner or admin of the list
//  AND of each project it touches; creating needs owner/admin/member of the project): this file
//  draws the answer and sends the core's commands, it never restates the rule.

#if os(macOS)
import AstridCore
import SwiftUI

enum MacListProjectControl {

    /// Projects are drawn only where Project Mode is on, as the sidebar's section is.
    @MainActor
    static var isOffered: Bool {
        MacProjectSelection.isOffered(
            deploymentShips: ServerCapabilityService.shared.capabilities.product.projectMode,
            flagEnabled: FeatureFlagService.shared.isEnabled(.projectMode))
    }

    /// The list menu's project entries: exactly the core's moves, nothing when Project Mode is off.
    static func menuChoices(offered: Bool, moves: ListProjectMoves, projects: [Project]) -> [ListProjectMoves.Choice] {
        offered ? moves.choices(projects: projects) : []
    }

    /// One row of List Settings' Project popup.
    enum Option: Hashable {
        case none
        case project(id: String, name: String)
        case newProject
    }

    /// What List Settings' Project row shows.
    struct Picker: Equatable {
        /// The project the list is in, by name, or nil.
        var current: Option
        /// The popup's rows. Empty when the row is read-only or has nothing to offer.
        var options: [Option]
        /// In a project the person may not take it out of: name it, offer nothing.
        var readOnly: Bool
    }

    /// The popup for `list`: None · the core's destinations · New Project… (a list in no project,
    /// for someone who may change its settings — the existing from-list flow).
    static func picker(list: TaskList, moves: ListProjectMoves, projects: [Project], canEditSettings: Bool) -> Picker {
        let current: Option = list.projectId.flatMap { id in
            projects.first { $0.id == id }.map { .project(id: id, name: $0.name) }
        } ?? .none
        if list.projectId != nil, !moves.canLeave {
            return Picker(current: current, options: [], readOnly: true)
        }
        var options: [Option] = [.none]
        if case .project = current { options.append(current) }
        for choice in moves.choices(projects: projects) {
            if case let .moveTo(id, name) = choice { options.append(.project(id: id, name: name)) }
        }
        if list.projectId == nil, canEditSettings { options.append(.newProject) }
        return Picker(current: current, options: options == [.none] ? [] : options, readOnly: false)
    }

    /// What choosing a popup row does. `confirmLeave` asks first: leaving can hide tasks that sit
    /// in the project's own columns until the list joins one with them again.
    enum Action: Equatable {
        case nothing
        case move(projectId: String)
        case confirmLeave
        case createProject
    }

    static func action(choosing option: Option, current: Option) -> Action {
        guard option != current else { return .nothing }
        switch option {
        case .none: return .confirmLeave
        case let .project(id, _): return .move(projectId: id)
        case .newProject: return .createProject
        }
    }

    /// Where a new list may be created from a project's sidebar row.
    static func offersNewList(in projectId: String, moves: ListProjectMoves) -> Bool {
        moves.creatableIn.contains(projectId)
    }

    /// Whether a list dragged onto a project row may land there.
    static func acceptsDrop(of list: TaskList, onto projectId: String, moves: ListProjectMoves) -> Bool {
        list.projectId != projectId && moves.destinations.contains(projectId)
    }

    /// The localized reason for a refusal the core or server names, or nil for any other failure.
    static func refusalKey(for error: Error) -> String? {
        guard let code = (error as? CoreFailure)?.code else { return nil }
        switch code {
        case "LIST_PROJECT_MOVE_FORBIDDEN", "PROJECT_ATTACH_FORBIDDEN", "PROJECT_DETACH_FORBIDDEN":
            return "projects.move_forbidden"
        case "LIST_PROJECT_CREATE_FORBIDDEN", "PROJECT_CREATE_FORBIDDEN":
            return "projects.create_forbidden"
        default:
            return nil
        }
    }

    // MARK: - Doing it

    /// Move `listId` into `projectId`, or out of its project with nil.
    @MainActor
    static func move(listId: String, to projectId: String?) {
        run("Move list to project") {
            try await ListService.shared.setListProject(listId: listId, projectId: projectId)
        }
    }

    /// Create a list inside a project; hands back the new list (to select it).
    @MainActor
    static func createList(named name: String, in projectId: String, then done: @escaping (TaskList) -> Void) {
        run("Create list in project") {
            let list = try await ListService.shared.createList(name: name, projectId: projectId)
            done(list)
        }
    }

    @MainActor
    private static func run(_ context: String, _ op: @escaping () async throws -> Void) {
        _Concurrency.Task {
            do { try await op() } catch {
                if let key = refusalKey(for: error) {
                    AppErrorCenter.shared.show(NSLocalizedString(key, comment: ""))
                } else {
                    AppErrorCenter.shared.report(context, error)
                }
            }
        }
    }
}

// MARK: - The list menu's entries

/// "Move to Project ▸" and "Remove from Project", in a list's right-click menu.
struct MacListProjectMenu: View {
    let list: TaskList

    var body: some View {
        let choices = MacListProjectControl.menuChoices(
            offered: MacListProjectControl.isOffered,
            moves: ListService.shared.projectMoves(listId: list.id),
            projects: ProjectService.shared.projects)
        let destinations = choices.compactMap { choice -> (String, String)? in
            if case let .moveTo(id, name) = choice { return (id, name) } else { return nil }
        }
        if !destinations.isEmpty {
            Menu(NSLocalizedString("projects.move_to", comment: "")) {
                ForEach(destinations, id: \.0) { id, name in
                    Button(name) { MacListProjectControl.move(listId: list.id, to: id) }
                }
            }
        }
        if choices.contains(.removeFromProject) {
            // A context menu cannot host a dialog, and the menu row is a deliberate second
            // step already; the settings popup, one click from a mistake, is the one that asks.
            Button(NSLocalizedString("projects.remove_from", comment: "")) {
                MacListProjectControl.move(listId: list.id, to: nil)
            }
        }
    }
}

// MARK: - List Settings ▸ Admin ▸ Project

struct MacListProjectRow: View {
    let list: TaskList
    @StateObject private var projectService = ProjectService.shared
    @StateObject private var listService = ListService.shared
    @State private var confirmingLeave = false

    var body: some View {
        let picker = MacListProjectControl.picker(
            list: list,
            moves: listService.projectMoves(listId: list.id),
            projects: projectService.projects,
            canEditSettings: ListPermissions.canEditSettings(list, userId: AuthManager.shared.userId))
        if MacListProjectControl.isOffered, picker.readOnly || !picker.options.isEmpty {
            HStack {
                Text(NSLocalizedString("projects.project", comment: ""))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if picker.readOnly {
                    Text(label(picker.current)).foregroundStyle(Theme.textSecondary)
                } else {
                    SwiftUI.Picker("", selection: Binding(
                        get: { picker.current },
                        set: { choose($0, current: picker.current) })) {
                        ForEach(picker.options, id: \.self) { option in
                            Text(label(option)).tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("listSettings.project")
                }
            }
            .padding(.horizontal, 4)
            .confirmationDialog(
                String(format: NSLocalizedString("projects.leave_confirm", comment: ""),
                       list.name, label(picker.current)),
                isPresented: $confirmingLeave) {
                Button(NSLocalizedString("projects.remove_from", comment: ""), role: .destructive) {
                    MacListProjectControl.move(listId: list.id, to: nil)
                }
                Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("projects.leave_confirm_detail", comment: ""))
            }
        }
    }

    private func label(_ option: MacListProjectControl.Option) -> String {
        switch option {
        case .none: return NSLocalizedString("projects.none", comment: "")
        case let .project(_, name): return name
        case .newProject: return NSLocalizedString("projects.new_project", comment: "")
        }
    }

    private func choose(_ option: MacListProjectControl.Option, current: MacListProjectControl.Option) {
        switch MacListProjectControl.action(choosing: option, current: current) {
        case .nothing: break
        case let .move(projectId): MacListProjectControl.move(listId: list.id, to: projectId)
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

struct MacNewListInProjectSheet: View {
    let project: Project
    var onCreated: (TaskList) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AstridTokens.Space.s12) {
            Text(String(format: NSLocalizedString("projects.new_list_in_title", comment: ""), project.name))
                .macFont(.headline).foregroundStyle(Theme.textPrimary)
            TextField(NSLocalizedString("lists.list_name", comment: ""), text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("projects.newListName")
                .onSubmit(create)
            HStack {
                Spacer()
                Button(NSLocalizedString("actions.cancel", comment: "")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(NSLocalizedString("actions.create", comment: ""), action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
                    .accessibilityIdentifier("projects.newListCreate")
            }
        }
        .padding(AstridTokens.Space.s20)
        .frame(minWidth: 320)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func create() {
        guard !trimmed.isEmpty else { return }
        MacListProjectControl.createList(named: trimmed, in: project.id, then: onCreated)
        dismiss()
    }
}
#endif
