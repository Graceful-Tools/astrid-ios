import Foundation

/// Reads a list's insights (AITD-545). Read-only, so nothing is journaled: the numbers are the
/// server's, computed over its history, and there is no offline version of them to show.
///
/// **It asks once per answer, not once per look (AITD-554).** The tab fetched on every
/// appearance — swiping back to the Insights page on iOS, reopening List Settings on Mac — and
/// on every window change. The route has no rate limit, and a cold answer loads every task on
/// the list and its whole status history, so the client is the side that has to be careful:
///
/// - an answer is kept for `freshFor`, the server's own Redis TTL, so a second look inside it
///   could not have shown anything newer anyway;
/// - concurrent asks for the same answer share one request;
/// - a failure is not kept, and nothing retries it: the next request is the person's next look.
@MainActor
final class ListInsightsService {
    static let shared = ListInsightsService()

    /// astrid-web `LIST_INSIGHTS_CACHE_TTL_SECONDS`.
    static let freshFor: TimeInterval = 300

    private struct Key: Hashable {
        let userId: String?
        let listId: String
        let days: Int
        let timeZone: String
    }

    private let apiClient: AstridAPIClient
    private let now: () -> Date
    /// In the key, so an account switch never reads the previous account's answer.
    private let userId: @MainActor () -> String?
    private var answers: [Key: (insights: ListInsights, at: Date)] = [:]
    private var inFlight: [Key: _Concurrency.Task<ListInsights, Error>] = [:]

    init(apiClient: AstridAPIClient = .shared,
         now: @escaping () -> Date = Date.init,
         userId: (@MainActor () -> String?)? = nil) {
        self.apiClient = apiClient
        self.now = now
        self.userId = userId ?? { AuthManager.shared.userId }
    }

    /// `days` is one of `ListInsightsFormat.windows`; `timeZone` buckets the days the way the
    /// person's calendar does.
    func insights(listId: String, days: Int, timeZone: TimeZone = .current) async throws -> ListInsights {
        let key = Key(userId: userId(), listId: listId, days: days, timeZone: timeZone.identifier)
        if let kept = answers[key], now().timeIntervalSince(kept.at) < Self.freshFor {
            return kept.insights
        }
        if let pending = inFlight[key] { return try await pending.value }

        // Unstructured on purpose: a view that goes away mid-request does not cancel it, so the
        // answer it paid for is kept for the next look instead of being asked for again.
        let request = _Concurrency.Task { [apiClient] in
            try await apiClient.getListInsights(listId: listId, days: days, timeZone: key.timeZone)
        }
        inFlight[key] = request
        defer { inFlight[key] = nil }

        let insights = try await request.value
        let at = now()
        answers = answers.filter { at.timeIntervalSince($0.value.at) < Self.freshFor }
        answers[key] = (insights, at)
        return insights
    }
}
