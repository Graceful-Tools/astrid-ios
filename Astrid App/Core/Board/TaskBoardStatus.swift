import Foundation

/// Which board column a task sits in, for the status pill on a LIST row (AITD-613).
///
/// Jon: "In list view, add board status as a pill on the row with date and other lists" — red
/// for Inbox, yellow for Waiting, green for Ready, another green for Doing, blue for Done. Never
/// on a board card: there the column header already says it.
///
/// Read synchronously from what the row already holds — the task's role and completion, the
/// cached lists and projects — because a row cannot wait on the core per task while it scrolls.
/// It answers the same column the core's `board` puts the card in for the cases a row meets:
/// completed is Done (D45), no role is Inbox, otherwise the role. A board's rename of a column
/// (`Project.customStates`) wins over the built-in name, as it does on the board.
///
/// Shared by iOS `TaskRowView` and Mac `MacTaskRow`, so the two rows cannot disagree.
nonisolated struct TaskBoardStatus: Equatable, Sendable {
    nonisolated enum Kind: String, Equatable, Sendable {
        case inbox, ready, doing, waiting, done, custom
    }

    let kind: Kind
    let name: String

    /// Localization key for a built-in column's name.
    static func nameKey(for kind: Kind) -> String? {
        kind == .custom ? nil : "board.status.\(kind.rawValue)"
    }

    /// The pill for `task`, or nil when it is on no board — or sits in a custom column whose name
    /// this client does not have (a raw `custom-…` role is never shown).
    static func of(_ task: Task, lists: [TaskList], projects: [Project]) -> TaskBoardStatus? {
        guard isTaskInProject(task, lists: lists) else { return nil }

        let role = task.statusRole ?? ""
        let kind: Kind
        if task.completed {
            kind = .done
        } else if role.isEmpty {
            kind = .inbox
        } else {
            kind = Kind(rawValue: role).flatMap { [.ready, .doing, .waiting].contains($0) ? $0 : nil }
                ?? .custom
        }

        // The board's own name for this role, when it renamed it or it is a custom column.
        let membership = taskListMembershipIds(task)
        let projectIds = Set(lists.filter { membership.contains($0.id) }.compactMap(\.projectId))
        let lookupRole = kind == .custom ? role : kind.rawValue
        let boardName = projects
            .filter { projectIds.contains($0.id) }
            .lazy
            .compactMap { $0.customStates?.first { $0.role == lookupRole && !$0.name.isEmpty }?.name }
            .first

        if let boardName { return TaskBoardStatus(kind: kind, name: boardName) }
        guard let key = nameKey(for: kind) else { return nil }
        return TaskBoardStatus(kind: kind, name: NSLocalizedString(key, comment: ""))
    }
}
