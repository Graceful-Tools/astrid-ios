//  GoalReadingLine.swift
//  A goal's reading where its goals are edited (ADEV-365; before that on the board header strip,
//  ADEV-183/321, which Jon asked to take off the board: "Should be in settings"). The wording follows
//  web's `ProjectGoalsStrip.tsx`: the measure, target, current value, progress, the source, how
//  fresh the reading is and a sparkline of its history, each only when its data exists.
//  Shared with the Mac target.

import SwiftUI

enum GoalReadingText {
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
}

/// Where a goal's number comes from, how fresh it is, and how it moved; nothing for a goal that
/// is only words.
struct GoalReadingLine: View {
    let goal: ProjectGoal
    @ThemedPalette private var palette

    var body: some View {
        let source = GoalReadingText.sourceText(goal)
        let freshness = GoalReadings.freshness(goal)
        let values = GoalReadings.sparkValues(goal)
        if source != nil || freshness != nil || values.count >= 2 {
            HStack(spacing: Theme.spacing8) {
                if let source { Text(verbatim: source).foregroundColor(palette.textSecondary) }
                if let freshness {
                    Text(verbatim: GoalReadingText.freshnessText(freshness))
                        .foregroundColor(freshness.stale ? palette.errorInk : palette.textSecondary)
                }
                GoalSparkline(values: values)
                    .foregroundColor(palette.textSecondary)
                    .accessibilityLabel(String(format: NSLocalizedString("project_goals.sparkline_label", comment: ""),
                                               goal.measure ?? goal.statement))
            }
            .font(Theme.Typography.caption1())
        }
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
