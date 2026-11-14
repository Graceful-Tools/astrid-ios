//  MacPaletteSearch.swift
//  Astrid for Mac — pure fuzzy search over tasks & lists for the ⌘K palette (Task 5003c622).
//  Kept separate from the view so the ranking/limit behavior is unit-testable.

#if os(macOS)
import Foundation

enum MacPaletteSearch {
    /// Open tasks whose title fuzzy-matches the query, best first, capped at `limit`. A query that
    /// is a task id (`awtd-1405`, any case) puts the task with that id first (AITD-565).
    static func matchingTasks(_ query: String, tasks: [Task], limit: Int = 6) -> [Task] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let open = tasks.filter { !$0.completed }
        let byId = identifierMatch(q, tasks: open)
        let ranked = FuzzyMatch.ranked(q, open.filter { $0.id != byId?.id }, title: \.title)
        return ([byId].compactMap { $0 } + ranked).prefix(limit).map { $0 }
    }

    /// The task whose identifier the query names, compared after the shared parse — so case and
    /// surrounding space do not matter, and `AWTD-1405` never matches `AWTD-14050`.
    static func identifierMatch(_ query: String, tasks: [Task]) -> Task? {
        guard let wanted = TaskIdentifiers.parse(query) else { return nil }
        return tasks.first { TaskIdentifiers.parse($0.identifier) == wanted }
    }

    /// Lists whose name fuzzy-matches the query, best first, capped at `limit`.
    static func matchingLists(_ query: String, lists: [TaskList], limit: Int = 6) -> [TaskList] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return FuzzyMatch.ranked(q, lists, title: \.name).prefix(limit).map { $0 }
    }
}
#endif
