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
    let registry = CommandRegistry()

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
