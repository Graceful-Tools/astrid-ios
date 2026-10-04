import Foundation

/// What the Apple apps still decide about a project board themselves (AITD-461).
///
/// The board's rules — its columns and their names, which card sits in which column and in what
/// order, what a move or a drop writes, which states the picker offers — are astrid-core's
/// (`board`, `dropBoardCard`, `moveTaskToColumn`, `setTaskStatus`, `taskStatusOptions`; CONTRACTS
/// D43–D46), asked through `BoardModel` and `TaskService`. What stays here is decoding the board's
/// stored columns, the shape a column arrives in, and the questions a row asks while it draws:
/// is this task on a board at all, and which one.

/// A board's own custom column, as stored on `Project.customStates` — web's `StatusState`.
///
/// Decoded here so a `Project` round-trips through the app; what the entries MEAN (a default
/// role is a rename, not a column; the first of a role wins; order) is the core's
/// `board::parse_custom_states`, which the board and the pickers ask.
///
/// Decoding is deliberately lenient: the server column is a free-form `Json?`
/// that nothing validates on read, so a single malformed entry must not fail
/// the whole `Project` — one bad row would otherwise empty the board. Junk
/// decodes to blank fields that the core then drops, which is how web behaves
/// entry-by-entry.
struct ProjectCustomState: Codable, Equatable, Hashable {
    let role: String
    let name: String
    let description: String?
    /// Absent means "wherever it landed" — the core fills in the insertion
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

let VIRTUAL_INBOX_COLUMN_ID = "__virtual_inbox__"
let VIRTUAL_DONE_COLUMN_ID  = "__virtual_done__"

/// What a column is. Raw values are the core's wire spelling.
nonisolated enum ProjectBoardColumnKind: String, Equatable, Decodable, Sendable {
    case inbox, status, done
}

nonisolated struct ProjectBoardColumn: Equatable, Identifiable, Sendable {
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

// MARK: - Which board a task is on

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

// MARK: - Layout

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

// MARK: - Memberships

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
