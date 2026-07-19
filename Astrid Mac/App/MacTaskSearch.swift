//  MacTaskSearch.swift
//  Astrid for Mac — pure global task search (Task 36587d3d). Full-text over title + notes across
//  ALL tasks including completed (the ⌘K palette only fuzzy-matches OPEN tasks). Pure + testable.

#if os(macOS)
import Foundation

enum MacTaskSearch {
    /// Tasks whose title or description contains every whitespace-separated term (case-insensitive).
    /// Incomplete first, then by most-recent. Empty query → no results (search is intentional).
    static func matches(_ tasks: [Task], query: String) -> [Task] {
        let terms = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        return tasks.filter { t in
            let hay = (t.title + " " + t.description).lowercased()
            return terms.allSatisfy { hay.contains($0) }
        }
        .sorted { a, b in
            if a.completed != b.completed { return !a.completed }
            return (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
        }
    }
}
#endif
