import Foundation

/// Result of fetching one page from a paginated endpoint.
///
/// `total` is the server-reported count for the full result set. It's
/// captured for logging/diagnostics but is INTENTIONALLY NOT USED by
/// the pagination helper to decide when to stop — see
/// `paginatedFetchAllItems` for why.
struct PaginatedPage<T> {
    let items: [T]
    let total: Int
}

/// Repeatedly invokes `fetchPage(limit, offset)` to accumulate every
/// item the server has, stopping only when the server returns a SHORT
/// page (`items.count < limit`) or an empty page.
///
/// **Why not use the server's `total` to stop?** Some endpoints (notably
/// the v1 tasks list, where the `where` clause uses a complex `OR`
/// over creator / assignee / list-membership) can have a Prisma `count`
/// query that disagrees with `findMany` — stale, approximate, or
/// affected by query-planner quirks. Trusting `total` causes the iOS
/// app to silently drop tasks for users with large libraries. See
/// `PaginatedFetchTests.test_serverLiesAboutTotal_stillFetchesAll` for
/// the regression case.
///
/// Pure (no I/O of its own). All network work happens inside the
/// closure, which the tests stub for deterministic coverage of
/// boundary cases (single short page, exact boundary, partial last
/// page, stale total, empty, error propagation).
func paginatedFetchAllItems<T>(
    limit: Int,
    fetchPage: (_ limit: Int, _ offset: Int) async throws -> PaginatedPage<T>
) async throws -> [T] {
    guard limit > 0 else { return [] }
    var all: [T] = []
    var offset = 0
    while true {
        let page = try await fetchPage(limit, offset)
        all.append(contentsOf: page.items)
        if page.items.isEmpty { break }
        if page.items.count < limit { break }
        offset += limit
    }
    return all
}
