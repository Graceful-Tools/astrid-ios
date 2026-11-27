//  MacTaskGoalSignalsRows.swift
//  Astrid for Mac — what a task does for its project's goals, in a task's editor (ADEV-323; the Mac
//  half of iOS `TaskDetailGoalSignalsRows`; core ADEV-285).
//
//  Read through `GoalSignalsService` and worded by `GoalSignalsWording`, both shared with iOS, so
//  the two platforms say the same thing. A part the server refused, or an empty one, draws no row.

#if os(macOS)
import SwiftUI

struct MacTaskGoalSignalsRows: View {
    let task: Task
    /// No Estimate button on a task this person may not change: asking writes a row (ADEV-329).
    var isReadOnly = false

    @ObservedObject private var service = GoalSignalsService.shared

    private var signals: GoalSignals? { service.signals(taskId: task.id) }

    var body: some View {
        Group {
            if let links = signals?.links, !links.links.isEmpty {
                row(icon: "target", NSLocalizedString("goalSignals.section", comment: "")) {
                    ForEach(links.links) { link in
                        Text(link.statement)
                        if link.via == "list" {
                            Text(NSLocalizedString("goalSignals.viaList", comment: ""))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            // The Estimate button and the estimate card (ADEV-329), shared with iOS.
            EstimateSection(task: task, isReadOnly: isReadOnly) { content in
                row(icon: "gauge.with.dots.needle.33percent", NSLocalizedString("goalSignals.estimate", comment: "")) {
                    content
                }
            }
            // Experiments on the task: results, link / unlink / refresh, the Add column offer (ADEV-330).
            ExperimentSection(task: task, isReadOnly: isReadOnly) { content in
                row(icon: "flask", NSLocalizedString("goalSignals.experiment.title", comment: "")) {
                    content
                }
            }
        }
        .task(id: task.id) { await service.load(taskId: task.id) }
    }

    private func row<Content: View>(icon: String, _ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MacDetailRowMetrics.columnGap) {
            Image(systemName: icon)
                .foregroundStyle(Theme.textMuted)
                .frame(width: MacDetailRowMetrics.leadingColumnWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.spacing4) {
                Text(label).foregroundStyle(Theme.textMuted)
                content()
            }
            Spacer(minLength: 0)
        }
    }
}

/// The Pending results card on the Mac board (ADEV-323): under the title of a card in the
/// `results` column, one line per experiment or verification, as iOS's `PendingResultsCardStrip`.
struct MacPendingResultsCardLines: View {
    let taskId: String

    @ObservedObject private var service = GoalSignalsService.shared

    var body: some View {
        let experiments = service.signals(taskId: taskId)?.experiments?.experiments ?? []
        VStack(alignment: .leading, spacing: Theme.spacing2) {
            ForEach(experiments) { link in
                Text(GoalSignalsWording.cardLine(link))
                    .lineLimit(2)
                    .foregroundStyle(link.stale ? Theme.textMuted : Theme.textSecondary)
            }
        }
        .macFont(.caption2)
        .task(id: taskId) { await service.loadExperiment(taskId: taskId) }
    }
}
#endif
