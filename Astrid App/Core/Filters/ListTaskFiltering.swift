//  ListTaskFiltering.swift
//  Astrid — SHARED per-list task filtering + sorting business logic.
//
//  Single source of truth for how a list's saved filters (completion / priority / due-date /
//  assignee / assigned-by / in-lists) and sort setting turn the raw task set into what's shown.
//  Extracted from the iOS TaskListView so iOS, Mac, and (contract-wise) web stay identical —
//  no per-platform reimplementation. Pure functions: no view state, no singletons (the current
//  user id and manual order are passed in), so they're unit-testable and reusable everywhere.

import Foundation

/// Apply a list's saved filters to `tasks`. `currentUserId` is passed in (the assignee /
/// assigned-by filters need it) so this stays pure. Mirrors iOS `applyListFilters`.
func filterTasksForList(_ tasks: [Task], list: TaskList, currentUserId: String?) -> [Task] {
    var filtered = tasks

    // Completion filter — honors the list's per-list recentlyCompletedWindow (shared helper).
    let completionFilter = list.filterCompletion ?? "default"
    filtered = applyCompletionFilterWithWindow(filtered, filter: completionFilter,
                                               window: list.recentlyCompletedWindow)

    // Priority filter
    if let priority = list.filterPriority, priority != "all", let priorityInt = Int(priority) {
        filtered = filtered.filter { $0.priority.rawValue == priorityInt }
    }

    // Due-date filter
    if let dueDate = list.filterDueDate, dueDate != "all" {
        filtered = applyListDueDateFilter(filtered, filter: dueDate)
    }

    // Assignee filter
    if let assignee = list.filterAssignee, assignee != "all" {
        switch assignee {
        case "current_user":
            filtered = currentUserId.map { uid in filtered.filter { $0.assigneeId == uid } } ?? []
        case "not_current_user":
            if let uid = currentUserId {
                filtered = filtered.filter { $0.assigneeId != uid && $0.assigneeId != nil }
            } else {
                filtered = filtered.filter { $0.assigneeId != nil }
            }
        case "unassigned":
            filtered = filtered.filter { $0.assigneeId == nil }
        default:
            filtered = filtered.filter { $0.assigneeId == assignee }
        }
    }

    // Assigned-by filter
    if let assignedBy = list.filterAssignedBy, assignedBy != "all" {
        switch assignedBy {
        case "current_user":
            filtered = currentUserId.map { uid in filtered.filter { $0.isCreatedBy(uid) } } ?? []
        case "not_current_user":
            if let uid = currentUserId { filtered = filtered.filter { !$0.isCreatedBy(uid) } }
        default:
            filtered = filtered.filter { $0.isCreatedBy(assignedBy) }
        }
    }

    // In-lists filter (virtual lists like "Not in a List" / "Public Lists")
    if let inLists = list.filterInLists, inLists != "dont_filter" {
        switch inLists {
        case "not_in_list":
            filtered = filtered.filter { ($0.lists?.count ?? 0) == 0 && ($0.listIds?.count ?? 0) == 0 }
        case "in_list":
            filtered = filtered.filter { ($0.lists?.count ?? 0) > 0 || ($0.listIds?.count ?? 0) > 0 }
        case "public_lists":
            filtered = filtered.filter { $0.lists?.contains(where: { $0.privacy == .PUBLIC }) ?? false }
        default:
            break
        }
    }

    return filtered
}

/// Time-bound due-date filter. All-day tasks compare in UTC, timed tasks in local time.
/// Overdue incomplete tasks surface in the time-bound buckets. Mirrors iOS `applyDueDateFilter`.
func applyListDueDateFilter(_ tasks: [Task], filter: String) -> [Task] {
    var utcCalendar = Calendar.current
    utcCalendar.timeZone = TimeZone(identifier: "UTC")!
    let localCalendar = Calendar.current
    let now = Date()

    let localComponents = localCalendar.dateComponents([.year, .month, .day], from: now)
    let todayUTC = utcCalendar.date(from: localComponents)!
    let todayLocal = localCalendar.startOfDay(for: now)

    return tasks.filter { task in
        guard let dueDateTime = task.dueDateTime else { return filter == "no_date" }

        let calendar = task.isAllDay ? utcCalendar : localCalendar
        let today = task.isAllDay ? todayUTC : todayLocal
        let dueDate = calendar.startOfDay(for: dueDateTime)
        let isOverdueIncomplete = dueDate < today && !task.completed

        switch filter {
        case "overdue":   return dueDate < today && !task.completed
        case "today":     return dueDate == today || isOverdueIncomplete
        case "this_week":
            let weekFromNow = calendar.date(byAdding: .day, value: 7, to: today)!
            return (dueDate >= today && dueDate <= weekFromNow) || isOverdueIncomplete
        case "this_month":
            let monthFromNow = calendar.date(byAdding: .day, value: 30, to: today)!
            return (dueDate >= today && dueDate <= monthFromNow) || isOverdueIncomplete
        case "no_date":   return false
        default:          return true
        }
    }
}

/// Sort tasks by a list's `sortBy` setting. `manualOrder` is passed in for the "manual" case.
/// Mirrors iOS `applySorting`. Completed tasks sink to the bottom in the value-based sorts.
func sortTasksByListSetting(_ tasks: [Task], sortBy: String, manualOrder: [String]?) -> [Task] {
    func byDueThenNil(_ a: Date?, _ b: Date?) -> Bool? {
        if let d1 = a, let d2 = b { return d1 == d2 ? nil : d1 < d2 }
        if a != nil { return true }
        if b != nil { return false }
        return nil
    }

    switch sortBy {
    case "auto":
        return tasks.sorted { t1, t2 in
            if t1.completed != t2.completed { return !t1.completed }
            if t1.priority.rawValue != t2.priority.rawValue { return t1.priority.rawValue > t2.priority.rawValue }
            if let r = byDueThenNil(t1.dueDateTime, t2.dueDateTime) { return r }
            return (t1.createdAt ?? .distantPast) < (t2.createdAt ?? .distantPast)
        }
    case "priority":
        return tasks.sorted { t1, t2 in
            if t1.completed != t2.completed { return !t1.completed }
            if t1.priority.rawValue != t2.priority.rawValue { return t1.priority.rawValue > t2.priority.rawValue }
            if let r = byDueThenNil(t1.dueDateTime, t2.dueDateTime) { return r }
            return false
        }
    case "when":
        return tasks.sorted { t1, t2 in
            if t1.completed != t2.completed { return !t1.completed }
            if let d1 = t1.dueDateTime, let d2 = t2.dueDateTime {
                return d1 != d2 ? d1 < d2 : t1.priority.rawValue > t2.priority.rawValue
            } else if t1.dueDateTime != nil { return true }
            else if t2.dueDateTime != nil { return false }
            return t1.priority.rawValue > t2.priority.rawValue
        }
    case "createdAt":
        return tasks.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    case "manual":
        guard let order = manualOrder, !order.isEmpty else {
            return tasks.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }
        let orderMap = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return tasks.sorted { t1, t2 in
            switch (orderMap[t1.id], orderMap[t2.id]) {
            case let (i1?, i2?): return i1 < i2
            case (_?, nil):      return true
            case (nil, _?):      return false
            case (nil, nil):     return (t1.createdAt ?? .distantPast) > (t2.createdAt ?? .distantPast)
            }
        }
    default:
        return sortTasksByListSetting(tasks, sortBy: "auto", manualOrder: manualOrder)
    }
}
