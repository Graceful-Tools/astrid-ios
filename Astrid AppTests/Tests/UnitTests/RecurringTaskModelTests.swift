import XCTest
@testable import Astrid_App

/// Unit tests for recurring task model functionality
/// Tests task model properties for repeating tasks, patterns, and end conditions
/// Note: Calculator logic is tested in RepeatingTaskCalculatorTests
final class RecurringTaskModelTests: XCTestCase {

    // MARK: - Basic Repeating Task Tests

    func testNonRepeatingTask() {
        // Given: A task that doesn't repeat
        let task = TestHelpers.createTestTask(repeating: nil)

        // Then: Repeating should be nil
        XCTAssertNil(task.repeating)
    }

    func testNeverRepeatingTask() {
        // Given: A task explicitly set to never repeat
        let task = TestHelpers.createTestTask(repeating: .never)

        // Then: Repeating should be never
        XCTAssertEqual(task.repeating, .never)
        XCTAssertEqual(task.repeating?.rawValue, "never")
        XCTAssertEqual(task.repeating?.displayName, NSLocalizedString("repeating.one_time_only", comment: ""))
    }

    func testDailyRepeatingTask() {
        // Given: A daily repeating task
        let task = TestHelpers.createRepeatingTask(repeating: .daily)

        // Then: Repeating should be daily
        XCTAssertEqual(task.repeating, .daily)
        XCTAssertEqual(task.repeating?.rawValue, "daily")
        XCTAssertEqual(task.repeating?.displayName, "Daily")
    }

    func testWeeklyRepeatingTask() {
        // Given: A weekly repeating task
        let task = TestHelpers.createRepeatingTask(repeating: .weekly)

        // Then: Repeating should be weekly
        XCTAssertEqual(task.repeating, .weekly)
        XCTAssertEqual(task.repeating?.rawValue, "weekly")
        XCTAssertEqual(task.repeating?.displayName, "Weekly")
    }

    func testMonthlyRepeatingTask() {
        // Given: A monthly repeating task
        let task = TestHelpers.createRepeatingTask(repeating: .monthly)

        // Then: Repeating should be monthly
        XCTAssertEqual(task.repeating, .monthly)
        XCTAssertEqual(task.repeating?.rawValue, "monthly")
        XCTAssertEqual(task.repeating?.displayName, "Monthly")
    }

    func testYearlyRepeatingTask() {
        // Given: A yearly repeating task
        let task = TestHelpers.createRepeatingTask(repeating: .yearly)

        // Then: Repeating should be yearly
        XCTAssertEqual(task.repeating, .yearly)
        XCTAssertEqual(task.repeating?.rawValue, "yearly")
        XCTAssertEqual(task.repeating?.displayName, "Yearly")
    }

    func testCustomRepeatingTask() {
        // Given: A custom repeating task
        let pattern = TestHelpers.createDailyPattern(interval: 3)
        let task = TestHelpers.createCustomRepeatingTask(pattern: pattern)

        // Then: Repeating should be custom with pattern
        XCTAssertEqual(task.repeating, .custom)
        XCTAssertEqual(task.repeating?.displayName, "Custom")
        XCTAssertNotNil(task.repeatingData)
        XCTAssertEqual(task.repeatingData?.interval, 3)
    }

    // MARK: - Repeat From Mode Tests

    func testRepeatFromDueDate() {
        // Given: A task that repeats from due date
        let task = TestHelpers.createRepeatingTask(
            repeating: .daily,
            repeatFrom: .DUE_DATE
        )

        // Then: Repeat from should be due date
        XCTAssertEqual(task.repeatFrom, .DUE_DATE)
        XCTAssertEqual(task.repeatFrom?.rawValue, "DUE_DATE")
        XCTAssertEqual(task.repeatFrom?.displayName, "Repeat from due date")
    }

    func testRepeatFromCompletionDate() {
        // Given: A task that repeats from completion date
        let task = TestHelpers.createRepeatingTask(
            repeating: .daily,
            repeatFrom: .COMPLETION_DATE
        )

        // Then: Repeat from should be completion date
        XCTAssertEqual(task.repeatFrom, .COMPLETION_DATE)
        XCTAssertEqual(task.repeatFrom?.rawValue, "COMPLETION_DATE")
        XCTAssertEqual(task.repeatFrom?.displayName, "Repeat from completion date")
    }

    // MARK: - Occurrence Count Tests

    func testNewRepeatingTaskOccurrenceCount() {
        // Given: A new repeating task
        let task = TestHelpers.createRepeatingTask(occurrenceCount: 0)

        // Then: Occurrence count should be 0
        XCTAssertEqual(task.occurrenceCount, 0)
    }

    func testRepeatingTaskWithOccurrences() {
        // Given: A repeating task that has occurred multiple times
        let task = TestHelpers.createRepeatingTask(occurrenceCount: 5)

        // Then: Occurrence count should be 5
        XCTAssertEqual(task.occurrenceCount, 5)
    }

    // MARK: - Custom Pattern Tests - Daily

    func testCustomDailyPattern() {
        // Given: A custom daily pattern (every 3 days)
        let pattern = TestHelpers.createDailyPattern(interval: 3)

        // Then: Pattern should have correct properties
        XCTAssertEqual(pattern.type, "custom")
        XCTAssertEqual(pattern.unit, "days")
        XCTAssertEqual(pattern.interval, 3)
        XCTAssertEqual(pattern.endCondition, "never")
    }

    func testCustomDailyPatternEndAfterOccurrences() {
        // Given: A daily pattern that ends after 10 occurrences
        let pattern = TestHelpers.createDailyPattern(
            interval: 1,
            endCondition: "after_occurrences",
            endAfterOccurrences: 10
        )

        // Then: End condition should be set
        XCTAssertEqual(pattern.endCondition, "after_occurrences")
        XCTAssertEqual(pattern.endAfterOccurrences, 10)
    }

    func testCustomDailyPatternEndUntilDate() {
        // Given: A daily pattern that ends on a specific date
        let endDate = TestHelpers.createDate(year: 2024, month: 12, day: 31)
        let pattern = TestHelpers.createDailyPattern(
            interval: 1,
            endCondition: "until_date",
            endUntilDate: endDate
        )

        // Then: End date should be set
        XCTAssertEqual(pattern.endCondition, "until_date")
        XCTAssertNotNil(pattern.endUntilDate)
    }

    // MARK: - Custom Pattern Tests - Weekly

    func testCustomWeeklyPattern() {
        // Given: A custom weekly pattern (M/W/F)
        let pattern = TestHelpers.createWeeklyPattern(weekdays: ["monday", "wednesday", "friday"])

        // Then: Pattern should have weekdays
        XCTAssertEqual(pattern.unit, "weeks")
        XCTAssertEqual(pattern.interval, 1)
        XCTAssertEqual(pattern.weekdays?.count, 3)
        XCTAssertTrue(pattern.weekdays?.contains("monday") ?? false)
        XCTAssertTrue(pattern.weekdays?.contains("wednesday") ?? false)
        XCTAssertTrue(pattern.weekdays?.contains("friday") ?? false)
    }

    func testCustomWeeklyPatternEveryOtherWeek() {
        // Given: A bi-weekly pattern (every 2 weeks)
        let pattern = TestHelpers.createWeeklyPattern(
            interval: 2,
            weekdays: ["monday"]
        )

        // Then: Interval should be 2
        XCTAssertEqual(pattern.interval, 2)
        XCTAssertEqual(pattern.weekdays, ["monday"])
    }

    func testCustomWeeklyPatternWeekends() {
        // Given: A weekend pattern
        let pattern = TestHelpers.createWeeklyPattern(
            weekdays: ["saturday", "sunday"]
        )

        // Then: Should have weekend days
        XCTAssertEqual(pattern.weekdays?.count, 2)
        XCTAssertTrue(pattern.weekdays?.contains("saturday") ?? false)
        XCTAssertTrue(pattern.weekdays?.contains("sunday") ?? false)
    }

    func testCustomWeeklyPatternWeekdays() {
        // Given: A weekdays pattern (Mon-Fri)
        let pattern = TestHelpers.createWeeklyPattern(
            weekdays: ["monday", "tuesday", "wednesday", "thursday", "friday"]
        )

        // Then: Should have all weekdays
        XCTAssertEqual(pattern.weekdays?.count, 5)
        XCTAssertFalse(pattern.weekdays?.contains("saturday") ?? true)
        XCTAssertFalse(pattern.weekdays?.contains("sunday") ?? true)
    }

    // MARK: - Custom Pattern Tests - Monthly

    func testCustomMonthlySameDatePattern() {
        // Given: A monthly pattern on the same date
        let pattern = TestHelpers.createMonthlySameDatePattern(interval: 1)

        // Then: Pattern should be same_date
        XCTAssertEqual(pattern.unit, "months")
        XCTAssertEqual(pattern.monthRepeatType, "same_date")
        XCTAssertNil(pattern.monthWeekday)
    }

    func testCustomMonthlySameWeekdayPattern() {
        // Given: A monthly pattern on same weekday (2nd Tuesday)
        let pattern = TestHelpers.createMonthlySameWeekdayPattern(
            weekday: "tuesday",
            weekOfMonth: 2
        )

        // Then: Pattern should be same_weekday
        XCTAssertEqual(pattern.unit, "months")
        XCTAssertEqual(pattern.monthRepeatType, "same_weekday")
        XCTAssertNotNil(pattern.monthWeekday)
        XCTAssertEqual(pattern.monthWeekday?.weekday, "tuesday")
        XCTAssertEqual(pattern.monthWeekday?.weekOfMonth, 2)
    }

    func testCustomMonthlyLastWeekdayPattern() {
        // Given: A monthly pattern on last Friday
        let pattern = TestHelpers.createMonthlySameWeekdayPattern(
            weekday: "friday",
            weekOfMonth: 5  // 5 typically means "last"
        )

        // Then: Pattern should be last weekday
        XCTAssertEqual(pattern.monthWeekday?.weekday, "friday")
        XCTAssertEqual(pattern.monthWeekday?.weekOfMonth, 5)
    }

    func testCustomMonthlyBiMonthly() {
        // Given: A bi-monthly pattern (every 2 months)
        let pattern = TestHelpers.createMonthlySameDatePattern(interval: 2)

        // Then: Interval should be 2
        XCTAssertEqual(pattern.interval, 2)
    }

    func testCustomMonthlyQuarterly() {
        // Given: A quarterly pattern (every 3 months)
        let pattern = TestHelpers.createMonthlySameDatePattern(interval: 3)

        // Then: Interval should be 3
        XCTAssertEqual(pattern.interval, 3)
    }

    // MARK: - Custom Pattern Tests - Yearly

    func testCustomYearlyPattern() {
        // Given: A yearly pattern (Christmas)
        let pattern = TestHelpers.createYearlyPattern(month: 12, day: 25)

        // Then: Pattern should have month and day
        XCTAssertEqual(pattern.unit, "years")
        XCTAssertEqual(pattern.month, 12)
        XCTAssertEqual(pattern.day, 25)
    }

    func testCustomYearlyPatternNewYear() {
        // Given: A yearly pattern (New Year's Day)
        let pattern = TestHelpers.createYearlyPattern(month: 1, day: 1)

        // Then: Should be January 1st
        XCTAssertEqual(pattern.month, 1)
        XCTAssertEqual(pattern.day, 1)
    }

    func testCustomYearlyPatternBiennial() {
        // Given: A bi-annual pattern (every 2 years)
        let pattern = TestHelpers.createYearlyPattern(interval: 2, month: 6, day: 15)

        // Then: Interval should be 2
        XCTAssertEqual(pattern.interval, 2)
    }

    // MARK: - All Repeating Types Tests

    func testAllRepeatingCases() {
        // Then: All cases should be present
        XCTAssertEqual(Task.Repeating.allCases.count, 6)
        XCTAssertTrue(Task.Repeating.allCases.contains(.never))
        XCTAssertTrue(Task.Repeating.allCases.contains(.daily))
        XCTAssertTrue(Task.Repeating.allCases.contains(.weekly))
        XCTAssertTrue(Task.Repeating.allCases.contains(.monthly))
        XCTAssertTrue(Task.Repeating.allCases.contains(.yearly))
        XCTAssertTrue(Task.Repeating.allCases.contains(.custom))
    }

    func testAllRepeatFromModeCases() {
        // Then: Both modes should be present
        XCTAssertEqual(Task.RepeatFromMode.allCases.count, 2)
        XCTAssertTrue(Task.RepeatFromMode.allCases.contains(.DUE_DATE))
        XCTAssertTrue(Task.RepeatFromMode.allCases.contains(.COMPLETION_DATE))
    }

    // MARK: - Complete Workflow Tests

    func testCreateDailyHabitWorkflow() {
        // Simulates: User creates a daily habit task

        // Create daily repeating task
        let dueDate = TestHelpers.createDate(year: 2024, month: 6, day: 15, hour: 7, minute: 0)
        let task = TestHelpers.createRepeatingTask(
            title: "Morning Exercise",
            repeating: .daily,
            repeatFrom: .COMPLETION_DATE,
            dueDateTime: dueDate,
            occurrenceCount: 0
        )

        // Verify workflow
        XCTAssertEqual(task.title, "Morning Exercise")
        XCTAssertEqual(task.repeating, .daily)
        XCTAssertEqual(task.repeatFrom, .COMPLETION_DATE)
        XCTAssertFalse(task.completed)
        XCTAssertEqual(task.occurrenceCount, 0)
    }

    func testCreateWeeklyMeetingWorkflow() {
        // Simulates: User creates a weekly meeting task

        // Create weekly pattern for every Monday
        let pattern = TestHelpers.createWeeklyPattern(weekdays: ["monday"])
        let dueDate = TestHelpers.createDate(year: 2024, month: 6, day: 17, hour: 10, minute: 0)  // Monday

        let task = TestHelpers.createCustomRepeatingTask(
            title: "Weekly Team Standup",
            pattern: pattern,
            repeatFrom: .DUE_DATE,
            dueDateTime: dueDate
        )

        // Verify workflow
        XCTAssertEqual(task.title, "Weekly Team Standup")
        XCTAssertEqual(task.repeating, .custom)
        XCTAssertEqual(task.repeatingData?.weekdays?.first, "monday")
        XCTAssertEqual(task.repeatFrom, .DUE_DATE)
    }

    func testCreateMonthlyBillWorkflow() {
        // Simulates: User creates a monthly bill reminder

        // Create monthly pattern for same date
        let pattern = TestHelpers.createMonthlySameDatePattern(interval: 1)
        let dueDate = TestHelpers.createDate(year: 2024, month: 6, day: 15, hour: 9, minute: 0)

        let task = TestHelpers.createCustomRepeatingTask(
            title: "Pay Rent",
            pattern: pattern,
            repeatFrom: .DUE_DATE,
            dueDateTime: dueDate
        )

        // Verify workflow
        XCTAssertEqual(task.title, "Pay Rent")
        XCTAssertEqual(task.repeating, .custom)
        XCTAssertEqual(task.repeatingData?.monthRepeatType, "same_date")

        // Verify due date is 15th
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.day, from: task.dueDateTime!), 15)
    }

    func testCreateAnniversaryWorkflow() {
        // Simulates: User creates a yearly anniversary reminder

        // Create yearly pattern
        let pattern = TestHelpers.createYearlyPattern(month: 7, day: 4)  // July 4th
        let dueDate = TestHelpers.createDate(year: 2024, month: 7, day: 4, hour: 9, minute: 0)

        let task = TestHelpers.createCustomRepeatingTask(
            title: "Independence Day",
            pattern: pattern,
            dueDateTime: dueDate
        )

        // Verify workflow
        XCTAssertEqual(task.title, "Independence Day")
        XCTAssertEqual(task.repeatingData?.month, 7)
        XCTAssertEqual(task.repeatingData?.day, 4)
    }

    func testCreateLimitedRepeatWorkflow() {
        // Simulates: User creates a task that repeats 5 times

        let pattern = TestHelpers.createDailyPattern(
            interval: 1,
            endCondition: "after_occurrences",
            endAfterOccurrences: 5
        )
        let dueDate = TestHelpers.createRelativeDate(daysFromNow: 1)

        let task = TestHelpers.createCustomRepeatingTask(
            title: "5-Day Challenge",
            pattern: pattern,
            dueDateTime: dueDate,
            occurrenceCount: 0
        )

        // Verify workflow
        XCTAssertEqual(task.title, "5-Day Challenge")
        XCTAssertEqual(task.repeatingData?.endCondition, "after_occurrences")
        XCTAssertEqual(task.repeatingData?.endAfterOccurrences, 5)
        XCTAssertEqual(task.occurrenceCount, 0)
    }

    // MARK: - Pattern Equality Tests

    @MainActor func testCustomPatternEquality() {
        // Given: Two identical patterns
        let pattern1 = TestHelpers.createDailyPattern(interval: 3)
        let pattern2 = TestHelpers.createDailyPattern(interval: 3)

        // Then: Should be equal
        XCTAssertEqual(pattern1, pattern2)
    }

    @MainActor func testCustomPatternInequality() {
        // Given: Two different patterns
        let pattern1 = TestHelpers.createDailyPattern(interval: 3)
        let pattern2 = TestHelpers.createDailyPattern(interval: 5)

        // Then: Should not be equal
        XCTAssertNotEqual(pattern1, pattern2)
    }

    // MARK: - Edge Cases

    func testRepeatingTaskWithNilDueDate() {
        // Given: A repeating task without due date
        // (Not typical, but the model should handle it)
        let task = TestHelpers.createRepeatingTask(
            repeating: .daily,
            dueDateTime: Date()  // Must provide date for repeating
        )

        // Then: Task should have repeating set
        XCTAssertEqual(task.repeating, .daily)
        XCTAssertNotNil(task.dueDateTime)
    }

    func testRepeatingTaskWithPriority() {
        // Given: A repeating high-priority task
        let task = TestHelpers.createTestTask(
            title: "Daily Standup",
            priority: .high,
            dueDateTime: Date(),
            repeating: .daily,
            repeatFrom: .DUE_DATE
        )

        // Then: Both priority and repeating should be set
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.repeating, .daily)
    }

    func testRepeatingTaskWithReminder() {
        // Given: A repeating task with reminder
        let dueDate = TestHelpers.createRelativeDate(daysFromNow: 1)
        let reminderTime = dueDate.addingTimeInterval(-3600)

        let task = TestHelpers.createTestTask(
            title: "Weekly Review",
            dueDateTime: dueDate,
            repeating: .weekly,
            repeatFrom: .DUE_DATE,
            reminderTime: reminderTime,
            reminderType: .push
        )

        // Then: Both repeating and reminder should be set
        XCTAssertEqual(task.repeating, .weekly)
        XCTAssertNotNil(task.reminderTime)
        XCTAssertEqual(task.reminderType, .push)
    }

    func testRepeatingTaskInSharedList() {
        // Given: A repeating task in a shared list with assignment
        let assignee = TestHelpers.createTestUser(id: "team-member", name: "Team Member")
        let sharedList = TestHelpers.createTestList(id: "shared-list", privacy: .SHARED)

        let task = TestHelpers.createTestTask(
            title: "Weekly Report",
            dueDateTime: Date(),
            repeating: .weekly,
            assigneeId: assignee.id,
            assignee: assignee,
            listIds: [sharedList.id],
            lists: [sharedList]
        )

        // Then: Task should have all properties set
        XCTAssertEqual(task.repeating, .weekly)
        XCTAssertEqual(task.assigneeId, "team-member")
        XCTAssertEqual(task.lists?.first?.privacy, .SHARED)
    }
}
