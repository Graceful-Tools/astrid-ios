import XCTest
@testable import Astrid_App

/// iOS port of `tests/lib/recently-completed-window.test.ts` from astrid-web.
///
/// These tests are the **contract** for the per-list completion-window
/// behavior: the list view's default completion filter and the board's
/// Done column both call into the helpers verified here. Same fixtures as
/// the web tests so the two platforms can never silently diverge.
final class RecentlyCompletedWindowTests: XCTestCase {

    // Fixed "now" for deterministic tests: Mon 2026-05-11 12:00 UTC
    private let now = ISO8601DateFormatter().date(from: "2026-05-11T12:00:00Z")!
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip_duration_day() throws {
        let value = RecentlyCompletedWindow.duration(amount: 7, unit: .day)
        let data = try JSONEncoder().encode(value)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"kind\":\"duration\""))
        XCTAssertTrue(json.contains("\"amount\":7"))
        XCTAssertTrue(json.contains("\"unit\":\"day\""))
        let decoded = try JSONDecoder().decode(RecentlyCompletedWindow.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testCodableRoundTrip_sinceWeekday() throws {
        let value = RecentlyCompletedWindow.sinceWeekday(weekday: 1) // Monday
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(RecentlyCompletedWindow.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testCodableRoundTrip_sinceDayOfMonth() throws {
        let value = RecentlyCompletedWindow.sinceDayOfMonth(day: 15)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(RecentlyCompletedWindow.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testCodableRoundTrip_sinceDate() throws {
        let value = RecentlyCompletedWindow.sinceDate(date: "2026-04-01")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(RecentlyCompletedWindow.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testDecode_unknownKindThrows() {
        let json = "{\"kind\":\"bogus\"}".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(RecentlyCompletedWindow.self, from: json))
    }

    // MARK: - getRecentlyCompletedCutoff: legacy default

    func testCutoff_nilWindow_isExactly24HoursAgo() {
        let cutoff = getRecentlyCompletedCutoff(nil, now: now, calendar: calendar)
        let expected = now.addingTimeInterval(-24 * 60 * 60)
        XCTAssertEqual(cutoff.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - getRecentlyCompletedCutoff: duration

    func testCutoff_duration_7Days() {
        let cutoff = getRecentlyCompletedCutoff(
            .duration(amount: 7, unit: .day),
            now: now, calendar: calendar
        )
        let expected = now.addingTimeInterval(-7 * 24 * 60 * 60)
        XCTAssertEqual(cutoff.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
    }

    func testCutoff_duration_2Hours() {
        let cutoff = getRecentlyCompletedCutoff(
            .duration(amount: 2, unit: .hour),
            now: now, calendar: calendar
        )
        let expected = now.addingTimeInterval(-2 * 60 * 60)
        XCTAssertEqual(cutoff.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
    }

    func testCutoff_duration_1Week() {
        let cutoff = getRecentlyCompletedCutoff(
            .duration(amount: 1, unit: .week),
            now: now, calendar: calendar
        )
        let expected = now.addingTimeInterval(-7 * 24 * 60 * 60)
        XCTAssertEqual(cutoff.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
    }

    func testCutoff_duration_1Month_uses30DayApproximation() {
        let cutoff = getRecentlyCompletedCutoff(
            .duration(amount: 1, unit: .month),
            now: now, calendar: calendar
        )
        let expected = now.addingTimeInterval(-30 * 24 * 60 * 60)
        XCTAssertEqual(cutoff.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - getRecentlyCompletedCutoff: since-weekday

    func testCutoff_sinceWeekday_lastSunday() {
        // now = Mon 2026-05-11. last Sunday at midnight = 2026-05-10 00:00 UTC.
        let cutoff = getRecentlyCompletedCutoff(
            .sinceWeekday(weekday: 0),
            now: now, calendar: calendar
        )
        let expected = ISO8601DateFormatter().date(from: "2026-05-10T00:00:00Z")!
        XCTAssertEqual(cutoff, expected)
    }

    func testCutoff_sinceWeekday_lastMonday_isToday() {
        // now = Mon 2026-05-11. "last Monday" should be today at midnight.
        let cutoff = getRecentlyCompletedCutoff(
            .sinceWeekday(weekday: 1),
            now: now, calendar: calendar
        )
        let expected = ISO8601DateFormatter().date(from: "2026-05-11T00:00:00Z")!
        XCTAssertEqual(cutoff, expected)
    }

    func testCutoff_sinceWeekday_lastTuesday_wrapsBack6Days() {
        // now = Mon 2026-05-11. last Tuesday = 2026-05-05 at midnight.
        let cutoff = getRecentlyCompletedCutoff(
            .sinceWeekday(weekday: 2),
            now: now, calendar: calendar
        )
        let expected = ISO8601DateFormatter().date(from: "2026-05-05T00:00:00Z")!
        XCTAssertEqual(cutoff, expected)
    }

    // MARK: - getRecentlyCompletedCutoff: since-day-of-month

    func testCutoff_sinceDayOfMonth_firstOfThisMonth() {
        // now = Mon 2026-05-11 -> 2026-05-01 00:00 UTC
        let cutoff = getRecentlyCompletedCutoff(
            .sinceDayOfMonth(day: 1),
            now: now, calendar: calendar
        )
        let expected = ISO8601DateFormatter().date(from: "2026-05-01T00:00:00Z")!
        XCTAssertEqual(cutoff, expected)
    }

    func testCutoff_sinceDayOfMonth_rollsBackOneMonth_whenTargetIsFuture() {
        // now = Mon 2026-05-11, target day = 15 -> previous month, 2026-04-15.
        let cutoff = getRecentlyCompletedCutoff(
            .sinceDayOfMonth(day: 15),
            now: now, calendar: calendar
        )
        let expected = ISO8601DateFormatter().date(from: "2026-04-15T00:00:00Z")!
        XCTAssertEqual(cutoff, expected)
    }

    // MARK: - getRecentlyCompletedCutoff: since-date

    func testCutoff_sinceDate_parsesYYYYMMDDAsLocalMidnight() {
        let cutoff = getRecentlyCompletedCutoff(
            .sinceDate(date: "2026-04-01"),
            now: now, calendar: calendar
        )
        let expected = ISO8601DateFormatter().date(from: "2026-04-01T00:00:00Z")!
        XCTAssertEqual(cutoff, expected)
    }

    // MARK: - isTaskRecentlyCompleted

    func testIsRecentlyCompleted_completedAtAfterCutoff_isTrue() {
        let completedAt = now.addingTimeInterval(-1 * 60 * 60) // 1h ago
        XCTAssertTrue(isTaskRecentlyCompleted(
            completedAt: completedAt,
            updatedAt: nil,
            window: nil,
            now: now,
            calendar: calendar
        ))
    }

    func testIsRecentlyCompleted_completedAtBeforeCutoff_isFalse() {
        let completedAt = now.addingTimeInterval(-48 * 60 * 60) // 2 days ago
        XCTAssertFalse(isTaskRecentlyCompleted(
            completedAt: completedAt,
            updatedAt: nil,
            window: nil,
            now: now,
            calendar: calendar
        ))
    }

    func testIsRecentlyCompleted_fallsBackToUpdatedAt_whenCompletedAtIsNil() {
        let updatedAt = now.addingTimeInterval(-1 * 60 * 60)
        XCTAssertTrue(isTaskRecentlyCompleted(
            completedAt: nil,
            updatedAt: updatedAt,
            window: nil,
            now: now,
            calendar: calendar
        ))
    }

    func testIsRecentlyCompleted_bothNil_isFalse() {
        XCTAssertFalse(isTaskRecentlyCompleted(
            completedAt: nil,
            updatedAt: nil,
            window: nil,
            now: now,
            calendar: calendar
        ))
    }

    // MARK: - shouldShowCompletedByFilter

    func testFilter_show_alwaysTrue() {
        XCTAssertTrue(shouldShowCompletedByFilter(
            filterMode: "show",
            completedAt: now.addingTimeInterval(-1000 * 24 * 60 * 60), // very old
            updatedAt: nil,
            window: nil,
            now: now,
            calendar: calendar
        ))
    }

    func testFilter_hide_alwaysFalse() {
        XCTAssertFalse(shouldShowCompletedByFilter(
            filterMode: "hide",
            completedAt: now.addingTimeInterval(-1),
            updatedAt: nil,
            window: nil,
            now: now,
            calendar: calendar
        ))
    }

    func testFilter_default_appliesWindow() {
        let recent = now.addingTimeInterval(-1 * 60 * 60)
        XCTAssertTrue(shouldShowCompletedByFilter(
            filterMode: "default",
            completedAt: recent,
            updatedAt: nil,
            window: nil,
            now: now,
            calendar: calendar
        ))

        let old = now.addingTimeInterval(-48 * 60 * 60)
        XCTAssertFalse(shouldShowCompletedByFilter(
            filterMode: "default",
            completedAt: old,
            updatedAt: nil,
            window: nil,
            now: now,
            calendar: calendar
        ))
    }

    func testFilter_allOrNil_returnsTrue() {
        XCTAssertTrue(shouldShowCompletedByFilter(
            filterMode: "all",
            completedAt: nil,
            updatedAt: nil,
            window: nil,
            now: now,
            calendar: calendar
        ))
        XCTAssertTrue(shouldShowCompletedByFilter(
            filterMode: nil,
            completedAt: nil,
            updatedAt: nil,
            window: nil,
            now: now,
            calendar: calendar
        ))
    }
}
