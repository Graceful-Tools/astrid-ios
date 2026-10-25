import Charts
import SwiftUI

/// The Insights tab of List Settings, on iOS and Mac (AITD-545) — web's `ListInsightsPanel`.
/// The numbers come from the server (`ListInsightsService`); this only draws them, through the
/// rules in `ListInsightsFormat`.
struct ListInsightsView: View {
    let listId: String
    var load: (_ listId: String, _ days: Int) async throws -> ListInsights = { listId, days in
        try await ListInsightsService.shared.insights(listId: listId, days: days)
    }

    @State private var days = ListInsightsFormat.defaultWindow
    @State private var insights: ListInsights?
    @State private var loadState = ListInsightsLoadState()

    var body: some View {
        ScrollView {
            ListInsightsContent(insights: insights?.window.days == days ? insights : nil,
                                failed: loadState.showsFailure(for: days),
                                days: $days)
                .padding(16)
        }
        // One ask per window per look; the service serves a repeat from its cache (AITD-554).
        .task(id: days) {
            let asked = days
            do {
                let answer = try await load(listId, asked)
                insights = answer
                loadState.loaded(days: asked)
            } catch is CancellationError {
            } catch {
                loadState.failed(days: asked)
            }
        }
    }
}

/// Which window last failed to load. A success clears it — it used to stay set, so a window that
/// failed once read "couldn't load" over a perfectly good answer from then on (AITD-554).
struct ListInsightsLoadState: Equatable {
    private var failedDays: Int?

    mutating func failed(days: Int) { failedDays = days }
    mutating func loaded(days: Int) { if failedDays == days { failedDays = nil } }
    func showsFailure(for days: Int) -> Bool { failedDays == days }
}

/// The tab's content for a given answer — no fetching, so a test can render any state.
struct ListInsightsContent: View {
    /// Nil while loading.
    let insights: ListInsights?
    let failed: Bool
    @Binding var days: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("", selection: $days) {
                ForEach(ListInsightsFormat.windows, id: \.self) { option in
                    Text(ListInsightsFormat.windowLabel(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("listInsights.window")

            if failed {
                note(NSLocalizedString("listInsights.load_failed", comment: ""))
            } else if let insights {
                activity(insights)
                DurationRow(label: NSLocalizedString("listInsights.time_to_complete", comment: ""),
                            value: insights.createToComplete)
                if let lanes = insights.lanes {
                    lanesSection(lanes)
                }
                contributors(insights.contributors)
            } else {
                note(NSLocalizedString("listInsights.loading", comment: ""))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("listInsights")
    }

    private func activity(_ insights: ListInsights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                heading(NSLocalizedString("listInsights.activity", comment: ""))
                Spacer()
                Text(ListInsightsFormat.totals(insights.totals))
                    .insightsFont(.note)
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(insights.series) { day in
                    if let date = ListInsightsFormat.plotDate(day.date) {
                        LineMark(x: .value("Day", date, unit: .day), y: .value("Count", day.created))
                            .foregroundStyle(by: .value("Series", NSLocalizedString("listInsights.created", comment: "")))
                        LineMark(x: .value("Day", date, unit: .day), y: .value("Count", day.completed))
                            .foregroundStyle(by: .value("Series", NSLocalizedString("listInsights.completed", comment: "")))
                    }
                }
            }
            .chartForegroundStyleScale([
                NSLocalizedString("listInsights.created", comment: ""): Theme.accent,
                NSLocalizedString("listInsights.completed", comment: ""): Theme.success,
            ])
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: false)
                }
            }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .chartLegend(position: .bottom)
            .frame(height: 176)
        }
    }

    private func lanesSection(_ lanes: [ListInsights.Lane]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            heading(NSLocalizedString("listInsights.time_in_lane", comment: ""))
            if ListInsightsFormat.lanesHaveHistory(lanes) {
                ForEach(lanes) { lane in
                    DurationRow(label: lane.name, value: lane.duration)
                }
            } else {
                note(NSLocalizedString("listInsights.not_enough_history", comment: "") + " "
                     + NSLocalizedString("listInsights.lane_history_note", comment: ""))
            }
        }
    }

    private func contributors(_ people: [ListInsights.Contributor]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(NSLocalizedString("listInsights.contributors", comment: ""))
            if people.isEmpty {
                note(NSLocalizedString("listInsights.no_activity", comment: ""))
            } else {
                ForEach(people) { person in
                    HStack(alignment: .top, spacing: 8) {
                        ContributorAvatar(user: person.user)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(person.name ?? "—").lineLimit(1)
                                if person.isAIAgent {
                                    Image(systemName: "cpu")
                                        .insightsFont(.badge)
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel(NSLocalizedString("lists.ai_coding_agent", comment: ""))
                                }
                            }
                            .insightsFont(.body)
                            Text(ListInsightsFormat.profileCounts(person))
                                .insightsFont(.note)
                                .foregroundStyle(.secondary)
                            Text(ListInsightsFormat.activityCounts(person))
                                .insightsFont(.note)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).insightsFont(.heading)
    }

    private func note(_ text: String) -> some View {
        Text(text).insightsFont(.note).foregroundStyle(.secondary)
    }
}

/// One median: "—" when there is none, otherwise the duration and how many it came from.
private struct DurationRow: View {
    let label: String
    let value: ListInsights.Duration

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).insightsFont(.body).foregroundStyle(.secondary)
            Spacer()
            if let median = ListInsightsFormat.median(value) {
                Text(median).insightsFont(.value)
                Text(ListInsightsFormat.sampleSize(value)).insightsFont(.note).foregroundStyle(.tertiary)
            } else {
                Text("—").insightsFont(.body).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct ContributorAvatar: View {
    let user: User
    private let size: CGFloat = 24

    var body: some View {
        Group {
            if let image = user.avatarURL, let url = URL(string: image) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { initials }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Theme.accent)
            Text(user.initials)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// The tab's few text styles. On Mac through `.macFont`, so the app's text-size setting reaches
/// them like every other Mac view; on iOS the system styles, which follow Dynamic Type.
private enum InsightsFont {
    case heading, value, body, note, badge

    #if os(macOS)
    var mac: MacFont {
        switch self {
        case .heading: return .subheadline.weight(.semibold)
        case .value: return .subheadline.weight(.medium)
        case .body: return .subheadline
        case .note: return .caption
        case .badge: return .caption2
        }
    }
    #else
    var font: Font {
        switch self {
        case .heading: return .subheadline.weight(.semibold)
        case .value: return .subheadline.weight(.medium)
        case .body: return .subheadline
        case .note: return .caption
        case .badge: return .caption2
        }
    }
    #endif
}

private extension View {
    @ViewBuilder func insightsFont(_ style: InsightsFont) -> some View {
        #if os(macOS)
        macFont(style.mac)
        #else
        font(style.font)
        #endif
    }
}
