import XCTest
@testable import Astrid_App

/// Cross-platform round-trip tests for all-day task handling.
///
/// The contract (Google Calendar / RFC 5545 semantics, shared with the web
/// in `astrid-web/lib/date-comparison.ts` + `date-filter-utils.ts`):
///
/// - **All-day tasks** are stored at **UTC midnight** representing a
///   calendar date. Date comparisons use UTC components so the same task
///   reads as the same day no matter the user's timezone.
/// - **Timed tasks** are stored as absolute timestamps and compared in the
///   user's local timezone.
///
/// These tests lock iOS to the same semantics the web validates in
/// `tests/lib/date-timezone-handling.test.ts`. Any change in iOS's logic
/// that would make a task disappear or shift a day on one platform but not
/// the other will fail here.
final class AllDayTimezoneTests: XCTestCase {

    // MARK: - Helpers

    /// Build a local-calendar today, returned at UTC midnight.
    /// Mirrors web's `new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()))`.
    private func todayAtUTCMidnight(offset days: Int = 0) -> Date {
        let now = Date()
        let localCalendar = Calendar.current
        var components = localCalendar.dateComponents([.year, .month, .day], from: now)
        components.day = (components.day ?? 0) + days
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        return utcCalendar.date(from: components)!
    }

    private func makeTask(dueDateTime: Date?, isAllDay: Bool, completed: Bool = false) -> Task {
        TestHelpers.createTestTask(title: "tz test", completed: completed, dueDateTime: dueDateTime, isAllDay: isAllDay)
    }

    // MARK: - All-day: isDueToday / isOverdue

    func testAllDay_DueTodayAtUTCMidnight_IsDueToday() {
        let task = makeTask(dueDateTime: todayAtUTCMidnight(), isAllDay: true)
        XCTAssertTrue(task.isDueToday, "All-day at UTC midnight of today should be due today")
        XCTAssertFalse(task.isOverdue, "Today is not overdue")
    }

    func testAllDay_DueYesterdayAtUTCMidnight_IsOverdue() {
        let task = makeTask(dueDateTime: todayAtUTCMidnight(offset: -1), isAllDay: true)
        XCTAssertTrue(task.isOverdue, "All-day yesterday should be overdue")
        XCTAssertFalse(task.isDueToday, "Yesterday is not today")
    }

    func testAllDay_DueTomorrowAtUTCMidnight_IsNotDueToday_IsNotOverdue() {
        let task = makeTask(dueDateTime: todayAtUTCMidnight(offset: 1), isAllDay: true)
        XCTAssertFalse(task.isDueToday)
        XCTAssertFalse(task.isOverdue)
    }

    // MARK: - Timed tasks

    /// A fixed "now" — 10:00 on Wednesday 11 March 2026 on the device's calendar — so these
    /// cases do not depend on when the suite runs (AITD-536).
    private var tenAM: Date { localTime(hour: 10) }

    private func localTime(day: Int = 11, hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    func testTimed_DueLaterTodayIsDueToday() {
        // Tasks due later today at 11pm local time count as "due today", and are not overdue yet.
        let task = makeTask(dueDateTime: localTime(hour: 23), isAllDay: false)
        XCTAssertTrue(task.isDueToday(at: tenAM), "Timed task later today is due today")
        XCTAssertFalse(task.isOverdue(at: tenAM))
    }

    /// Regression: iOS used to require `dueDate > now` for timed tasks,
    /// so a task due at 9am checked at 10am reported `isDueToday == false`.
    /// Web treats it as due-today-but-overdue. iOS now matches.
    func testTimed_DueEarlierTodayStillCountsAsDueToday() {
        let task = makeTask(dueDateTime: localTime(hour: 9), isAllDay: false)
        XCTAssertTrue(
            task.isDueToday(at: tenAM),
            "Timed task earlier today must still be `isDueToday` (web parity)"
        )
        XCTAssertTrue(task.isOverdue(at: tenAM), "and it is overdue — due today but already passed")
    }

    func testTimed_DueYesterday_IsOverdueNotDueToday() {
        let task = makeTask(dueDateTime: localTime(day: 10, hour: 10), isAllDay: false)
        XCTAssertTrue(task.isOverdue(at: tenAM))
        XCTAssertFalse(task.isDueToday(at: tenAM))
    }

    // MARK: - Codable / JSON round-trip (Task with all-day due date)

    /// The wire format of an all-day task is a UTC midnight ISO timestamp.
    /// Decode it, re-encode it, verify the result round-trips bit-for-bit
    /// so cached and freshly-fetched tasks behave identically.
    func testAllDay_JSONRoundTrip_PreservesUTCMidnight() throws {
        let due = todayAtUTCMidnight()
        let task = makeTask(dueDateTime: due, isAllDay: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(task)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Task.self, from: data)

        XCTAssertEqual(decoded.dueDateTime?.timeIntervalSince1970 ?? 0,
                       due.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.isAllDay, true)

        // Decoded task preserves UTC midnight structure.
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(utcCal.component(.hour, from: decoded.dueDateTime!), 0)
        XCTAssertEqual(utcCal.component(.minute, from: decoded.dueDateTime!), 0)
    }
}
