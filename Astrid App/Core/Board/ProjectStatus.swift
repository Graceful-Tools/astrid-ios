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

/// Returns the user's real status lists in display order, excluding any
/// legacy Inbox/Done lists (the board renders virtual columns for those).
///
/// Status lists are per-user globals — one Ready/Doing/Waiting set shared
/// across every project board, not duplicated per project. This therefore
/// takes no project id; every board renders the same status columns.
func getProjectStatusLists(_ lists: [TaskList]) -> [TaskList] {
    let intMax = Int.max
    return lists
        .filter { isProjectStatusList($0) }
        .filter { !isLegacyDoneStatusList($0) && !isLegacyInboxStatusList($0) }
        .sorted { a, b in
            let aOrder = a.statusOrder ?? intMax
            let bOrder = b.statusOrder ?? intMax
            if aOrder != bOrder { return aOrder < bOrder }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
}

/// Build the ordered board columns: [virtual Inbox, ...real statuses, virtual Done].
func getProjectBoardColumns(_ lists: [TaskList]) -> [ProjectBoardColumn] {
    var result: [ProjectBoardColumn] = [
        ProjectBoardColumn(
            id: VIRTUAL_INBOX_COLUMN_ID,
            name: "Inbox",
            description: "Move them to \"Ready\" when they are... ready!",
            kind: .inbox,
            statusList: nil
        )
    ]
    for status in getProjectStatusLists(lists) {
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
func getTaskProjectColumnId(_ task: Task, lists: [TaskList]) -> String {
    if task.completed { return VIRTUAL_DONE_COLUMN_ID }

    let statusLists = getProjectStatusLists(lists)
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
///   inbox  → strip the (global) status, completed=false
///   done   → strip the (global) status, completed=true
///   status → replace any existing status with the target, completed=false
/// Regular (non-status) list memberships are preserved in all cases.
func resolveProjectColumnMove(
    _ task: Task,
    targetColumn: ProjectBoardColumn,
    lists: [TaskList]
) -> ProjectColumnMove {
    let projectStatusIds = Set(
        lists
            .filter { isProjectStatusList($0) }
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
///
/// Status is a single per-user global concept, so a task has at most one
/// status list total (not one per project).
func normalizeProjectStatusListIds(
    requestedListIds: [String],
    knownLists: [TaskList],
    completed: Bool? = nil
) -> NormalizedProjectStatusListIds {
    let allStatusIds = Set(knownLists.filter(isProjectStatusList).map { $0.id })

    func orderedUnique(_ ids: [String]) -> [String] {
        Array(NSOrderedSet(array: ids)) as? [String] ?? []
    }

    // Task being marked done → drop every status membership.
    if completed == true {
        return NormalizedProjectStatusListIds(
            listIds: orderedUnique(requestedListIds.filter { !allStatusIds.contains($0) }),
            completedFromStatus: nil
        )
    }

    let statusInRequest = requestedListIds.filter { allStatusIds.contains($0) }
    if statusInRequest.isEmpty {
        return NormalizedProjectStatusListIds(
            listIds: orderedUnique(requestedListIds),
            completedFromStatus: nil
        )
    }

    // Keep at most one status list — the last one in the request wins.
    let winningStatus = statusInRequest[statusInRequest.count - 1]
    let nonStatus = requestedListIds.filter { !allStatusIds.contains($0) }
    return NormalizedProjectStatusListIds(
        listIds: orderedUnique(nonStatus + [winningStatus]),
        completedFromStatus: false
    )
}

// MARK: - Project domain tasks

// MARK: - Column ordering + reorder-on-drop

/// Returns the tasks belonging to `column` in display order.
/// When `manualOrder` is set, tasks are sorted by their position in
/// that array (unknown ids sort last). When nil/empty, returns the
/// project-domain tasks in their incoming order — caller can apply
/// a different sort if desired.
func boardColumnTasksSorted(
    _ allTasks: [Task],
    projectId: String,
    column: ProjectBoardColumn,
    lists: [TaskList],
    manualOrder: [String]?,
    recentlyCompletedWindow: RecentlyCompletedWindow? = nil,
    completionFilter: String? = nil,
    now: Date = Date()
) -> [Task] {
    let inColumn = allTasks.filter { task in
        getTaskProjectColumnId(task, lists: lists) == column.id
    }
    // The Done column honors the list's recently-completed window so the board
    // matches the web (project-status-board.tsx) — otherwise iOS shows every
    // completed task forever.
    let windowed: [Task]
    if column.kind == .done {
        windowed = inColumn.filter { task in
            shouldShowCompletedByFilter(
                filterMode: completionFilter ?? "default",
                completedAt: nil,
                updatedAt: task.updatedAt,
                window: recentlyCompletedWindow,
                now: now
            )
        }
    } else {
        windowed = inColumn
    }
    let domain = getProjectDomainTasks(windowed, lists: lists, projectId: projectId)
    guard let manualOrder = manualOrder, !manualOrder.isEmpty else {
        return domain
    }
    let orderIdx = Dictionary(uniqueKeysWithValues:
        manualOrder.enumerated().map { ($1, $0) })
    return domain.sorted { a, b in
        let ai = orderIdx[a.id] ?? Int.max
        let bi = orderIdx[b.id] ?? Int.max
        return ai < bi
    }
}

/// Output of `resolveBoardReorder`. `listIds` / `completed` are what
/// the task PUT should send; `newManualOrder` is what the project's
/// domain list's PUT should send for `manualSortOrder`.
struct BoardReorder: Equatable {
    let listIds: [String]
    let completed: Bool
    let newManualOrder: [String]
}

/// Compute the persisted state for a drag-drop reorder onto a board
/// column at a specific slot index.
///
/// Inputs:
/// - `task`: the dragged task
/// - `targetColumn`: where it was dropped
/// - `targetIndex`: 0-based slot within the column's visible tasks
///   (caller computes this from which card was hovered). Pass
///   `tasks-in-target.count` to append at end.
/// - `projectId`, `lists`, `allTasks`: board context
/// - `currentManualOrder`: the project domain list's existing
///   `manualSortOrder` (use `[]` if none yet).
///
/// The function is pure — no I/O. Tests pin the contract; the SwiftUI
/// view layer only persists the result.
func resolveBoardReorder(
    task: Task,
    targetColumn: ProjectBoardColumn,
    targetIndex: Int,
    projectId: String,
    lists: [TaskList],
    allTasks: [Task],
    currentManualOrder: [String],
    recentlyCompletedWindow: RecentlyCompletedWindow? = nil,
    completionFilter: String? = nil,
    now: Date = Date()
) -> BoardReorder {
    let move = resolveProjectColumnMove(
        task,
        targetColumn: targetColumn,
        lists: lists
    )

    // Tasks that will be in the target column AFTER this drop, ignoring
    // the dragged task itself. We figure out the global insertion point
    // by locating the task we're dropping ABOVE in this filtered list,
    // then translating that to a global manualSortOrder index.
    let targetColumnTasks = boardColumnTasksSorted(
        allTasks.filter { $0.id != task.id },
        projectId: projectId,
        column: targetColumn,
        lists: lists,
        manualOrder: currentManualOrder,
        recentlyCompletedWindow: recentlyCompletedWindow,
        completionFilter: completionFilter,
        now: now
    )

    var newOrder = currentManualOrder
    newOrder.removeAll { $0 == task.id }

    let clamped = max(0, min(targetIndex, targetColumnTasks.count))
    if clamped < targetColumnTasks.count {
        let anchorId = targetColumnTasks[clamped].id
        if let globalIdx = newOrder.firstIndex(of: anchorId) {
            newOrder.insert(task.id, at: globalIdx)
        } else {
            // Anchor isn't in current manual order yet — append, then
            // the rest of the column will sort behind it naturally.
            newOrder.append(task.id)
        }
    } else {
        // Append-at-end: place after the column's current last task in
        // the global manual order so it stays the tail of the column.
        if let lastInColumn = targetColumnTasks.last,
           let globalIdx = newOrder.firstIndex(of: lastInColumn.id) {
            newOrder.insert(task.id, at: globalIdx + 1)
        } else {
            newOrder.append(task.id)
        }
    }

    return BoardReorder(
        listIds: move.listIds,
        completed: move.completed,
        newManualOrder: newOrder
    )
}

/// True when the task is already in the target column. Used by the
/// drop handler to short-circuit no-op moves (e.g. dragging a card a
/// few pixels and releasing inside its own column). Without this every
/// touch-drag triggered a round-trip PUT for an unchanged state, which
/// is wasteful and — more importantly — flickered the cell visually
/// because the optimistic update re-rendered.
func isTaskAlreadyInColumn(_ task: Task,
                           targetColumn: ProjectBoardColumn,
                           lists: [TaskList]) -> Bool {
    getTaskProjectColumnId(task, lists: lists) == targetColumn.id
}

/// Decide how many board columns to fit side-by-side based on the
/// available width.
///
/// Phone-narrow widths render one full-screen column with paging snap
/// (the existing behavior). At iPad-portrait+ widths we fan out to
/// 2-5 columns side-by-side so the user can see the whole board at a
/// glance — the user's stated target is "3-5 columns visible in iPad
/// landscape".
///
/// `targetMinColumnWidth` is the smallest width we want any single
/// column to be (defaults to 300pt — comfortable for two task chips
/// plus a margin). The result is clamped to [1, 5].
func boardColumnsVisible(availableWidth: CGFloat,
                         targetMinColumnWidth: CGFloat = 300) -> Int {
    guard availableWidth > 0, targetMinColumnWidth > 0 else { return 1 }
    let raw = Int((availableWidth / targetMinColumnWidth).rounded(.down))
    return max(1, min(5, raw))
}

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

// MARK: - Board create / disable: local list-state mirroring

/// Merge a project's seeded status lists into a list array. Idempotent
/// — a status list already present (matched by id) is not duplicated;
/// non-status lists in `statusLists` are ignored.
///
/// Used right after creating a board: `POST /api/v1/projects` seeds
/// Ready/Doing/Waiting and returns them on the project, but they must
/// be mirrored into `ListService.lists` or the board has no columns
/// until the next full sync.
func applyProjectStatusLists(_ lists: [TaskList], adding statusLists: [TaskList]) -> [TaskList] {
    var result = lists
    for statusList in statusLists where statusList.listType == "status" {
        if !result.contains(where: { $0.id == statusList.id }) {
            result.append(statusList)
        }
    }
    return result
}

/// Mirror a project deletion onto a list array, matching the server's
/// `DELETE /api/v1/projects/[id]` cascade: the project's domain lists are
/// detached — `projectId` cleared, the list itself kept.
///
/// Status lists are per-user globals (`projectId == nil`), shared across
/// every board, so they are NOT touched by a project deletion.
///
/// Used when disabling a board so the in-memory state is consistent
/// immediately, without waiting for a full sync.
func applyProjectDeletion(_ lists: [TaskList], deletedProjectId: String) -> [TaskList] {
    lists.map { list in
        guard list.projectId == deletedProjectId else { return list }
        var detached = list
        detached.projectId = nil                      // domain list — detached, kept
        return detached
    }
}
