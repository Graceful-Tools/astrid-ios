import Foundation

/// Swift port of astrid-web's `lib/project-status.ts`. Pure logic — no
/// network, no Core Data, no UI. The web counterpart is the canonical
/// spec; if these diverge, iOS will render boards differently than the
/// web and that's a bug.
///
/// See docs/product/project-status-board.md in astrid-web for the rules.

enum ProjectStatusRole: String {
    case ready, doing, waiting, custom
}

struct ProjectStatusDefinition: Equatable {
    let role: ProjectStatusRole
    let name: String
    let description: String
    let order: Int
}

let DEFAULT_PROJECT_STATUSES: [ProjectStatusDefinition] = [
    .init(role: .ready,   name: "Ready",   description: "Time to get to work!",                       order: 0),
    .init(role: .doing,   name: "Doing",   description: "Active work in progress!",                   order: 1),
    .init(role: .waiting, name: "Waiting", description: "Paused until the circumstances are right.",  order: 2),
]

let VIRTUAL_INBOX_COLUMN_ID = "__virtual_inbox__"
let VIRTUAL_DONE_COLUMN_ID  = "__virtual_done__"

enum ProjectBoardColumnKind: Equatable {
    case inbox, status, done
}

struct ProjectBoardColumn: Equatable, Identifiable {
    let id: String
    let name: String
    let description: String
    let kind: ProjectBoardColumnKind
    let statusList: TaskList?

    static func == (lhs: ProjectBoardColumn, rhs: ProjectBoardColumn) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind
    }
}

// MARK: - Status-list predicates

/// True when the list is a project status list (Ready / Doing / Waiting / custom).
func isProjectStatusList(_ list: TaskList?) -> Bool {
    list?.listType == "status"
}

/// Legacy: early projects seeded a real "Done" status list. New projects
/// don't. Treat any such list as a Done-bucket so the virtual Done column
/// owns those tasks instead of rendering a duplicate column.
func isLegacyDoneStatusList(_ list: TaskList?) -> Bool {
    guard isProjectStatusList(list) else { return false }
    return list?.statusRole == "done" || list?.statusCompleted == true
}

/// Legacy mirror for the old Inbox status list.
func isLegacyInboxStatusList(_ list: TaskList?) -> Bool {
    guard isProjectStatusList(list) else { return false }
    return list?.statusRole == "inbox"
}

// MARK: - Column derivation

/// Returns the project's real status lists in display order, excluding
/// any legacy Inbox/Done lists (the board renders virtual columns for those).
func getProjectStatusLists(_ lists: [TaskList], projectId: String) -> [TaskList] {
    let intMax = Int.max
    return lists
        .filter { $0.projectId == projectId && isProjectStatusList($0) }
        .filter { !isLegacyDoneStatusList($0) && !isLegacyInboxStatusList($0) }
        .sorted { a, b in
            let aOrder = a.statusOrder ?? intMax
            let bOrder = b.statusOrder ?? intMax
            if aOrder != bOrder { return aOrder < bOrder }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
}

/// Build the ordered board columns: [virtual Inbox, ...real statuses, virtual Done].
func getProjectBoardColumns(_ lists: [TaskList], projectId: String) -> [ProjectBoardColumn] {
    var result: [ProjectBoardColumn] = [
        ProjectBoardColumn(
            id: VIRTUAL_INBOX_COLUMN_ID,
            name: "Inbox",
            description: "Move them to \"Ready\" when they are... ready!",
            kind: .inbox,
            statusList: nil
        )
    ]
    for status in getProjectStatusLists(lists, projectId: projectId) {
        let description = status.statusDescription
            ?? status.description
            ?? ""
        result.append(ProjectBoardColumn(
            id: status.id,
            name: status.name,
            description: description,
            kind: .status,
            statusList: status
        ))
    }
    result.append(ProjectBoardColumn(
        id: VIRTUAL_DONE_COLUMN_ID,
        name: "Done",
        description: "Complete — congrats!",
        kind: .done,
        statusList: nil
    ))
    return result
}

// MARK: - Task → column

/// Returns the board column id a task currently belongs to:
///   completed=true              → virtual Done id
///   has a real status list      → that list's id
///   otherwise                   → virtual Inbox id
///
/// Reads both `task.lists` (full join, present after a fresh fetch) and
/// `task.listIds` (compact form, present after a Core Data load). Either
/// is sufficient to assign a column.
func getTaskProjectColumnId(_ task: Task, projectId: String, lists: [TaskList]) -> String {
    if task.completed { return VIRTUAL_DONE_COLUMN_ID }

    let statusLists = getProjectStatusLists(lists, projectId: projectId)
    let taskListIds = taskListMembershipIds(task)
    if let explicit = statusLists.first(where: { taskListIds.contains($0.id) }) {
        return explicit.id
    }
    return VIRTUAL_INBOX_COLUMN_ID
}

// MARK: - Move resolution

struct ProjectColumnMove: Equatable {
    let listIds: [String]
    let completed: Bool
}

/// Compute the post-move task state when dragging a task onto a board column.
///   inbox  → strip every project status from this project, completed=false
///   done   → strip every project status from this project, completed=true
///   status → replace any existing status with the target, completed=false
/// Regular (non-status) list memberships are preserved in all cases.
func resolveProjectColumnMove(
    _ task: Task,
    targetColumn: ProjectBoardColumn,
    projectId: String,
    lists: [TaskList]
) -> ProjectColumnMove {
    let projectStatusIds = Set(
        lists
            .filter { $0.projectId == projectId && isProjectStatusList($0) }
            .map { $0.id }
    )
    // Honor both `task.lists` (hydrated) AND `task.listIds` (cache). Without
    // the listIds fallback a Core-Data-loaded task drops every list
    // membership during a board move, vanishing from the board after the
    // drop. The "in-order" variant preserves the iteration order so the
    // persisted listIds stay stable across rounds.
    let retainedListIds = taskListMembershipIdsInOrder(task)
        .filter { !projectStatusIds.contains($0) }

    switch targetColumn.kind {
    case .inbox:
        return ProjectColumnMove(listIds: retainedListIds, completed: false)
    case .done:
        return ProjectColumnMove(listIds: retainedListIds, completed: true)
    case .status:
        return ProjectColumnMove(listIds: retainedListIds + [targetColumn.id], completed: false)
    }
}

// MARK: - Server-side guard (mirror for iOS client validation)

struct NormalizedProjectStatusListIds: Equatable {
    let listIds: [String]
    let completedFromStatus: Bool?
}

/// Mirrors the web's `normalizeProjectStatusListIds`. The server enforces
/// this; iOS only uses it for optimistic-state computations so the UI
/// can preview the same outcome before the network round-trip.
func normalizeProjectStatusListIds(
    requestedListIds: [String],
    knownLists: [TaskList],
    completed: Bool? = nil
) -> NormalizedProjectStatusListIds {
    let statusLists = knownLists.filter(isProjectStatusList)
    let statusById = Dictionary(uniqueKeysWithValues: statusLists.map { ($0.id, $0) })
    let allStatusIds = Set(statusById.keys)

    // Task being marked done → drop every project status.
    if completed == true {
        let filtered = Array(NSOrderedSet(array: requestedListIds.filter { !allStatusIds.contains($0) })) as? [String] ?? []
        return NormalizedProjectStatusListIds(listIds: filtered, completedFromStatus: nil)
    }

    var selectedStatusByProject: [String: TaskList] = [:]
    for listId in requestedListIds {
        if let status = statusById[listId], let projectId = status.projectId {
            selectedStatusByProject[projectId] = status
        }
    }

    if selectedStatusByProject.isEmpty {
        let deduped = Array(NSOrderedSet(array: requestedListIds)) as? [String] ?? []
        return NormalizedProjectStatusListIds(listIds: deduped, completedFromStatus: nil)
    }

    var affectedStatusIds = Set<String>()
    for projectId in selectedStatusByProject.keys {
        for list in knownLists where list.projectId == projectId && isProjectStatusList(list) {
            affectedStatusIds.insert(list.id)
        }
    }

    var result = requestedListIds.filter { !affectedStatusIds.contains($0) }
    for status in selectedStatusByProject.values {
        result.append(status.id)
    }
    let deduped = Array(NSOrderedSet(array: result)) as? [String] ?? []
    return NormalizedProjectStatusListIds(listIds: deduped, completedFromStatus: false)
}

// MARK: - Project domain tasks

/// Tasks that should appear on a project's board: those attached to at
/// least one of the project's regular (non-status) lists. A task with
/// only a status membership and no domain list isn't a "project task".
///
/// Honors both `task.lists` (full join) AND `task.listIds` (compact form
/// stored in Core Data). Without the listIds fallback the Inbox column
/// is empty on cold start until the next full sync hydrates `task.lists`.
func getProjectDomainTasks(_ tasks: [Task], lists: [TaskList], projectId: String) -> [Task] {
    let regularIds = Set(
        lists
            .filter { $0.projectId == projectId && $0.listType != "status" }
            .map { $0.id }
    )
    return tasks.filter { task in
        !taskListMembershipIds(task).isDisjoint(with: regularIds)
    }
}

/// The union of a task's list-membership identifiers from both the
/// hydrated `task.lists` array and the compact `task.listIds` cache.
/// Centralizes the fallback so every board-side filter respects both.
func taskListMembershipIds(_ task: Task) -> Set<String> {
    Set(taskListMembershipIdsInOrder(task))
}

/// Same union as `taskListMembershipIds` but preserves the first
/// observed order across `task.lists` then `task.listIds`. Used by
/// `resolveProjectColumnMove` so the persisted listIds keep a stable
/// ordering that round-trips cleanly through the server.
func taskListMembershipIdsInOrder(_ task: Task) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for id in (task.lists?.map { $0.id } ?? []) {
        if seen.insert(id).inserted { out.append(id) }
    }
    for id in (task.listIds ?? []) {
        if seen.insert(id).inserted { out.append(id) }
    }
    return out
}
