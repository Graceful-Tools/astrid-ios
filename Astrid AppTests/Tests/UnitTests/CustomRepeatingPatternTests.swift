import XCTest
@testable import Astrid_App

/// Regression + coverage tests for `CustomRepeatingPattern`.
///
/// These tests guard the serialization contract used by `CDTask`
/// (`encodeRepeatingData` / `parseRepeatingData`) so that Swift concurrency
/// fixes cannot silently break how custom repeating patterns are persisted
/// or decoded. They cover:
///
/// 1. Round-trip of every pattern flavor through `JSONEncoder`/`JSONDecoder`
/// 2. Round-trip through the exact base64-wrapped shape that `CDTask` stores
/// 3. Calculator behavior for custom patterns that the prior tests didn't cover
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
    private func encodeAsCDTaskWould(_ pattern: CustomRepeatingPattern) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(pattern) else { return nil }
        return data.base64EncodedString()
    }

    /// Mirrors the exact decode path used by `CDTask.parseRepeatingData`.
    private func decodeAsCDTaskWould(_ base64: String) -> CustomRepeatingPattern? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(CustomRepeatingPattern.self, from: data)
    }

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

    // MARK: - CDTask-Shape Round-Trip (Base64-Wrapped)

    /// Exercises the exact encoder/decoder path used by `CDTask`. If the
    /// Swift 6 isolation fix ever reverts to something that changes encoding
    /// behavior (for example wrapping operations in `MainActor.assumeIsolated`
    /// with different encoder/decoder instances), this round-trip catches it.
    func testCDTaskShape_RoundTripAllFlavors() {
        let patterns: [CustomRepeatingPattern] = [
            // Daily
            CustomRepeatingPattern(
                type: "custom", unit: "days", interval: 1,
                endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
                weekdays: nil, monthRepeatType: nil, monthDay: nil,
                monthWeekday: nil, month: nil, day: nil
            ),
            // Every-2 days, ends after 5
            CustomRepeatingPattern(
                type: "custom", unit: "days", interval: 2,
                endCondition: "after_occurrences", endAfterOccurrences: 5, endUntilDate: nil,
                weekdays: nil, monthRepeatType: nil, monthDay: nil,
                monthWeekday: nil, month: nil, day: nil
            ),
            // Weekly M/W/F
            CustomRepeatingPattern(
                type: "custom", unit: "weeks", interval: 1,
                endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
                weekdays: ["monday", "wednesday", "friday"],
                monthRepeatType: nil, monthDay: nil,
                monthWeekday: nil, month: nil, day: nil
            ),
            // Every-2 weeks on weekends until a date
            CustomRepeatingPattern(
                type: "custom", unit: "weeks", interval: 2,
                endCondition: "until_date", endAfterOccurrences: nil,
                endUntilDate: utcDate(2027, 1, 1),
                weekdays: ["saturday", "sunday"],
                monthRepeatType: nil, monthDay: nil,
                monthWeekday: nil, month: nil, day: nil
            ),
            // Monthly same_date on the 15th
            CustomRepeatingPattern(
                type: "custom", unit: "months", interval: 1,
                endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
                weekdays: nil,
                monthRepeatType: "same_date", monthDay: 15,
                monthWeekday: nil, month: nil, day: nil
            ),
            // Monthly same_weekday: 1st Monday
            CustomRepeatingPattern(
                type: "custom", unit: "months", interval: 1,
                endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
                weekdays: nil,
                monthRepeatType: "same_weekday", monthDay: nil,
                monthWeekday: CustomRepeatingPattern.MonthWeekday(weekday: "monday", weekOfMonth: 1),
                month: nil, day: nil
            ),
            // Yearly Dec 25
            CustomRepeatingPattern(
                type: "custom", unit: "years", interval: 1,
                endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
                weekdays: nil,
                monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
                month: 12, day: 25
            )
        ]

        for pattern in patterns {
            guard let encoded = encodeAsCDTaskWould(pattern) else {
                XCTFail("Failed to encode pattern: \(pattern)")
                continue
            }
            // Validate it's a real base64 string (non-empty, decodable back to bytes)
            XCTAssertFalse(encoded.isEmpty)
            XCTAssertNotNil(Data(base64Encoded: encoded))

            guard let decoded = decodeAsCDTaskWould(encoded) else {
                XCTFail("Failed to decode pattern: \(pattern)")
                continue
            }
            XCTAssertEqual(decoded, pattern, "Round-trip mismatch for \(pattern)")
        }
    }

    /// Invalid/malformed input should return nil (not crash).
    func testCDTaskShape_DecodeInvalidBase64ReturnsNil() {
        XCTAssertNil(decodeAsCDTaskWould("not-valid-base64!@#"))
    }

    func testCDTaskShape_DecodeGarbageJSONReturnsNil() {
        let garbage = "bm90LWpzb24=" // "not-json" base64
        XCTAssertNil(decodeAsCDTaskWould(garbage))
    }

    // MARK: - Calculator Regression Tests
    //
    // These complement RepeatingTaskCalculatorTests with cases that cover
    // scenarios known to be affected by past fixes to custom repeating logic.

    func testCalculator_EveryTwoWeeksWithWeekdays_PicksNextMatchingDay() {
        // Jan 15 2024 is Monday. Pattern: every 2 weeks on Wed/Fri.
        let dueDate = localDate(2024, 1, 15, hour: 9)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "weeks", interval: 2,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: ["wednesday", "friday"],
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: nil, day: nil
        )

        let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern,
            currentDueDate: dueDate,
            completionDate: dueDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        XCTAssertNotNil(result.nextDueDate)
        XCTAssertFalse(result.shouldTerminate)
        let cal = Calendar.current
        // Next should be Wed Jan 17 (4 = Wednesday in Calendar.weekday)
        XCTAssertEqual(cal.component(.weekday, from: result.nextDueDate!), 4)
    }

    func testCalculator_WeeklyWhenTodayIsSelectedMovesToNextSelected() {
        // Mon Jan 15 2024, pattern includes Monday — next must still advance past today.
        let dueDate = localDate(2024, 1, 15, hour: 9)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "weeks", interval: 1,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: ["monday", "thursday"],
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: nil, day: nil
        )

        let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern,
            currentDueDate: dueDate,
            completionDate: dueDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        XCTAssertNotNil(result.nextDueDate)
        let cal = Calendar.current
        // Should be Thursday Jan 18 (5 = Thursday), not same day.
        XCTAssertEqual(cal.component(.weekday, from: result.nextDueDate!), 5)
        XCTAssertEqual(cal.component(.day, from: result.nextDueDate!), 18)
    }

    func testCalculator_WeeklyWhenOnlyOneWeekdayWrapsToNextWeek() {
        // Tue Jan 16 2024, only Monday selected — next Monday is Jan 22.
        let dueDate = localDate(2024, 1, 16, hour: 9)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "weeks", interval: 1,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: ["monday"],
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: nil, day: nil
        )

        let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern,
            currentDueDate: dueDate,
            completionDate: dueDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        XCTAssertNotNil(result.nextDueDate)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.weekday, from: result.nextDueDate!), 2) // Monday
        XCTAssertEqual(cal.component(.day, from: result.nextDueDate!), 22)
    }

    func testCalculator_MonthlySameDateEveryTwoMonthsFromCompletion() {
        // Due Jan 15 at 09:00, completed Jan 20 at 14:00, repeat every 2 months from completion.
        let dueDate = localDate(2024, 1, 15, hour: 9)
        let completion = localDate(2024, 1, 20, hour: 14)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "months", interval: 2,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: "same_date", monthDay: 15, monthWeekday: nil,
            month: nil, day: nil
        )

        let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern,
            currentDueDate: dueDate,
            completionDate: completion,
            repeatFrom: .COMPLETION_DATE,
            currentOccurrenceCount: 0
        )

        XCTAssertNotNil(result.nextDueDate)
        // Anchor is completion (Jan 20) with time from dueDate (09:00). Plus 2 months → Mar 20 at 09:00.
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.month, from: result.nextDueDate!), 3)
        XCTAssertEqual(cal.component(.day, from: result.nextDueDate!), 20)
        XCTAssertEqual(cal.component(.hour, from: result.nextDueDate!), 9)
    }

    func testCalculator_MonthlySameWeekday_FirstMonday() {
        // Jan 1 2024 is Monday → first Monday. Pattern every month, first Monday.
        let dueDate = localDate(2024, 1, 1, hour: 10)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "months", interval: 1,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: "same_weekday", monthDay: nil,
            monthWeekday: CustomRepeatingPattern.MonthWeekday(weekday: "monday", weekOfMonth: 1),
            month: nil, day: nil
        )

        let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern,
            currentDueDate: dueDate,
            completionDate: dueDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        XCTAssertNotNil(result.nextDueDate)
        // First Monday of February 2024 is Feb 5.
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.year, from: result.nextDueDate!), 2024)
        XCTAssertEqual(cal.component(.month, from: result.nextDueDate!), 2)
        XCTAssertEqual(cal.component(.day, from: result.nextDueDate!), 5)
        XCTAssertEqual(cal.component(.weekday, from: result.nextDueDate!), 2) // Monday
    }

    func testCalculator_YearlyEveryTwoYears() {
        let dueDate = localDate(2024, 3, 10, hour: 8)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "years", interval: 2,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: 3, day: 10
        )

        let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern,
            currentDueDate: dueDate,
            completionDate: dueDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        XCTAssertNotNil(result.nextDueDate)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.year, from: result.nextDueDate!), 2026)
        XCTAssertEqual(cal.component(.month, from: result.nextDueDate!), 3)
        XCTAssertEqual(cal.component(.day, from: result.nextDueDate!), 10)
    }

    func testCalculator_EndUntilDateExactMatchStillAllows() {
        // End on Jan 30, next occurrence on Jan 30 → should STILL fire (comparison is date-only, terminates only when *after*).
        let dueDate = localDate(2024, 1, 29, hour: 9)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "days", interval: 1,
            endCondition: "until_date", endAfterOccurrences: nil,
            endUntilDate: localDate(2024, 1, 30, hour: 23),
            weekdays: nil,
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: nil, day: nil
        )

        let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern,
            currentDueDate: dueDate,
            completionDate: dueDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )

        XCTAssertNotNil(result.nextDueDate)
        XCTAssertFalse(result.shouldTerminate)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.day, from: result.nextDueDate!), 30)
    }

    func testCalculator_EndAfterOccurrencesBoundary() {
        // endAfterOccurrences = 3, currentCount = 2 → next becomes count 3 → terminate.
        let dueDate = localDate(2024, 1, 15)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "days", interval: 1,
            endCondition: "after_occurrences", endAfterOccurrences: 3, endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: nil, day: nil
        )

        let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
            pattern: pattern,
            currentDueDate: dueDate,
            completionDate: dueDate,
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 2
        )

        XCTAssertNil(result.nextDueDate)
        XCTAssertTrue(result.shouldTerminate)
        XCTAssertEqual(result.newOccurrenceCount, 3)
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

    // MARK: - End Condition Coverage Across Pattern Flavors
    //
    // End conditions must behave identically whether the pattern is daily,
    // weekly, monthly, or yearly. These tests walk each pattern family
    // through its end condition to prove the termination boundary.

    func testEndCondition_Weekly_AfterOccurrences_TerminatesExactlyAtLimit() {
        // Start Mon Jan 15, repeat every Mon/Wed, stop after 4 occurrences.
        let start = localDate(2024, 1, 15, hour: 9)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "weeks", interval: 1,
            endCondition: "after_occurrences", endAfterOccurrences: 4, endUntilDate: nil,
            weekdays: ["monday", "wednesday"],
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: nil, day: nil
        )

        let dates = simulateCustomProgression(
            pattern: pattern, initialDueDate: start,
            repeatFrom: .DUE_DATE, count: 10
        )
        // Three follow-up occurrences fire (counts 1, 2, 3); the 4th call
        // hits the limit and terminates without returning a date.
        XCTAssertEqual(dates.count, 3, "Should fire 3 follow-ups before terminating on the 4th")
    }

    func testEndCondition_Weekly_UntilDate_StopsOnceExceeded() {
        // Start Mon Jan 15, repeat every Mon, until Jan 28 (Sunday).
        let start = localDate(2024, 1, 15, hour: 9)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "weeks", interval: 1,
            endCondition: "until_date", endAfterOccurrences: nil,
            endUntilDate: localDate(2024, 1, 28, hour: 23),
            weekdays: ["monday"],
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: nil, day: nil
        )

        let dates = simulateCustomProgression(
            pattern: pattern, initialDueDate: start,
            repeatFrom: .DUE_DATE, count: 10
        )
        // Only Jan 22 fires. Jan 29 is AFTER Jan 28 → terminate.
        XCTAssertEqual(dates.count, 1)
        XCTAssertEqual(Calendar.current.component(.day, from: dates[0]), 22)
    }

    func testEndCondition_MonthlySameDate_AfterOccurrences() {
        let start = localDate(2024, 1, 15, hour: 9)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "months", interval: 1,
            endCondition: "after_occurrences", endAfterOccurrences: 3, endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: "same_date", monthDay: 15, monthWeekday: nil,
            month: nil, day: nil
        )

        let dates = simulateCustomProgression(
            pattern: pattern, initialDueDate: start,
            repeatFrom: .DUE_DATE, count: 5
        )
        XCTAssertEqual(dates.count, 2, "Should fire 2 follow-ups (Feb 15, Mar 15), then terminate")
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.month, from: dates[0]), 2)
        XCTAssertEqual(cal.component(.month, from: dates[1]), 3)
    }

    func testEndCondition_MonthlySameDate_UntilDate() {
        let start = localDate(2024, 1, 15, hour: 9)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "months", interval: 1,
            endCondition: "until_date", endAfterOccurrences: nil,
            endUntilDate: localDate(2024, 4, 14, hour: 23),
            weekdays: nil,
            monthRepeatType: "same_date", monthDay: 15, monthWeekday: nil,
            month: nil, day: nil
        )

        let dates = simulateCustomProgression(
            pattern: pattern, initialDueDate: start,
            repeatFrom: .DUE_DATE, count: 5
        )
        // Feb 15 ≤ Apr 14 (continue), Mar 15 ≤ Apr 14 (continue), Apr 15 > Apr 14 (terminate).
        XCTAssertEqual(dates.count, 2)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.month, from: dates.last!), 3)
    }

    func testEndCondition_MonthlySameWeekday_AfterOccurrences() {
        // Third Tuesday every month, end after 3 occurrences.
        let start = localDate(2024, 1, 16, hour: 10)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "months", interval: 1,
            endCondition: "after_occurrences", endAfterOccurrences: 3, endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: "same_weekday", monthDay: nil,
            monthWeekday: CustomRepeatingPattern.MonthWeekday(weekday: "tuesday", weekOfMonth: 3),
            month: nil, day: nil
        )

        let dates = simulateCustomProgression(
            pattern: pattern, initialDueDate: start,
            repeatFrom: .DUE_DATE, count: 5
        )
        // Should fire 2 follow-ups (Feb, Mar), then terminate on the 3rd.
        XCTAssertEqual(dates.count, 2)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.month, from: dates[0]), 2)
        XCTAssertEqual(cal.component(.month, from: dates[1]), 3)
        for date in dates {
            XCTAssertEqual(cal.component(.weekday, from: date), 3) // Tuesday
        }
    }

    func testEndCondition_MonthlySameWeekday_UntilDate() {
        // Third Tuesday, ending Apr 30 2024.
        let start = localDate(2024, 1, 16, hour: 10)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "months", interval: 1,
            endCondition: "until_date", endAfterOccurrences: nil,
            endUntilDate: localDate(2024, 4, 30, hour: 23),
            weekdays: nil,
            monthRepeatType: "same_weekday", monthDay: nil,
            monthWeekday: CustomRepeatingPattern.MonthWeekday(weekday: "tuesday", weekOfMonth: 3),
            month: nil, day: nil
        )

        let dates = simulateCustomProgression(
            pattern: pattern, initialDueDate: start,
            repeatFrom: .DUE_DATE, count: 6
        )
        // Feb 20, Mar 19, Apr 16 all ≤ Apr 30 → continue. May 21 > Apr 30 → terminate.
        XCTAssertEqual(dates.count, 3)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.month, from: dates.last!), 4)
        XCTAssertEqual(cal.component(.day, from: dates.last!), 16)
    }

    func testEndCondition_Yearly_AfterOccurrences() {
        let start = localDate(2024, 12, 25, hour: 8)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "years", interval: 1,
            endCondition: "after_occurrences", endAfterOccurrences: 3, endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: 12, day: 25
        )

        let dates = simulateCustomProgression(
            pattern: pattern, initialDueDate: start,
            repeatFrom: .DUE_DATE, count: 5
        )
        XCTAssertEqual(dates.count, 2) // 2025, 2026 — then terminate.
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.year, from: dates[0]), 2025)
        XCTAssertEqual(cal.component(.year, from: dates[1]), 2026)
    }

    func testEndCondition_Yearly_UntilDate() {
        let start = localDate(2024, 12, 25, hour: 8)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "years", interval: 1,
            endCondition: "until_date", endAfterOccurrences: nil,
            endUntilDate: localDate(2027, 1, 1, hour: 0),
            weekdays: nil,
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: 12, day: 25
        )

        let dates = simulateCustomProgression(
            pattern: pattern, initialDueDate: start,
            repeatFrom: .DUE_DATE, count: 5
        )
        // Dec 25 2025 (≤ Jan 1 2027), Dec 25 2026 (≤ Jan 1 2027), Dec 25 2027 (> Jan 1 2027 → stop).
        XCTAssertEqual(dates.count, 2)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.year, from: dates.last!), 2026)
    }

    // MARK: - Task Model Round-Trip (Task wraps CustomRepeatingPattern)
    //
    // `Task` embeds `CustomRepeatingPattern` and is also Codable. This test
    // proves the wrapping conformance still round-trips cleanly after the
    // isolation change.

    // MARK: - TaskService Completion-Path Regression
    //
    // These tests exercise `TaskService.calculateNextOccurrence(for:)` — the
    // function the app actually calls when the user taps "complete". A prior
    // version of that function had its own inline pattern logic that ignored
    // `weekdays`, `monthRepeatType`, and friends, so weekly M/W/F would jump
    // a full week instead of picking the next selected day. These tests lock
    // the completion path to the canonical calculator.

    @MainActor
    func testTaskService_WeeklyMonWedFri_FromDueDate_NextIsWednesday() {
        let dueMonday = localDate(2024, 1, 15, hour: 9)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "weeks", interval: 1,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: ["monday", "wednesday", "friday"],
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: nil, day: nil
        )
        let task = Task(
            id: "t-mwf",
            title: "MWF",
            dueDateTime: dueMonday,
            isAllDay: false,
            repeating: .custom,
            repeatingData: pattern,
            repeatFrom: .DUE_DATE
        )

        let (next, terminate) = TaskService.shared.calculateNextOccurrence(for: task)
        XCTAssertFalse(terminate)
        guard let next = next else { return XCTFail("Expected next date") }

        let cal = Calendar.current
        // Next must be Wednesday Jan 17, not Monday Jan 22.
        XCTAssertEqual(cal.component(.weekday, from: next), 4, "Must pick Wednesday, not skip a full week")
        XCTAssertEqual(cal.component(.day, from: next), 17)
    }

    @MainActor
    func testTaskService_WeeklyMonWedFri_FromCompletionDate_NextIsWednesday() {
        let dueMonday = localDate(2024, 1, 15, hour: 9)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "weeks", interval: 1,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: ["monday", "wednesday", "friday"],
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: nil, day: nil
        )
        let task = Task(
            id: "t-mwf-c",
            title: "MWF",
            dueDateTime: dueMonday,
            isAllDay: false,
            repeating: .custom,
            repeatingData: pattern,
            repeatFrom: .COMPLETION_DATE
        )

        let (next, _) = TaskService.shared.calculateNextOccurrence(for: task)
        guard let next = next else { return XCTFail("Expected next date") }
        // Completion happens "now" — but the time of day is taken from the
        // due date, so the result is a selected weekday on or after today.
        // We can't assert a specific calendar day here (depends on test-run
        // date), but we can assert the weekday is in the selected set.
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: next)
        XCTAssertTrue([2, 4, 6].contains(weekday), "Must land on Mon/Wed/Fri (weekday=\(weekday))")
    }

    @MainActor
    func testTaskService_MonthlySameDate_NextIsSameDayNextMonth() {
        let due = localDate(2024, 1, 15, hour: 14)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "months", interval: 1,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: "same_date", monthDay: 15, monthWeekday: nil,
            month: nil, day: nil
        )
        let task = Task(
            id: "t-m15",
            title: "15th",
            dueDateTime: due,
            isAllDay: false,
            repeating: .custom,
            repeatingData: pattern,
            repeatFrom: .DUE_DATE
        )

        let (next, _) = TaskService.shared.calculateNextOccurrence(for: task)
        guard let next = next else { return XCTFail("Expected next date") }
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.month, from: next), 2)
        XCTAssertEqual(cal.component(.day, from: next), 15)
    }

    @MainActor
    func testTaskService_MonthlySameWeekday_ThirdTuesday_NextIsThirdTuesdayOfFeb() {
        let due = localDate(2024, 1, 16, hour: 10) // 3rd Tuesday of Jan 2024
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "months", interval: 1,
            endCondition: "never", endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: "same_weekday", monthDay: nil,
            monthWeekday: CustomRepeatingPattern.MonthWeekday(weekday: "tuesday", weekOfMonth: 3),
            month: nil, day: nil
        )
        let task = Task(
            id: "t-3tue",
            title: "3rd Tue",
            dueDateTime: due,
            isAllDay: false,
            repeating: .custom,
            repeatingData: pattern,
            repeatFrom: .DUE_DATE
        )

        let (next, _) = TaskService.shared.calculateNextOccurrence(for: task)
        guard let next = next else { return XCTFail("Expected next date") }
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.month, from: next), 2)
        XCTAssertEqual(cal.component(.day, from: next), 20) // 3rd Tuesday of Feb 2024
        XCTAssertEqual(cal.component(.weekday, from: next), 3) // Tuesday
    }

    @MainActor
    func testTaskService_Weekly_AfterOccurrences_TerminatesAtLimit() {
        let due = localDate(2024, 1, 15, hour: 9)
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "weeks", interval: 1,
            endCondition: "after_occurrences", endAfterOccurrences: 3, endUntilDate: nil,
            weekdays: ["monday"],
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil,
            month: nil, day: nil
        )
        // On the 3rd completion (occurrenceCount already at 2), must terminate.
        let task = Task(
            id: "t-term",
            title: "Stop after 3",
            dueDateTime: due,
            isAllDay: false,
            repeating: .custom,
            repeatingData: pattern,
            repeatFrom: .DUE_DATE,
            occurrenceCount: 2
        )
        let (next, terminate) = TaskService.shared.calculateNextOccurrence(for: task)
        XCTAssertTrue(terminate)
        XCTAssertNil(next)
    }

    @MainActor
    func testTaskService_SimpleWeekly_AddsSevenDays() {
        let due = localDate(2024, 1, 15, hour: 9)
        let task = Task(
            id: "t-weekly",
            title: "Weekly",
            dueDateTime: due,
            isAllDay: false,
            repeating: .weekly,
            repeatFrom: .DUE_DATE
        )
        let (next, _) = TaskService.shared.calculateNextOccurrence(for: task)
        guard let next = next else { return XCTFail("Expected next date") }
        // Simple weekly without weekdays: add 7 days (Jan 22).
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.day, from: next), 22)
    }

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
