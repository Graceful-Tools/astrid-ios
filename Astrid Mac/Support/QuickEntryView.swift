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
    /// The same one-task overrides the add bar keeps (AITD-387). nil means "use the default".
    @State private var priorityOverride: Int?
    @State private var assigneeOverride: String?      // "unassigned" = explicitly no one
    @State private var showingOptions = false
    @Environment(\.dismiss) private var dismiss

    /// The priority this task would get right now. There is no list here — the quick-add window
    /// adds to My Tasks (AITD-387) — so there is no list default to fall back to.
    private var resolvedPriority: Task.Priority {
        Task.Priority(rawValue: priorityOverride ?? 0) ?? .none
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                // The same checkbox-as-options-button the add bar uses: it previews what the task
                // will start as, and opens the picker (AITD-387).
                MacTaskCheckbox(completed: false, priority: resolvedPriority,
                                size: MacTaskVisuals.rowCheckboxSize,
                                repeating: false)
                    .contentShape(Rectangle())
                    .onTapGesture { showingOptions = true }
                    .macPointingHand()
                    .help(NSLocalizedString("tasks.priority", comment: ""))
                    .popover(isPresented: $showingOptions, arrowEdge: .top) {
                        MacDraftDefaultsPicker(
                            priorityOverride: $priorityOverride,
                            assigneeOverride: $assigneeOverride,
                            resolvedPriority: resolvedPriority,
                            // No list, so the default really is "unassigned" — say so rather than
                            // naming a list default that does not exist here.
                            defaultAssigneeLabel: MacDraftDefaults.defaultAssigneeLabel(
                                defaultAssigneeId: nil,
                                currentUserId: AuthManager.shared.userId,
                                members: []),
                            assigneeChoices: MacDraftDefaults.assigneeChoices(
                                members: [], currentUserId: AuthManager.shared.userId,
                                hasList: false))
                    }

                TextField(NSLocalizedString("mac.quick_add_placeholder", comment: ""), text: $text, axis: .vertical)
                    .lineLimit(1...4)   // wraps + expands vertically (a02a6819)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .macTextSelection()
                    .onSubmit(save)
            }
            HStack {
                Spacer()
                Button(NSLocalizedString("actions.cancel", comment: "")) { dismiss() }.keyboardShortcut(.escape, modifiers: [])
                Button(NSLocalizedString("actions.add", comment: ""), action: save).keyboardShortcut(.return, modifiers: [])
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(Theme.bgPrimary)
        .macTextSelection()
    }

    private func save() {
        // Use the shared SmartTaskParser (dates/priority/#lists/repeat) — same engine as the sidebar
        // and menu-bar quick-add — instead of the naive local QuickEntryParser (Task fa267754).
        guard let args = MacQuickAdd.makeGlobalArgs(rawText: text, lists: ListService.shared.lists,
                                                    smartEnabled: UserSettingsService.shared.smartTaskCreationEnabled,
                                                    priorityOverride: priorityOverride,
                                                    currentUserId: AuthManager.shared.userId) else {
            NSLog("[Astrid] QuickEntry: nothing to add (empty text)")
            return
        }
        // The assignee override is applied HERE rather than inside makeGlobalArgs, exactly as the
        // add bar does it — "unassigned" is a deliberate nobody, not a missing value (AITD-387).
        let chosenAssignee = assigneeOverride
        // Offline-first: creates locally + journals through the Outbox, syncs when online.
        MacActions.perform("Add task") {
            _ = try await TaskService.shared.createTask(
                listIds: args.listIds, title: args.title, priority: args.priority,
                whenDate: args.whenDate,
                assigneeId: chosenAssignee == "unassigned" ? nil : (chosenAssignee ?? args.assigneeId),
                isPrivate: args.isPrivate,
                repeating: args.repeating, repeatingData: args.repeatingData)
        }
        text = ""
        // The overrides apply to ONE task, like iOS and like the add bar.
        priorityOverride = nil
        assigneeOverride = nil
        dismiss()
    }
}
#endif
