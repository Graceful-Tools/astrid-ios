//  MacAppModel.swift
//  Astrid for Mac — lightweight app-shell state (palette visibility + command registry).
//
//  Shell state only — no business logic. Commands route through the shared services.

#if os(macOS)
import SwiftUI
import Combine

final class MacAppModel: ObservableObject {
    static let shared = MacAppModel()

    @Published var showPalette = false
    @Published var showShortcutsHelp = false
    /// Current content selection, mirrored from MacRootView so menu/shortcut commands can act on it.
    @Published var selectedListId: String?
    @Published var selectedTaskIds: Set<String> = []
    /// Selection *requested* by the palette; MacRootView applies then clears these (Task 5003c622).
    @Published var requestedListId: String?
    @Published var requestedTaskId: String?

    /// A view-level shortcut request (select/rename/open/cycle/focus). Carries a nonce so repeated
    /// identical requests still fire `onChange`. MacRootView + MacTaskDetailView observe it (9a60b697).
    struct ShortcutRequest: Equatable {
        let nonce: Int
        let kind: Kind
        enum Kind: Equatable {
            case selectAdjacent(Int)   // -1 previous, +1 next
            case cycleList
            case beginRename
            case openWindow
            case focus(MacShortcutEffect.FocusField)
        }
    }
    @Published var shortcutRequest: ShortcutRequest?
    private var shortcutNonce = 0
    @MainActor private func emit(_ kind: ShortcutRequest.Kind) {
        shortcutNonce += 1
        shortcutRequest = ShortcutRequest(nonce: shortcutNonce, kind: kind)
    }

    let registry = CommandRegistry()

    /// Navigate the main window to a list (from the command palette).
    @MainActor func openList(_ id: String) { requestedListId = id }
    /// Navigate to a task within its list (from the command palette).
    @MainActor func openTask(listId: String?, taskId: String) {
        if let listId { requestedListId = listId }
        requestedTaskId = taskId
    }

    /// Bare-key/menu actions the Mac app performs — the FULL shared table (9a60b697). Kept as an
    /// exhaustive set so `perform` and the ⌘/ help sheet never advertise a key that does nothing.
    static let handledActions: Set<ShortcutAction> = Set(ShortcutAction.allCases)

    /// Route a resolved shortcut/menu action to the shared services. Returns true if handled.
    /// Menus and the bare-key monitor both call this so the two stay identical (Task cdfbd79f).
    @MainActor @discardableResult
    func perform(_ action: ShortcutAction) -> Bool {
        // Pure data mutations (priority / due shifts / clear-due / unassign) apply to the selection.
        if let effect = MacShortcutEffect.dataEffect(for: action) {
            applyData(effect)
            return true
        }
        // Field-focus actions (d/i/s/c) route to the detail view.
        if let field = MacShortcutEffect.focusField(for: action) {
            emit(.focus(field))
            return true
        }
        switch action {
        case .newTask:       requestNewTask()
        case .completeTask:  completeSelectedTasks()
        case .deleteTask:    deleteSelectedTasks()
        case .showShortcuts: showShortcutsHelp = true
        case .editTitle:     emit(.beginRename)
        case .togglePanel:   emit(.openWindow)
        case .cycleFilters:  emit(.cycleList)
        case .selectPrevious: emit(.selectAdjacent(-1))
        case .selectNext:     emit(.selectAdjacent(1))
        default: return false   // unreachable: every action is covered above
        }
        return true
    }

    /// Apply a pure task-data effect to every selected task through the canonical service.
    @MainActor private func applyData(_ effect: MacShortcutEffect.DataEffect) {
        let ids = selectedTaskIds
        guard !ids.isEmpty else { return }
        let all = TaskService.shared.tasks
        for id in ids {
            guard let t = all.first(where: { $0.id == id }) else { continue }
            _Concurrency.Task {
                switch effect {
                case .priority(let p):
                    _ = try? await TaskService.shared.updateTask(taskId: id, priority: p, task: t)
                case .shiftDueDays(let d):
                    let newDue = MacShortcutEffect.shiftedDueDate(current: t.dueDateTime, days: d, today: Date())
                    _ = try? await TaskService.shared.updateTask(taskId: id, dueDateTime: newDue, task: t)
                case .clearDueDate:
                    _ = try? await TaskService.shared.updateTask(taskId: id, dueDateTime: .distantPast, task: t)
                case .assignNoOne:
                    _ = try? await TaskService.shared.updateTask(taskId: id, assigneeId: "", task: t)
                }
            }
        }
    }

    @MainActor func requestNewTask() { openQuickAdd() }

    @MainActor func completeSelectedTasks() {
        let ids = selectedTaskIds
        guard !ids.isEmpty else { return }
        _Concurrency.Task {
            for id in ids { _ = try? await TaskService.shared.completeTask(id: id, completed: true) }
        }
    }

    @MainActor func deleteSelectedTasks() {
        let ids = selectedTaskIds
        guard !ids.isEmpty else { return }
        selectedTaskIds = []
        _Concurrency.Task {
            for id in ids { try? await TaskService.shared.deleteTask(id: id) }
        }
    }

    private init() {
        registry.register(AppCommand(id: "new-task", title: "New Task",
                                     subtitle: "Quick add", shortcut: "⌥Space") { [weak self] in
            self?.openQuickAdd()
        })
        registry.register(AppCommand(id: "refresh-lists", title: "Refresh Lists",
                                     subtitle: nil, shortcut: nil) {
            _Concurrency.Task { _ = try? await ListService.shared.fetchLists() }
        })
    }

    func openPalette() { showPalette = true }

    private func openQuickAdd() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .astridOpenQuickAdd, object: nil)
    }
}
#endif
