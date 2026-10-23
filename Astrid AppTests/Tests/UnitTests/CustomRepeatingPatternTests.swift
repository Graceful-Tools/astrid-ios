import XCTest
@testable import Astrid_App

/// Coverage for `CustomRepeatingPattern` on the Swift side:
///
/// 1. Round-trip of every pattern flavor through `JSONEncoder`/`JSONDecoder` — the shape the
///    wire and `Task`'s `Codable` conformance carry.
/// 2. Multi-step progressions of the patterns users reported, through `RepeatingTaskCalculator`
///    (which reaches astrid-core).
///
/// The rest of the next-occurrence contract is astrid-core's, pinned by its fixtures (ASTRID.md §0
/// rule 4). That completing a repeating task actually rolls it is `CompleteTaskRolloverTests`,
/// through `TaskService.completeTask` (AITD-532).
final class CustomRepeatingPatternTests: XCTestCase {

    // MARK: - Helpers

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    private func localDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    /// Mirrors the exact encode path used by `CDTask.encodeRepeatingData`.
    // MARK: - JSON Round-Trip Tests

    func testJSONRoundTrip_DailyEveryThreeDaysNever() throws {
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "days", interval: 3,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: nil, day: nil
        )

        let data = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(CustomRepeatingPattern.self, from: data)
        XCTAssertEqual(decoded, pattern)
    }

    func testJSONRoundTrip_WeeklyWithWeekdaysAfterOccurrences() throws {
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "weeks", interval: 2,
            endCondition: "after_occurrences", endAfterOccurrences: 10, endUntilDate: nil,
            weekdays: ["monday", "wednesday", "friday"],
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: nil, day: nil
        )

        let data = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(CustomRepeatingPattern.self, from: data)
        XCTAssertEqual(decoded, pattern)
        XCTAssertEqual(decoded.weekdays, ["monday", "wednesday", "friday"])
    }

    func testJSONRoundTrip_MonthlySameDate() throws {
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "months", interval: 1,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: "same_date", monthDay: 15, monthWeekday: nil,
            month: nil, day: nil
        )

        let data = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(CustomRepeatingPattern.self, from: data)
        XCTAssertEqual(decoded, pattern)
        XCTAssertEqual(decoded.monthRepeatType, "same_date")
        XCTAssertEqual(decoded.monthDay, 15)
    }

    func testJSONRoundTrip_MonthlySameWeekdayUntilDate() throws {
        let until = utcDate(2026, 12, 31)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "months", interval: 1,
            endCondition: "until_date", endAfterOccurrences: nil, endUntilDate: until,
            weekdays: nil,
            monthRepeatType: "same_weekday",
            monthDay: nil,
            monthWeekday: CustomRepeatingPattern.MonthWeekday(weekday: "tuesday", weekOfMonth: 3),
            month: nil, day: nil
        )

        let data = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(CustomRepeatingPattern.self, from: data)
        XCTAssertEqual(decoded, pattern)
        XCTAssertEqual(decoded.monthWeekday?.weekday, "tuesday")
        XCTAssertEqual(decoded.monthWeekday?.weekOfMonth, 3)
        XCTAssertEqual(decoded.endUntilDate?.timeIntervalSince1970 ?? 0, until.timeIntervalSince1970, accuracy: 0.001)
    }

    func testJSONRoundTrip_Yearly() throws {
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "years", interval: 1,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: 12, day: 25
        )

        let data = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(CustomRepeatingPattern.self, from: data)
        XCTAssertEqual(decoded, pattern)
        XCTAssertEqual(decoded.month, 12)
        XCTAssertEqual(decoded.day, 25)
    }

    func testJSONRoundTrip_PreservesNilFields() throws {
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "days", interval: 1,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: nil, day: nil
        )
        let data = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(CustomRepeatingPattern.self, from: data)

        XCTAssertNil(decoded.weekdays)
        XCTAssertNil(decoded.monthRepeatType)
        XCTAssertNil(decoded.monthDay)
        XCTAssertNil(decoded.monthWeekday)
        XCTAssertNil(decoded.month)
        XCTAssertNil(decoded.day)
        XCTAssertNil(decoded.endAfterOccurrences)
        XCTAssertNil(decoded.endUntilDate)
    }


    // MARK: - Multi-Step Progression Tests
    //
    // These walk a task's due date through many completions to lock down the
    // patterns a user relies on most. The expected results mirror what the
    // web (`astrid-web/lib/repeating-task-handler.ts` + `types/repeating.ts`)
    // produces for the same inputs.

    /// Runs `count` completions for a custom pattern, feeding the prior
    /// result back in as the next due date. Returns the ordered list of
    /// calculated next-due-dates (excluding terminations).
    private func simulateCustomProgression(
        pattern: CustomRepeatingPattern,
        initialDueDate: Date,
        repeatFrom: Task.RepeatFromMode,
        count: Int
    ) -> [Date] {
        var dates: [Date] = []
        var currentDueDate = initialDueDate
        var occurrenceCount = 0
        for _ in 0..<count {
            let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
                pattern: pattern,
                currentDueDate: currentDueDate,
                completionDate: currentDueDate,
                repeatFrom: repeatFrom,
                currentOccurrenceCount: occurrenceCount
            )
            guard let next = result.nextDueDate else { break }
            dates.append(next)
            currentDueDate = next
            occurrenceCount = result.newOccurrenceCount
            if result.shouldTerminate { break }
        }
        return dates
    }

    /// User-reported pattern: "Every week on Mon, Wed, Fri from due date".
    /// Starting on Monday Jan 15 2024, the next 6 completions must land on
    /// Wed, Fri, Mon, Wed, Fri, Mon in order.
    func testUserPattern_WeeklyMonWedFri_FromDueDate_StepsThroughCycle() {
        let start = localDate(2024, 1, 15, hour: 9) // Monday
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "weeks", interval: 1,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: ["monday", "wednesday", "friday"],
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: nil, day: nil
        )

        let dates = simulateCustomProgression(
            pattern: pattern, initialDueDate: start,
            repeatFrom: .DUE_DATE, count: 6
        )

        XCTAssertEqual(dates.count, 6)
        let cal = Calendar.current

        // Expected days: Wed Jan 17, Fri Jan 19, Mon Jan 22, Wed Jan 24, Fri Jan 26, Mon Jan 29.
        let expectedDays = [17, 19, 22, 24, 26, 29]
        // Swift Calendar weekday: Sun=1, Mon=2, Tue=3, Wed=4, Thu=5, Fri=6, Sat=7.
        let expectedWeekdays = [4, 6, 2, 4, 6, 2]

        for (i, date) in dates.enumerated() {
            XCTAssertEqual(cal.component(.day, from: date), expectedDays[i],
                           "Step \(i + 1): expected day \(expectedDays[i])")
            XCTAssertEqual(cal.component(.weekday, from: date), expectedWeekdays[i],
                           "Step \(i + 1): expected weekday \(expectedWeekdays[i])")
            XCTAssertEqual(cal.component(.hour, from: date), 9,
                           "Step \(i + 1): time must be preserved")
        }
    }

    /// COMPLETION_DATE variant of the same pattern. Completions happen on
    /// the due date, so each next occurrence advances to the next selected
    /// weekday, same as DUE_DATE mode.
    func testUserPattern_WeeklyMonWedFri_FromCompletionDate_StepsThroughCycle() {
        let start = localDate(2024, 1, 15, hour: 9) // Monday
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "weeks", interval: 1,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: ["monday", "wednesday", "friday"],
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: nil, day: nil
        )

        let dates = simulateCustomProgression(
            pattern: pattern, initialDueDate: start,
            repeatFrom: .COMPLETION_DATE, count: 6
        )

        XCTAssertEqual(dates.count, 6)
        let cal = Calendar.current
        let expectedDays = [17, 19, 22, 24, 26, 29]
        for (i, date) in dates.enumerated() {
            XCTAssertEqual(cal.component(.day, from: date), expectedDays[i])
        }
    }

    /// User-reported pattern: "Same Date of every month". Starting on
    /// Jan 15 2024, the next 12 completions must land on the 15th of each
    /// subsequent month.
    func testUserPattern_MonthlySameDate_StepsThroughYear() {
        let start = localDate(2024, 1, 15, hour: 14)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "months", interval: 1,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: "same_date", monthDay: 15, monthWeekday: nil,
            month: nil, day: nil
        )

        let dates = simulateCustomProgression(
            pattern: pattern, initialDueDate: start,
            repeatFrom: .DUE_DATE, count: 12
        )

        XCTAssertEqual(dates.count, 12)
        let cal = Calendar.current
        for (i, date) in dates.enumerated() {
            XCTAssertEqual(cal.component(.day, from: date), 15,
                           "Step \(i + 1): month-day must stay at 15")
            let expectedMonth = ((1 + i) % 12) + 1 // Feb=2, Mar=3, ..., Jan=1 (Jan 2025)
            XCTAssertEqual(cal.component(.month, from: date), expectedMonth,
                           "Step \(i + 1): expected month \(expectedMonth)")
            XCTAssertEqual(cal.component(.hour, from: date), 14,
                           "Step \(i + 1): time must be preserved")
        }
    }

    /// User-reported pattern: "Same weekday and week of month" — third
    /// Tuesday of each month. Starting Jan 16 2024 (the 3rd Tuesday of
    /// January), verify the next 6 occurrences match the third Tuesday of
    /// Feb, Mar, Apr, May, Jun, Jul.
    func testUserPattern_MonthlySameWeekday_ThirdTuesday_StepsThroughSixMonths() {
        let start = localDate(2024, 1, 16, hour: 10) // Third Tuesday of Jan 2024
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "months", interval: 1,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: "same_weekday", monthDay: nil,
            monthWeekday: CustomRepeatingPattern.MonthWeekday(weekday: "tuesday", weekOfMonth: 3),
            month: nil, day: nil
        )

        let dates = simulateCustomProgression(
            pattern: pattern, initialDueDate: start,
            repeatFrom: .DUE_DATE, count: 6
        )

        XCTAssertEqual(dates.count, 6)
        let cal = Calendar.current
        // 3rd Tuesdays: Feb 20, Mar 19, Apr 16, May 21, Jun 18, Jul 16 — all 2024.
        let expectedMonths = [2, 3, 4, 5, 6, 7]
        let expectedDays = [20, 19, 16, 21, 18, 16]
        for (i, date) in dates.enumerated() {
            XCTAssertEqual(cal.component(.month, from: date), expectedMonths[i],
                           "Step \(i + 1): month mismatch")
            XCTAssertEqual(cal.component(.day, from: date), expectedDays[i],
                           "Step \(i + 1): day mismatch (expected \(expectedDays[i]))")
            XCTAssertEqual(cal.component(.weekday, from: date), 3, // Tuesday
                           "Step \(i + 1): must be a Tuesday")
        }
    }

    // MARK: - Task Model Round-Trip (Task wraps CustomRepeatingPattern)
    //
    // `Task` embeds `CustomRepeatingPattern` and is also Codable. This test
    // proves the wrapping conformance still round-trips cleanly after the
    // isolation change.

    @MainActor
    func testTaskRoundTripWithCustomRepeatingPattern() throws {
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "weeks", interval: 2,
            endCondition: "after_occurrences", endAfterOccurrences: 4, endUntilDate: nil,
            weekdays: ["tuesday", "thursday"],
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: nil, day: nil
        )
        let task = Task(
            id: "t1",
            title: "Sample",
            repeating: .custom,
            repeatingData: pattern
        )

        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(Task.self, from: data)

        XCTAssertEqual(decoded.repeatingData, pattern)
        XCTAssertEqual(decoded.repeating, .custom)
    }
}
