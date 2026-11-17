//  ListProjectControl.swift
//  Moving a list into and out of a project, and creating a list inside one — shared by Mac
//  (AITD-681) and iPhone/iPad (AITD-682); core AITD-680 / D68, server AWTD-1702.
//
//  Jon, 2026-11-15: "How can I move lists into / out of projects or create a new list in a
//  project? Cannot figure it out." Every decision here is astrid-core's `listProjectMoves` (owner
//  or admin of the list AND of each project it touches; creating needs owner/admin/member of the
//  project): this file draws the answer and sends the core's commands, it never restates the rule.

import AstridCore
import SwiftUI

enum ListProjectControl {

    /// Projects are drawn only where Project Mode is on, as the sidebar's section is.
    @MainActor
    static var isOffered: Bool {
        isOffered(deploymentShips: ServerCapabilityService.shared.capabilities.product.projectMode,
                  flagEnabled: FeatureFlagService.shared.isEnabled(.projectMode))
    }

    /// The deployment ships Project Mode AND this person has the `project_mode` flag
    /// (PRODUCT_CONTRACT.md §9).
    static func isOffered(deploymentShips: Bool, flagEnabled: Bool) -> Bool {
        deploymentShips && flagEnabled
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

    /// Whether a project's sidebar row offers Delete Project… (ADEV-46). Deleting is the
    /// server's owner-only rule (`DELETE /api/v1/projects/:id`, 403 for anyone else), so the
    /// action is drawn for the owner. A cached board whose owner is unknown keeps it and lets the
    /// server decide — its refusal is named by `deleteRefusalKey`.
    static func offersDelete(of project: Project, userId: String?, offered: Bool) -> Bool {
        guard offered, let userId else { return false }
        guard let ownerId = project.ownerId else { return true }
        return ownerId == userId
    }

    /// Whether a project's sidebar row offers Rename Project… and Edit Project… (ADEV-65). The
    /// server's bar for `PATCH /api/v1/projects/:id` is the owner or a project admin (ADEV-48/67);
    /// anyone else gets 403. A cached board whose owner is unknown keeps the actions and lets the
    /// server decide, as Delete does.
    static func offersEdit(of project: Project, userId: String?, offered: Bool) -> Bool {
        guard offered, let userId else { return false }
        guard let ownerId = project.ownerId else { return true }
        if ownerId == userId { return true }
        return project.members?.contains { $0.userId == userId && $0.role == "admin" } ?? false
    }

    /// What saving the edit sheet sends: only the fields that changed (ADEV-65). Nil when the name
    /// is blank, which the server refuses (`PROJECT_NAME_REQUIRED`). A blank description clears
    /// one that was set; a colour the server would refuse is never sent.
    static func edit(of project: Project, name: String, description: String, color: String) -> ProjectEdit? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedDescription = project.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ProjectEdit(
            name: name == project.name ? nil : name,
            description: description == storedDescription ? nil : description,
            color: ListColors.change(from: project.color ?? "", to: color))
    }

    /// The localized reason a project edit was refused, or nil for any other failure.
    static func editRefusalKey(for error: Error) -> String? {
        guard let failure = error as? CoreFailure else { return nil }
        switch failure.code {
        case "PROJECT_COLOR_INVALID": return "projects.color_invalid"
        case "PROJECT_NAME_REQUIRED": return "projects.name_required"
        default: return failure.status == 403 ? "projects.edit_forbidden" : nil
        }
    }

    /// The localized reason a project delete was refused, or nil for any other failure.
    static func deleteRefusalKey(for error: Error) -> String? {
        (error as? CoreFailure)?.status == 403 ? "projects.delete_forbidden" : nil
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

    /// Delete a project: its lists stay, outside any project (ADEV-46; Mac ADEV-27).
    @MainActor
    static func deleteProject(id projectId: String, then done: @escaping () -> Void) {
        _Concurrency.Task {
            do {
                _ = try await ProjectService.shared.deleteProject(id: projectId)
                done()
            } catch {
                if let key = deleteRefusalKey(for: error) {
                    AppErrorCenter.shared.show(NSLocalizedString(key, comment: ""))
                } else {
                    AppErrorCenter.shared.report("Delete project", error)
                }
            }
        }
    }

    /// Rename or edit a project (ADEV-65). The core writes the cache first and puts it back if
    /// the server refuses; a refusal is named.
    @MainActor
    static func updateProject(id projectId: String, edit: ProjectEdit) {
        guard !edit.isEmpty else { return }
        _Concurrency.Task {
            do {
                _ = try await ProjectService.shared.updateProject(id: projectId, edit: edit)
            } catch {
                if let key = editRefusalKey(for: error) {
                    AppErrorCenter.shared.show(NSLocalizedString(key, comment: ""))
                } else {
                    AppErrorCenter.shared.report("Edit project", error)
                }
            }
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
struct ListProjectMenu: View {
    let list: TaskList

    var body: some View {
        let choices = ListProjectControl.menuChoices(
            offered: ListProjectControl.isOffered,
            moves: ListService.shared.projectMoves(listId: list.id),
            projects: ProjectService.shared.projects)
        let destinations = choices.compactMap { choice -> (String, String)? in
            if case let .moveTo(id, name) = choice { return (id, name) } else { return nil }
        }
        if !destinations.isEmpty {
            Menu(NSLocalizedString("projects.move_to", comment: "")) {
                ForEach(destinations, id: \.0) { id, name in
                    Button(name) { ListProjectControl.move(listId: list.id, to: id) }
                }
            }
        }
        if choices.contains(.removeFromProject) {
            // A context menu cannot host a dialog, and the menu row is a deliberate second
            // step already; the settings popup, one click from a mistake, is the one that asks.
            Button(NSLocalizedString("projects.remove_from", comment: "")) {
                ListProjectControl.move(listId: list.id, to: nil)
            }
        }
    }
}
