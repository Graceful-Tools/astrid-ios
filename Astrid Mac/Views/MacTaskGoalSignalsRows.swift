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
            if let estimate = signals?.estimates?.latest {
                row(icon: "gauge.with.dots.needle.33percent", NSLocalizedString("goalSignals.estimate", comment: "")) {
                    estimateLines(estimate, links: signals?.links)
                }
            }
            if let results = signals?.experiments, !results.experiments.isEmpty {
                row(icon: "flask", NSLocalizedString("goalSignals.results.title", comment: "")) {
                    ForEach(results.experiments) { link in
                        Text(GoalSignalsWording.resultLine(link))
                        if let date = link.decideByDate {
                            Text(GoalSignalsWording.decideBy(date)).foregroundStyle(Theme.textMuted)
                        }
                        if link.stale {
                            Text(NSLocalizedString("goalSignals.results.stale", comment: ""))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
        }
        .task(id: task.id) { await service.load(taskId: task.id) }
    }

    @ViewBuilder
    private func estimateLines(_ estimate: Estimate, links: TaskGoalLinks?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing8) {
            if let label = estimate.label {
                Text(GoalSignalsWording.label(label)).bold()
            }
            if estimate.rough {
                Text(NSLocalizedString("goalSignals.rough", comment: "")).foregroundStyle(Theme.textMuted)
            }
        }
        ForEach(Array(GoalSignalsWording.summaryLines(estimate, links: links).enumerated()), id: \.offset) { _, line in
            Text(line).foregroundStyle(Theme.textSecondary)
        }
        if let rationale = estimate.rationale, !rationale.isEmpty {
            Text(rationale).foregroundStyle(Theme.textMuted)
        }
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
