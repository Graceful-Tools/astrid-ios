//  TaskDetailGoalSignalsRows.swift
//  What a task does for its project's goals, in task details (ADEV-323; core ADEV-285): the goals
//  it serves, the trade-off label chip and the estimate summary, and the Pending results lines.
//
//  Everything is read through `GoalSignalsService` and worded by `GoalSignalsWording`; nothing is
//  computed here. A part the server refused, or one with nothing in it, draws no row, so a task in
//  a project without goal signals shows its details unchanged. iOS only: the Mac draws its own
//  (`MacTaskGoalSignalsRows`) at its density, from the same service and wording.

#if os(iOS)
import SwiftUI

struct TaskDetailGoalSignalsRows: View {
    let task: Task
    /// No Estimate button on a task this person may not change: asking writes a row (ADEV-329).
    var isReadOnly = false

    @ObservedObject private var service = GoalSignalsService.shared
    @ObservedObject private var listService = ListService.shared

    private var signals: GoalSignals? { service.signals(taskId: task.id) }
    /// The project whose goals the chips offer; nil off a project or with Project Mode off.
    private var projectId: String? {
        guard ListProjectControl.isOffered else { return nil }
        return EstimateOffer.projectId(for: task, lists: listService.lists)
    }

    var body: some View {
        Group {
            // Linking and unlinking goals (ADEV-328) where the task is in a project; the read-only
            // list otherwise, for links a project-less task still carries.
            if let projectId {
                GoalChipsView(subject: .task(task.id), projectId: projectId, canEdit: !isReadOnly) { chips in
                    TwoColumnRow(label: NSLocalizedString("goalSignals.section", comment: ""), icon: "target") {
                        chips
                    }
                }
            } else if let links = signals?.links, !links.links.isEmpty {
                TwoColumnRow(label: NSLocalizedString("goalSignals.section", comment: ""), icon: "target") {
                    GoalLinksList(links: links)
                }
            }
            // The Estimate button and the estimate card (ADEV-329), shared with the Mac.
            EstimateSection(task: task, isReadOnly: isReadOnly) { content in
                TwoColumnRow(label: NSLocalizedString("goalSignals.estimate", comment: ""), icon: "gauge.with.dots.needle.33percent") {
                    content.font(Theme.Typography.caption1())
                }
            }
            // Experiments on the task: results, link / unlink / refresh, the Add column offer (ADEV-330).
            ExperimentSection(task: task, isReadOnly: isReadOnly) { content in
                TwoColumnRow(label: NSLocalizedString("goalSignals.experiment.title", comment: ""), icon: "flask") {
                    content.font(Theme.Typography.caption1())
                }
            }
        }
        .task(id: task.id) { await service.load(taskId: task.id) }
    }
}

/// The goals a task serves, one per line; one inherited from a list says so.
struct GoalLinksList: View {
    let links: TaskGoalLinks

    @ThemedPalette private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing4) {
            ForEach(links.links) { link in
                VStack(alignment: .leading, spacing: Theme.spacing2) {
                    Text(link.statement)
                        .font(Theme.Typography.body())
                        .foregroundColor(palette.textPrimary)
                    if link.via == "list" {
                        Text(NSLocalizedString("goalSignals.viaList", comment: ""))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(palette.textMuted)
                    }
                }
            }
        }
    }
}

#endif
