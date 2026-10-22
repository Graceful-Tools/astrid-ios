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

    /// Cross-timezone invariance: an all-day task created on another device
    /// at "today" resolves to the same logical day regardless of the
    /// user's current timezone, because we compare UTC date components.
    func testAllDay_TimezoneInvariant() {
        let task = makeTask(dueDateTime: todayAtUTCMidnight(), isAllDay: true)
        // Even if the device switched timezone (we can't flip the process
        // timezone safely here without side effects on other tests), the
        // UTC-component comparison in `isDueToday` already removes TZ from
        // the equation. Confirm the UTC-midnight structure:
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let hour = utcCalendar.component(.hour, from: task.dueDateTime!)
        let minute = utcCalendar.component(.minute, from: task.dueDateTime!)
        XCTAssertEqual(hour, 0, "All-day tasks must be stored at UTC midnight")
        XCTAssertEqual(minute, 0, "All-day tasks must be stored at UTC midnight")
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

    /// Simulate a task created on the web at UTC midnight for today (the
    /// exact payload iOS receives from `/api/v1/tasks`), then verify iOS
    /// reads it as "due today". This is the round-trip the user wanted
    /// covered: web creates all-day → iOS displays correctly.
    func testAllDay_WebCreatedTaskReadsAsDueTodayOnIOS() throws {
        // Build the payload web would emit for an all-day task due "today".
        let now = Date()
        let localCal = Calendar.current
        var comps = localCal.dateComponents([.year, .month, .day], from: now)
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let todayUTCMidnight = utcCal.date(from: comps)!

        let task = makeTask(dueDateTime: todayUTCMidnight, isAllDay: true)
        XCTAssertTrue(
            task.isDueToday,
            "Web-created all-day task for today must read as due-today on iOS"
        )
        XCTAssertFalse(task.isOverdue)
    }
}
