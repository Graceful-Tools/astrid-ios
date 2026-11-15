import Foundation

/// The multi-list project board (AITD-674, web AWTD-1660): each chosen list is a row and the
/// project's status columns stay columns.
///
/// Swift copies of web's pure `lib/project-board-rows.ts`, which astrid-core does not carry yet.
/// Which column a card sits in is NOT decided here. That is the core's `board`, asked per row
/// (`ProjectBoardModel`), so a card can't land in one column on a list's board and another on its
/// project's board.
///
/// Which lists are rows is saved per person per project on the server
/// (`GET|PUT /api/v1/projects/{id}/board-rows`). `nil` means nothing has been saved yet, and the
/// board shows the project's own lists. `[]` is a board the person emptied on purpose.
enum ProjectBoardRows {
    /// The most rows one board may save (the API refuses more).
    static let maxRows = 100

    /// The project's own domain lists, in the order the lists arrive.
    static func defaultListIds(projectId: String, lists: [TaskList]) -> [String] {
        lists.filter { $0.projectId == projectId && $0.isDomainList }.map(\.id)
    }

    /// The lists drawn as rows. Drops saved ids the person can no longer see, repeats, and anything
    /// that isn't a domain list (status rows, labels).
    static func resolve(saved: [String]?, projectId: String, lists: [TaskList]) -> [TaskList] {
        let ids = saved ?? defaultListIds(projectId: projectId, lists: lists)
        var byId: [String: TaskList] = [:]
        for list in lists where list.isDomainList && byId[list.id] == nil { byId[list.id] = list }
        var seen = Set<String>()
        return ids.compactMap { id in
            guard let list = byId[id], seen.insert(id).inserted else { return nil }
            return list
        }
    }

    static func add(_ listId: String, to rowIds: [String]) -> [String] {
        rowIds.contains(listId) ? rowIds : rowIds + [listId]
    }

    static func remove(_ listId: String, from rowIds: [String]) -> [String] {
        rowIds.filter { $0 != listId }
    }

    /// Lists that could be added: domain lists, not virtual, not rows yet, sorted by name.
    static func candidates(lists: [TaskList], rowIds: [String]) -> [TaskList] {
        let rows = Set(rowIds)
        var seen = Set<String>()
        return lists
            .filter { $0.isDomainList && $0.isVirtual != true && !rows.contains($0.id) }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// The cards of one row: the ids the core's board for that list put in a column, keeping only
    /// tasks that belong to that list. A card on two row lists shows in both rows.
    static func rowCardIds(_ ids: [String], listId: String, tasksById: [String: Task]) -> [String] {
        ids.filter { id in
            guard let task = tasksById[id] else { return false }
            return taskListMembershipIds(task).contains(listId)
        }
    }

    /// One row's cells under the project's columns. `rowColumns` is the core's board for the row's
    /// list. For the project's own lists its columns are the project's. A list from another
    /// project brings that board's columns: a card in a column this project also has (Ready,
    /// Doing, Waiting, Done, a shared custom role) keeps it, and one this project lacks waits in
    /// the Inbox column. A card is placed once per row.
    static func cells(rowColumns: [(id: String, ids: [String])], projectColumnIds: [String],
                      listId: String, tasksById: [String: Task]) -> [String: [String]] {
        var cells = Dictionary(uniqueKeysWithValues: projectColumnIds.map { ($0, [String]()) })
        let fallback = projectColumnIds.contains(VIRTUAL_INBOX_COLUMN_ID)
            ? VIRTUAL_INBOX_COLUMN_ID : projectColumnIds.first
        var placed = Set<String>()
        for column in rowColumns {
            guard let target = cells[column.id] != nil ? column.id : fallback else { continue }
            for id in rowCardIds(column.ids, listId: listId, tasksById: tasksById)
            where placed.insert(id).inserted {
                cells[target, default: []].append(id)
            }
        }
        return cells
    }
}

/// What a sidebar list carries when it is dragged onto a project board. A task card carries its
/// bare id, so the prefix is what tells the two apart (web `PROJECT_BOARD_LIST_DRAG_TYPE`).
enum ProjectBoardListDrag {
    static let prefix = "astrid-list:"

    static func payload(listId: String) -> String { prefix + listId }

    /// The list id a drag carries, or nil when it is not a list (a task card).
    static func listId(from payload: String) -> String? {
        guard payload.hasPrefix(prefix) else { return nil }
        let id = String(payload.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }
}
