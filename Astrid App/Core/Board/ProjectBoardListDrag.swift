import Foundation

/// What a sidebar list carries when it is dragged onto a project board (AITD-674). A task card
/// carries its bare id, so the prefix is what tells the two apart (web
/// `PROJECT_BOARD_LIST_DRAG_TYPE`).
enum ProjectBoardListDrag {
    nonisolated static let prefix = "astrid-list:"

    nonisolated static func payload(listId: String) -> String { prefix + listId }

    /// The list id a drag carries, or nil when it is not a list (a task card).
    nonisolated static func listId(from payload: String) -> String? {
        guard payload.hasPrefix(prefix) else { return nil }
        let id = String(payload.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }
}
