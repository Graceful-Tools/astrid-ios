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
    let registry = CommandRegistry()

    /// Navigate the main window to a list (from the command palette).
    @MainActor func openList(_ id: String) { requestedListId = id }
    /// Navigate to a task within its list (from the command palette).
    @MainActor func openTask(listId: String?, taskId: String) {
        if let listId { requestedListId = listId }
        requestedTaskId = taskId
    }

    /// Bare-key/menu actions the Mac app actually performs (single source of truth for dispatch).
    static let handledActions: Set<ShortcutAction> = [.newTask, .completeTask, .deleteTask, .showShortcuts]

    /// Route a resolved shortcut/menu action to the shared services. Returns true if handled.
    /// Menus and the bare-key monitor both call this so the two stay identical (Task cdfbd79f).
    @MainActor @discardableResult
    func perform(_ action: ShortcutAction) -> Bool {
        switch action {
        case .newTask:      requestNewTask()
        case .completeTask: completeSelectedTasks()
        case .deleteTask:   deleteSelectedTasks()
        case .showShortcuts: showShortcutsHelp = true
        default: return false
        }
        return true
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
