//  ProjectGoalsStrip.swift
//  ADEV-183 (web ADEV-179, `components/projects/ProjectGoalsStrip.tsx`): a project board's
//  compact "Goals: N · Guardrails: N" control. It opens to show the lists: a goal with its
//  measure, "Target: …" and "Now: …", and a guardrail with an "Enforced" mark. It draws nothing
//  when the project has neither. Shared with the Mac target. The board loads the goals
//  (`ProjectGoalsService.load`) and includes this only when `shows` says so.

import SwiftUI

struct ProjectGoalsStrip: View {
    let projectId: String
    /// The board's own side margin, so the strip lines up with its columns.
    var horizontalPadding: CGFloat = Theme.spacing16

    @StateObject private var service = ProjectGoalsService.shared
    @ThemedPalette private var palette
    @State private var expanded = false

    /// Whether there is anything to draw.
    static func shows(_ goals: ProjectGoals?) -> Bool {
        guard let goals else { return false }
        return !goals.isEmpty
    }

    static func countsText(_ goals: ProjectGoals) -> String {
        String(format: NSLocalizedString("project_goals.counts", comment: "Goals: N · Guardrails: N"),
               goals.goals.count, goals.guardrails.count)
    }

    /// A goal's measure, target and current value on one line, e.g. "IRR · Target: 8% · Now: 6%".
    static func detail(_ goal: ProjectGoal) -> String? {
        var parts: [String] = []
        if let measure = goal.measure, !measure.isEmpty { parts.append(measure) }
        if let target = goal.target, !target.isEmpty {
            parts.append(String(format: NSLocalizedString("project_goals.target_value", comment: ""), target))
        }
        if let current = goal.current, !current.isEmpty {
            parts.append(String(format: NSLocalizedString("project_goals.current_value", comment: ""), current))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        let goals = service.goals(projectId: projectId)
        Group {
            if let goals, Self.shows(goals) {
                DisclosureGroup(isExpanded: $expanded) {
                    lists(goals)
                } label: {
                    Text(verbatim: Self.countsText(goals))
                        .foregroundColor(palette.textSecondary)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, Theme.spacing8)
                .accessibilityIdentifier("projectGoals.strip")
            }
        }
        #if os(macOS)
        .macFont(.caption)
        #else
        .font(Theme.Typography.caption1())
        #endif
    }

    private func lists(_ goals: ProjectGoals) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            if !goals.goals.isEmpty {
                heading("project_goals.goals_heading")
                ForEach(Array(goals.goals.enumerated()), id: \.offset) { _, goal in
                    VStack(alignment: .leading, spacing: Theme.spacing2) {
                        Text(verbatim: goal.statement).foregroundColor(palette.textPrimary)
                        if let detail = Self.detail(goal) {
                            Text(verbatim: detail).foregroundColor(palette.textSecondary)
                        }
                    }
                }
            }
            if !goals.guardrails.isEmpty {
                heading("project_goals.guardrails_heading")
                ForEach(Array(goals.guardrails.enumerated()), id: \.offset) { _, guardrail in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.spacing8) {
                        Text(verbatim: guardrail.statement).foregroundColor(palette.textPrimary)
                        if guardrail.kind == .enforced {
                            AstridPill(text: NSLocalizedString("project_goals.kind_enforced", comment: ""),
                                       tint: palette.textSecondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.spacing4)
    }

    private func heading(_ key: String) -> some View {
        Text(NSLocalizedString(key, comment: "")).bold().foregroundColor(palette.textSecondary)
    }
}
