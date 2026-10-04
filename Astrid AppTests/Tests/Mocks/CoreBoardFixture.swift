//  CoreBoardFixture.swift
//  A project board, asked of a throwaway astrid-core holding just the given lists, tasks and board
//  — the parity spec for AITD-461, which runs the tests the Swift `ProjectStatus` rules had
//  (columns, which column a card is in, a column's cards, moves, drops) against the core's
//  `board`, `taskStatusOptions`, `setTaskStatus`, `moveTaskToColumn` and `dropBoardCard`.
//  The Mac test target has the same file.

import AstridCore
import Foundation
@testable import Astrid_App

enum CoreBoardFixture {
    /// The board a test's lists stand for when none of them carries a project.
    static let projectId = "fixture-project"
    static let domainListId = "fixture-board"

    /// What a move left the task as: its lists, whether it is finished, its column's role.
    struct Move: Equatable {
        let listIds: [String]
        let completed: Bool
        let statusRole: String?
    }

    /// What a drop left: the move, and the board list's manual order.
    struct Reorder: Equatable {
        let listIds: [String]
        let completed: Bool
        let newManualOrder: [String]
        let statusRole: String?
    }

    /// What a move to a column asked of the task, as the old planner named it: nothing, the column
    /// alone, the column then completion, or un-completion then the column. The ORDER of the two
    /// writes is the core's (its D45 tests); from here a plan is told by what changed.
    enum Plan: Equatable {
        case none
        case setLists([String], statusRole: String)
        case complete([String], statusRole: String)
        case uncomplete([String], statusRole: String)
    }

    // MARK: - Seeding

    /// The tasks as the core stores them: one membership array, the union of both of Swift's —
    /// a task the core hands the app always carries `listIds`.
    private static func stored(_ tasks: [Task]) -> [Task] {
        tasks.map { task in
            var copy = task
            copy.listIds = taskListMembershipIdsInOrder(task)
            copy.lists = nil
            return copy
        }
    }

    /// An in-memory core holding `tasks`, `lists` and `projects`.
    static func session(tasks: [Task] = [], lists: [TaskList], projects: [Project]) throws -> CoreSession {
        let session = try CoreSession(cachePath: ":memory:", credentials: CoreSearchFixture.NoCredentials(),
                                      background: false)
        var command = CoreCommand(kind: "seedCache")
        command.set("tasks", stored(tasks))
        command.set("lists", lists)
        command.set("projects", projects)
        struct Seeded: Decodable { let seeded: Bool }
        _ = try session.runBlocking(command, as: Seeded.self)
        return session
    }

    /// The custom states a set of columns stands for — the ones that are not a default.
    static func customStates(of columns: [ProjectBoardColumn]) -> [ProjectCustomState] {
        columns.enumerated().compactMap { index, column in
            guard column.kind == .status, !["ready", "doing", "waiting"].contains(column.id) else { return nil }
            return ProjectCustomState(role: column.id, name: column.name, order: index)
        }
    }

    /// The board `lists` belong to: the first project one of them names, or the fixture's own.
    private static func board(for lists: [TaskList], memberOf task: Task? = nil) -> String {
        let membership = task.map { Set(taskListMembershipIdsInOrder($0)) }
        return lists.first { list in
            list.projectId != nil && list.listType != "status" && (membership?.contains(list.id) ?? true)
        }?.projectId ?? projectId
    }

    /// `lists`, plus the fixture's own board list when none of them is on `project`.
    private static func withDomain(_ lists: [TaskList], project: String) -> (lists: [TaskList], domain: String) {
        if let domain = lists.first(where: { $0.projectId == project && $0.listType != "status" }) {
            return (lists, domain.id)
        }
        var board = TaskList(id: domainListId, name: "Board")
        board.projectId = project
        return (lists + [board], domainListId)
    }

    // MARK: - Columns

    /// A board's own columns as the core reads `customStates` (`board::parse_custom_states`):
    /// unusable entries dropped, role and name trimmed, the first of a role kept, by order.
    static func parsedStates(_ raw: [ProjectCustomState]?) -> [ProjectCustomState] {
        customStates(of: columns([], customStates: raw)).map {
            ProjectCustomState(role: $0.role, name: $0.name)
        }
    }

    /// The board's columns, as the core draws them for these lists and custom states.
    static func columns(_ lists: [TaskList], customStates: [ProjectCustomState]? = nil) -> [ProjectBoardColumn] {
        let project = board(for: lists)
        let (seeded, domain) = withDomain(lists, project: project)
        let session = try! session(lists: seeded,
                                   projects: [Project(id: project, name: "Board", customStates: customStates)])
        return try! drawn(session, listId: domain).map(\.column)
    }

    /// The column `task` is in, on its own board with these custom states.
    static func columnId(_ task: Task, lists: [TaskList], customStates: [ProjectCustomState]? = nil) -> String {
        let project = board(for: lists, memberOf: task)
        var (seeded, domain) = withDomain(lists, project: project)
        var placed = task
        if !taskListMembershipIdsInOrder(task).contains(where: { id in seeded.contains { $0.id == id && $0.projectId == project } }) {
            placed.listIds = taskListMembershipIdsInOrder(task) + [domain]
            placed.lists = nil
        }
        if !seeded.contains(where: { $0.id == domain }) { seeded.append(TaskList(id: domain, name: "Board")) }
        let session = try! session(tasks: [placed], lists: seeded,
                                   projects: [Project(id: project, name: "Board", customStates: customStates)])
        return try! statusOptions(session, taskId: task.id).current
    }

    /// The columns the state picker offers a task on a board with these custom states.
    static func pickerColumns(customStates: [ProjectCustomState]? = nil) -> [ProjectBoardColumn] {
        var board = TaskList(id: domainListId, name: "Board")
        board.projectId = projectId
        var task = Task(id: "picked", title: "Picked")
        task.listIds = [domainListId]
        let session = try! session(tasks: [task], lists: [board],
                                   projects: [Project(id: projectId, name: "Board", customStates: customStates)])
        return try! statusOptions(session, taskId: task.id).columns.map(\.column)
    }

    /// The same, against a board already drawn.
    static func columnId(_ task: Task, columns: [ProjectBoardColumn]) -> String {
        columnId(task, lists: [], customStates: customStates(of: columns))
    }

    // MARK: - Cards

    /// One column's cards, in the order the board draws them. `now` is the test's clock: the
    /// tasks' timestamps are moved by the distance from it to the real one, which is what the
    /// core reads.
    static func columnTasks(_ allTasks: [Task], projectId: String, column: ProjectBoardColumn,
                            lists: [TaskList], customStates: [ProjectCustomState]? = nil,
                            manualOrder: [String]?, recentlyCompletedWindow: RecentlyCompletedWindow? = nil,
                            completionFilter: String? = nil, now: Date = Date()) -> [Task] {
        let shift = Date().timeIntervalSince(now)
        let moved = allTasks.map { task -> Task in
            var copy = task
            copy.updatedAt = task.updatedAt?.addingTimeInterval(shift)
            return copy
        }
        var seeded = lists
        let domain: String
        if let index = seeded.firstIndex(where: { $0.projectId == projectId && $0.listType != "status" }) {
            seeded[index].manualSortOrder = manualOrder
            seeded[index].recentlyCompletedWindow = recentlyCompletedWindow
            seeded[index].filterCompletion = completionFilter
            domain = seeded[index].id
        } else {
            var board = TaskList(id: domainListId, name: "Board")
            board.projectId = projectId
            board.manualSortOrder = manualOrder
            board.recentlyCompletedWindow = recentlyCompletedWindow
            board.filterCompletion = completionFilter
            seeded.append(board)
            domain = domainListId
        }
        let session = try! session(tasks: moved, lists: seeded,
                                   projects: [Project(id: projectId, name: "Board", customStates: customStates)])
        let byId = Dictionary(allTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = (try? drawn(session, listId: domain).first { $0.id == column.id }?.ids) ?? nil
        return (ids ?? []).compactMap { byId[$0] }
    }

    // MARK: - Moves

    /// Move `task` to `column` on its own board, and read back what it became. Dropped on the
    /// column (`dropBoardCard`), which writes the move whether or not the card was already there —
    /// what the old resolver described; `plan` is the state menu's move, which writes nothing then.
    static func move(_ task: Task, to column: ProjectBoardColumn, lists: [TaskList],
                     customStates: [ProjectCustomState]? = nil) -> Move {
        moveOrPlan(task, to: column, lists: lists, customStates: customStates, kind: "dropBoardCard")
    }

    /// Whether `task` is already in `column` — a move there writes nothing.
    static func isAlreadyIn(_ task: Task, column: ProjectBoardColumn, lists: [TaskList],
                            customStates: [ProjectCustomState]? = nil) -> Bool {
        columnId(task, lists: lists, customStates: customStates) == column.id
    }

    /// Every card on `projectId`'s board, whichever column — the board's own tasks.
    static func domainTasks(_ tasks: [Task], lists: [TaskList], projectId: String) -> [Task] {
        var seeded = lists
        if !seeded.contains(where: { $0.projectId == projectId && $0.listType != "status" }) {
            var board = TaskList(id: domainListId, name: "Board")
            board.projectId = projectId
            seeded.append(board)
        }
        let session = try! session(tasks: tasks, lists: seeded, projects: [Project(id: projectId, name: "Board")])
        let ids = Set((try? drawn(session, projectId: projectId).flatMap(\.ids)) ?? [])
        return tasks.filter { ids.contains($0.id) }
    }

    private static func moveOrPlan(_ task: Task, to column: ProjectBoardColumn, lists: [TaskList],
                                   customStates: [ProjectCustomState]?, kind: String) -> Move {
        let project = board(for: lists, memberOf: task)
        var states = customStates ?? []
        if column.kind == .status, !["ready", "doing", "waiting"].contains(column.id),
           !states.contains(where: { $0.role == column.id }) {
            states.append(ProjectCustomState(role: column.id, name: column.name, order: states.count))
        }
        var (seeded, domain) = withDomain(lists, project: project)
        var placed = task
        let added = !taskListMembershipIdsInOrder(task).contains { id in seeded.contains { $0.id == id && $0.projectId == project } }
        if added {
            placed.listIds = taskListMembershipIdsInOrder(task) + [domain]
            placed.lists = nil
        }
        if !seeded.contains(where: { $0.id == domain }) { seeded.append(TaskList(id: domain, name: "Board")) }
        let session = try! session(tasks: [placed], lists: seeded,
                                   projects: [Project(id: project, name: "Board", customStates: states)])
        var command = CoreCommand(kind: kind)
        command.set("taskId", task.id)
        command.set("columnId", column.id)
        let after: Task
        if kind == "dropBoardCard" {
            command.set("listId", domain)
            command.set("index", Int.max / 2)
            struct Dropped: Decodable { let task: Task }
            after = try! CoreRowsFixture.wait(session, command, as: Dropped.self).task
        } else {
            after = try! CoreRowsFixture.wait(session, command, as: Task.self)
        }
        let listIds = (after.listIds ?? []).filter { !(added && $0 == domain) }
        return Move(listIds: listIds, completed: after.completed, statusRole: after.statusRole)
    }

    /// What a move to `column` asked of the task — see `Plan`.
    static func plan(task: Task, column: ProjectBoardColumn, lists: [TaskList],
                     customStates: [ProjectCustomState]? = nil) -> Plan {
        let moved = moveOrPlan(task, to: column, lists: lists, customStates: customStates, kind: "setTaskStatus")
        let role = moved.statusRole ?? ""
        if moved.completed == task.completed, moved.statusRole == task.statusRole,
           moved.listIds == taskListMembershipIdsInOrder(task) {
            return .none
        }
        if moved.completed, !task.completed { return .complete(moved.listIds, statusRole: role) }
        if !moved.completed, task.completed { return .uncomplete(moved.listIds, statusRole: role) }
        return .setLists(moved.listIds, statusRole: role)
    }

    /// Drop `task` at `targetIndex` in `targetColumn` of `projectId`'s board, whose list holds
    /// `currentManualOrder`; read back the task and the list's new order.
    static func reorder(task: Task, targetColumn: ProjectBoardColumn, targetIndex: Int, projectId: String,
                        lists: [TaskList], allTasks: [Task], currentManualOrder: [String],
                        recentlyCompletedWindow: RecentlyCompletedWindow? = nil,
                        completionFilter: String? = nil) -> Reorder {
        var seeded = lists
        let domain: String
        if let index = seeded.firstIndex(where: { $0.projectId == projectId && $0.listType != "status" }) {
            seeded[index].manualSortOrder = currentManualOrder
            seeded[index].recentlyCompletedWindow = recentlyCompletedWindow
            seeded[index].filterCompletion = completionFilter
            domain = seeded[index].id
        } else {
            var board = TaskList(id: domainListId, name: "Board")
            board.projectId = projectId
            board.manualSortOrder = currentManualOrder
            seeded.append(board)
            domain = domainListId
        }
        let session = try! session(tasks: allTasks, lists: seeded, projects: [Project(id: projectId, name: "Board")])
        var command = CoreCommand(kind: "dropBoardCard")
        command.set("taskId", task.id)
        command.set("columnId", targetColumn.id)
        command.set("listId", domain)
        command.set("index", targetIndex)
        struct Dropped: Decodable { let task: Task; let list: TaskList }
        let dropped = try! CoreRowsFixture.wait(session, command, as: Dropped.self)
        return Reorder(listIds: dropped.task.listIds ?? [], completed: dropped.task.completed,
                       newManualOrder: dropped.list.manualSortOrder ?? [], statusRole: dropped.task.statusRole)
    }

    // MARK: - Asking

    /// The board's columns with their card ids.
    static func drawn(_ session: CoreSession, listId: String? = nil, projectId: String? = nil) throws -> [BoardModel.Column] {
        struct Answer: Decodable { let columns: [BoardModel.Column] }
        return try CoreRowsFixture.wait(session, BoardModel.command(for: .init(listId: listId, projectId: projectId)),
                                        as: Answer.self).columns
    }

    /// The state picker's answer for a task.
    static func statusOptions(_ session: CoreSession, taskId: String) throws -> TaskStatusOptions.Answer {
        var command = CoreCommand(kind: "taskStatusOptions")
        command.set("taskId", taskId)
        return try CoreRowsFixture.wait(session, command, as: TaskStatusOptions.Answer.self)
    }
}

extension Task {
    /// The task as a move left it — what the core wrote, applied to a test's copy, so a test can
    /// ask which column it is in now.
    func applyingBoardMove(_ move: CoreBoardFixture.Move) -> Task {
        var moved = self
        moved.listIds = move.listIds
        moved.lists = nil
        moved.completed = move.completed
        moved.statusRole = move.statusRole
        return moved
    }
}
