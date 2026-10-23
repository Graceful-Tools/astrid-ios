import Foundation

/// What the task list says when it has nothing to show — one string per kind of list, matching
/// web's `AstridEmptyState` (astrid-web/components/ui/astrid-empty-state.tsx). ASTRID.md §8 names
/// it as a cross-platform contract, so the decision lives here, where a test calls it (AITD-538).
///
/// There is no completed-task threshold: iOS once switched to a "caught up" message after ten
/// completions, which web never had.
enum EmptyStateMessage: Equatable {
    case searchPrompt
    case `default`
    case myTasks
    case today
    case publicList
    case sharedList
    case list(name: String)

    static func decide(selectedListId: String?, searchText: String, list: TaskList?) -> EmptyStateMessage {
        if selectedListId == "search" { return searchText.isEmpty ? .searchPrompt : .default }
        // A search typed from the sidebar answers with the default, whatever list is open.
        if !searchText.isEmpty { return .default }
        if selectedListId == "my-tasks" { return .myTasks }
        guard let list else { return .default }
        if list.isVirtual == true {
            switch list.virtualListType {
            case "my-tasks": return .myTasks
            case "today": return .today
            default: return .default
            }
        }
        switch list.privacy {
        case .PUBLIC: return .publicList
        case .SHARED: return .sharedList
        default: return .list(name: list.name)
        }
    }

    /// The `Localizable.strings` key it reads.
    var key: String {
        switch self {
        case .searchPrompt: return "tasks.search_tasks_placeholder"
        case .default: return "empty_state.default"
        case .myTasks: return "empty_state.my_tasks"
        case .today: return "empty_state.today"
        case .publicList: return "empty_state.public_list"
        case .sharedList: return "empty_state.shared_list"
        case .list: return "empty_state.list_with_name"
        }
    }

    var text: String {
        switch self {
        // The My Tasks copy names the brand.
        case .myTasks: return Brand.localized(key)
        case .list(let name): return String(format: NSLocalizedString(key, comment: ""), name)
        default: return NSLocalizedString(key, comment: "")
        }
    }
}
