//  SidebarProjects.swift
//  The sidebar's Projects section, as astrid-core draws it (ADEV-16; core AWTD-1681, D70).
//
//  Which projects are rows, in what order, and which lists sit under each is the core's `sidebar`
//  rule — a list under the project its own `projectId` names, domain lists only, both by name.
//  This only translates: the app's models go in, the core's ids come back as the same models.

import AstridCore
import Foundation

/// One row of the Projects section: a project, and the lists it expands to, in drawing order.
struct SidebarProjectEntry: Identifiable, Equatable {
    let project: Project
    /// The name the row shows — the project's, or its key when it has none (the core's choice).
    let name: String
    let lists: [TaskList]
    var id: String { project.id }
}

enum SidebarProjects {
    /// The section, or `[]` when none is drawn: Project Mode not offered, no projects, or no
    /// answer from the core. Saved filters (virtual lists) are not sidebar places and stay out.
    static func entries(offered: Bool, projects: [Project], lists: [TaskList]) -> [SidebarProjectEntry] {
        let places = lists.filter { $0.isVirtual != true }
        let rows = CoreRules.sidebarProjects(
            lists: places.map {
                SidebarListInput(id: $0.id, name: $0.name, projectId: $0.projectId, listType: $0.listType)
            },
            projects: offered ? projects.map {
                SidebarProjectInput(id: $0.id, name: $0.name, key: $0.key, color: $0.color)
            } : nil
        ) ?? []
        let projectsById = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let listsById = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return rows.compactMap { row in
            guard let project = projectsById[row.id] else { return nil }
            return SidebarProjectEntry(project: project, name: row.name, lists: row.listIds.compactMap { listsById[$0] })
        }
    }
}
