import XCTest
@testable import Astrid_App

/// A weekly custom repeat always repeats on a day (AITD-550).
///
/// "Every 4 weeks" saved with no day of the week completed and never came back: the shared rule
/// (web `types/repeating.ts`, astrid-core) ends a weekly series that names no weekday rather than
/// guess one. Web's editor refuses to save such a pattern; the Apple editors saved it. So a day
/// is required — and when none was picked, it is the due date's.
final class WeeklyRepeatWeekdayTests: XCTestCase {

    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    private func pattern(_ unit: String, interval: Int = 4, weekdays: [String]? = nil) -> CustomRepeatingPattern {
        CustomRepeatingPattern(
            type: "custom", unit: unit, interval: interval,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: weekdays, monthRepeatType: unit == "months" ? "same_date" : nil,
            monthDay: unit == "months" ? 23 : nil, monthWeekday: nil, month: nil, day: nil)
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    // MARK: - The cause

    /// The rule the editors have to satisfy: no weekday, no next occurrence.
    func testAWeeklyPatternWithNoWeekdayEndsTheSeries_AITD550() {
        let due = date("2026-10-23T16:00:00Z")
        for weekdays in [nil, [String]()] {
            let next = RepeatingTaskCalculator.calculateCustomNextOccurrence(
                pattern: pattern("weeks", weekdays: weekdays), currentDueDate: due, completionDate: due,
                repeatFrom: .DUE_DATE, currentOccurrenceCount: 0, timeZone: losAngeles).nextDueDate
            XCTAssertNil(next, "weekdays \(String(describing: weekdays)) ends the series — which is why one is required")
        }
    }

    // MARK: - The rule

    /// A timed task repeats on its due date's weekday where the person is.
    func testAWeeklyPatternWithNoDayTakesTheDueDatesWeekday_AITD550() {
        // Friday 09:00 in Los Angeles.
        let due = date("2026-10-23T16:00:00Z")
        let filled = pattern("weeks").requiringWeekday(dueDate: due, isAllDay: false, timeZone: losAngeles)
        XCTAssertEqual(filled.weekdays, ["friday"])
        XCTAssertEqual(pattern("weeks", weekdays: []).requiringWeekday(
            dueDate: due, isAllDay: false, timeZone: losAngeles).weekdays, ["friday"])
    }

    /// An all-day task's date is a UTC midnight, and the core reads its weekday in UTC: Friday's
    /// all-day date is Thursday evening in Los Angeles, and must still mean Friday.
    func testAnAllDayTaskTakesItsWeekdayInUTC_AITD550() {
        let due = date("2026-10-23T00:00:00Z")
        XCTAssertEqual(pattern("weeks").requiringWeekday(dueDate: due, isAllDay: true, timeZone: losAngeles).weekdays,
                       ["friday"])
        XCTAssertEqual(pattern("weeks").requiringWeekday(dueDate: due, isAllDay: false, timeZone: losAngeles).weekdays,
                       ["thursday"], "a timed task at that instant is Thursday where the person is")
    }

    /// With no due date there is nothing to read, so the day is today's.
    func testWithNoDueDateTheDayIsToday_AITD550() {
        let monday = date("2026-10-19T18:00:00Z")
        XCTAssertEqual(pattern("weeks").requiringWeekday(dueDate: nil, isAllDay: false,
                                                         timeZone: losAngeles, now: monday).weekdays,
                       ["monday"])
    }

    /// A choice already made is the person's, and other units have no weekdays to require.
    func testChosenDaysAndOtherUnitsAreLeftAlone_AITD550() {
        let due = date("2026-10-23T16:00:00Z")
        let chosen = pattern("weeks", weekdays: ["monday", "wednesday"])
        XCTAssertEqual(chosen.requiringWeekday(dueDate: due, isAllDay: false, timeZone: losAngeles), chosen)
        for unit in ["days", "months", "years"] {
            let other = pattern(unit)
            XCTAssertEqual(other.requiringWeekday(dueDate: due, isAllDay: false, timeZone: losAngeles), other,
                           "\(unit) has no weekday to require")
        }
    }

    // MARK: - End to end

    /// Jon's report: every 4 weeks, no day picked. Once the editor fills the day in, completing
    /// it creates the next one four weeks on.
    func testEveryFourWeeksWithNoDayPickedRepeatsFourWeeksOn_AITD550() {
        let due = date("2026-10-23T16:00:00Z")
        let saved = pattern("weeks").requiringWeekday(dueDate: due, isAllDay: false, timeZone: losAngeles)
        let next = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: saved, currentDueDate: due, completionDate: due,
            repeatFrom: .DUE_DATE, currentOccurrenceCount: 0, timeZone: losAngeles).nextDueDate
        XCTAssertEqual(next, date("2026-11-20T17:00:00Z"), "Friday 09:00 Los Angeles, four weeks on (after the clocks change)")
    }
}
