//  GoalChipsView.swift
//  The goals a task or a list serves, as chips that link and unlink (ADEV-328; web ADEV-276
//  `GoalChips`). Shared by iOS and Mac task details and list settings.
//
//  A task's own links are removable, links it has through a list are read-only and say so, and
//  the Add menu offers the project's other goals, all only when `canEdit` (the caller asks
//  `ListPermissions`). Writes go through `GoalSignalsService`, which asks the core. Nothing is
//  drawn while loading, when a read fails, or when the project states no goals.

import SwiftUI

struct GoalChipsView<Row: View>: View {
    enum Subject: Equatable {
        case task(String)
        case list(String)
    }

    let subject: Subject
    let projectId: String
    /// Write access to the task, or admin on the list.
    let canEdit: Bool
    /// Wraps the chips in the platform's own row; not called when there is nothing to draw.
    let row: (AnyView) -> Row

    @ObservedObject private var service = GoalSignalsService.shared
    @ObservedObject private var goalsService = ProjectGoalsService.shared
    @ThemedPalette private var palette
    @State private var failed = false
    @State private var busy = false

    private var links: [GoalLink]? {
        switch subject {
        case .task(let taskId): return service.signals(taskId: taskId)?.links?.links
        case .list(let listId): return service.listLinks(listId: listId)?.links
        }
    }

    private var model: GoalChipsModel? {
        guard let goals = goalsService.goals(projectId: projectId)?.goals, !goals.isEmpty,
              let links else { return nil }
        return GoalChipsModel(links: links, goals: goals, projectId: projectId, isList: isList, canEdit: canEdit)
    }

    private var isList: Bool {
        if case .list = subject { return true }
        return false
    }

    var body: some View {
        Group {
            if let model, !model.isEmpty {
                row(AnyView(VStack(alignment: .leading, spacing: Theme.spacing4) {
                    chips(model)
                    if failed {
                        Text(NSLocalizedString("projectMode.goals.linkFailed", comment: ""))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(palette.errorInk)
                    }
                }))
            }
        }
        .task(id: "\(subject)|\(projectId)") {
            failed = false
            if goalsService.goals(projectId: projectId) == nil { await goalsService.load(projectId: projectId) }
            if case .list(let listId) = subject { await service.loadList(listId: listId) }
        }
    }

    private func chips(_ model: GoalChipsModel) -> some View {
        FlowLayout(spacing: Theme.spacing4, rowSpacing: Theme.spacing4) {
            ForEach(model.own) { chip in
                HStack(spacing: Theme.spacing4) {
                    Text(chip.statement)
                        .foregroundColor(palette.textPrimary)
                    if model.canEdit {
                        Button { write { await unlink(chip.goalId) } } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(palette.textMuted)
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .accessibilityLabel(String(format: NSLocalizedString("projectMode.goals.unlinkGoal", comment: ""), chip.statement))
                    }
                }
                .font(Theme.Typography.caption1())
                .chipBackground(palette)
                .accessibilityIdentifier("goalChip")
            }
            ForEach(model.inherited) { chip in
                Text(chip.statement)
                    .font(Theme.Typography.caption1())
                    .foregroundColor(palette.textSecondary)
                    .chipBackground(palette)
                    .help(NSLocalizedString("projectMode.goals.viaList", comment: ""))
                    .accessibilityHint(NSLocalizedString("projectMode.goals.viaList", comment: ""))
                    .accessibilityIdentifier("goalChip.inherited")
            }
            if model.canEdit, !model.addable.isEmpty {
                Menu {
                    ForEach(model.addable) { goal in
                        Button(goal.statement) { write { await link(goal.goalId) } }
                    }
                } label: {
                    Label(NSLocalizedString("projectMode.goals.linkGoal", comment: ""), systemImage: "plus")
                        .font(Theme.Typography.caption1())
                        .foregroundColor(palette.textMuted)
                        .chipBackground(palette)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .disabled(busy)
                .accessibilityIdentifier("goalChip.add")
            }
        }
    }

    private func write(_ action: @escaping () async -> Bool) {
        _Concurrency.Task {
            busy = true
            failed = false
            failed = !(await action())
            busy = false
        }
    }

    private func link(_ goalId: String) async -> Bool {
        switch subject {
        case .task(let taskId): return await service.linkGoal(taskId: taskId, goalId: goalId, projectId: projectId)
        case .list(let listId): return await service.linkListGoal(listId: listId, goalId: goalId)
        }
    }

    private func unlink(_ goalId: String) async -> Bool {
        switch subject {
        case .task(let taskId): return await service.unlinkGoal(taskId: taskId, goalId: goalId, projectId: projectId)
        case .list(let listId): return await service.unlinkListGoal(listId: listId, goalId: goalId)
        }
    }
}

/// Who may link a task's goals: anyone who may write the task (web `canUserEditTask`), asked of
/// `ListPermissions` for the task's first list this device knows; with none known, the server decides.
enum GoalChipsAccess {
    static func canEditTask(_ task: Task, lists: [TaskList], userId: String?) -> Bool {
        let ids = task.listIds ?? []
        guard let list = ids.lazy.compactMap({ id in lists.first { $0.id == id } }).first ?? task.lists?.first else {
            return true
        }
        return !ListPermissions.isTaskReadOnly(task, in: list, userId: userId)
    }
}
