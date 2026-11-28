//  ProjectsSettings.swift
//  Settings ▸ Projects (ADEV-357): what the screen lists and what each row offers. Shared by
//  iPhone, iPad and Mac; the view (`ProjectsSettingsView`) only draws it.
//
//  Jon, 2026-11-27: "Remove New project from the side-bar and add to settings … add / edit should
//  also be in a separate settings tab on mac, web, ios." Who may edit or delete is not decided
//  here: it is `ListProjectControl.offersEdit` / `offersDelete`, the server's bar.

import AstridCore
import Foundation

enum ProjectsSettings {

    /// One project in the list, with what this person may do to it.
    struct Row: Identifiable, Equatable {
        let project: Project
        let canEdit: Bool
        let canDelete: Bool

        var id: String { project.id }
        var name: String { project.name }
        var color: String? { project.color }
    }

    /// The tab and the settings row exist only where Project Mode is on, as the sidebar's section does.
    static func isShown(offered: Bool) -> Bool { offered }

    /// The projects by name, or nothing with Project Mode off.
    static func rows(projects: [Project], userId: String?, offered: Bool) -> [Row] {
        guard offered else { return [] }
        return projects
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { project in
                Row(project: project,
                    canEdit: ListProjectControl.offersEdit(of: project, userId: userId, offered: offered),
                    canDelete: ListProjectControl.offersDelete(of: project, userId: userId, offered: offered))
            }
    }

    /// The name a new project is created with, or nil when there is nothing to create.
    static func projectName(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Create a project on its own; a refusal the server names is shown in its own words.
    @MainActor
    static func create(named name: String, then done: @escaping (Project) -> Void = { _ in }) {
        _Concurrency.Task {
            do {
                done(try await ProjectService.shared.createProject(name: name))
            } catch {
                if let key = ListProjectControl.refusalKey(for: error) {
                    AppErrorCenter.shared.show(NSLocalizedString(key, comment: ""))
                } else {
                    AppErrorCenter.shared.report("Create project", error)
                }
            }
        }
    }
}
