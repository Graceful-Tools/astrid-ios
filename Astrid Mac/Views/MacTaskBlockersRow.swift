//  MacTaskBlockersRow.swift
//  Astrid for Mac — "Waiting on" in task details (AITD-430; iOS AITD-429; web AWTD-1002).
//
//  Shares everything but the styling with iOS: `MacTaskFields.rows` places the row via
//  `TaskBlockers.showsRow`, the picker ranks through `TaskBlockers.rankCandidates`, and every
//  call goes through `TaskBlockerService`. Mac specifics: the picker works from the keyboard
//  (↑/↓, Return to add, Escape to close), and a chip opens its task on click or from its
//  context menu.
//
//  It never writes `statusRole` — the server moves Ready ↔ Waiting and sends `task_updated`.

#if os(macOS)
import SwiftUI

struct MacTaskBlockersRow: View {
    let task: Task

    @State private var blockedBy: [TaskBlocker] = []
    @State private var dependentIds: [String] = []
    @State private var showingPicker = false

    private let service = TaskBlockerService.shared

    var body: some View {
        // Wraps with no count cap: designed for one to three, assumes neither.
        FlowLayout(spacing: 6, rowSpacing: 6) {
            if blockedBy.isEmpty {
                Text(NSLocalizedString("tasks.waitingOn.empty", comment: ""))
                    .font(MacTypography.label)
                    .foregroundStyle(Theme.textMuted)
            }
            ForEach(blockedBy) { blocker in
                chip(for: blocker)
            }
            Button(NSLocalizedString("tasks.waitingOn.add", comment: "")) { showingPicker = true }
                .buttonStyle(.link)
                .font(MacTypography.label)
                .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
                    MacTaskBlockerPicker(task: task,
                                         excludedIds: blockedBy.map(\.id) + dependentIds,
                                         onBlockersChanged: { blockedBy = $0 })
                }
        }
        .task(id: task.id) { await load() }
    }

    private func chip(for blocker: TaskBlocker) -> some View {
        HStack(spacing: 4) {
            if blocker.isHidden {
                Image(systemName: "lock").font(MacTypography.label)
            }
            Text(blocker.isHidden
                 ? NSLocalizedString("tasks.waitingOn.hidden", comment: "")
                 : blocker.title ?? blocker.identifier ?? "")
                .font(MacTypography.label)
                .strikethrough(blocker.isCompleted)
                .lineLimit(1)
                .foregroundStyle(blocker.isHidden || blocker.isCompleted ? Theme.textMuted : Theme.textPrimary)
                .onTapGesture { open(blocker) }
            Button { remove(blocker) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textMuted)
            .help(NSLocalizedString("tasks.waitingOn.remove", comment: ""))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 6))
        .contextMenu {
            if !blocker.isHidden {
                Button(NSLocalizedString("Open", comment: "")) { open(blocker) }
            }
            Button(NSLocalizedString("tasks.waitingOn.remove", comment: "")) { remove(blocker) }
        }
    }

    /// A hidden blocker cannot be opened — the reader may not see it — but it still blocks.
    @MainActor private func open(_ blocker: TaskBlocker) {
        guard !blocker.isHidden else { return }
        let cached = TaskService.shared.tasks.first { $0.id == blocker.id }
        MacAppModel.shared.openTask(listId: cached.flatMap { taskListMembershipIdsInOrder($0).first },
                                    taskId: blocker.id)
    }

    private func load() async {
        guard let response = try? await service.blockers(taskId: task.id) else { return }
        blockedBy = response.blockedBy
        dependentIds = response.dependentIds
    }

    private func remove(_ blocker: TaskBlocker) {
        let before = blockedBy
        blockedBy.removeAll { $0.id == blocker.id }
        _Concurrency.Task {
            do {
                blockedBy = try await service.removeBlocker(taskId: task.id, blockingTaskId: blocker.id)
            } catch {
                blockedBy = before
            }
        }
    }
}

/// Stays open between picks — adding two or three at once is common.
private struct MacTaskBlockerPicker: View {
    let task: Task
    let excludedIds: [String]
    let onBlockersChanged: ([TaskBlocker]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var hits: [BlockerSearchHit] = []
    @State private var added: [String] = []
    @State private var highlighted = 0
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    private let service = TaskBlockerService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(NSLocalizedString("tasks.waitingOn.searchPlaceholder", comment: ""), text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { if hits.indices.contains(highlighted) { add(hits[highlighted]) } }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.escape) { dismiss(); return .handled }
            if let errorMessage {
                Text(errorMessage).font(MacTypography.label).foregroundStyle(Theme.error)
            }
            if TaskBlockers.shouldSearch(query) && hits.isEmpty {
                Text(NSLocalizedString("tasks.waitingOn.noResults", comment: ""))
                    .font(MacTypography.label).foregroundStyle(Theme.textMuted)
            }
            ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                Text(hit.title)
                    .strikethrough(hit.completed == true)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(index == highlighted ? Theme.accent.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: 4))
                    .contentShape(Rectangle())
                    .onTapGesture { add(hit) }
            }
        }
        .padding(10)
        .frame(width: 300)
        .onAppear { fieldFocused = true }
        .task(id: query) { await search() }
    }

    private func move(_ delta: Int) {
        guard !hits.isEmpty else { return }
        highlighted = min(max(highlighted + delta, 0), hits.count - 1)
    }

    private func search() async {
        // Debounce: `.task(id:)` cancels this when the query changes again.
        try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        guard !_Concurrency.Task.isCancelled else { return }
        let found = (try? await service.candidates(query: query, task: task,
                                                   excludedIds: excludedIds + added)) ?? []
        guard !_Concurrency.Task.isCancelled else { return }
        hits = found
        highlighted = 0
    }

    private func add(_ hit: BlockerSearchHit) {
        errorMessage = nil
        hits.removeAll { $0.id == hit.id }
        highlighted = min(highlighted, max(hits.count - 1, 0))
        added.append(hit.id)
        _Concurrency.Task {
            do {
                onBlockersChanged(try await service.addBlocker(taskId: task.id, blockingTaskId: hit.id))
            } catch {
                added.removeAll { $0 == hit.id }
                errorMessage = NSLocalizedString(TaskBlockers.isCycleRefusal(error)
                                                 ? "tasks.waitingOn.cycleError" : "tasks.waitingOn.addError",
                                                 comment: "")
            }
        }
    }
}
#endif
