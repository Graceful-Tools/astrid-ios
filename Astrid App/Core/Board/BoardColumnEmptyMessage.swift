import Foundation

/// What an empty board column says (ADEV-81). Each column speaks to its own state: an empty
/// Waiting column is good news, an empty Doing column is a nudge. Every column used to borrow the
/// list's "Ready to capture your thoughts?" line, which fits none of them.
///
/// Shared by the iOS `BoardColumnView` and the Mac `MacBoardView`, so the two boards say the same
/// thing. Web's board says "Drop tasks here" today; its half is filed with this English so the
/// strings can be hoisted into astrid-core's shared catalog once both clients match.
enum BoardColumnEmptyMessage: Equatable, CaseIterable {
    case inbox, ready, doing, waiting, done, custom

    static func decide(_ column: ProjectBoardColumn) -> BoardColumnEmptyMessage {
        switch column.kind {
        case .inbox: return .inbox
        case .done: return .done
        case .status:
            switch column.id {
            case "ready": return .ready
            case "doing": return .doing
            case "waiting": return .waiting
            default: return .custom
            }
        }
    }

    /// The `Localizable.strings` key it reads.
    var key: String {
        switch self {
        case .inbox: return "empty_state.board.inbox"
        case .ready: return "empty_state.board.ready"
        case .doing: return "empty_state.board.doing"
        case .waiting: return "empty_state.board.waiting"
        case .done: return "empty_state.board.done"
        case .custom: return "empty_state.board.custom"
        }
    }

    var text: String { NSLocalizedString(key, comment: "") }
}
