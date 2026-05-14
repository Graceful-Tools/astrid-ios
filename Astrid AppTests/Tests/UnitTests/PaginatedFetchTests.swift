import XCTest
@testable import Astrid_App

/// Pins pagination semantics so the iOS sync can't silently drop tasks
/// for users with large task counts.
///
/// Context: 2026-05-14 user report — after deleting the iOS app and
/// reinstalling, "old tasks aren't showing up" for an account with
/// 600+ tasks accumulated over a year. The previous loop terminated
/// on `meta.total` from the server response, which can disagree with
/// the actual result set when the API's `where` clause has a complex
/// `OR` (Prisma `count` and `findMany` can return different cardinalities
/// in rare cases). These tests pin the contract that pagination must
/// NOT trust `total` — only `items.count < limit` or an empty page is
/// authoritative.
final class PaginatedFetchTests: XCTestCase {

    /// Single short page (fewer items than limit) → 1 call returns all.
    func test_singleShortPage_returnsAll_singleCall() async throws {
        var calls = 0
        let result = try await paginatedFetchAllItems(limit: 1000) { _, _ in
            calls += 1
            return PaginatedPage(items: Array(0..<5), total: 5)
        }
        XCTAssertEqual(result, Array(0..<5))
        XCTAssertEqual(calls, 1)
    }

    /// Exact boundary: page size equals limit → need a second empty
    /// call to confirm there are no more items. Without this we'd
    /// guess and risk dropping records.
    func test_fullPageThenEmpty_terminatesCleanly() async throws {
        var calls = 0
        let result = try await paginatedFetchAllItems(limit: 3) { _, offset in
            calls += 1
            if offset == 0 { return PaginatedPage(items: [10, 11, 12], total: 3) }
            return PaginatedPage<Int>(items: [], total: 3)
        }
        XCTAssertEqual(result, [10, 11, 12])
        XCTAssertEqual(calls, 2)
    }

    /// Multi-page, last page partial: 1000 then 500.
    func test_multiPagePartialLast_aggregates() async throws {
        var calls = 0
        let result = try await paginatedFetchAllItems(limit: 1000) { _, offset in
            calls += 1
            if offset == 0 { return PaginatedPage(items: Array(0..<1000), total: 1500) }
            return PaginatedPage(items: Array(1000..<1500), total: 1500)
        }
        XCTAssertEqual(result.count, 1500)
        XCTAssertEqual(calls, 2)
    }

    /// **Regression test for "old tasks missing after fresh install".**
    /// Server reports total=100 but the result set actually has 600
    /// items (this can happen when Prisma's `count` query disagrees
    /// with `findMany` under complex `OR` where-clauses — a stale or
    /// approximate count, or a planner quirk). The helper MUST NOT
    /// trust `total` for termination.
    func test_serverLiesAboutTotal_stillFetchesAll() async throws {
        var calls = 0
        let result = try await paginatedFetchAllItems(limit: 1000) { _, offset in
            calls += 1
            if offset == 0 {
                // Server returns 600 actual items but claims total=100.
                return PaginatedPage(items: Array(0..<600), total: 100)
            }
            return PaginatedPage<Int>(items: [], total: 100)
        }
        XCTAssertEqual(result.count, 600,
                       "Pagination helper must not honor a stale/wrong server total")
    }

    /// Empty server → one call, zero items, no infinite loop.
    func test_emptyServer_singleCall_noInfiniteLoop() async throws {
        var calls = 0
        let result = try await paginatedFetchAllItems(limit: 1000) { _, _ in
            calls += 1
            return PaginatedPage<Int>(items: [], total: 0)
        }
        XCTAssertEqual(result, [])
        XCTAssertEqual(calls, 1)
    }

    /// Degenerate input: limit must be positive. Zero/negative limit
    /// returns empty without making any calls (no infinite loop).
    func test_nonPositiveLimit_returnsEmpty_noCalls() async throws {
        var calls = 0
        let zeroResult = try await paginatedFetchAllItems(limit: 0) { _, _ in
            calls += 1
            return PaginatedPage(items: [1, 2], total: 2)
        }
        XCTAssertEqual(zeroResult, [])
        XCTAssertEqual(calls, 0)
    }

    /// Offset advances by exactly the page's limit each iteration so
    /// the caller's server query stays in sync with what's already
    /// been fetched.
    func test_offsetAdvancesByLimit_each_iteration() async throws {
        var offsetsSeen: [Int] = []
        let limit = 100
        _ = try await paginatedFetchAllItems(limit: limit) { _, offset in
            offsetsSeen.append(offset)
            if offset < 250 {
                return PaginatedPage(items: Array(offset..<offset + limit), total: 250)
            }
            return PaginatedPage<Int>(items: [], total: 250)
        }
        XCTAssertEqual(offsetsSeen, [0, 100, 200, 300])
    }

    /// Page items are concatenated in fetch order — paging order
    /// preserves server order.
    func test_concatenationPreservesPageOrder() async throws {
        let pages: [[Int]] = [
            [1, 2, 3, 4, 5],
            [6, 7, 8, 9, 10],
            [11, 12],
        ]
        var pageIndex = 0
        let limit = 5
        let result = try await paginatedFetchAllItems(limit: limit) { _, _ in
            defer { pageIndex += 1 }
            let items = pages[pageIndex]
            return PaginatedPage(items: items, total: 12)
        }
        XCTAssertEqual(result, Array(1...12))
    }

    /// Errors from the fetch closure surface to the caller — the helper
    /// does not swallow them and leave a partial result.
    func test_fetchClosureThrows_propagatesError() async {
        struct TestError: Error {}
        do {
            _ = try await paginatedFetchAllItems(limit: 100) { _, _ in
                throw TestError() as Error
            } as [Int]
            XCTFail("Expected error to propagate")
        } catch is TestError {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
