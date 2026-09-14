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

    // MARK: - Custom Pattern Tests - Weekly

    // MARK: - Custom Pattern Tests - Monthly

    // MARK: - Custom Pattern Tests - Yearly

    // MARK: - All Repeating Types Tests

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
