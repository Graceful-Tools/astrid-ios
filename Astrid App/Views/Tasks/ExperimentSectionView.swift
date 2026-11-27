//  ExperimentSectionView.swift
//  The experiment row in task details, iOS and Mac (ADEV-330; web `TaskDetailExperimentRow`,
//  `ExperimentLinkForm`, `ResultsColumnOffer`, ADEV-282).
//
//  For each experiment or verification: its state, verdict, metric deltas, the service's
//  recommendation, a link out and Remove; Refresh while one is open; the picker to link another;
//  and, to the board's owner, the one-tap offer to add the Pending results column. Every number and
//  verdict is the experiment service's. Writes go through `GoalSignalsService`, never an API client.

import SwiftUI

/// Whether the experiment row is drawn at all.
enum ExperimentRow {
    /// A refused read (`experiments == nil`: goal signals not granted) draws nothing. With links it
    /// always shows; with none, only to someone who can link one, on a board.
    static func shows(experiments: TaskExperiments?, isReadOnly: Bool, inProject: Bool) -> Bool {
        guard let experiments else { return false }
        if !experiments.experiments.isEmpty { return true }
        return !isReadOnly && inProject
    }
}

struct ExperimentSection<Row: View>: View {
    let task: Task
    let isReadOnly: Bool
    /// Wraps the section in the platform's own detail row.
    let row: (AnyView) -> Row

    @ObservedObject private var service = GoalSignalsService.shared
    @ObservedObject private var listService = ListService.shared
    @ObservedObject private var projectService = ProjectService.shared
    @ThemedPalette private var palette
    @State private var adding = false
    @State private var refreshing = false
    @State private var failure: String?
    @State private var offerDismissed = false

    private var experiments: TaskExperiments? { service.signals(taskId: task.id)?.experiments }
    private var projectId: String? {
        ListProjectControl.isOffered ? EstimateOffer.projectId(for: task, lists: listService.lists) : nil
    }

    var body: some View {
        if ExperimentRow.shows(experiments: experiments, isReadOnly: isReadOnly, inProject: projectId != nil) {
            row(AnyView(content))
        }
    }

    private var content: some View {
        let links = experiments?.experiments ?? []
        return VStack(alignment: .leading, spacing: Theme.spacing8) {
            if links.isEmpty {
                Text(NSLocalizedString("goalSignals.experiment.none", comment: "")).foregroundColor(palette.textMuted)
            }
            ForEach(links) { link in
                ExperimentItemView(link: link, canEdit: !isReadOnly) {
                    _Concurrency.Task {
                        failure = nil
                        if !(await service.unlinkExperiment(taskId: task.id, experimentId: link.id)) {
                            failure = NSLocalizedString("goalSignals.experiment.linkFailed", comment: "")
                        }
                    }
                }
            }
            HStack(spacing: Theme.spacing8) {
                if links.contains(where: \.isOpen) {
                    Button {
                        _Concurrency.Task {
                            refreshing = true
                            failure = nil
                            if !(await service.refreshExperiments(taskId: task.id)) {
                                failure = NSLocalizedString("goalSignals.experiment.refreshFailed", comment: "")
                            }
                            refreshing = false
                        }
                    } label: {
                        Label(NSLocalizedString(refreshing ? "goalSignals.experiment.refreshing" : "goalSignals.experiment.refresh",
                                                comment: ""), systemImage: "arrow.clockwise")
                    }
                    .disabled(refreshing)
                    .accessibilityIdentifier("experiment-refresh")
                }
                if !isReadOnly, !adding, projectId != nil {
                    Button(NSLocalizedString("goalSignals.experiment.addButton", comment: "")) { adding = true }
                        .accessibilityIdentifier("experiment-add")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if let failure {
                Text(failure).foregroundColor(palette.error)
            }
            if adding, let projectId {
                ExperimentLinkForm(taskId: task.id, projectId: projectId) { adding = false }
            }
            if !isReadOnly, let projectId, offerShows(projectId: projectId, hasLinks: !links.isEmpty) {
                ResultsColumnOfferView(projectId: projectId) { offerDismissed = true }
            }
        }
    }

    private func offerShows(projectId: String, hasLinks: Bool) -> Bool {
        guard !offerDismissed else { return false }
        return ResultsColumnOffer.shows(hasLinks: hasLinks, project: projectService.project(id: projectId),
                                        currentUserId: AuthManager.shared.currentUser?.id,
                                        dismissed: ResultsColumnOffer.Dismissals().isDismissed(projectId: projectId))
    }
}

/// One experiment or verification.
private struct ExperimentItemView: View {
    let link: ExperimentLink
    let canEdit: Bool
    let onRemove: () -> Void

    @ThemedPalette private var palette

    /// Only a web link is offered as one.
    private var linkOut: URL? {
        guard let text = link.url, let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing2) {
            HStack(spacing: Theme.spacing8) {
                Text(GoalSignalsWording.experimentTitle(link)).fontWeight(.semibold).foregroundColor(palette.textPrimary)
                Text(GoalSignalsWording.state(link.state)).foregroundColor(palette.textMuted)
                if let verdict = link.verdict.flatMap(GoalSignalsWording.verdict) {
                    Text(verdict).foregroundColor(palette.textPrimary)
                }
                if let linkOut {
                    Link(NSLocalizedString("goalSignals.experiment.open", comment: ""), destination: linkOut)
                }
                if canEdit {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(palette.textMuted)
                    .accessibilityLabel(NSLocalizedString("goalSignals.experiment.remove", comment: ""))
                }
            }
            ForEach(link.metrics, id: \.metricKey) { metric in
                Text(GoalSignalsWording.metricLine(metric)).foregroundColor(palette.textMuted)
            }
            if let recommendation = link.recommendation.flatMap(GoalSignalsWording.recommendation) {
                Text(recommendation).foregroundColor(palette.textSecondary)
            }
            if link.isOpen, let date = link.decideByDate {
                Text(GoalSignalsWording.decideBy(date)).foregroundColor(palette.textMuted)
            }
            if link.isOpen, link.stale {
                Text(GoalSignalsWording.noData(since: link.fetchedAtDate)).foregroundColor(palette.warning)
            }
        }
    }
}

/// Link an experiment (with a connector this person may read) or verify for N days.
private struct ExperimentLinkForm: View {
    enum Mode: Hashable { case experiment, verification }

    let taskId: String
    let projectId: String
    let onDone: () -> Void

    @ObservedObject private var service = GoalSignalsService.shared
    @ThemedPalette private var palette
    @State private var connectors: [ProjectConnector] = []
    @State private var mode: Mode = .verification
    @State private var connectorId = ""
    @State private var externalKey = ""
    @State private var days = "7"
    @State private var busy = false
    @State private var failed = false

    private var request: ExperimentLinkRequest? {
        switch mode {
        case .experiment:
            let key = externalKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return connectorId.isEmpty || key.isEmpty ? nil : .experiment(connectorId: connectorId, externalKey: key)
        case .verification:
            return ExperimentLinkRequest.verificationDays(days).map { .verification(days: $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            if !connectors.isEmpty {
                Picker("", selection: $mode) {
                    Text(NSLocalizedString("goalSignals.experiment.linkExperiment", comment: "")).tag(Mode.experiment)
                    Text(NSLocalizedString("goalSignals.experiment.verifyFor", comment: "")).tag(Mode.verification)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if mode == .experiment {
                HStack(spacing: Theme.spacing8) {
                    if connectors.count > 1 {
                        Picker(NSLocalizedString("goalSignals.experiment.connectorLabel", comment: ""), selection: $connectorId) {
                            ForEach(connectors) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    TextField(NSLocalizedString("goalSignals.experiment.keyLabel", comment: ""), text: $externalKey)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("experiment-key-input")
                }
            } else {
                HStack(spacing: Theme.spacing8) {
                    Text(NSLocalizedString("goalSignals.experiment.verifyFor", comment: ""))
                    TextField("", text: $days)
                        .textFieldStyle(.roundedBorder)
                        .fixedSize()
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .accessibilityIdentifier("experiment-days-input")
                    Text(NSLocalizedString("goalSignals.experiment.days", comment: ""))
                }
            }
            if failed {
                Text(NSLocalizedString("goalSignals.experiment.linkFailed", comment: "")).foregroundColor(palette.error)
            }
            HStack(spacing: Theme.spacing8) {
                Button(NSLocalizedString("goalSignals.experiment.add", comment: "")) {
                    guard let request else { return }
                    _Concurrency.Task {
                        busy = true
                        failed = false
                        let ok = await service.linkExperiment(taskId: taskId, request: request, projectId: projectId)
                        busy = false
                        if ok { onDone() } else { failed = true }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(request == nil || busy)
                .accessibilityIdentifier("experiment-link-submit")
                Button(NSLocalizedString("actions.cancel", comment: ""), action: onDone)
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .task(id: projectId) {
            connectors = await service.experimentConnectors(projectId: projectId)
            if let first = connectors.first {
                mode = .experiment
                connectorId = first.id
            }
        }
    }
}

/// "Hold tasks like this in a Pending results column until the result is in?" — Add column / Not now.
private struct ResultsColumnOfferView: View {
    let projectId: String
    let onDismiss: () -> Void

    @ObservedObject private var service = GoalSignalsService.shared
    @ThemedPalette private var palette
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing4) {
            Text(NSLocalizedString("goalSignals.experiment.offer", comment: "")).foregroundColor(palette.textMuted)
            HStack(spacing: Theme.spacing8) {
                Button(NSLocalizedString("goalSignals.experiment.offerAdd", comment: "")) {
                    _Concurrency.Task {
                        busy = true
                        failed = false
                        if await service.addResultsColumn(projectId: projectId) {
                            await ProjectService.shared.reload()
                        } else {
                            failed = true
                        }
                        busy = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
                .accessibilityIdentifier("results-column-offer-add")
                Button(NSLocalizedString("goalSignals.experiment.offerDismiss", comment: "")) {
                    ResultsColumnOffer.Dismissals().dismiss(projectId: projectId)
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
            if failed {
                Text(NSLocalizedString("goalSignals.experiment.offerFailed", comment: "")).foregroundColor(palette.error)
            }
        }
        .accessibilityIdentifier("results-column-offer")
    }
}
