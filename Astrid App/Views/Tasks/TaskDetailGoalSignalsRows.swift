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

    private var signals: GoalSignals? { service.signals(taskId: task.id) }

    var body: some View {
        Group {
            if let links = signals?.links, !links.links.isEmpty {
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
            if let results = signals?.experiments, !results.experiments.isEmpty {
                TwoColumnRow(label: NSLocalizedString("goalSignals.results.title", comment: ""), icon: "flask") {
                    PendingResultsLines(results: results)
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

/// Each experiment or verification: kind, state and verdict, when to decide, and a stale note.
struct PendingResultsLines: View {
    let results: TaskExperiments

    @ThemedPalette private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing4) {
            ForEach(results.experiments) { link in
                VStack(alignment: .leading, spacing: Theme.spacing2) {
                    Text(GoalSignalsWording.resultLine(link))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(palette.textPrimary)
                    if let date = link.decideByDate {
                        Text(GoalSignalsWording.decideBy(date))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(palette.textMuted)
                    }
                    if link.stale {
                        Text(NSLocalizedString("goalSignals.results.stale", comment: ""))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(palette.textMuted)
                    }
                }
            }
        }
    }
}
#endif
