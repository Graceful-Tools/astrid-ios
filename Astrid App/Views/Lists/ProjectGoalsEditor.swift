//  ProjectGoalsEditor.swift
//  ADEV-183 (web ADEV-179, `components/projects/ProjectGoalsEditor.tsx`): the Goals & guardrails
//  sections of Edit Project…, for whoever the server says may edit them (`canEdit`). Since ADEV-365
//  each goal and guardrail is a numbered card with every field labeled: a goal's description,
//  measure and source, which way is better, target, target date and current value; a guardrail's
//  statement, Stated / Enforced and, enforced, its metric limit. The whole value is PUT on save. A new row is sent without an id (the server assigns
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
        sections
            .task(id: projectId) {
                guard let projectId else { return }
                metricConnectors = await GoalSignalsService.shared.connectors(projectId: projectId, kind: "metric")
            }
    }

    /// Two Form sections on iPhone and iPad; on the Mac, two settings cards (ADEV-395), the design
    /// every Mac settings surface shares (`MacSettingsPage`).
    @ViewBuilder private var sections: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: Theme.spacing16) {
            MacSettingsCard(systemImage: "target", title: NSLocalizedString("project_goals.goals_heading", comment: ""),
                            description: NSLocalizedString("project_goals.intro", comment: "")) {
                goalRows
            }
            MacSettingsCard(systemImage: "shield", title: NSLocalizedString("project_goals.guardrails_heading", comment: ""),
                            description: NSLocalizedString("project_goals.kind_hint", comment: "")) {
                guardrailRows
            }
        }
        #else
        Section {
            goalRows
        } header: {
            Text(NSLocalizedString("project_goals.goals_heading", comment: ""))
        } footer: {
            Text(NSLocalizedString("project_goals.intro", comment: ""))
        }

        Section {
            guardrailRows
        } header: {
            Text(NSLocalizedString("project_goals.guardrails_heading", comment: ""))
        } footer: {
            Text(NSLocalizedString("project_goals.kind_hint", comment: ""))
        }
        #endif
    }

    @ViewBuilder private var goalRows: some View {
        ForEach($draft.goals) { $row in
            goalRow($row)
            #if os(macOS)
            Divider()
            #endif
        }
        Button {
            draft.goals.append(.init(value: ProjectGoal(id: nil, statement: "")))
        } label: {
            Label(NSLocalizedString("project_goals.add_goal", comment: ""), systemImage: "plus")
        }
        .accessibilityIdentifier("projectGoals.addGoal")
    }

    @ViewBuilder private var guardrailRows: some View {
        ForEach($draft.guardrails) { $row in
            guardrailRow($row)
            #if os(macOS)
            Divider()
            #endif
        }
        Button {
            draft.guardrails.append(.init(value: ProjectGuardrail(id: nil, statement: "")))
        } label: {
            Label(NSLocalizedString("project_goals.add_guardrail", comment: ""), systemImage: "plus")
        }
        .accessibilityIdentifier("projectGoals.addGuardrail")
    }

    // MARK: A goal card (ADEV-365)
    //
    // Jon: "Goal-1: increase MAU (higher is better) / Measure: Astrid Analytics (last updated: #) /
    // Target: 1000 by December 15, 2027". Every field carries its label, so a filled-in card still
    // says what each value is; the old rows of bare placeholders read as "# of insec… 0 TBD".

    private func goalRow(_ row: Binding<ProjectGoalsDraft.Row<ProjectGoal>>) -> some View {
        let id = row.wrappedValue.id
        let index = draft.goals.firstIndex { $0.id == id } ?? 0
        let goal = row.value
        return VStack(alignment: .leading, spacing: Theme.spacing8) {
            cardHeader(ProjectGoalsEditorText.goalTitle(index)) { draft.goals.removeAll { $0.id == id } }
            field("project_goals.field.goal") {
                TextField(NSLocalizedString("project_goals.goal_placeholder", comment: ""),
                          text: goal.statement, axis: .vertical)
            }
            field("project_goals.measure_placeholder") {
                optionalField("project_goals.measure_placeholder", goal.measure)
                sourceFields(Binding(
                    get: { goal.wrappedValue.metricSource ?? MetricSource(connectorId: "", metricKey: "") },
                    set: { source in
                        let empty = source.connectorId.isEmpty && source.metricKey.isEmpty
                        if !goal.wrappedValue.hasMetric, !empty { goal.wrappedValue.addMetric() }
                        goal.wrappedValue.metricSource = empty ? nil : source
                    }))
            }
            field("project_goals.metric.direction") {
                Picker(NSLocalizedString("project_goals.metric.direction", comment: ""), selection: goal.betterWhen) {
                    Text(NSLocalizedString("project_goals.metric.up", comment: "")).tag(MetricDirection.up)
                    Text(NSLocalizedString("project_goals.metric.down", comment: "")).tag(MetricDirection.down)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack(alignment: .top, spacing: Theme.spacing12) {
                field("project_goals.target_placeholder") {
                    TextField(NSLocalizedString("project_goals.target_placeholder", comment: ""),
                              text: Binding(get: { goal.wrappedValue.target ?? "" }, set: { goal.wrappedValue.setTarget($0) }))
                }
                field("project_goals.metric.unit") { optionalField("project_goals.metric.unit", goal.unit) }
            }
            field("project_goals.field.target_date") { targetDateRow(goal) }
            field("project_goals.current_placeholder") {
                // A connector writes the reading; by hand only when nothing feeds it.
                if goal.wrappedValue.metricSource != nil {
                    Text(verbatim: goal.wrappedValue.current ?? "–").foregroundColor(palette.textSecondary)
                } else {
                    optionalField("project_goals.current_placeholder", goal.current)
                }
                GoalReadingLine(goal: goal.wrappedValue)
            }
            if goal.wrappedValue.hasMetric {
                DisclosureGroup(NSLocalizedString("project_goals.field.more", comment: "")) {
                    HStack(alignment: .top, spacing: Theme.spacing12) {
                        field("project_goals.metric.baseline") { numberField("project_goals.metric.baseline", goal.metricBaseline) }
                        field("project_goals.metric.stale_after_hours") {
                            numberField("project_goals.metric.stale_after_hours", goal.metricStaleAfterHours)
                        }
                    }
                    Button(role: .destructive) { goal.wrappedValue.removeMetric() } label: {
                        Text(NSLocalizedString("project_goals.metric.remove", comment: ""))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("projectGoals.removeMetric")
                }
            }
        }
        .padding(.vertical, Theme.spacing4)
        .accessibilityIdentifier("projectGoals.goal")
    }

    @ViewBuilder
    private func targetDateRow(_ goal: Binding<ProjectGoal>) -> some View {
        if let day = goal.wrappedValue.targetDate {
            HStack {
                DatePicker(NSLocalizedString("project_goals.field.target_date", comment: ""),
                           selection: Binding(get: { goal.wrappedValue.targetDate ?? day }, set: { goal.wrappedValue.targetDate = $0 }),
                           displayedComponents: .date)
                    .labelsHidden()
                removeButton(label: "project_goals.field.clear_date") { goal.wrappedValue.targetDate = nil }
            }
        } else {
            Button(NSLocalizedString("project_goals.field.add_date", comment: "")) {
                goal.wrappedValue.targetDate = Calendar.current.date(byAdding: .month, value: 3, to: Date())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("projectGoals.addTargetDate")
        }
    }

    // MARK: A guardrail card (ADEV-365)

    private func guardrailRow(_ row: Binding<ProjectGoalsDraft.Row<ProjectGuardrail>>) -> some View {
        let id = row.wrappedValue.id
        let index = draft.guardrails.firstIndex { $0.id == id } ?? 0
        return VStack(alignment: .leading, spacing: Theme.spacing8) {
            cardHeader(ProjectGoalsEditorText.guardrailTitle(index)) { draft.guardrails.removeAll { $0.id == id } }
            field("project_goals.field.guardrail") {
                TextField(NSLocalizedString("project_goals.guardrail_placeholder", comment: ""),
                          text: row.value.statement, axis: .vertical)
            }
            field("project_goals.kind_label") {
                Picker(NSLocalizedString("project_goals.kind_label", comment: ""), selection: row.value.kind) {
                    Text(NSLocalizedString("project_goals.kind_stated", comment: "")).tag(ProjectGuardrail.Kind.stated)
                    Text(NSLocalizedString("project_goals.kind_enforced", comment: "")).tag(ProjectGuardrail.Kind.enforced)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if row.wrappedValue.value.kind == .enforced {
                checkBlock(row.value)
            }
        }
        .padding(.vertical, Theme.spacing4)
        .accessibilityIdentifier("projectGoals.guardrail")
    }

    @ViewBuilder
    private func checkBlock(_ rail: Binding<ProjectGuardrail>) -> some View {
        if let check = rail.wrappedValue.metricCheck {
            let binding = Binding(get: { rail.wrappedValue.metricCheck ?? check }, set: { rail.wrappedValue.metricCheck = $0 })
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                field("project_goals.measure_placeholder") { sourceFields(binding.source) }
                field("project_goals.field.limit") {
                    HStack {
                        Picker(NSLocalizedString("project_goals.check.op", comment: ""), selection: binding.op) {
                            Text(NSLocalizedString("project_goals.check.at_most", comment: "")).tag(GuardrailMetricCheck.Op.atMost)
                            Text(NSLocalizedString("project_goals.check.at_least", comment: "")).tag(GuardrailMetricCheck.Op.atLeast)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        numberField("project_goals.check.threshold", binding.threshold)
                        optionalField("project_goals.metric.unit", binding.unit)
                    }
                }
                if !check.isComplete {
                    Text(NSLocalizedString("project_goals.check.incomplete", comment: ""))
                        .goalsFont(.caption)
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

    // MARK: Pieces

    /// "Goal 1" / "Guardrail 1" and the remove button.
    private func cardHeader(_ title: String, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(verbatim: title).goalsFont(.headline)
            Spacer()
            removeButton(label: "project_goals.remove", remove)
        }
    }

    /// A field with its label always showing above it.
    private func field<Content: View>(_ labelKey: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing2) {
            Text(NSLocalizedString(labelKey, comment: ""))
                .goalsFont(.caption)
                .foregroundColor(palette.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func removeButton(label: String, _ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(NSLocalizedString(label, comment: ""))
    }
}

/// The editor's words that tests pin (ADEV-365).
enum ProjectGoalsEditorText {
    static func goalTitle(_ index: Int) -> String {
        String(format: NSLocalizedString("project_goals.goal_n", comment: "Goal 1"), index + 1)
    }

    static func guardrailTitle(_ index: Int) -> String {
        String(format: NSLocalizedString("project_goals.guardrail_n", comment: "Guardrail 1"), index + 1)
    }
}

/// The editor's fonts: the iOS type styles, and on the Mac the same styles through `.macFont`, so
/// View ▸ Bigger / Smaller reaches them (ADEV-395).
private enum GoalsFont { case headline, caption }

private extension View {
    @ViewBuilder func goalsFont(_ style: GoalsFont) -> some View {
        #if os(macOS)
        switch style {
        case .headline: macFont(.headline)
        case .caption: macFont(.caption)
        }
        #else
        switch style {
        case .headline: font(Theme.Typography.headline())
        case .caption: font(Theme.Typography.caption1())
        }
        #endif
    }
}
