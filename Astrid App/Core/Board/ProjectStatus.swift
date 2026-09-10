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

/// A board's own custom column, as stored on `Project.customStates`.
///
/// Swift mirror of web's `StatusState` (`lib/task-status.ts`). The three
/// defaults are NOT stored here — they are `DEFAULT_PROJECT_STATUSES` config,
/// shared by every board. A DEFAULT role appearing in this array is a NAME
/// OVERRIDE for that built-in, not a sixth column; `getProjectBoardColumns`
/// tells the two apart, exactly as web's `isDefaultStatusRole` does.
///
/// Decoding is deliberately lenient: the server column is a free-form `Json?`
/// that nothing validates on read, so a single malformed entry must not fail
/// the whole `Project` — one bad row would otherwise empty the board. Junk
/// decodes to blank fields that `parseProjectCustomStates` then drops, which is
/// how web behaves entry-by-entry.
struct ProjectCustomState: Codable, Equatable, Hashable {
    let role: String
    let name: String
    let description: String?
    /// Absent means "wherever it landed" — the parser fills in the insertion
    /// index, matching web's `byRole.size` fallback.
    let order: Int?

    init(role: String, name: String, description: String? = nil, order: Int? = nil) {
        self.role = role
        self.name = name
        self.description = description
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `try?` twice over: the key may be missing, and the value may be the
        // wrong JSON type. Neither is worth failing a project for.
        role = ((try? c.decodeIfPresent(String.self, forKey: .role)) ?? nil) ?? ""
        name = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? ""
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? nil
        order = (try? c.decodeIfPresent(Int.self, forKey: .order)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case role, name, description, order
    }
}

/// Port of web's `parseCustomStates` (`lib/task-status.ts`). Same rules, in
/// the same order, because the two platforms must agree about which columns a
/// board has and what they are called:
///
///   * `role` and `name` are trimmed; an entry missing either is dropped.
///   * The FIRST entry for a role wins — a later duplicate is ignored.
///   * An absent `order` becomes the entry's insertion index.
///   * The result is sorted by `order`, ties broken by insertion order.
func parseProjectCustomStates(_ raw: [ProjectCustomState]?) -> [ProjectCustomState] {
    guard let raw else { return [] }

    var seen: Set<String> = []
    var kept: [ProjectCustomState] = []
    for entry in raw {
        let role = entry.role.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !role.isEmpty, !name.isEmpty else { continue }
        guard seen.insert(role).inserted else { continue }
        kept.append(ProjectCustomState(
            role: role,
            name: name,
            description: entry.description,
            order: entry.order ?? kept.count
        ))
    }

    // Sort is not guaranteed stable in Swift, so tie-break on the insertion
    // index explicitly rather than trusting it.
    return kept.enumerated()
        .sorted { a, b in
            let aOrder = a.element.order ?? a.offset
            let bOrder = b.element.order ?? b.offset
            if aOrder != bOrder { return aOrder < bOrder }
            return a.offset < b.offset
        }
        .map(\.element)
}

let VIRTUAL_INBOX_COLUMN_ID = "__virtual_inbox__"
let VIRTUAL_DONE_COLUMN_ID  = "__virtual_done__"

enum ProjectBoardColumnKind: Equatable {
    case inbox, status, done
}

struct ProjectBoardColumn: Equatable, Identifiable {
    /// The ROLE — `ready`, `doing`, `waiting`, a `custom-*` role, or one of the two
    /// virtual ids. Never a list id (task e5c74b5e): the `listType: 'status'` rows
    /// this used to key off are deleted, so a cached one must not decide the shape
    /// of the board, and its id must never go out on the wire.
    let id: String
    let name: String
    let description: String
    let kind: ProjectBoardColumnKind

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

/// The roles that always have a column, whether a list backs them or not.
let DEFAULT_STATUS_ROLES: Set<String> = Set(DEFAULT_PROJECT_STATUSES.map { $0.role.rawValue })

/// Build the ordered board columns: [virtual Inbox, ...defaults, ...customs, virtual Done].
///
/// The three defaults come from CONFIG (task 2e41c645, mirroring web's
/// a1722040 step 4). Deriving the whole board from `listType: "status"` rows
/// meant the day they were deleted the board would render Inbox and Done and
/// nothing else — so those rows could not be deleted at all while iOS depended
/// on them. Now the deletion is a no-op here.
///
/// **The column id is the ROLE, always** (task e5c74b5e). It used to be the LIST
/// id whenever a row happened to be cached, which handed the shape of the board
/// to whatever a client had lying around from before the migration: two clients
/// disagreed about the same card, and the id leaked onto the wire as a membership
/// in a list that no longer exists.
///
/// **Custom columns come from `Project.customStates`** (task AITD-379, porting
/// web's b346e377 / 9ddf4a6f). They used to come from project-scoped status
/// rows, which `20260821000000_drop_status_lists` deleted — so that scan found
/// nothing and iOS silently rendered no custom column at all. A custom state
/// still belongs to exactly one board, but now because it is stored ON that
/// board rather than because a `projectId` filtered the rows.
///
/// A cached row may still supply a renamed default's NAME, below an override
/// stored in `customStates` and above the config default. It may never supply
/// an id, and it can no longer contribute a column of its own.
func getProjectBoardColumns(_ lists: [TaskList],
                            customStates: [ProjectCustomState]? = nil) -> [ProjectBoardColumn] {
    let parsed = parseProjectCustomStates(customStates)
    // A default role in the array is a rename of that built-in, not a new
    // column — the same split web makes with `isDefaultStatusRole`.
    var renames: [String: ProjectCustomState] = [:]
    var customs: [ProjectCustomState] = []
    for state in parsed {
        if DEFAULT_STATUS_ROLES.contains(state.role) {
            renames[state.role] = state
        } else {
            customs.append(state)
        }
    }

    var byRole: [String: TaskList] = [:]
    for status in getProjectStatusLists(lists) {
        if let role = status.statusRole { byRole[role] = status }
    }

    var result: [ProjectBoardColumn] = [
        ProjectBoardColumn(
            id: VIRTUAL_INBOX_COLUMN_ID,
            name: "Inbox",
            description: "Move them to \"Ready\" when they are... ready!",
            kind: .inbox
        )
    ]

    for state in DEFAULT_PROJECT_STATUSES {
        let role = state.role.rawValue
        let backing = byRole[role]
        result.append(ProjectBoardColumn(
            id: role,
            // A rename is durable in `customStates`; a renamed default was also
            // once a PUT on the list, so a surviving cached row still answers
            // for clients that have one. Only the NAME either way — the id is
            // the role, so the board's shape never depends on the cache.
            name: renames[role]?.name ?? backing?.name ?? state.name,
            description: backing?.statusDescription ?? backing?.description ?? state.description,
            kind: .status
        ))
    }

    for state in customs {
        result.append(ProjectBoardColumn(
            id: state.role,
            name: state.name,
            description: state.description ?? "",
            kind: .status
        ))
    }

    result.append(ProjectBoardColumn(
        id: VIRTUAL_DONE_COLUMN_ID,
        name: "Done",
        description: "Complete — congrats!",
        kind: .done
    ))
    return result
}

// MARK: - Task → column

/// Returns the board column id a task currently belongs to:
///   completed=true              → virtual Done id
///   has a matching status role  → that role's current column id
///   otherwise                   → virtual Inbox id
///
/// Column resolution is statusRole-only. Status-list membership is transitional
/// state that can outlive its backing rows and must not drive columning.
///
/// Convenience over the `columns:` variant for callers holding lists rather
/// than a built board. `customStates` is the board's own — omit it and a custom
/// role resolves to Inbox, which is the safe answer for a caller that does not
/// know which board it is looking at.
func getTaskProjectColumnId(_ task: Task,
                            lists: [TaskList],
                            customStates: [ProjectCustomState]? = nil) -> String {
    getTaskProjectColumnId(task, columns: getProjectBoardColumns(lists, customStates: customStates))
}

/// Resolved against the board's COLUMNS, not against the user's lists — the
/// same signature web uses, and the reason the "resolved id is always a column
/// the board renders" invariant holds by construction rather than by agreement
/// between two separate derivations.
///
/// Also the fast variant: callers grouping many tasks (the Mac board's one-pass
/// column grouping, Task 6042bde0) build the columns once and hoist them out of
/// the per-task loop instead of rescanning for every task.
func getTaskProjectColumnId(_ task: Task, columns: [ProjectBoardColumn]) -> String {
    if task.completed { return VIRTUAL_DONE_COLUMN_ID }

    // Status is a STATE on the task (AWTD-562). Prefer the field: it lives on
    // the shared task, so two members of a board cannot resolve different
    // columns — the failure that status-as-list-membership could not fix
    // without duplicating a Ready/Doing/Waiting set per project.
    guard let role = task.statusRole, !role.isEmpty else { return VIRTUAL_INBOX_COLUMN_ID }

    // A role has a column only while this board declares one. The defaults
    // always do, from config, so a card does not fall to Inbox merely because
    // the rows are gone. A custom role does only while `customStates` says so —
    // and a card matching NO column is gone from the board while still in the
    // list view, so an unmatched role falls to Inbox instead of being returned
    // bare. Showing a card in the wrong column is recoverable; losing it is not.
    if columns.contains(where: { $0.kind == .status && $0.id == role }) { return role }
    return VIRTUAL_INBOX_COLUMN_ID
}

/// The board a selected list belongs to, if any. Mirrors web's
/// `getProjectIdForBoard` (`lib/project-status.ts`).
///
/// Needed now that columns depend on the board's own `customStates` (AITD-379):
/// a caller holding only a list id has to resolve WHICH board before it can ask
/// what columns that board has.
func getProjectIdForBoard(_ lists: [TaskList], selectedListId: String?) -> String? {
    guard let selectedListId else { return nil }
    return lists.first { $0.id == selectedListId }?.projectId
}

/// The board a task is on, if any — the same question `isTaskInProject` answers
/// as a Bool, for callers that need to know which one.
///
/// Only the list memberships can answer it. A bare `statusRole` proves the task
/// is on SOME board (which is what `isTaskInProject` uses it for) but not which,
/// so it cannot name the board whose custom states apply.
func getProjectIdForTask(_ task: Task, lists: [TaskList]) -> String? {
    let membership = taskListMembershipIds(task)
    return lists.first { membership.contains($0.id) && $0.projectId != nil }?.projectId
}

/// Is this task part of a project — i.e. does it have a board column at all? (AITD-327)
///
/// Two ways of being in one, and both are needed. The list memberships are the ordinary answer:
/// a task in a list that carries a `projectId` is on that project's board. The `statusRole` is
/// the fallback for the case that answer cannot cover — a task whose lists have not loaded, or
/// whose project list is not in this client's cache, still carries the role it was moved to, and
/// a task sitting in a Doing column is in a project whatever the list array currently says.
///
/// Shared rather than written at the call site because "is this a project task" is the same
/// question on both platforms, and the Mac's detail row and the board must not disagree about it.
func isTaskInProject(_ task: Task, lists: [TaskList]) -> Bool {
    if let role = task.statusRole, !role.isEmpty { return true }
    let membership = taskListMembershipIds(task)
    return lists.contains { membership.contains($0.id) && $0.projectId != nil }
}

// MARK: - Move resolution

struct ProjectColumnMove: Equatable {
    let listIds: [String]
    let completed: Bool
    /// The status to write to `Task.statusRole`. Nil for Inbox and Done, which
    /// carry no status.
    ///
    /// The only thing written. The membership half of the old dual-write is gone
    /// (task e5c74b5e): the rows it pointed at are deleted, and `PUT /tasks/[id]`
    /// rejects the ENTIRE write when one id in `listIds` does not exist — so a
    /// client still appending one makes every board move fail, silently, and only
    /// for sessions that were open across the deploy.
    let statusRole: String?
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
        return ProjectColumnMove(listIds: retainedListIds, completed: false, statusRole: nil)
    case .done:
        return ProjectColumnMove(listIds: retainedListIds, completed: true, statusRole: nil)
    case .status:
        // Status list membership is no longer written: status is represented by
        // `statusRole`, while listIds retain only domain-list memberships. The
        // column id IS the role, so there is nothing to look up.
        return ProjectColumnMove(
            listIds: retainedListIds,
            completed: false,
            statusRole: targetColumn.id
        )
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
    /// The board's own custom states, so a card in a custom column is found
    /// here too (AITD-379). Omitted, such a card resolves to Inbox.
    customStates: [ProjectCustomState]? = nil,
    manualOrder: [String]?,
    recentlyCompletedWindow: RecentlyCompletedWindow? = nil,
    completionFilter: String? = nil,
    now: Date = Date()
) -> [Task] {
    // Built once, not per task: the filter below is the hot path on a board
    // with many cards.
    let columns = getProjectBoardColumns(lists, customStates: customStates)
    let inColumn = allTasks.filter { task in
        getTaskProjectColumnId(task, columns: columns) == column.id
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
    /// Carried through from `ProjectColumnMove` so the drop handler can actually write it.
    /// It used to stop at the inner type, which is how the board came to compute the new
    /// status role and then send only the membership (AWTD-566). nil for Inbox and Done.
    let statusRole: String?
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
        newManualOrder: newOrder,
        statusRole: move.statusRole
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
                           lists: [TaskList],
                           customStates: [ProjectCustomState]? = nil) -> Bool {
    getTaskProjectColumnId(task, lists: lists, customStates: customStates) == targetColumn.id
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

// MARK: - Applying a move

extension Task {
    /// The task as it will be once a board move is persisted.
    ///
    /// This exists because nothing joined the two halves of a card move. `resolveProjectColumnMove`
    /// computed the new `statusRole`, `getTaskProjectColumnId` preferred that field when picking a
    /// column, and in between, the board's drop handler wrote only `completed` and `listIds` — so
    /// the role never changed. Dragging out of Ready removed the membership, left the role, and the
    /// resolver put the card back where it came from ("moving from Ready to Inbox doesn't always
    /// work" — only tasks that HAD a role were stuck).
    ///
    /// Having the move expressed as a function means the round trip is checkable: apply it, then
    /// ask which column the task is in. Tests do exactly that, in both directions, for every pair
    /// of columns.
    func applyingBoardMove(_ move: ProjectColumnMove) -> Task {
        var moved = self
        moved.listIds = move.listIds
        // `lists` is the hydrated mirror of `listIds`; leaving it stale would let the resolver
        // read the OLD membership back out through taskListMembershipIds.
        moved.lists = lists?.filter { move.listIds.contains($0.id) }
        moved.completed = move.completed
        // Inbox and Done carry no status, so this CLEARS the role rather than leaving it.
        // That clearing is the whole fix.
        moved.statusRole = move.statusRole
        return moved
    }
}

// MARK: - Moving a task to a column, as a plan (task 729a190e)

/// What a move to a board column requires, in the order it must happen.
///
/// This lived in `MacBoardMove` and was Mac-only, which was fine while the board was the only
/// way to change a task's column. Task 729a190e adds a second way — the quick changer in task
/// details, on BOTH platforms — so the rule moved here rather than being written a second time.
/// A separate iOS copy of "what moving to Done means" is exactly how two surfaces start
/// disagreeing about whether a move completes a task.
///
/// Each case carries the status role as well as the lists, because the board resolves a card's
/// column from `Task.statusRole` first (AWTD-566). A plan that described only the membership
/// left the role behind and the resolver put the card straight back where it came from —
/// "moving from Ready to Inbox doesn't always work", where "not always" meant "not for any
/// task that has a role".
///
/// `statusRole` is "" for Inbox and Done, which carry no status; "" is the value that CLEARS
/// it, both locally and on the server.
enum ProjectColumnMovePlan: Equatable {
    case none                                              // already in that column
    case setLists([String], statusRole: String)            // status/inbox move, no completion change
    case complete([String], statusRole: String)            // → Done: set lists then complete
    case uncomplete([String], statusRole: String)          // Done → elsewhere: un-complete then set lists
}

func planProjectColumnMove(task: Task,
                           column: ProjectBoardColumn,
                           lists: [TaskList],
                           customStates: [ProjectCustomState]? = nil) -> ProjectColumnMovePlan {
    if getTaskProjectColumnId(task, lists: lists, customStates: customStates) == column.id { return .none }
    let move = resolveProjectColumnMove(task, targetColumn: column, lists: lists)
    let role = move.statusRole ?? ""
    switch column.kind {
    case .done:
        return .complete(move.listIds, statusRole: role)
    case .inbox, .status:
        return task.completed
            ? .uncomplete(move.listIds, statusRole: role)
            : .setLists(move.listIds, statusRole: role)
    }
}
