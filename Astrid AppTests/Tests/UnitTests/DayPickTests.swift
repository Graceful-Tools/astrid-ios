import XCTest
@testable import Astrid_App

/// AITD-635 — "Updating a task date to a future date is reverting back to the previously set date"
/// (task details, from My Tasks → Today). A quick pick is UTC midnight; on a TIMED task, west of
/// UTC, that instant is still the old day locally, so details showed the old day and the next time
/// edit saved it back. A day picked for a timed task has to land on that day, at the task's time.
final class DayPickTests: XCTestCase {

    private let pacific: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private let tokyo: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private func local(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func utcMidnight(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func dayAndTime(_ date: Date, _ calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    /// The reported case: a 3pm task due today, moved to "Tomorrow" from details in California.
    func testQuickPickTomorrowOnATimedTaskLandsTomorrowAtTheSameTime_AITD635() {
        let existing = local(pacific, 2026, 11, 13, 15)
        let tomorrowPick = utcMidnight(2026, 11, 14)

        // The bug, pinned: read as a timed instant here, the pick is still the 13th.
        XCTAssertEqual(pacific.component(.day, from: tomorrowPick), 13)

        let moved = DayPick.keepingTime(of: existing, on: tomorrowPick, dayIsUTCMidnight: true, calendar: pacific)
        XCTAssertEqual(dayAndTime(moved, pacific),
                       DateComponents(year: 2026, month: 11, day: 14, hour: 15, minute: 0))
    }

    /// East of UTC the quick pick is the right day already; keeping the time must not shift it.
    func testQuickPickEastOfUTCKeepsTheDayAndTheTime_AITD635() {
        let existing = local(tokyo, 2026, 11, 13, 9, 30)
        let moved = DayPick.keepingTime(of: existing, on: utcMidnight(2026, 11, 20),
                                        dayIsUTCMidnight: true, calendar: tokyo)
        XCTAssertEqual(dayAndTime(moved, tokyo),
                       DateComponents(year: 2026, month: 11, day: 20, hour: 9, minute: 30))
    }

    /// The calendar's own pick is a local instant. 4pm in California is midnight UTC the next day,
    /// so reading its day in UTC would be a day late; it is read locally.
    func testCalendarPickIsReadAsALocalDay_AITD635() {
        let existing = local(pacific, 2026, 11, 13, 16)
        let calendarPick = local(pacific, 2026, 11, 18, 16)
        let moved = DayPick.keepingTime(of: existing, on: calendarPick, dayIsUTCMidnight: false, calendar: pacific)
        XCTAssertEqual(dayAndTime(moved, pacific),
                       DateComponents(year: 2026, month: 11, day: 18, hour: 16, minute: 0))
    }
}
