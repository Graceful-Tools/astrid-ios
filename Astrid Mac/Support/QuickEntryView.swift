//  QuickEntryView.swift
//  Astrid for Mac — global quick-entry (M0 de-risk target / M2)
//
//  Minimal capture window opened by the global hotkey. For the M0 spike it just needs to
//  appear from anywhere and dismiss. In M2 the text is parsed for natural-language dates and
//  #list / !task tokens (reuse the existing parser) and saved through TaskService → Outbox.

#if os(macOS)
import SwiftUI
import AppKit
import Combine

/// Owns the GlobalHotKey and opens the "Quick Add" window when it fires.
final class QuickEntryHotKeyController: ObservableObject {
    static let windowID = "quick-add"
    private var hotKey: GlobalHotKey?

    @MainActor func registerIfNeeded() {
        guard hotKey == nil else { return }
        // Default ⌥Space; make user-rebindable in M2.
        hotKey = GlobalHotKey { [weak self] in self?.open() }
        if hotKey == nil {
            NSLog("[Astrid][M0] GlobalHotKey registration FAILED — see docs/MAC_M0_NOTES.md fallback.")
        }
    }

    @MainActor private func open() {
        NSApp.activate(ignoringOtherApps: true)
        // SwiftUI Window is addressed by id; openWindow is injected where a View is available.
        // For M0 the AstridMacApp Window(id:) + this activate() is enough to prove the flow.
        NotificationCenter.default.post(name: .astridOpenQuickAdd, object: nil)
    }
}

extension Notification.Name {
    static let astridOpenQuickAdd = Notification.Name("astridOpenQuickAdd")
}

struct QuickEntryView: View {
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            TextField("Add a task…  (try “Report friday #work urgent”)", text: $text)
                .textFieldStyle(.plain)
                .font(.title2)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape, modifiers: [])
                Button("Add", action: save).keyboardShortcut(.return, modifiers: [])
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(Theme.bgPrimary)
    }

    private func save() {
        // Use the shared SmartTaskParser (dates/priority/#lists/repeat) — same engine as the sidebar
        // and menu-bar quick-add — instead of the naive local QuickEntryParser (Task fa267754).
        guard let args = MacQuickAdd.makeGlobalArgs(rawText: text, lists: ListService.shared.lists,
                                                    smartEnabled: UserSettingsService.shared.smartTaskCreationEnabled) else {
            NSLog("[Astrid] QuickEntry: nothing to add (empty text or no list)")
            return
        }
        // Offline-first: creates locally + journals through the Outbox, syncs when online.
        _Concurrency.Task {
            _ = try? await TaskService.shared.createTask(
                listIds: args.listIds, title: args.title, priority: args.priority,
                whenDate: args.whenDate, repeating: args.repeating, repeatingData: args.repeatingData)
        }
        text = ""
        dismiss()
    }
}
#endif
