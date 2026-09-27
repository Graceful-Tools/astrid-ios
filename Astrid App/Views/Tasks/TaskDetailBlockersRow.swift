//  TaskDetailBlockersRow.swift
//  "Waiting on" in task details (AITD-429; web AWTD-1002, `TaskDetailBlockersRow.tsx`).
//
//  Whether it shows is `TaskBlockers.showsRow`, the rule web states and the Mac shares, with
//  "is this task on a board" asked of `isTaskInProject` — the board's own derivation. The picker, the
//  ranking and the API all come from Core — this file is the iOS styling around them.
//
//  It never writes `statusRole`. Adding a blocker to a Ready task moves it to Waiting and
//  completing the last one moves it back; the server does both, and the result arrives as
//  `task_updated`, which redraws the detail view's board-state row on its own.

import SwiftUI

struct TaskDetailBlockersRow: View {
    let task: Task
    let isReadOnly: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var blockedBy: [TaskBlocker] = []
    @State private var dependentIds: [String] = []
    @State private var showingPicker = false
    @StateObject private var listService = ListService.shared

    private let service = TaskBlockerService.shared

    private var isInProject: Bool { isTaskInProject(task, lists: listService.lists) }

    var body: some View {
        Group {
            if TaskBlockers.showsRow(isInProject: isInProject, isReadOnly: isReadOnly,
                                     hasBlockers: !blockedBy.isEmpty) {
                TwoColumnRow(label: NSLocalizedString("tasks.waitingOn.label", comment: ""),
                             icon: "hourglass") {
                    chips
                }
            }
        }
        .task(id: "\(task.id)|\(isInProject)") { await load() }
        .sheet(isPresented: $showingPicker) {
            TaskBlockerPickerSheet(task: task,
                                   excludedIds: blockedBy.map(\.id) + dependentIds,
                                   onBlockersChanged: { blockedBy = $0 })
        }
    }

    // Reads like the When row (AITD-438): the empty state is a chip that says so and opens the
    // picker, as "No due date" opens the date picker, and a blocker is a chip naming its short
    // task id. Wraps with no cap and no "+N more": designed for one to three, assumes neither.
    private var chips: some View {
        FlowLayout(spacing: Theme.spacing8, rowSpacing: Theme.spacing8) {
            if blockedBy.isEmpty {
                Button { showingPicker = true } label: {
                    Text(NSLocalizedString("tasks.waitingOn.empty", comment: ""))
                        .font(Theme.Typography.body())
                        .foregroundColor(textMuted)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .chipBackground(colorScheme)
                }
                .buttonStyle(.plain)
                .disabled(isReadOnly)
            }
            ForEach(blockedBy) { blocker in
                chip(for: blocker)
            }
            if !isReadOnly && !blockedBy.isEmpty {
                Button { showingPicker = true } label: {
                    Image(systemName: "plus")
                        .font(Theme.Typography.body())
                        .foregroundColor(textMuted)
                        .chipBackground(colorScheme)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("tasks.waitingOn.add", comment: ""))
            }
        }
    }

    /// Tapping the id opens that task's details on top of this one, so Back returns here.
    private func chip(for blocker: TaskBlocker) -> some View {
        HStack(spacing: Theme.spacing4) {
            Button { open(blocker) } label: {
                HStack(spacing: Theme.spacing4) {
                    if blocker.isHidden {
                        Image(systemName: "lock")
                            .font(Theme.Typography.caption1())
                    }
                    Text(TaskBlockers.chipLabel(for: blocker))
                        .font(Theme.Typography.body())
                        .strikethrough(blocker.isCompleted)
                        .lineLimit(1)
                }
                .foregroundColor(blocker.isHidden || blocker.isCompleted ? textMuted : textPrimary)
            }
            .buttonStyle(.plain)
            .disabled(blocker.isHidden)
            .accessibilityHint(blocker.title ?? "")

            if !isReadOnly {
                Button { remove(blocker) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("tasks.waitingOn.remove", comment: ""))
            }
        }
        .chipBackground(colorScheme)
    }

    /// The same in-stack navigation the description's `astrid://tasks/` links use.
    private func open(_ blocker: TaskBlocker) {
        guard !blocker.isHidden, let url = URL(string: "astrid://tasks/\(blocker.id)") else { return }
        openURL(url)
    }

    private func load() async {
        // Off a board the row never shows, so it asks nothing — the routes need project mode.
        guard isInProject, let response = try? await service.blockers(taskId: task.id) else { return }
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

    private var textPrimary: Color { colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary }
    private var textMuted: Color { colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted }
}

private extension View {
    /// The When row's compact chip (`InlineDatePicker(compact: true)`), so the two rows match.
    func chipBackground(_ colorScheme: ColorScheme) -> some View {
        padding(.horizontal, Theme.spacing8)
            .padding(.vertical, Theme.spacing4)
            .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
    }
}

/// Search the server for a task to wait on. Stays open between picks — adding two or three at
/// once is common.
private struct TaskBlockerPickerSheet: View {
    let task: Task
    let excludedIds: [String]
    let onBlockersChanged: ([TaskBlocker]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var hits: [BlockerSearchHit] = []
    @State private var added: [String] = []
    @State private var errorMessage: String?

    private let service = TaskBlockerService.shared

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Typography.caption1())
                        .foregroundColor(Theme.error)
                }
                if TaskBlockers.shouldSearch(query) && hits.isEmpty {
                    Text(NSLocalizedString("tasks.waitingOn.noResults", comment: ""))
                        .foregroundColor(Theme.textSecondary)
                }
                ForEach(hits) { hit in
                    Button { add(hit) } label: {
                        Text(hit.title)
                            .strikethrough(hit.completed == true)
                    }
                }
            }
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: NSLocalizedString("tasks.waitingOn.searchPlaceholder", comment: ""))
            .navigationTitle(NSLocalizedString("tasks.waitingOn.label", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }
                }
            }
            .task(id: query) { await search() }
        }
    }

    private func search() async {
        // Debounce: `.task(id:)` cancels this when the query changes again.
        try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        guard !_Concurrency.Task.isCancelled else { return }
        let found = (try? await service.candidates(query: query, task: task,
                                                   excludedIds: excludedIds + added)) ?? []
        guard !_Concurrency.Task.isCancelled else { return }
        hits = found
    }

    private func add(_ hit: BlockerSearchHit) {
        errorMessage = nil
        hits.removeAll { $0.id == hit.id }
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
