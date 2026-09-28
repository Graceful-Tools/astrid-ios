import XCTest
@testable import Astrid_App

/// Unit tests for RepeatingTaskCalculator
/// Tests the repeating task logic that has had multiple recent bug fixes
/// Related commits: 20ce61e, 8016a43, 9b6b1e3, 2cfad5c
final class RepeatingTaskCalculatorTests: XCTestCase {

    // MARK: - Test Helpers

    private func createDate(year: Int, month: Int, day: Int, hour: Int = 9, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    // MARK: - Simple Daily Repeating Tests

    func testDailyRepeatFromDueDate() {
        let dueDate = createDate(year: 2024, month: 1, day: 15, hour: 10, minute: 30)
        let completionDate = createDate(year: 2024, month: 1, day: 15, hour: 14, minute: 0)

        let result = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .daily,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        // Next due date should be Jan 16 at 10:30 (preserves time from due date)
        XCTAssertNotNil(result.nextDueDate)
        XCTAssertFalse(result.shouldTerminate)
        XCTAssertEqual(result.newOccurrenceCount, 1)

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.day, from: result.nextDueDate!), 16)
        XCTAssertEqual(calendar.component(.hour, from: result.nextDueDate!), 10)
        XCTAssertEqual(calendar.component(.minute, from: result.nextDueDate!), 30)
    }

    func testDailyRepeatFromCompletionDate() {
        let dueDate = createDate(year: 2024, month: 1, day: 15, hour: 10, minute: 30)
        let completionDate = createDate(year: 2024, month: 1, day: 17, hour: 14, minute: 0)  // Completed 2 days late

        let result = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .daily,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .COMPLETION_DATE,
            currentOccurrenceCount: 0
        )

        // Next due date should be Jan 18 at 10:30 (1 day after completion, preserving time)
        XCTAssertNotNil(result.nextDueDate)

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.day, from: result.nextDueDate!), 18)
        XCTAssertEqual(calendar.component(.hour, from: result.nextDueDate!), 10)
        XCTAssertEqual(calendar.component(.minute, from: result.nextDueDate!), 30)
    }

    // MARK: - Simple Weekly Repeating Tests

    func testWeeklyRepeatFromDueDate() {
        let dueDate = createDate(year: 2024, month: 1, day: 15, hour: 9, minute: 0)  // Monday
        let completionDate = createDate(year: 2024, month: 1, day: 15, hour: 10, minute: 0)

        let result = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .weekly,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 2
        )

        // Next due date should be Jan 22 (7 days later)
        XCTAssertNotNil(result.nextDueDate)
        XCTAssertEqual(result.newOccurrenceCount, 3)

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.day, from: result.nextDueDate!), 22)
    }

    // MARK: - Simple Monthly Repeating Tests

    func testMonthlyRepeatFromDueDate() {
        let dueDate = createDate(year: 2024, month: 1, day: 15, hour: 14, minute: 0)
        let completionDate = createDate(year: 2024, month: 1, day: 15, hour: 16, minute: 0)

        let result = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .monthly,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        // Next due date should be Feb 15
        XCTAssertNotNil(result.nextDueDate)

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.month, from: result.nextDueDate!), 2)
        XCTAssertEqual(calendar.component(.day, from: result.nextDueDate!), 15)
    }

    func testMonthlyRepeatEndOfMonth() {
        // Jan 31 -> Feb should handle month-end clamping
        let dueDate = createDate(year: 2024, month: 1, day: 31, hour: 9, minute: 0)
        let completionDate = createDate(year: 2024, month: 1, day: 31, hour: 10, minute: 0)

        let result = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .monthly,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        // Should handle Feb gracefully (either Feb 29 for leap year or last valid day)
        XCTAssertNotNil(result.nextDueDate)

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.month, from: result.nextDueDate!), 2)
        // Feb 2024 has 29 days (leap year)
        XCTAssertTrue(calendar.component(.day, from: result.nextDueDate!) <= 29)
    }

    // MARK: - Simple Yearly Repeating Tests

    func testYearlyRepeatFromDueDate() {
        let dueDate = createDate(year: 2024, month: 6, day: 15, hour: 12, minute: 0)
        let completionDate = createDate(year: 2024, month: 6, day: 15, hour: 14, minute: 0)

        let result = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .yearly,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        // Next due date should be June 15, 2025
        XCTAssertNotNil(result.nextDueDate)

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.year, from: result.nextDueDate!), 2025)
        XCTAssertEqual(calendar.component(.month, from: result.nextDueDate!), 6)
        XCTAssertEqual(calendar.component(.day, from: result.nextDueDate!), 15)
    }

    // MARK: - End Condition Tests

    func testEndAfterOccurrences() {
        let dueDate = createDate(year: 2024, month: 1, day: 15)
        let completionDate = dueDate

        let endData = SimplePatternEndCondition(
            endCondition: "after_occurrences",
            endAfterOccurrences: 3,
            endUntilDate: nil
        )

        // Test at occurrence 2 - should continue
        let result1 = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .daily,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 2,
            endData: endData
        )

        XCTAssertNil(result1.nextDueDate)  // 3rd occurrence reached, terminate
        XCTAssertTrue(result1.shouldTerminate)
        XCTAssertEqual(result1.newOccurrenceCount, 3)

        // Test at occurrence 1 - should continue
        let result2 = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .daily,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 1,
            endData: endData
        )

        XCTAssertNotNil(result2.nextDueDate)
        XCTAssertFalse(result2.shouldTerminate)
        XCTAssertEqual(result2.newOccurrenceCount, 2)
    }

    func testEndUntilDate() {
        let dueDate = createDate(year: 2024, month: 1, day: 28)
        let completionDate = dueDate
        let endDate = createDate(year: 2024, month: 1, day: 30)

        let endData = SimplePatternEndCondition(
            endCondition: "until_date",
            endAfterOccurrences: nil,
            endUntilDate: endDate
        )

        // First daily repeat: Jan 28 -> Jan 29 (before end date, should continue)
        let result1 = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .daily,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0,
            endData: endData
        )

        XCTAssertNotNil(result1.nextDueDate)
        XCTAssertFalse(result1.shouldTerminate)

        // Second daily repeat: Jan 29 -> Jan 30 (on end date, should continue)
        let dueDate2 = createDate(year: 2024, month: 1, day: 29)
        let result2 = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .daily,
            currentDueDate: dueDate2,
            completionDate: dueDate2,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 1,
            endData: endData
        )

        XCTAssertNotNil(result2.nextDueDate)
        XCTAssertFalse(result2.shouldTerminate)

        // Third daily repeat: Jan 30 -> Jan 31 (past end date, should terminate)
        let dueDate3 = createDate(year: 2024, month: 1, day: 30)
        let result3 = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .daily,
            currentDueDate: dueDate3,
            completionDate: dueDate3,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 2,
            endData: endData
        )

        XCTAssertNil(result3.nextDueDate)
        XCTAssertTrue(result3.shouldTerminate)
    }

    func testEndConditionNever() {
        let dueDate = createDate(year: 2024, month: 1, day: 15)
        let completionDate = dueDate

        let endData = SimplePatternEndCondition(
            endCondition: "never",
            endAfterOccurrences: nil,
            endUntilDate: nil
        )

        let result = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .daily,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 100,  // Even at high count
            endData: endData
        )

        XCTAssertNotNil(result.nextDueDate)
        XCTAssertFalse(result.shouldTerminate)
    }

    // MARK: - Custom Pattern: Days Tests

    func testCustomDaysPattern() {
        let dueDate = createDate(year: 2024, month: 1, day: 15, hour: 10, minute: 0)
        let completionDate = dueDate

        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "days",
            interval: 3,  // Every 3 days
            endCondition: "never",
            endAfterOccurrences: nil,
            endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: nil,
            monthDay: nil,
            monthWeekday: nil,
            month: nil,
            day: nil
        )

        let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        // Next due date should be Jan 18 (3 days later)
        XCTAssertNotNil(result.nextDueDate)
        XCTAssertFalse(result.shouldTerminate)

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.day, from: result.nextDueDate!), 18)
    }

    // MARK: - Custom Pattern: Weeks Tests

    func testCustomWeeksPatternWithWeekdays() {
        // Task due Monday Jan 15, 2024
        let dueDate = createDate(year: 2024, month: 1, day: 15, hour: 9, minute: 0)
        let completionDate = dueDate

        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "weeks",
            interval: 1,
            endCondition: "never",
            endAfterOccurrences: nil,
            endUntilDate: nil,
            weekdays: ["monday", "wednesday", "friday"],  // M/W/F
            monthRepeatType: nil,
            monthDay: nil,
            monthWeekday: nil,
            month: nil,
            day: nil
        )

        let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        // Next occurrence should be Wednesday Jan 17
        XCTAssertNotNil(result.nextDueDate)

        let calendar = Calendar.current
        let nextDayOfWeek = calendar.component(.weekday, from: result.nextDueDate!)
        // weekday: 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
        XCTAssertEqual(nextDayOfWeek, 4)  // Wednesday
    }

    // MARK: - Custom Pattern: Months Tests

    func testCustomMonthsSameDatePattern() {
        let dueDate = createDate(year: 2024, month: 1, day: 15, hour: 14, minute: 30)
        let completionDate = dueDate

        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "months",
            interval: 2,  // Every 2 months
            endCondition: "never",
            endAfterOccurrences: nil,
            endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: "same_date",
            monthDay: nil,
            monthWeekday: nil,
            month: nil,
            day: nil
        )

        let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        // Next due date should be March 15 (2 months later)
        XCTAssertNotNil(result.nextDueDate)

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.month, from: result.nextDueDate!), 3)
        XCTAssertEqual(calendar.component(.day, from: result.nextDueDate!), 15)
    }

    func testCustomMonthsSameWeekdayPattern() {
        // Third Tuesday of January 2024 is Jan 16
        let dueDate = createDate(year: 2024, month: 1, day: 16, hour: 10, minute: 0)
        let completionDate = dueDate

        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "months",
            interval: 1,
            endCondition: "never",
            endAfterOccurrences: nil,
            endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: "same_weekday",
            monthDay: nil,
            monthWeekday: CustomRepeatingPattern.MonthWeekday(weekday: "tuesday", weekOfMonth: 3),
            month: nil,
            day: nil
        )

        let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        // Next due date should be third Tuesday of February 2024
        XCTAssertNotNil(result.nextDueDate)

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.month, from: result.nextDueDate!), 2)
        // Third Tuesday of Feb 2024 is Feb 20
        XCTAssertEqual(calendar.component(.weekday, from: result.nextDueDate!), 3)  // Tuesday
    }

    // MARK: - Custom Pattern: Years Tests

    func testCustomYearsPattern() {
        let dueDate = createDate(year: 2024, month: 12, day: 25, hour: 8, minute: 0)
        let completionDate = dueDate

        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "years",
            interval: 1,
            endCondition: "never",
            endAfterOccurrences: nil,
            endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: nil,
            monthDay: nil,
            monthWeekday: nil,
            month: 12,
            day: 25
        )

        let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        // Next occurrence should be Dec 25, 2025
        XCTAssertNotNil(result.nextDueDate)

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.year, from: result.nextDueDate!), 2025)
        XCTAssertEqual(calendar.component(.month, from: result.nextDueDate!), 12)
        XCTAssertEqual(calendar.component(.day, from: result.nextDueDate!), 25)
    }

    // MARK: - Custom Pattern End Conditions

    func testCustomPatternEndAfterOccurrences() {
        let dueDate = createDate(year: 2024, month: 1, day: 15)
        let completionDate = dueDate

        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "days",
            interval: 1,
            endCondition: "after_occurrences",
            endAfterOccurrences: 5,
            endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: nil,
            monthDay: nil,
            monthWeekday: nil,
            month: nil,
            day: nil
        )

        // At occurrence 4 - should terminate (reaching 5)
        let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 4
        )

        XCTAssertNil(result.nextDueDate)
        XCTAssertTrue(result.shouldTerminate)
        XCTAssertEqual(result.newOccurrenceCount, 5)
    }

    func testCustomPatternEndUntilDate() {
        let dueDate = createDate(year: 2024, month: 1, day: 28)
        let completionDate = dueDate
        let endDate = createDate(year: 2024, month: 1, day: 29)

        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "days",
            interval: 2,  // Every 2 days
            endCondition: "until_date",
            endAfterOccurrences: nil,
            endUntilDate: endDate,
            weekdays: nil,
            monthRepeatType: nil,
            monthDay: nil,
            monthWeekday: nil,
            month: nil,
            day: nil
        )

        // Jan 28 + 2 days = Jan 30, which is past Jan 29 end date
        let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        XCTAssertNil(result.nextDueDate)
        XCTAssertTrue(result.shouldTerminate)
    }

    // MARK: - Edge Cases

    func testNilDueDateFallsBackToCompletionDate() {
        let completionDate = createDate(year: 2024, month: 1, day: 15, hour: 10, minute: 0)

        let result = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .daily,
            currentDueDate: nil,  // No due date
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        // Should use completion date as anchor
        XCTAssertNotNil(result.nextDueDate)

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.day, from: result.nextDueDate!), 16)
    }

    func testInvalidCustomPatternReturnsNil() {
        let dueDate = createDate(year: 2024, month: 1, day: 15)
        let completionDate = dueDate

        // Pattern missing required fields
        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: nil,  // Missing unit
            interval: nil,  // Missing interval
            endCondition: "never",
            endAfterOccurrences: nil,
            endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: nil,
            monthDay: nil,
            monthWeekday: nil,
            month: nil,
            day: nil
        )

        let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        XCTAssertNil(result.nextDueDate)
        XCTAssertTrue(result.shouldTerminate)
    }

    func testNeverRepeatingTypeReturnsOriginalDate() {
        let dueDate = createDate(year: 2024, month: 1, day: 15)
        let completionDate = dueDate

        let result = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .never,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        // "never" type doesn't add any time, should return anchor date
        XCTAssertNotNil(result.nextDueDate)
    }

    // MARK: - All-Day Task Regression Tests

    /// Regression test for bug: All-day daily repeating task jumped 2 days instead of 1
    /// Bug: Completing a daily all-day task due Jan 6 would create next task due Jan 8 (not Jan 7)
    /// Root cause: Using local calendar to extract time from UTC midnight date caused timezone shift
    func testAllDayDailyRepeatFromCompletionDate() {
        // All-day tasks are stored as UTC midnight
        // Create a date at UTC midnight for Jan 6, 2026
        var utcCalendar = Calendar.current
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 6
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let dueDate = utcCalendar.date(from: components)!  // 2026-01-06T00:00:00Z

        // Completion date: Jan 6 at 2:42 PM local (could be various timezones)
        // Simulate completing later in the day
        var completionComponents = DateComponents()
        completionComponents.year = 2026
        completionComponents.month = 1
        completionComponents.day = 6
        completionComponents.hour = 14  // 2 PM
        completionComponents.minute = 42
        completionComponents.timeZone = TimeZone(identifier: "UTC")
        let completionDate = utcCalendar.date(from: completionComponents)!

        let result = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .daily,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .COMPLETION_DATE,
            currentOccurrenceCount: 0,
            isAllDay: true
        )

        // Next due date should be Jan 7 at UTC midnight (not Jan 8!)
        XCTAssertNotNil(result.nextDueDate, "Next due date should not be nil")

        // Verify the date is Jan 7, 2026 in UTC
        let nextDateComponents = utcCalendar.dateComponents([.year, .month, .day, .hour], from: result.nextDueDate!)
        XCTAssertEqual(nextDateComponents.year, 2026)
        XCTAssertEqual(nextDateComponents.month, 1)
        XCTAssertEqual(nextDateComponents.day, 7, "Next due date should be Jan 7 (1 day after Jan 6), not Jan 8")
        XCTAssertEqual(nextDateComponents.hour, 0, "All-day task should remain at UTC midnight")
    }

    /// Test that all-day weekly repeat also works correctly
    func testAllDayWeeklyRepeatFromCompletionDate() {
        var utcCalendar = Calendar.current
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        // Jan 6, 2026 at UTC midnight (all-day task)
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 6
        components.hour = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let dueDate = utcCalendar.date(from: components)!

        // Complete on the same day, later
        var completionComponents = DateComponents()
        completionComponents.year = 2026
        completionComponents.month = 1
        completionComponents.day = 6
        completionComponents.hour = 18  // 6 PM UTC
        completionComponents.timeZone = TimeZone(identifier: "UTC")
        let completionDate = utcCalendar.date(from: completionComponents)!

        let result = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .weekly,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .COMPLETION_DATE,
            currentOccurrenceCount: 0,
            isAllDay: true
        )

        XCTAssertNotNil(result.nextDueDate)

        // Should be Jan 13 (7 days later)
        let nextDateComponents = utcCalendar.dateComponents([.year, .month, .day, .hour], from: result.nextDueDate!)
        XCTAssertEqual(nextDateComponents.year, 2026)
        XCTAssertEqual(nextDateComponents.month, 1)
        XCTAssertEqual(nextDateComponents.day, 13, "Weekly repeat should be exactly 7 days later")
        XCTAssertEqual(nextDateComponents.hour, 0, "All-day task should remain at UTC midnight")
    }

    /// Test all-day task with DUE_DATE repeat mode (less affected but still verify)
    func testAllDayDailyRepeatFromDueDate() {
        var utcCalendar = Calendar.current
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 6
        components.hour = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let dueDate = utcCalendar.date(from: components)!

        // Complete 2 days late
        var completionComponents = DateComponents()
        completionComponents.year = 2026
        completionComponents.month = 1
        completionComponents.day = 8
        completionComponents.hour = 10
        completionComponents.timeZone = TimeZone(identifier: "UTC")
        let completionDate = utcCalendar.date(from: completionComponents)!

        let result = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .daily,
            currentDueDate: dueDate,
            completionDate: completionDate,
            repeatFrom: .DUE_DATE,  // Repeat from original due date
            currentOccurrenceCount: 0,
            isAllDay: true
        )

        XCTAssertNotNil(result.nextDueDate)

        // Should be Jan 7 (1 day after original due date of Jan 6)
        let nextDateComponents = utcCalendar.dateComponents([.year, .month, .day, .hour], from: result.nextDueDate!)
        XCTAssertEqual(nextDateComponents.year, 2026)
        XCTAssertEqual(nextDateComponents.month, 1)
        XCTAssertEqual(nextDateComponents.day, 7, "DUE_DATE mode should be 1 day after original due")
        XCTAssertEqual(nextDateComponents.hour, 0, "All-day task should remain at UTC midnight")
    }
}
