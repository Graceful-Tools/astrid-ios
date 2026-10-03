//  TaskSearch.swift
//  Astrid — task search, for iOS and Mac alike.
//
//  iOS searched inline in TaskListView: the query as one phrase, case-insensitive, over the title,
//  the description and the assignee's name; top-level tasks only (a subtask shows under its
//  parent); completed work hidden as a list hides it by default; highest priority first. The Mac
//  had its own search — every word anywhere in title and notes, completed included, newest first —
//  so the same query found different tasks on the two apps. Jon, 2026-10-03: on disagreement
//  follow iOS — so iOS's search moved here and both apps call it.

import Foundation

enum TaskSearch {
    /// Whether `task` matches `query`: the whole query, as typed, in its title, description or
    /// assignee's name, ignoring case.
    static func matches(_ task: Task, query: String) -> Bool {
        let q = query.lowercased()
        if task.title.lowercased().contains(q) { return true }
        if task.description.lowercased().contains(q) { return true }
        if let name = task.assignee?.displayName, name.lowercased().contains(q) { return true }
        return false
    }

    /// The search results for `query`. An empty query finds nothing: search is intentional.
    static func results(_ tasks: [Task], query: String) -> [Task] {
        guard !query.isEmpty else { return [] }
        let found = tasks.filter { $0.parentTaskId == nil && matches($0, query: query) }
        let visible = applyCompletionFilterWithWindow(found, filter: "default", window: nil)
        return sortTasksByListSetting(visible, sortBy: "priority", manualOrder: nil)
    }
}
