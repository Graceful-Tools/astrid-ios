//  ProjectGoalsStrip.swift
//  ADEV-183 (web ADEV-179, `components/projects/ProjectGoalsStrip.tsx`): a project board's
//  compact "Goals: N · Guardrails: N" control. It opens to show the lists: a goal with its
//  measure, "Target: …" and "Now: …", and a guardrail with an "Enforced" mark. It draws nothing
//  when the project has neither. Shared with the Mac target. The board loads the goals
//  (`ProjectGoalsService.load`) and includes this only when `shows` says so.
//  ADEV-321 (web ADEV-276): a goal also shows its progress, its source, how fresh its reading is
//  and a sparkline of its history — each only when its data exists.

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

    /// A goal's measure, target, current value, progress and the work that served it on one line,
    /// e.g. "IRR · Target: 8% · Now: 6% · 75% of target · 3 tasks served this goal".
    static func detail(_ goal: ProjectGoal, workServed: Int? = nil) -> String? {
        var parts: [String] = []
        if let measure = goal.measure, !measure.isEmpty { parts.append(measure) }
        if let target = goal.target, !target.isEmpty {
            parts.append(String(format: NSLocalizedString("project_goals.target_value", comment: ""), target))
        }
        if let current = goal.current, !current.isEmpty {
            parts.append(String(format: NSLocalizedString("project_goals.current_value", comment: ""), current))
        }
        // Progress toward the target when both read as numbers (web ADEV-182/270; ADEV-321).
        if let progress = GoalReadings.progress(goal) {
            if progress.met {
                parts.append(NSLocalizedString("project_goals.target_met", comment: ""))
            } else if let percent = progress.percent {
                parts.append(String(format: NSLocalizedString("project_goals.progress_value", comment: ""), String(percent)))
            }
        }
        if let workServed, workServed > 0 {
            parts.append(String(format: NSLocalizedString("project_goals.work_served", comment: ""), String(workServed)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Source: posthog · dau" for a goal read from an outside source (web ADEV-276); nil otherwise.
    static func sourceText(_ goal: ProjectGoal) -> String? {
        guard let source = goal.metric?.source else { return nil }
        return String(format: NSLocalizedString("project_goals.source_name", comment: ""),
                      "\(source.connectorId) · \(source.metricKey)")
    }

    /// "Updated 3 hours ago", or "Stale · updated 3 days ago" past the goal's freshness limit.
    static func freshnessText(_ freshness: GoalReadings.Freshness, now: Date = Date()) -> String {
        let age = RelativeDateTimeFormatter().localizedString(for: freshness.measuredAt, relativeTo: now)
        let key = freshness.stale ? "project_goals.stale_since" : "project_goals.updated_ago"
        return String(format: NSLocalizedString(key, comment: ""), age)
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
                        if let detail = Self.detail(goal, workServed: goal.id.flatMap { goals.workByGoal[$0] }) {
                            Text(verbatim: detail).foregroundColor(palette.textSecondary)
                        }
                        signal(goal)
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

    /// Where the goal's number comes from, how fresh it is, and how it moved. Nothing for a prose goal.
    @ViewBuilder
    private func signal(_ goal: ProjectGoal) -> some View {
        let source = Self.sourceText(goal)
        let freshness = GoalReadings.freshness(goal)
        let values = GoalReadings.sparkValues(goal)
        if source != nil || freshness != nil || values.count >= 2 {
            HStack(spacing: Theme.spacing8) {
                if let source { Text(verbatim: source).foregroundColor(palette.textSecondary) }
                if let freshness {
                    Text(verbatim: Self.freshnessText(freshness))
                        .foregroundColor(freshness.stale ? palette.errorInk : palette.textSecondary)
                }
                GoalSparkline(values: values)
                    .foregroundColor(palette.textSecondary)
                    .accessibilityLabel(String(format: NSLocalizedString("project_goals.sparkline_label", comment: ""),
                                               goal.measure ?? goal.statement))
            }
        }
    }

    private func heading(_ key: String) -> some View {
        Text(NSLocalizedString(key, comment: "")).bold().foregroundColor(palette.textSecondary)
    }
}

/// A goal's recent readings as a tiny line (web `GoalSparkline`, ADEV-276). Drawn only from two or
/// more readings, so a goal with no history shows nothing.
struct GoalSparkline: View {
    let values: [Double]

    var body: some View {
        if values.count >= 2 {
            GeometryReader { geometry in
                Path { path in
                    let low = values.min() ?? 0
                    let span = (values.max() ?? 0) - low
                    let range = span == 0 ? 1 : span
                    let size = geometry.size
                    for (index, value) in values.enumerated() {
                        let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let y = size.height - size.height * CGFloat((value - low) / range)
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(style: StrokeStyle(lineWidth: Theme.spacing2, lineCap: .round, lineJoin: .round))
            }
            .frame(width: Theme.spacing48, height: Theme.spacing12)
            .accessibilityElement()
        }
    }
}
