import Foundation

/// A list's activity over a window, computed once on the server (AITD-545, companion to web's
/// AWTD-1329). The source of truth is astrid-web `lib/list-insights.ts` and
/// `app/api/v1/lists/[id]/insights/route.ts`; these types only mirror what it returns.
struct ListInsights: Codable, Equatable {
    struct Window: Codable, Equatable {
        let days: Int
        let timeZone: String
        /// `yyyy-MM-dd` in `timeZone`, inclusive.
        let start: String
        let end: String
    }

    /// One calendar day, oldest first.
    struct Day: Codable, Equatable, Identifiable {
        let date: String
        let created: Int
        let completed: Int
        var id: String { date }
    }

    struct Totals: Codable, Equatable {
        let created: Int
        let completed: Int
    }

    /// A median, or nil when there was nothing to take one of — shown as "—", never 0.
    struct Duration: Codable, Equatable {
        let medianMs: Double?
        let sampleSize: Int
    }

    /// Median time a card spent in one board column, in column order.
    struct Lane: Codable, Equatable, Identifiable {
        let role: String
        let name: String
        let medianMs: Double?
        let sampleSize: Int
        var id: String { role }
        var duration: Duration { Duration(medianMs: medianMs, sampleSize: sampleSize) }
    }

    struct Contributor: Codable, Equatable, Identifiable {
        let userId: String
        let name: String?
        let image: String?
        let isAIAgent: Bool
        /// The profile's metrics, for this list (web AWTD-1333).
        let completed: Int
        let inspired: Int
        let supported: Int
        let created: Int
        let edited: Int
        let commented: Int
        let total: Int
        var id: String { userId }

        /// As a `User`, for the shared initials and avatar rules.
        var user: User {
            var user = User(id: userId, email: nil, name: name, image: image)
            user.isAIAgent = isAIAgent
            return user
        }

        init(userId: String, name: String?, image: String?, isAIAgent: Bool, completed: Int,
             inspired: Int = 0, supported: Int = 0, created: Int, edited: Int, commented: Int, total: Int) {
            self.userId = userId
            self.name = name
            self.image = image
            self.isAIAgent = isAIAgent
            self.completed = completed
            self.inspired = inspired
            self.supported = supported
            self.created = created
            self.edited = edited
            self.commented = commented
            self.total = total
        }

        /// `inspired` and `supported` arrived after the rest (AWTD-1333); a server without them
        /// still decodes, as zero.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            userId = try c.decode(String.self, forKey: .userId)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            image = try c.decodeIfPresent(String.self, forKey: .image)
            isAIAgent = try c.decodeIfPresent(Bool.self, forKey: .isAIAgent) ?? false
            completed = try c.decodeIfPresent(Int.self, forKey: .completed) ?? 0
            inspired = try c.decodeIfPresent(Int.self, forKey: .inspired) ?? 0
            supported = try c.decodeIfPresent(Int.self, forKey: .supported) ?? 0
            created = try c.decodeIfPresent(Int.self, forKey: .created) ?? 0
            edited = try c.decodeIfPresent(Int.self, forKey: .edited) ?? 0
            commented = try c.decodeIfPresent(Int.self, forKey: .commented) ?? 0
            total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        }
    }

    let window: Window
    let series: [Day]
    let totals: Totals
    let createToComplete: Duration
    /// Nil for a list that is not a board.
    let lanes: [Lane]?
    let contributors: [Contributor]
}

struct ListInsightsResponse: Codable {
    let insights: ListInsights
}

/// How the Insights section presents the numbers — web's `ListInsightsPanel.tsx`, rule for rule.
enum ListInsightsFormat {
    /// The windows the route accepts; anything else is a 400.
    static let windows = [7, 30, 90]
    static let defaultWindow = 30

    /// Insights are for every list but a saved filter (web: `!list.isVirtual`).
    static func isAvailable(for list: TaskList) -> Bool {
        list.isVirtual != true
    }

    private static let minute = 60_000.0
    private static let hour = 60 * minute
    private static let day = 24 * hour

    /// A duration at the one unit that reads naturally: minutes under an hour, hours under two
    /// days, then days — web's `formatInsightDuration`.
    static func duration(_ ms: Double) -> String {
        if ms < hour {
            return String(format: NSLocalizedString("listInsights.duration.minutes", comment: ""),
                          number(max(1, (ms / minute).rounded())))
        }
        if ms < 2 * day {
            return String(format: NSLocalizedString("listInsights.duration.hours", comment: ""),
                          number(((ms / hour) * 10).rounded() / 10))
        }
        return String(format: NSLocalizedString("listInsights.duration.days", comment: ""),
                      number(((ms / day) * 10).rounded() / 10))
    }

    /// The median, or nil for "—".
    static func median(_ value: ListInsights.Duration) -> String? {
        value.medianMs.map(duration)
    }

    static func sampleSize(_ value: ListInsights.Duration) -> String {
        String(format: NSLocalizedString("listInsights.sample_size", comment: ""), String(value.sampleSize))
    }

    /// Lane moves are only recorded from web's AWTD-1329 deploy on, so a board with no samples in
    /// any lane says so rather than drawing a column of dashes.
    static func lanesHaveHistory(_ lanes: [ListInsights.Lane]) -> Bool {
        lanes.contains { $0.sampleSize > 0 }
    }

    static func windowLabel(_ days: Int) -> String {
        NSLocalizedString("listInsights.days\(days)", comment: "")
    }

    static func totals(_ totals: ListInsights.Totals) -> String {
        String(format: NSLocalizedString("listInsights.created_total", comment: ""), String(totals.created))
            + " · "
            + String(format: NSLocalizedString("listInsights.completed_total", comment: ""), String(totals.completed))
    }

    static func profileCounts(_ person: ListInsights.Contributor) -> String {
        String(format: NSLocalizedString("listInsights.profile_counts", comment: ""),
               String(person.completed), String(person.inspired), String(person.supported))
    }

    static func activityCounts(_ person: ListInsights.Contributor) -> String {
        String(format: NSLocalizedString("listInsights.activity_counts", comment: ""),
               String(person.created), String(person.edited), String(person.commented))
    }

    /// A day's `yyyy-MM-dd`, as a date to plot — midnight UTC, so the axis never shifts it a day.
    static func plotDate(_ day: String) -> Date? {
        dayFormatter.date(from: day)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// `12`, `1.5` — a whole number without a trailing `.0`, as JavaScript prints one.
    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
