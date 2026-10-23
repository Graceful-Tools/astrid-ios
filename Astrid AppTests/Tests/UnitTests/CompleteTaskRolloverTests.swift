//  CompleteTaskRolloverTests.swift
//  Completing a repeating task through `TaskService.completeTask` — the call the complete button
//  makes — rolls it to the occurrence astrid-core picks (AITD-532). These replace tests that asked
//  `TaskService.calculateNextOccurrence`, a wrapper no production code called: the app's path is
//  `completeTask` → `CoreCommand.completeTask`, and that is what is driven here, against the unit
//  host's in-memory core. The pattern math itself is astrid-core's, pinned by its contract
//  fixtures (ASTRID.md §0 rule 4); these only prove the Swift face reaches it with the task's
//  edited fields (rule 3) and shows the rolled task.

import XCTest
@testable import Astrid_App

@MainActor
final class CompleteTaskRolloverTests: XCTestCase {
    private var service: TaskService { TaskService.shared }

    private func localDate(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func pattern(
        unit: String, weekdays: [String]? = nil, monthRepeatType: String? = nil,
        monthDay: Int? = nil, monthWeekday: CustomRepeatingPattern.MonthWeekday? = nil,
        endCondition: String = "never", endAfterOccurrences: Int? = nil
    ) -> CustomRepeatingPattern {
        CustomRepeatingPattern(
            type: "custom", unit: unit, interval: 1,
            endCondition: endCondition, endAfterOccurrences: endAfterOccurrences, endUntilDate: nil,
            weekdays: weekdays, monthRepeatType: monthRepeatType, monthDay: monthDay,
            monthWeekday: monthWeekday, month: nil, day: nil)
    }

    /// Makes a timed repeating task, then completes it the way an editable view does: with the
    /// edited fields copied into the `task:` argument.
    private func complete(
        due: Date, repeating: String, pattern: CustomRepeatingPattern? = nil,
        repeatFrom: Task.RepeatFromMode, occurrenceCount: Int? = nil
    ) async throws -> Task {
        var made = try await service.createTask(
            listIds: [], title: "Repeats \(UUID().uuidString)", whenDate: due, whenTime: due,
            repeating: repeating, repeatingData: pattern)
        made.repeatFrom = repeatFrom
        if let occurrenceCount { made.occurrenceCount = occurrenceCount }
        return try await service.completeTask(
            id: made.id, completed: true, task: made)
    }

    /// Weekly Mon/Wed/Fri from the due date goes Monday → Wednesday, not a full week on. An older
    /// completion path ignored `weekdays` and did exactly that.
    func testWeeklyMonWedFriFromDueDateRollsToWednesday_AITD532() async throws {
        let rolled = try await complete(
            due: localDate(2024, 1, 15, hour: 9), repeating: "custom",
            pattern: pattern(unit: "weeks", weekdays: ["monday", "wednesday", "friday"]),
            repeatFrom: .DUE_DATE)

        XCTAssertFalse(rolled.completed, "a repeating task rolls on rather than closing")
        XCTAssertEqual(rolled.dueDateTime, localDate(2024, 1, 17, hour: 9))
        XCTAssertEqual(service.tasksById[rolled.id]?.dueDateTime, localDate(2024, 1, 17, hour: 9),
                       "the row the list draws shows the next occurrence")
    }

    /// From the completion date the series restarts from now — the core reads the clock, not the
    /// `completedAt` stamp — so the Monday occurrence of January 2024 rolls to the next Mon/Wed/Fri
    /// after today. From the due date it would be Wednesday 17 January 2024, so this tells the two
    /// modes apart.
    func testWeeklyMonWedFriFromCompletionDateRollsFromNow_AITD532() async throws {
        let before = Date()
        let rolled = try await complete(
            due: localDate(2024, 1, 15, hour: 9), repeating: "custom",
            pattern: pattern(unit: "weeks", weekdays: ["monday", "wednesday", "friday"]),
            repeatFrom: .COMPLETION_DATE)

        let next = try XCTUnwrap(rolled.dueDateTime)
        let cal = Calendar.current
        XCTAssertGreaterThan(next, before)
        XCTAssertLessThanOrEqual(next.timeIntervalSince(before), 3 * 86_400 + 3_600,
                                 "the next selected weekday is at most three days on")
        XCTAssertTrue([2, 4, 6].contains(cal.component(.weekday, from: next)), "a Mon, Wed or Fri")
        XCTAssertEqual(cal.component(.hour, from: next), 9, "the time of day is kept")
    }

    func testMonthlySameDateRollsToTheSameDayNextMonth_AITD532() async throws {
        let rolled = try await complete(
            due: localDate(2024, 1, 15, hour: 14), repeating: "custom",
            pattern: pattern(unit: "months", monthRepeatType: "same_date", monthDay: 15),
            repeatFrom: .DUE_DATE)

        XCTAssertEqual(rolled.dueDateTime, localDate(2024, 2, 15, hour: 14))
    }

    /// The day is the third Tuesday; the time of day is dropped to midnight on the local clock —
    /// web's D3 (`types/repeating.ts` nextMonthOccurrence), which the core follows.
    func testMonthlyThirdTuesdayRollsToTheThirdTuesdayOfFebruary_AITD532() async throws {
        let rolled = try await complete(
            due: localDate(2024, 1, 16, hour: 10), repeating: "custom",
            pattern: pattern(
                unit: "months", monthRepeatType: "same_weekday",
                monthWeekday: CustomRepeatingPattern.MonthWeekday(weekday: "tuesday", weekOfMonth: 3)),
            repeatFrom: .DUE_DATE)

        XCTAssertEqual(rolled.dueDateTime, localDate(2024, 2, 20, hour: 0))
    }

    /// The third completion of a stop-after-3 series closes the task instead of rolling it.
    func testTheLastOccurrenceOfAnEndingSeriesCompletesTheTask_AITD532() async throws {
        let due = localDate(2024, 1, 15, hour: 9)
        let ended = try await complete(
            due: due, repeating: "custom",
            pattern: pattern(
                unit: "weeks", weekdays: ["monday"],
                endCondition: "after_occurrences", endAfterOccurrences: 3),
            repeatFrom: .DUE_DATE, occurrenceCount: 2)

        XCTAssertTrue(ended.completed)
        XCTAssertEqual(ended.dueDateTime, due, "the series ends where it stands")
    }

    func testSimpleWeeklyRollsSevenDays_AITD532() async throws {
        let rolled = try await complete(
            due: localDate(2024, 1, 15, hour: 9), repeating: "weekly", repeatFrom: .DUE_DATE)

        XCTAssertEqual(rolled.dueDateTime, localDate(2024, 1, 22, hour: 9))
    }
}
