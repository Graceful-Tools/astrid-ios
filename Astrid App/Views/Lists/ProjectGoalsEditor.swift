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

    var update: ProjectGoalsUpdate {
        ProjectGoalsUpdate(goals: goals.map(\.value), guardrails: guardrails.map(\.value))
    }
}

struct ProjectGoalsEditor: View {
    @Binding var draft: ProjectGoalsDraft

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
        }
        .accessibilityIdentifier("projectGoals.guardrail")
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
