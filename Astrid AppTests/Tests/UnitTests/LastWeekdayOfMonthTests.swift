import XCTest
@testable import Astrid_App

/// AITD-562: `monthWeekday.weekOfMonth = -1` means the LAST <weekday> of the month — web and
/// astrid-core agreed on it in AWTD-1295. It counts back from the target month's last day, so it
/// never leaves the month; 5 does, when the month has only four of that weekday. The editor must
/// write -1 for "Last", and the summary must not read "the -1th Thursday".
final class LastWeekdayOfMonthTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 10))!
    }

    private func monthly(_ weekday: String, weekOfMonth: Int, interval: Int = 1) -> CustomRepeatingPattern {
        CustomRepeatingPattern(
            type: "custom", unit: "months", interval: interval, endCondition: "never",
            endAfterOccurrences: nil, endUntilDate: nil, weekdays: nil,
            monthRepeatType: "same_weekday", monthDay: nil,
            monthWeekday: CustomRepeatingPattern.MonthWeekday(weekday: weekday, weekOfMonth: weekOfMonth),
            month: nil, day: nil
        )
    }

    private func next(_ pattern: CustomRepeatingPattern, from due: Date) -> Date? {
        RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern, currentDueDate: due, completionDate: due, repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0, timeZone: calendar.timeZone
        ).nextDueDate
    }

    private func ymd(_ date: Date?) -> String? {
        guard let date else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    // MARK: - The rule (astrid-core, through RepeatingTaskCalculator)

    func test_AITD562_lastWednesday_fromJanuary31_landsOnFebruarysLastWednesday() {
        // Plain calendar arithmetic picks February; an overflowing step would reach March.
        XCTAssertEqual(ymd(next(monthly("wednesday", weekOfMonth: -1), from: date(2024, 1, 31))), "2024-02-28")
    }

    func test_AITD562_lastMonday_intoAMonthWithOnlyFour_staysInThatMonth() {
        XCTAssertEqual(ymd(next(monthly("monday", weekOfMonth: -1), from: date(2024, 1, 29))), "2024-02-26")
    }

    func test_AITD562_lastFriday_crossesTheYear() {
        XCTAssertEqual(ymd(next(monthly("friday", weekOfMonth: -1), from: date(2024, 12, 27))), "2025-01-31")
    }

    func test_AITD562_lastThursday_everyThreeMonths() {
        XCTAssertEqual(ymd(next(monthly("thursday", weekOfMonth: -1, interval: 3), from: date(2024, 10, 31))), "2025-01-30")
    }

    // MARK: - The words

    func test_AITD562_summary_saysLast_notMinusFirst() {
        let text = CustomRepeatSummary.text(for: monthly("thursday", weekOfMonth: -1))
        XCTAssertEqual(text, "Every 1 months on the last Thursday")
    }

    func test_AITD562_summary_numberedWeeksUnchanged() {
        XCTAssertEqual(CustomRepeatSummary.weekOfMonth(3), "3rd")
        XCTAssertEqual(CustomRepeatSummary.weekOfMonth(5), "5th")
        XCTAssertEqual(CustomRepeatSummary.weekOfMonth(-1), "last")
    }

    // MARK: - What the editor writes

    func test_AITD562_editorOffersLast_andItWritesMinusOne_notFive() {
        let choices = CustomRepeatSummary.weekOfMonthChoices
        XCTAssertEqual(choices.map(\.value), [1, 2, 3, 4, 5, -1])
        XCTAssertEqual(choices.last?.labelKey, "repeating.last")
    }
}
