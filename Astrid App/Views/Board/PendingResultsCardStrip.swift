//  PendingResultsCardStrip.swift
//  The Pending results card (ADEV-323; core ADEV-274 / ADEV-285): under a card in a board's
//  `results` column, each experiment or verification it waits on — kind, state, verdict, when to
//  decide, and whether its source has gone quiet.
//
//  Read through `GoalSignalsService.loadExperiment` (`getTaskExperiment`), so offline it shows what
//  the core last cached; it refreshes when the core announces `taskGoalSignals`. Shared by iOS and
//  Mac boards. Nothing to show, or a refusal, draws nothing.

import SwiftUI

struct PendingResultsCardStrip: View {
    let taskId: String

    @ObservedObject private var service = GoalSignalsService.shared

    private var experiments: [ExperimentLink] {
        service.signals(taskId: taskId)?.experiments?.experiments ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(experiments) { link in
                Text(GoalSignalsWording.cardLine(link))
                    .font(Theme.Typography.caption1())
                    .foregroundStyle(link.stale ? Theme.textMuted : Theme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, Theme.spacing8)
        .padding(.vertical, experiments.isEmpty ? 0 : Theme.spacing4)
        .task(id: taskId) { await service.loadExperiment(taskId: taskId) }
    }
}
