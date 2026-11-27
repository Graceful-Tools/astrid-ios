//  GoalLinks.swift
//  Linking and unlinking goals on a task or a list (ADEV-328; web ADEV-276 `GoalChips`).
//
//  The writes are astrid-core's (`setTaskGoalLinks`, `unlinkTaskGoal`, `getListGoalLinks`,
//  `setListGoalLinks`, `unlinkListGoal`): sent at once, never journalled, and the server's answer —
//  the whole new set — replaces what is held. `GoalChipsModel` sorts the links into the chips web
//  draws; nothing here decides who may edit (the view passes that in from `ListPermissions`).

import AstridCore
import Foundation

/// The goals a list serves (`GET /api/v1/lists/{id}/goal-links`). `projectId` is nil for a list in
/// no project, which has no goals to link.
struct ListGoalLinks: Decodable, Equatable {
    var listId: String = ""
    var projectId: String?
    var links: [GoalLink] = []

    init(listId: String, projectId: String?, links: [GoalLink]) {
        self.listId = listId
        self.projectId = projectId
        self.links = links
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        listId = try container.decodeIfPresent(String.self, forKey: .listId) ?? ""
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        links = try container.decodeIfPresent([GoalLink].self, forKey: .links) ?? []
    }

    private enum CodingKeys: String, CodingKey { case listId, projectId, links }
}

/// The goal-link writes, as closures so tests can stand in for the core.
struct GoalLinkWrites {
    /// Task id, its own goal ids in the project, the project id.
    var setTask: @MainActor (String, [String], String?) async throws -> TaskGoalLinks
    /// Task id, goal id, project id.
    var unlinkTask: @MainActor (String, String, String?) async throws -> TaskGoalLinks
    var readList: @MainActor (String) async throws -> ListGoalLinks
    var setList: @MainActor (String, [String]) async throws -> ListGoalLinks
    var unlinkList: @MainActor (String, String) async throws -> ListGoalLinks

    static var core: GoalLinkWrites {
        func run<T: Decodable>(_ kind: String, _ fields: [String: CoreValue], as type: T.Type) async throws -> T {
            try await AppCore.shared.session.run(CoreCommand(kind: kind, fields), as: type)
        }
        func fields(_ base: [String: CoreValue], projectId: String?) -> [String: CoreValue] {
            var all = base
            if let projectId { all["projectId"] = .value(projectId) }
            return all
        }
        return GoalLinkWrites(
            setTask: { taskId, goalIds, projectId in
                try await run("setTaskGoalLinks", fields(["taskId": .value(taskId), "goalIds": .value(goalIds)], projectId: projectId),
                              as: TaskGoalLinks.self)
            },
            unlinkTask: { taskId, goalId, projectId in
                try await run("unlinkTaskGoal", fields(["taskId": .value(taskId), "goalId": .value(goalId)], projectId: projectId),
                              as: TaskGoalLinks.self)
            },
            readList: { try await run("getListGoalLinks", ["listId": .value($0)], as: ListGoalLinks.self) },
            setList: { try await run("setListGoalLinks", ["listId": .value($0), "goalIds": .value($1)], as: ListGoalLinks.self) },
            unlinkList: { try await run("unlinkListGoal", ["listId": .value($0), "goalId": .value($1)], as: ListGoalLinks.self) })
    }
}

/// The chips for one task or list in one project, as web's `GoalChips` sorts them.
struct GoalChipsModel: Equatable {
    struct Chip: Equatable, Identifiable {
        let goalId: String
        let statement: String
        var id: String { goalId }
    }

    /// The task's own links, or all of a list's: removable when editable.
    let own: [Chip]
    /// A task's links inherited from its lists: read-only, unlinked on the list.
    let inherited: [Chip]
    /// The project's goals not linked either way: the Add menu, when editable.
    let addable: [Chip]
    let canEdit: Bool

    /// - Parameters:
    ///   - isList: a list's links are all its own; a task's `via: "list"` ones are inherited.
    init(links: [GoalLink], goals: [ProjectGoal], projectId: String, isList: Bool, canEdit: Bool) {
        let inProject = links.filter { $0.projectId == projectId }
        let statements = Dictionary(goals.compactMap { goal in goal.id.map { ($0, goal.statement) } },
                                    uniquingKeysWith: { first, _ in first })
        func chip(_ link: GoalLink) -> Chip {
            Chip(goalId: link.goalId, statement: statements[link.goalId] ?? link.statement)
        }
        own = inProject.filter { isList || $0.via != "list" }.map(chip)
        inherited = isList ? [] : inProject.filter { $0.via == "list" }.map(chip)
        let linked = Set(own.map(\.goalId) + inherited.map(\.goalId))
        addable = goals.compactMap { goal in
            guard let id = goal.id, !linked.contains(id) else { return nil }
            return Chip(goalId: id, statement: goal.statement)
        }
        self.canEdit = canEdit
    }

    /// Nothing to draw: no links, and nothing this person could add.
    var isEmpty: Bool { own.isEmpty && inherited.isEmpty && !(canEdit && !addable.isEmpty) }

    /// The own goal ids after adding one, for the replace-all write.
    func ownIds(adding goalId: String) -> [String] {
        own.map(\.goalId) + [goalId]
    }
}
