//  ProjectGoalsEditor.swift
//  ADEV-183 (web ADEV-179, `components/projects/ProjectGoalsEditor.tsx`): the Goals & guardrails
//  sections of Edit Project…, for whoever the server says may edit them (`canEdit`). A goal has a
//  statement, a measure, a target and a current value; a guardrail has a statement and Stated /
//  Enforced. The whole value is PUT on save. A new row is sent without an id (the server assigns
//  g1/r1), and the server trims and drops blank rows. Shared with the Mac target.

import SwiftUI

/// What the editor holds while the sheet is open.
nonisolated struct ProjectGoalsDraft: Equatable {
    /// A row with an identity of its own, so a removal or a keystroke never rebinds another row.
    struct Row<Value: Equatable>: Identifiable, Equatable {
        let id = UUID()
        var value: Value
    }

    var goals: [Row<ProjectGoal>]
    var guardrails: [Row<ProjectGuardrail>]

    init(_ goals: ProjectGoals) {
        self.goals = goals.goals.map { Row(value: $0) }
        self.guardrails = goals.guardrails.map { Row(value: $0) }
    }

    /// The PUT body. An unfinished metric check is left out: the server would refuse it.
    var update: ProjectGoalsUpdate {
        ProjectGoalsUpdate(goals: goals.map(\.value), guardrails: guardrails.map(\.value)).sanitized
    }
}

struct ProjectGoalsEditor: View {
    @Binding var draft: ProjectGoalsDraft
    /// The project being edited, to list its metric connectors for a source (ADEV-331).
    var projectId: String?

    @State private var metricConnectors: [ProjectConnector] = []
    @ThemedPalette private var palette

    var body: some View {
        Section {
            ForEach($draft.goals) { $row in
                goalRow($row)
            }
            Button {
                draft.goals.append(.init(value: ProjectGoal(id: nil, statement: "")))
            } label: {
                Label(NSLocalizedString("project_goals.add_goal", comment: ""), systemImage: "plus")
            }
            .accessibilityIdentifier("projectGoals.addGoal")
        } header: {
            Text(NSLocalizedString("project_goals.goals_heading", comment: ""))
        } footer: {
            Text(NSLocalizedString("project_goals.intro", comment: ""))
        }

        Section {
            ForEach($draft.guardrails) { $row in
                guardrailRow($row)
            }
            Button {
                draft.guardrails.append(.init(value: ProjectGuardrail(id: nil, statement: "")))
            } label: {
                Label(NSLocalizedString("project_goals.add_guardrail", comment: ""), systemImage: "plus")
            }
            .accessibilityIdentifier("projectGoals.addGuardrail")
        } header: {
            Text(NSLocalizedString("project_goals.guardrails_heading", comment: ""))
        } footer: {
            Text(NSLocalizedString("project_goals.kind_hint", comment: ""))
        }
        .task(id: projectId) {
            guard let projectId else { return }
            metricConnectors = await GoalSignalsService.shared.connectors(projectId: projectId, kind: "metric")
        }
    }

    private func goalRow(_ row: Binding<ProjectGoalsDraft.Row<ProjectGoal>>) -> some View {
        let id = row.wrappedValue.id
        return VStack(alignment: .leading, spacing: Theme.spacing4) {
            HStack {
                TextField(NSLocalizedString("project_goals.goal_placeholder", comment: ""),
                          text: row.value.statement, axis: .vertical)
                removeButton { draft.goals.removeAll { $0.id == id } }
            }
            HStack {
                optionalField("project_goals.measure_placeholder", row.value.measure)
                optionalField("project_goals.target_placeholder", row.value.target)
                optionalField("project_goals.current_placeholder", row.value.current)
            }
            metricBlock(row.value)
        }
        .accessibilityIdentifier("projectGoals.goal")
    }

    private func guardrailRow(_ row: Binding<ProjectGoalsDraft.Row<ProjectGuardrail>>) -> some View {
        let id = row.wrappedValue.id
        return VStack(alignment: .leading, spacing: Theme.spacing4) {
            HStack {
                TextField(NSLocalizedString("project_goals.guardrail_placeholder", comment: ""),
                          text: row.value.statement, axis: .vertical)
                removeButton { draft.guardrails.removeAll { $0.id == id } }
            }
            Picker(NSLocalizedString("project_goals.kind_label", comment: ""),
                   selection: row.value.kind) {
                Text(NSLocalizedString("project_goals.kind_stated", comment: ""))
                    .tag(ProjectGuardrail.Kind.stated)
                Text(NSLocalizedString("project_goals.kind_enforced", comment: ""))
                    .tag(ProjectGuardrail.Kind.enforced)
            }
            .pickerStyle(.segmented)
            if row.wrappedValue.value.kind == .enforced {
                checkBlock(row.value)
            }
        }
        .accessibilityIdentifier("projectGoals.guardrail")
    }

    // MARK: The metric block (ADEV-331)

    @ViewBuilder
    private func metricBlock(_ goal: Binding<ProjectGoal>) -> some View {
        if goal.wrappedValue.hasMetric {
            VStack(alignment: .leading, spacing: Theme.spacing4) {
                HStack {
                    Picker(NSLocalizedString("project_goals.metric.direction", comment: ""), selection: goal.metricDirection) {
                        Text(NSLocalizedString("project_goals.metric.up", comment: "")).tag(MetricDirection.up)
                        Text(NSLocalizedString("project_goals.metric.down", comment: "")).tag(MetricDirection.down)
                    }
                    .pickerStyle(.segmented)
                    optionalField("project_goals.metric.unit", goal.metricUnit)
                }
                HStack {
                    numberField("project_goals.metric.target", goal.metricTarget)
                    numberField("project_goals.metric.baseline", goal.metricBaseline)
                    numberField("project_goals.metric.stale_after_hours", goal.metricStaleAfterHours)
                }
                sourceFields(Binding(
                    get: { goal.wrappedValue.metricSource ?? MetricSource(connectorId: "", metricKey: "") },
                    set: { goal.wrappedValue.metricSource = $0.connectorId.isEmpty && $0.metricKey.isEmpty ? nil : $0 }))
                Button(role: .destructive) { goal.wrappedValue.removeMetric() } label: {
                    Text(NSLocalizedString("project_goals.metric.remove", comment: ""))
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("projectGoals.removeMetric")
            }
            .accessibilityIdentifier("projectGoals.metric")
        } else {
            Button { goal.wrappedValue.addMetric() } label: {
                Label(NSLocalizedString("project_goals.metric.add", comment: ""), systemImage: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("projectGoals.addMetric")
        }
    }

    @ViewBuilder
    private func checkBlock(_ rail: Binding<ProjectGuardrail>) -> some View {
        if let check = rail.wrappedValue.metricCheck {
            let binding = Binding(get: { rail.wrappedValue.metricCheck ?? check }, set: { rail.wrappedValue.metricCheck = $0 })
            VStack(alignment: .leading, spacing: Theme.spacing4) {
                sourceFields(binding.source)
                HStack {
                    Picker(NSLocalizedString("project_goals.check.op", comment: ""), selection: binding.op) {
                        Text(NSLocalizedString("project_goals.check.at_most", comment: "")).tag(GuardrailMetricCheck.Op.atMost)
                        Text(NSLocalizedString("project_goals.check.at_least", comment: "")).tag(GuardrailMetricCheck.Op.atLeast)
                    }
                    .pickerStyle(.segmented)
                    numberField("project_goals.check.threshold", binding.threshold)
                    optionalField("project_goals.metric.unit", binding.unit)
                }
                if !check.isComplete {
                    Text(NSLocalizedString("project_goals.check.incomplete", comment: ""))
                        .foregroundColor(palette.textMuted)
                }
                Button(role: .destructive) { rail.wrappedValue.metricCheck = nil } label: {
                    Text(NSLocalizedString("project_goals.check.remove", comment: ""))
                }
                .buttonStyle(.borderless)
            }
            .accessibilityIdentifier("projectGoals.check")
        } else if !metricConnectors.isEmpty {
            Button {
                rail.wrappedValue.metricCheck = GuardrailMetricCheck(
                    source: MetricSource(connectorId: metricConnectors[0].id, metricKey: ""), op: .atMost, threshold: nil)
            } label: {
                Label(NSLocalizedString("project_goals.check.add", comment: ""), systemImage: "gauge.with.dots.needle.33percent")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("projectGoals.addCheck")
        }
    }

    /// The connector (a picker, when this person may read the project's metric connectors) and the
    /// metric's key in it. Without the list, a stored connector is kept as it is.
    @ViewBuilder
    private func sourceFields(_ source: Binding<MetricSource>) -> some View {
        HStack {
            if !metricConnectors.isEmpty {
                Picker(NSLocalizedString("project_goals.metric.source", comment: ""), selection: source.connectorId) {
                    Text(NSLocalizedString("project_goals.metric.no_source", comment: "")).tag("")
                    ForEach(metricConnectors) { Text($0.name).tag($0.id) }
                    // A stored connector this list does not name still shows as chosen.
                    if !source.wrappedValue.connectorId.isEmpty,
                       !metricConnectors.contains(where: { $0.id == source.wrappedValue.connectorId }) {
                        Text(source.wrappedValue.connectorId).tag(source.wrappedValue.connectorId)
                    }
                }
                .pickerStyle(.menu)
            }
            if !metricConnectors.isEmpty || !source.wrappedValue.connectorId.isEmpty {
                TextField(NSLocalizedString("project_goals.metric.key", comment: ""), text: source.metricKey)
            }
        }
    }

    private func numberField(_ key: String, _ value: Binding<Double?>) -> some View {
        TextField(NSLocalizedString(key, comment: ""), value: value, format: .number)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
    }

    private func optionalField(_ key: String, _ value: Binding<String?>) -> some View {
        TextField(NSLocalizedString(key, comment: ""),
                  text: Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0 }))
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(NSLocalizedString("project_goals.remove", comment: ""))
    }
}
