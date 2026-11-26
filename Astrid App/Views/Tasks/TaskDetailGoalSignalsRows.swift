//  TaskDetailGoalSignalsRows.swift
//  What a task does for its project's goals, in task details (ADEV-323; core ADEV-285): the goals
//  it serves, the trade-off label chip and the estimate summary, and the Pending results lines.
//
//  Everything is read through `GoalSignalsService` and worded by `GoalSignalsWording`; nothing is
//  computed here. A part the server refused, or one with nothing in it, draws no row, so a task in
//  a project without goal signals shows its details unchanged.

import SwiftUI

struct TaskDetailGoalSignalsRows: View {
    let task: Task

    @ObservedObject private var service = GoalSignalsService.shared

    private var signals: GoalSignals? { service.signals(taskId: task.id) }

    var body: some View {
        Group {
            if let links = signals?.links, !links.links.isEmpty {
                TwoColumnRow(label: NSLocalizedString("goalSignals.section", comment: ""), icon: "target") {
                    GoalLinksList(links: links)
                }
            }
            if let estimate = signals?.estimates?.latest {
                TwoColumnRow(label: NSLocalizedString("goalSignals.estimate", comment: ""), icon: "gauge.with.dots.needle.33percent") {
                    EstimateSummary(estimate: estimate, links: signals?.links)
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
                VStack(alignment: .leading, spacing: 0) {
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

/// The label chip, then the estimate in words: reasons, each goal's range, risk and confidence,
/// and the estimator's rationale. A built-in estimate is tagged "Rough estimate".
struct EstimateSummary: View {
    let estimate: Estimate
    let links: TaskGoalLinks?

    @ThemedPalette private var palette

    private var lines: [String] { GoalSignalsWording.summaryLines(estimate, links: links) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing4) {
            HStack(spacing: Theme.spacing8) {
                if let label = estimate.label {
                    Text(GoalSignalsWording.label(label))
                        .font(Theme.Typography.body())
                        .foregroundColor(palette.textPrimary)
                        .chipBackground(palette)
                }
                if estimate.rough {
                    Text(NSLocalizedString("goalSignals.rough", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(palette.textMuted)
                }
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Theme.Typography.caption1())
                    .foregroundColor(palette.textSecondary)
            }
            if let rationale = estimate.rationale, !rationale.isEmpty {
                Text(rationale)
                    .font(Theme.Typography.caption1())
                    .foregroundColor(palette.textMuted)
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
                VStack(alignment: .leading, spacing: 0) {
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
