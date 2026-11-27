//  EstimateCardView.swift
//  The one-tap Estimate and the estimate card, in task details on iOS and Mac (ADEV-329; web
//  `EstimateControl` / `EstimateCard`, ADEV-280).
//
//  The card draws `EstimateCardModel` and words it with `GoalSignalsWording`; it computes nothing of
//  its own. Asking goes through `GoalSignalsService.requestEstimate` (a person-only action), never an
//  API client. Both platforms share this view; each wraps it in its own row and font.

import SwiftUI

/// The Estimate section: the button (and the picker, with more than one estimator), what came of
/// asking, then the card for the latest estimate. Draws nothing where there is nothing to estimate
/// and no estimate to show.
struct EstimateSection<Row: View>: View {
    let task: Task
    let isReadOnly: Bool
    /// Wraps the section in the platform's own detail row.
    let row: (AnyView) -> Row

    @ObservedObject private var service = GoalSignalsService.shared
    @ObservedObject private var capabilities = ServerCapabilityService.shared
    @ObservedObject private var goalsService = ProjectGoalsService.shared
    @ObservedObject private var listService = ListService.shared
    @State private var outcome: EstimateRequestOutcome?

    private var projectId: String? { EstimateOffer.projectId(for: task, lists: listService.lists) }
    private var goals: ProjectGoals? { projectId.flatMap { goalsService.goals(projectId: $0) } }
    private var latest: Estimate? { service.signals(taskId: task.id)?.estimates?.latest }

    private var offer: EstimateOffer {
        EstimateOffer(projectMode: ListProjectControl.isOffered, projectId: projectId, goals: goals,
                      estimators: capabilities.capabilities.goalSignals.estimators, isReadOnly: isReadOnly)
    }

    var body: some View {
        Group {
            if latest != nil || offer.showsButton || outcome != nil {
                row(AnyView(content))
            }
        }
        .task(id: "\(task.id)|\(projectId ?? "")") {
            outcome = nil
            if ListProjectControl.isOffered, let projectId, goalsService.goals(projectId: projectId) == nil {
                await goalsService.load(projectId: projectId)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            if offer.showsButton { controls }
            if let outcome, let message = GoalSignalsWording.outcome(outcome) {
                EstimateOutcomeLine(outcome: outcome, message: message)
            }
            if let latest {
                EstimateCardView(model: EstimateCardModel(estimate: latest, goals: goals, now: Date()),
                                 links: service.signals(taskId: task.id)?.links)
            }
        }
    }

    private var controls: some View {
        EstimateAskControls(task: task, offer: offer, hasEstimate: latest != nil, outcome: $outcome)
    }
}

/// The Estimate button, and the picker when there is more than one estimator to choose.
struct EstimateAskControls: View {
    let task: Task
    let offer: EstimateOffer
    let hasEstimate: Bool
    @Binding var outcome: EstimateRequestOutcome?

    @ObservedObject private var service = GoalSignalsService.shared
    @State private var chosen: String?

    var body: some View {
        let estimators = offer.estimators
        let selected = chosen ?? estimators.first?.key ?? ""
        let busy = service.isEstimating(taskId: task.id)
        HStack(spacing: Theme.spacing8) {
            if offer.showsPicker {
                Picker(NSLocalizedString("goalSignals.estimate.picker", comment: ""),
                       selection: Binding(get: { selected }, set: { chosen = $0 })) {
                    ForEach(estimators) { Text($0.name).tag($0.key) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            Button {
                _Concurrency.Task {
                    outcome = nil
                    outcome = await service.requestEstimate(taskId: task.id, estimator: selected, projectId: offer.projectId)
                }
            } label: {
                Label(title(busy: busy), systemImage: "gauge.with.dots.needle.33percent")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(busy)
            .accessibilityIdentifier("estimate-button")
        }
    }

    private func title(busy: Bool) -> String {
        if busy { return NSLocalizedString("goalSignals.estimate.busy", comment: "") }
        return NSLocalizedString(hasEstimate ? "goalSignals.estimate.again" : "goalSignals.estimate.button", comment: "")
    }
}

/// An idea card's Estimate (web `EstimateControl compact`): the button, then the label chip once
/// an estimate has been read, or what came of asking. The card itself opens task details, where
/// the full card is; so a board of ideas reads nothing until someone asks.
struct EstimateCardControl: View {
    let task: Task

    @ObservedObject private var service = GoalSignalsService.shared
    @ObservedObject private var capabilities = ServerCapabilityService.shared
    @ObservedObject private var goalsService = ProjectGoalsService.shared
    @ObservedObject private var listService = ListService.shared
    @ThemedPalette private var palette
    @State private var outcome: EstimateRequestOutcome?

    private var offer: EstimateOffer {
        let projectId = EstimateOffer.projectId(for: task, lists: listService.lists)
        return EstimateOffer(projectMode: ListProjectControl.isOffered, projectId: projectId,
                             goals: projectId.flatMap { goalsService.goals(projectId: $0) },
                             estimators: capabilities.capabilities.goalSignals.estimators, isReadOnly: false)
    }

    var body: some View {
        if EstimateOffer.isIdea(task), offer.showsButton {
            let latest = service.signals(taskId: task.id)?.estimates?.latest
            VStack(alignment: .leading, spacing: Theme.spacing4) {
                HStack(spacing: Theme.spacing8) {
                    EstimateAskControls(task: task, offer: offer, hasEstimate: latest != nil, outcome: $outcome)
                    if let label = latest?.label {
                        Text(GoalSignalsWording.label(label))
                            .foregroundColor(palette.textPrimary)
                            .chipBackground(palette)
                    }
                }
                if let outcome, let message = GoalSignalsWording.outcome(outcome) {
                    EstimateOutcomeLine(outcome: outcome, message: message)
                }
            }
        }
    }
}

/// What came of asking: pending, no key, failed — or not granted, with the request-access button.
private struct EstimateOutcomeLine: View {
    let outcome: EstimateRequestOutcome
    let message: String

    @ObservedObject private var service = GoalSignalsService.shared
    @ThemedPalette private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing4) {
            Text(message)
                .foregroundColor(outcome == .pending ? palette.textMuted : palette.error)
                .accessibilityIdentifier("estimate-outcome")
            if outcome == .notGranted {
                if service.accessRequested {
                    Text(NSLocalizedString("goalSignals.estimate.accessRequested", comment: ""))
                        .foregroundColor(palette.textMuted)
                } else {
                    Button(NSLocalizedString("goalSignals.estimate.requestAccess", comment: "")) {
                        _Concurrency.Task { await service.requestAccess() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

/// One estimate, drawn: the label chip, the rough tag, source · confidence · age (always), a range
/// bar per goal and guardrail with its reference line, the risk chip and its factors, the impact /
/// cost / opportunity tiles, the rationale, then the label's reasons.
struct EstimateCardView: View {
    let model: EstimateCardModel
    let links: TaskGoalLinks?

    @ThemedPalette private var palette

    private var estimate: Estimate { model.estimate }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            meta
            if !model.goalRows.isEmpty {
                EstimateRangeSection(title: NSLocalizedString("goalSignals.estimate.goals", comment: ""),
                                     rows: model.goalRows, color: palette.categoryBlue)
            }
            if !model.guardrailRows.isEmpty {
                EstimateRangeSection(title: NSLocalizedString("goalSignals.estimate.guardrails", comment: ""),
                                     rows: model.guardrailRows, color: palette.categoryPurple)
            }
            risk
            tiles
            if let rationale = estimate.rationale, !rationale.isEmpty {
                Text(rationale).foregroundColor(palette.textSecondary)
            }
            ForEach(Array(estimate.reasons.compactMap { GoalSignalsWording.reason($0, links: links) }.enumerated()),
                    id: \.offset) { _, line in
                Text(line).foregroundColor(palette.textSecondary)
            }
        }
        .accessibilityIdentifier("estimate-card")
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: Theme.spacing4) {
            HStack(spacing: Theme.spacing8) {
                if let label = estimate.label {
                    Text(GoalSignalsWording.label(label))
                        .foregroundColor(palette.textPrimary)
                        .chipBackground(palette)
                }
                if estimate.rough {
                    Text(NSLocalizedString("goalSignals.rough", comment: ""))
                        .foregroundColor(palette.textMuted)
                        .chipBackground(palette)
                }
            }
            Text(metaLine).foregroundColor(palette.textSecondary)
        }
    }

    /// "Source: Built-in model · Confidence: low · 3 h ago".
    private var metaLine: String {
        var parts = [GoalSignalsWording.source(model.source)]
        if let confidence = estimate.confidence { parts.append(GoalSignalsWording.confidence(confidence)) }
        if let age = model.age { parts.append(GoalSignalsWording.age(age)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var risk: some View {
        if let level = estimate.risk {
            FlowChips(items: [GoalSignalsWording.riskChip(level)] + estimate.riskFactors) { index, text in
                Text(text)
                    .foregroundColor(index == 0 && level == .high ? palette.error : palette.textPrimary)
                    .chipBackground(palette)
            }
        }
    }

    private var tiles: some View {
        HStack(alignment: .top, spacing: Theme.spacing8) {
            EstimateTile(title: NSLocalizedString("goalSignals.estimate.impact", comment: ""),
                         value: model.impact.map(GoalSignalsWording.range))
            EstimateTile(title: NSLocalizedString("goalSignals.estimate.cost", comment: ""),
                         value: model.cost,
                         detail: model.effortHours.map(GoalSignalsWording.effort))
            EstimateTile(title: NSLocalizedString("goalSignals.estimate.opportunity", comment: ""),
                         value: model.opportunity.map(GoalSignalsWording.opportunity))
        }
    }
}

/// A heading, one line of words per row, then the bars on a shared axis.
private struct EstimateRangeSection: View {
    let title: String
    let rows: [EstimateRangeRow]
    let color: Color

    @ThemedPalette private var palette

    var body: some View {
        let domain = EstimateCardModel.domain(rows)
        VStack(alignment: .leading, spacing: Theme.spacing4) {
            Text(title).fontWeight(.semibold).foregroundColor(palette.textMuted)
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: Theme.spacing2) {
                    Text(words(row)).foregroundColor(palette.textSecondary)
                    EstimateRangeBar(row: row, domain: domain, color: color)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func words(_ row: EstimateRangeRow) -> String {
        var parts = [row.statement, GoalSignalsWording.range(row)]
        if let reference = GoalSignalsWording.reference(row) { parts.append(reference) }
        if let probability = row.breachProbability { parts.append(GoalSignalsWording.breach(probability)) }
        return parts.joined(separator: " ")
    }
}

/// The track, the zero tick, the range, and the target or limit as a reference line.
private struct EstimateRangeBar: View {
    let row: EstimateRangeRow
    let domain: ClosedRange<Double>
    let color: Color

    @ThemedPalette private var palette

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let x = { (value: Double) in CGFloat(EstimateCardModel.fraction(value, in: domain)) * width }
            let low = x(row.low)
            let high = x(row.high)
            ZStack(alignment: .leading) {
                Capsule().fill(palette.border)
                    .frame(height: Theme.spacing2)
                Rectangle().fill(palette.textMuted)
                    .frame(width: Theme.spacing2 / 2, height: Theme.spacing8)
                    .offset(x: x(0))
                Capsule().fill(color)
                    .frame(width: max(high - low, Theme.spacing4), height: Theme.spacing8)
                    .offset(x: low)
                if let reference = row.reference {
                    Rectangle().fill(palette.categoryAmber)
                        .frame(width: Theme.spacing2, height: Theme.spacing12)
                        .offset(x: x(reference))
                        .accessibilityIdentifier("estimate-reference-line")
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: Theme.spacing12)
    }
}

/// One of the three tiles; "Not estimated" when the estimator gave nothing for it.
private struct EstimateTile: View {
    let title: String
    let value: String?
    var detail: String?

    @ThemedPalette private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing2) {
            Text(title).foregroundColor(palette.textMuted)
            Text(value ?? NSLocalizedString("goalSignals.estimate.notEstimated", comment: ""))
                .fontWeight(value == nil ? .regular : .semibold)
                .foregroundColor(value == nil ? palette.textMuted : palette.textPrimary)
            if let detail {
                Text(detail).foregroundColor(palette.textMuted)
            }
        }
        .padding(Theme.spacing8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(palette.border))
    }
}

/// Chips that wrap onto as many lines as they need.
private struct FlowChips<Chip: View>: View {
    let items: [String]
    let chip: (Int, String) -> Chip

    var body: some View {
        FlowLayout(spacing: Theme.spacing4, rowSpacing: Theme.spacing4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, text in chip(index, text) }
        }
    }
}
