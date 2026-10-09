//  MacBoardCardHeader.swift
//  Astrid for Mac — the open board card's header controls: web's ⋮ (AITD-470) and an editable
//  title (AITD-471). Layout decisions live in `MacBoardExpand`; these are the views.

#if os(macOS)
import SwiftUI

/// The ⋮ on an open card — web's compact `TaskActionMenu`. Renders the SAME items as the card's
/// right-click menu (`MacTaskRowMenuContent`), so the two cannot drift; right-click is invisible,
/// and this is the affordance that says the actions exist.
struct MacBoardCardActionsMenu: View {
    static let items = MacTaskRowMenu.items(for: .boardCard)

    let task: Task
    let lists: [TaskList]
    let currentListId: String?
    let actions: MacTaskRowMenuActions

    var body: some View {
        Menu {
            MacTaskRowMenuContent(task: task, surface: .boardCard, lists: lists,
                                  currentListId: currentListId, actions: actions)
        } label: {
            // SF Symbols has no vertical ellipsis on macOS; turned, so it reads as web's ⋮.
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .rotationEffect(.degrees(90))
        .foregroundStyle(Theme.textMuted)
        .help(NSLocalizedString("mac.task_actions", comment: ""))
        .accessibilityLabel(NSLocalizedString("mac.task_actions", comment: ""))
        .accessibilityIdentifier("board.card.actions")
    }
}

/// The open card's title, editable in place. Return or clicking away saves, through the same
/// rule as the detail's title row (`MacTaskTitleEdit`) and the same service write.
struct MacBoardCardTitleField: View {
    let task: Task
    /// Rename from a menu lands the caret here rather than merely opening the card — whether
    /// the card was already open or opens because of it.
    var focusRequested = false
    var onFocused: () -> Void = {}

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        // `axis: .vertical` so a long title wraps like the face it replaces; Shift-Return is a newline.
        TextField(NSLocalizedString("mac.title", comment: ""), text: $draft, axis: .vertical)
            .labelsHidden()
            .textFieldStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .strikethrough(task.completed)
            .focused($focused)
            .onSubmit { save(); focused = false }
            .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
            // Another device renamed it while the card was open: follow, unless mid-edit.
            .onChange(of: task.title) { _, title in if !focused { draft = title } }
            .onAppear {
                draft = task.title
                if focusRequested { takeFocus() }
            }
            .onChange(of: focusRequested) { _, requested in if requested { takeFocus() } }
            .accessibilityIdentifier("board.card.title")
    }

    private func takeFocus() {
        DispatchQueue.main.async { focused = true; onFocused() }
    }

    private func save() {
        guard let title = MacTaskTitleEdit.titleToSave(draft: draft, current: task.title) else { return }
        let task = task
        AppActions.perform("Save title") {
            _ = try await TaskService.shared.updateTask(taskId: task.id, title: title, task: task)
        }
    }
}
#endif
