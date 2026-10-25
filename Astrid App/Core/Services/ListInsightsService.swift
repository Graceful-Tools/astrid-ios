import Foundation

/// Reads a list's insights (AITD-545). Read-only, so nothing is journaled: the numbers are the
/// server's, computed over its history, and there is no offline version of them to show.
@MainActor
final class ListInsightsService {
    static let shared = ListInsightsService()

    private let apiClient: AstridAPIClient

    init(apiClient: AstridAPIClient = .shared) {
        self.apiClient = apiClient
    }

    /// `days` is one of `ListInsightsFormat.windows`; `timeZone` buckets the days the way the
    /// person's calendar does.
    func insights(listId: String, days: Int, timeZone: TimeZone = .current) async throws -> ListInsights {
        try await apiClient.getListInsights(listId: listId, days: days, timeZone: timeZone.identifier)
    }
}
