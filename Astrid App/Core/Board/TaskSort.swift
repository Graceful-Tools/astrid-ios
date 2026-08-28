import Foundation

/// Swift port of `lib/task-sort.ts` from astrid-web. Pure logic — used
/// by both the list view and the board so columns sort identically to
/// the web. iOS Task has a single `dueDateTime` field, so the web's
/// "when || dueDate" fallbacks collapse to "dueDateTime".

enum TaskSortBy: String {
    case auto, priority, when, assignee, completed, incomplete, completedAt, manual
}

/// Comparator returning `< 0` if a < b, `0` if equal, `> 0` if a > b.
/// Matches JavaScript's compare contract.
func compareTasksBySort(
    _ a: Task,
    _ b: Task,
    sortBy: String?,
    manualOrderMap: [String: Int]? = nil
) -> Int {
    switch sortBy {
    case "priority":
        return (b.priority.rawValue) - (a.priority.rawValue)

    case "when":
        return compareDates(a.dueDateTime, b.dueDateTime)

    case "assignee":
        let aName = a.assignee?.name ?? a.assignee?.email ?? "Unassigned"
        let bName = b.assignee?.name ?? b.assignee?.email ?? "Unassigned"
        return aName.localizedCompare(bName) == .orderedAscending ? -1 :
               aName.localizedCompare(bName) == .orderedDescending ? 1 : 0

    case "completed":
        if a.completed == b.completed { return 0 }
        return a.completed ? 1 : -1

    case "incomplete":
        if a.completed == b.completed { return 0 }
        return a.completed ? -1 : 1

    case "completedAt":
        // Most recently completed first. Completed tasks LEAD — the sort exists
        // to review what got done — and the open half keeps the default auto
        // ordering so it stays a usable to-do list rather than scrambling.
        if a.completed != b.completed { return a.completed ? -1 : 1 }
        if a.completed && b.completed {
            // `completedAt` is the real stamp and is backdatable by sync;
            // `updatedAt` is the legacy fallback for tasks finished before the
            // column existed. Same convention as the recently-completed window
            // (RecentlyCompletedPresets) — a task with neither sorts last.
            return compareDates(a.completedAt ?? a.updatedAt,
                                b.completedAt ?? b.updatedAt,
                                descending: true)
        }
        return autoCompare(a, b)

    case "manual":
        if let map = manualOrderMap {
            let aRank = map[a.id] ?? map.count
            let bRank = map[b.id] ?? map.count
            return aRank - bRank
        }
        // No manual order yet — fall back to created-at ascending.
        return compareDates(a.createdAt, b.createdAt)

    default: // "auto" or anything else
        return autoCompare(a, b)
    }
}

private func autoCompare(_ a: Task, _ b: Task) -> Int {
    if a.completed != b.completed {
        return a.completed ? 1 : -1
    }
    if a.priority.rawValue != b.priority.rawValue {
        return b.priority.rawValue - a.priority.rawValue
    }
    let due = compareDates(a.dueDateTime, b.dueDateTime)
    if due != 0 { return due }
    let created = compareDates(a.createdAt, b.createdAt)
    if created != 0 { return created }
    return a.title.localizedCompare(b.title) == .orderedAscending ? -1 :
           a.title.localizedCompare(b.title) == .orderedDescending ? 1 : 0
}

/// Nils sort last in BOTH directions — `descending` flips the comparison of two
/// real dates, not the treatment of a missing one. A task with no stamp belongs
/// at the bottom whichever way the column is pointed.
private func compareDates(_ a: Date?, _ b: Date?, descending: Bool = false) -> Int {
    switch (a, b) {
    case (nil, nil): return 0
    case (nil, _):   return 1   // nils sort last
    case (_, nil):   return -1
    case let (a?, b?):
        if a < b { return descending ? 1 : -1 }
        if a > b { return descending ? -1 : 1 }
        return 0
    }
}

/// Build the lookup map for "manual" sort. Tasks not present in
/// `manualOrder` are placed after the ordered ones, sorted by createdAt.
func buildManualOrderMap(tasks: [Task], manualOrder: [String]?) -> [String: Int]? {
    guard let manualOrder, !manualOrder.isEmpty else { return nil }
    var map: [String: Int] = [:]
    for (index, id) in manualOrder.enumerated() {
        map[id] = index
    }
    let known = Set(manualOrder)
    let missing = tasks
        .filter { !known.contains($0.id) }
        .sorted { compareDates($0.createdAt, $1.createdAt) < 0 }
    var next = map.count
    for task in missing where map[task.id] == nil {
        map[task.id] = next
        next += 1
    }
    return map
}

/// Sort a copy of `tasks` by `sortBy`. The manual-order map is built
/// on demand if `sortBy == "manual"`.
func sortTasksForList(
    _ tasks: [Task],
    sortBy: String?,
    manualOrder: [String]? = nil
) -> [Task] {
    let map: [String: Int]? = sortBy == "manual"
        ? buildManualOrderMap(tasks: tasks, manualOrder: manualOrder)
        : nil
    return tasks.sorted { compareTasksBySort($0, $1, sortBy: sortBy, manualOrderMap: map) < 0 }
}
