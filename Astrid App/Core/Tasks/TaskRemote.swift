//  TaskRemote.swift
//  Where a task on a GitHub Projects board lives on GitHub (AITD-491, web spec §11.2).
//
//  The server sends `remote` only on a GitHub-backed task (`lib/backends/task-remote.ts`), so a
//  classic task has none. Same shape as astrid-core's `TaskRemote` (CONTRACTS D55).

import Foundation

nonisolated struct TaskRemote: Codable, Equatable, Hashable {
    /// `issue`, `pull_request` or `draft_issue`.
    var kind: String?
    /// The issue or pull request on GitHub. Nil for a draft, which has no page of its own.
    var url: String?
    var nodeId: String?
    var version: String?
    /// `owner/repo`. Nil for a draft.
    var repo: String?
    var number: Int?

    /// The page the chip opens.
    var pageURL: URL? { url.flatMap(URL.init(string:)) }

    /// `owner/repo#N`, the chip a row draws; nil when there is no page to open, because a chip
    /// that goes nowhere is worse than no chip. The same rule as astrid-core's `chip_label`.
    var chipLabel: String? {
        guard pageURL != nil, let repo, let number else { return nil }
        return "\(repo)#\(number)"
    }
}
