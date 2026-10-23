import XCTest
import EventKit
@testable import Astrid_App

/// Unit tests for Apple Reminders sync functionality
/// Tests priority mapping, recurrence mapping, and sync models
final class AppleRemindersSyncTests: XCTestCase {

    // MARK: - Priority Mapping

    /// Astrid → Apple, one row per priority (Apple: 0 none, 1 high … 9 low), and back again.
    @MainActor
    func testMapPriorityToAppleAndBack() {
        let service = AppleRemindersService.shared
        let cases: [(astrid: Task.Priority, apple: Int)] = [(.none, 0), (.low, 9), (.medium, 5), (.high, 1)]
        XCTAssertEqual(cases.map(\.astrid), Task.Priority.allCases, "every priority has a row")
        for (astrid, apple) in cases {
            XCTAssertEqual(service.mapPriorityToApple(astrid), apple, "\(astrid)")
            XCTAssertEqual(service.mapPriorityFromApple(apple), astrid, "round trip of \(astrid)")
        }
    }

    /// Apple → Astrid over Apple's whole 0–9 range: 1–4 high, 5 medium, 6–9 low.
    @MainActor
    func testMapPriorityFromApple() {
        let service = AppleRemindersService.shared
        let expected: [Task.Priority] = [.none, .high, .high, .high, .high, .medium, .low, .low, .low, .low]
        for (apple, astrid) in expected.enumerated() {
            XCTAssertEqual(service.mapPriorityFromApple(apple), astrid, "Apple priority \(apple)")
        }
    }

    // MARK: - Due Date Mapping Tests

    @MainActor
    func testMapDueDateFromApple_NilComponents() {
        let service = AppleRemindersService.shared
        let (date, isAllDay) = service.mapDueDateFromApple(nil)
        XCTAssertNil(date)
        XCTAssertTrue(isAllDay)
    }

    @MainActor
    func testMapDueDateFromApple_AllDayDate() {
        let service = AppleRemindersService.shared
        // All-day: only year, month, day - no hour/minute
        var components = DateComponents()
        components.year = 2025
        components.month = 6
        components.day = 15

        let (date, isAllDay) = service.mapDueDateFromApple(components)
        XCTAssertTrue(isAllDay)
        // An all-day due lives at UTC midnight of that day, whatever the device's zone (AITD-536)
        XCTAssertEqual(date.map { ISO8601DateFormatter().string(from: $0) }, "2025-06-15T00:00:00Z")
    }

    @MainActor
    func testMapDueDateFromApple_TimedDate() {
        let service = AppleRemindersService.shared
        // Timed: includes hour and minute
        var components = DateComponents()
        components.year = 2025
        components.month = 6
        components.day = 15
        components.hour = 14
        components.minute = 30

        let (date, isAllDay) = service.mapDueDateFromApple(components)
        XCTAssertFalse(isAllDay)
        // A timed due is that wall-clock time on the device's calendar
        let local = date.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
        XCTAssertEqual(local, DateComponents(year: 2025, month: 6, day: 15, hour: 14, minute: 30))
    }

    // MARK: - Recurrence Mapping Tests (Astrid -> Apple)

    @MainActor
    func testMapRecurrenceToApple_Never() {
        let service = AppleRemindersService.shared
        let rule = service.mapRecurrenceToApple(.never, data: nil)
        XCTAssertNil(rule)
    }

    @MainActor
    func testMapRecurrenceToApple_Daily() {
        let service = AppleRemindersService.shared
        let rule = service.mapRecurrenceToApple(.daily, data: nil)
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .daily)
        XCTAssertEqual(rule?.interval, 1)
    }

    @MainActor
    func testMapRecurrenceToApple_Weekly() {
        let service = AppleRemindersService.shared
        let rule = service.mapRecurrenceToApple(.weekly, data: nil)
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .weekly)
        XCTAssertEqual(rule?.interval, 1)
    }

    @MainActor
    func testMapRecurrenceToApple_Monthly() {
        let service = AppleRemindersService.shared
        let rule = service.mapRecurrenceToApple(.monthly, data: nil)
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .monthly)
        XCTAssertEqual(rule?.interval, 1)
    }

    @MainActor
    func testMapRecurrenceToApple_Yearly() {
        let service = AppleRemindersService.shared
        let rule = service.mapRecurrenceToApple(.yearly, data: nil)
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .yearly)
        XCTAssertEqual(rule?.interval, 1)
    }

    @MainActor
    func testMapRecurrenceToApple_CustomDays() {
        let service = AppleRemindersService.shared
        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "days",
            interval: 3,
            endCondition: "never"
        )
        let rule = service.mapRecurrenceToApple(.custom, data: pattern)
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .daily)
        XCTAssertEqual(rule?.interval, 3)
    }

    @MainActor
    func testMapRecurrenceToApple_CustomWeeks() {
        let service = AppleRemindersService.shared
        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "weeks",
            interval: 2,
            endCondition: "never"
        )
        let rule = service.mapRecurrenceToApple(.custom, data: pattern)
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .weekly)
        XCTAssertEqual(rule?.interval, 2)
    }

    @MainActor
    func testMapRecurrenceToApple_CustomWithOccurrenceLimit() {
        let service = AppleRemindersService.shared
        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "days",
            interval: 1,
            endCondition: "after_occurrences",
            endAfterOccurrences: 5
        )
        let rule = service.mapRecurrenceToApple(.custom, data: pattern)
        XCTAssertNotNil(rule)
        XCTAssertNotNil(rule?.recurrenceEnd)
        XCTAssertEqual(rule?.recurrenceEnd?.occurrenceCount, 5)
    }

    @MainActor
    func testMapRecurrenceToApple_CustomWithEndDate() {
        let service = AppleRemindersService.shared
        let endDate = ISO8601DateFormatter().date(from: "2025-07-15T00:00:00Z")!
        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "weeks",
            interval: 1,
            endCondition: "until_date",
            endUntilDate: endDate
        )
        let rule = service.mapRecurrenceToApple(.custom, data: pattern)
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.recurrenceEnd?.endDate, endDate, "the series ends on the pattern's date")
        XCTAssertEqual(rule?.recurrenceEnd?.occurrenceCount, 0)
    }

    // MARK: - Recurrence Mapping Tests (Apple -> Astrid)

    @MainActor
    func testMapRecurrenceFromApple_Nil() {
        let service = AppleRemindersService.shared
        let (repeating, data) = service.mapRecurrenceFromApple(nil)
        XCTAssertEqual(repeating, .never)
        XCTAssertNil(data)
    }

    /// Every-1 rules with no end and no weekdays import as the four simple repeats (AITD-538).
    @MainActor
    func testMapRecurrenceFromApple_SimpleFrequencies() {
        let service = AppleRemindersService.shared
        let cases: [(EKRecurrenceFrequency, Task.Repeating)] = [
            (.daily, .daily), (.weekly, .weekly), (.monthly, .monthly), (.yearly, .yearly)
        ]
        for (frequency, expected) in cases {
            let rule = EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil)
            let (repeating, data) = service.mapRecurrenceFromApple(rule)
            XCTAssertEqual(repeating, expected, "\(frequency.rawValue)")
            XCTAssertNil(data, "a simple repeat carries no pattern")
        }
    }

    /// Every 3 days is a custom pattern with that interval.
    @MainActor
    func testMapRecurrenceFromApple_IntervalBecomesCustom() {
        let service = AppleRemindersService.shared
        let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 3, end: nil)
        let (repeating, data) = service.mapRecurrenceFromApple(rule)
        XCTAssertEqual(repeating, .custom)
        XCTAssertEqual(data?.unit, "days")
        XCTAssertEqual(data?.interval, 3)
        XCTAssertEqual(data?.endCondition, "never")
    }

    /// "Daily, 5 times" kept only "daily": the end was dropped on import, and the next export
    /// wrote an endless series back over the reminder (AITD-538).
    @MainActor
    func testMapRecurrenceFromApple_EveryOneWithOccurrenceEndKeepsTheEnd() {
        let service = AppleRemindersService.shared
        let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 5))
        let (repeating, data) = service.mapRecurrenceFromApple(rule)
        XCTAssertEqual(repeating, .custom)
        XCTAssertEqual(data?.unit, "days")
        XCTAssertEqual(data?.interval, 1)
        XCTAssertEqual(data?.endCondition, "after_occurrences")
        XCTAssertEqual(data?.endAfterOccurrences, 5)
    }

    @MainActor
    func testMapRecurrenceFromApple_UntilDate() {
        let service = AppleRemindersService.shared
        let endDate = ISO8601DateFormatter().date(from: "2025-07-15T00:00:00Z")!
        let rule = EKRecurrenceRule(recurrenceWith: .monthly, interval: 2, end: EKRecurrenceEnd(end: endDate))
        let (repeating, data) = service.mapRecurrenceFromApple(rule)
        XCTAssertEqual(repeating, .custom)
        XCTAssertEqual(data?.unit, "months")
        XCTAssertEqual(data?.interval, 2)
        XCTAssertEqual(data?.endCondition, "until_date")
        XCTAssertEqual(data?.endUntilDate, endDate)
    }

    /// "Weekly on Mon, Wed, Fri" imported as plain weekly — one day a week (AITD-538).
    @MainActor
    func testMapRecurrenceFromApple_WeekdaysAreKept() {
        let service = AppleRemindersService.shared
        let rule = EKRecurrenceRule(
            recurrenceWith: .weekly, interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.wednesday), EKRecurrenceDayOfWeek(.friday)],
            daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil,
            setPositions: nil, end: nil)
        let (repeating, data) = service.mapRecurrenceFromApple(rule)
        XCTAssertEqual(repeating, .custom)
        XCTAssertEqual(data?.unit, "weeks")
        XCTAssertEqual(data?.interval, 1)
        XCTAssertEqual(data?.weekdays, ["monday", "wednesday", "friday"])
    }

    /// A weekly pattern's weekdays reach the reminder; they were dropped on export (AITD-538).
    @MainActor
    func testMapRecurrenceToApple_CustomWeekdays() {
        let service = AppleRemindersService.shared
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "weeks", interval: 2, endCondition: "never",
            weekdays: ["tuesday", "sunday"])
        let rule = service.mapRecurrenceToApple(.custom, data: pattern)
        XCTAssertEqual(rule?.frequency, .weekly)
        XCTAssertEqual(rule?.interval, 2)
        XCTAssertEqual(rule?.daysOfTheWeek?.map(\.dayOfTheWeek), [.tuesday, .sunday])
    }

    /// Import then export must hand back the rule Apple had. Anything the round trip loses, the
    /// export planner sees as a change and writes over the user's reminder (AITD-538).
    @MainActor
    func testRecurrenceRoundTripLeavesTheReminderUnchanged() {
        let service = AppleRemindersService.shared
        let until = ISO8601DateFormatter().date(from: "2025-07-15T00:00:00Z")!
        let rules: [EKRecurrenceRule] = [
            EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil),
            EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil),
            EKRecurrenceRule(recurrenceWith: .daily, interval: 4, end: nil),
            EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 3)),
            EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: EKRecurrenceEnd(end: until)),
            EKRecurrenceRule(
                recurrenceWith: .weekly, interval: 2,
                daysOfTheWeek: [EKRecurrenceDayOfWeek(.saturday), EKRecurrenceDayOfWeek(.sunday)],
                daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil,
                setPositions: nil, end: nil),
        ]
        for rule in rules {
            let (repeating, data) = service.mapRecurrenceFromApple(rule)
            let exported = service.mapRecurrenceToApple(repeating, data: data)
            XCTAssertEqual(AppleExportPlanner.recurrenceKey(exported), AppleExportPlanner.recurrenceKey(rule),
                           "round trip of \(AppleExportPlanner.recurrenceKey(rule) ?? "nil")")
        }
    }

    // MARK: - Due Date Mapping Tests (Astrid -> Apple)

    @MainActor
    func testMapDueDateToApple_None() {
        XCTAssertNil(AppleRemindersService.shared.mapDueDateToApple(nil, isAllDay: true))
    }

    /// An all-day due at UTC midnight is that UTC calendar day, with no time and no calendar —
    /// read in the local zone it lands on the previous day for anyone west of UTC.
    @MainActor
    func testMapDueDateToApple_AllDayIsTheUTCDay() {
        let due = ISO8601DateFormatter().date(from: "2025-06-15T00:00:00Z")!
        let components = AppleRemindersService.shared.mapDueDateToApple(due, isAllDay: true)
        XCTAssertEqual(components, DateComponents(year: 2025, month: 6, day: 15))
    }

    @MainActor
    func testMapDueDateToApple_TimedIsTheLocalWallClock() {
        let due = Calendar.current.date(from: DateComponents(year: 2025, month: 6, day: 15, hour: 14, minute: 30))!
        let components = AppleRemindersService.shared.mapDueDateToApple(due, isAllDay: false)
        XCTAssertEqual(components, DateComponents(year: 2025, month: 6, day: 15, hour: 14, minute: 30))
    }

    /// Export then import gives the task back its due, all-day and timed alike.
    @MainActor
    func testDueDateRoundTrip() {
        let service = AppleRemindersService.shared
        let allDay = ISO8601DateFormatter().date(from: "2025-06-15T00:00:00Z")!
        let timed = Calendar.current.date(from: DateComponents(year: 2025, month: 6, day: 15, hour: 14, minute: 30))!
        for (due, isAllDay) in [(allDay, true), (timed, false)] {
            let (back, backAllDay) = service.mapDueDateFromApple(service.mapDueDateToApple(due, isAllDay: isAllDay))
            XCTAssertEqual(back, due)
            XCTAssertEqual(backAllDay, isAllDay)
        }
    }

    // MARK: - ReminderListLink Model Tests

    @MainActor func testReminderListLinkCreation() {
        let link = ReminderListLink(
            astridListId: "list-123",
            astridListName: "My Tasks",
            reminderCalendarId: "calendar-456",
            reminderCalendarTitle: "Reminders",
            syncDirection: .export,
            createdAt: Date(),
            lastSyncedAt: nil,
            includeCompletedTasks: true
        )

        XCTAssertEqual(link.id, "list-123") // id is computed from astridListId
        XCTAssertEqual(link.astridListId, "list-123")
        XCTAssertEqual(link.astridListName, "My Tasks")
        XCTAssertEqual(link.reminderCalendarId, "calendar-456")
        XCTAssertEqual(link.reminderCalendarTitle, "Reminders")
        XCTAssertEqual(link.syncDirection, .export)
        XCTAssertNil(link.lastSyncedAt)
        XCTAssertTrue(link.includeCompletedTasks)
    }

    @MainActor func testReminderListLinkWithIncludeCompletedFalse() {
        let link = ReminderListLink(
            astridListId: "list-abc",
            astridListName: "Work",
            reminderCalendarId: "cal-xyz",
            reminderCalendarTitle: "Work Reminders",
            syncDirection: .bidirectional,
            createdAt: Date(),
            lastSyncedAt: Date(),
            includeCompletedTasks: false
        )

        XCTAssertFalse(link.includeCompletedTasks)
        XCTAssertNotNil(link.lastSyncedAt)
    }

    @MainActor func testReminderListLinkDefaultIncludeCompleted() {
        // Test that includeCompletedTasks defaults to true
        let link = ReminderListLink(
            astridListId: "list-def",
            astridListName: "Default",
            reminderCalendarId: "cal-def",
            reminderCalendarTitle: "Default Cal",
            syncDirection: .import_,
            createdAt: Date(),
            lastSyncedAt: nil
        )

        XCTAssertTrue(link.includeCompletedTasks)
    }

    // MARK: - SyncDirection Tests

    @MainActor func testSyncDirectionRawValues() {
        XCTAssertEqual(SyncDirection.export.rawValue, "export")
        XCTAssertEqual(SyncDirection.import_.rawValue, "import")
        XCTAssertEqual(SyncDirection.bidirectional.rawValue, "bidirectional")
    }

    /// The direction picker shows these (rule 8, AITD-537). Each reads its key, and the key
    /// resolves — so this holds in every host language, not only English.
    @MainActor func testSyncDirectionDisplayNamesReadTheirKeys_AITD537() {
        let expected: [(SyncDirection, String)] = [
            (.export, "apple_reminders.direction.export"),
            (.import_, "reminders.import_from_reminders"),
            (.bidirectional, "apple_reminders.direction.bidirectional"),
        ]
        for (direction, key) in expected {
            XCTAssertNotEqual(NSLocalizedString(key, comment: ""), key, "\(key) is missing")
            XCTAssertEqual(direction.displayName, NSLocalizedString(key, comment: ""))
        }
    }

    @MainActor func testSyncDirectionDescriptionsReadTheirKeysAndNameTheBrand_AITD537() {
        let expected: [(SyncDirection, String)] = [
            (.export, "apple_reminders.direction.export_description"),
            (.import_, "apple_reminders.direction.import_description"),
            (.bidirectional, "apple_reminders.direction.bidirectional_description"),
        ]
        for (direction, key) in expected {
            let format = NSLocalizedString(key, comment: "")
            XCTAssertNotEqual(format, key, "\(key) is missing")
            XCTAssertEqual(direction.description, String(format: format, Brand.appName))
        }
        XCTAssertTrue(SyncDirection.export.description.contains(Brand.appName))
        XCTAssertTrue(SyncDirection.import_.description.contains(Brand.appName))
    }

    @MainActor func testSyncDirectionAllCases() {
        XCTAssertEqual(SyncDirection.allCases.count, 3)
        XCTAssertTrue(SyncDirection.allCases.contains(.export))
        XCTAssertTrue(SyncDirection.allCases.contains(.import_))
        XCTAssertTrue(SyncDirection.allCases.contains(.bidirectional))
    }

    // MARK: - AppleRemindersError Tests

    @MainActor func testAppleRemindersErrorsReadTheirKeys_AITD537() {
        let expected: [(AppleRemindersError, String)] = [
            (.notAuthorized, "apple_reminders.error.not_authorized"),
            (.noCalendarSource, "apple_reminders.error.no_calendar_source"),
            (.listNotLinked, "apple_reminders.error.list_not_linked"),
            (.calendarNotFound, "apple_reminders.error.calendar_not_found"),
        ]
        for (error, key) in expected {
            XCTAssertNotEqual(NSLocalizedString(key, comment: ""), key, "\(key) is missing")
            XCTAssertEqual(error.errorDescription, NSLocalizedString(key, comment: ""))
        }
        let notFound = NSLocalizedString("apple_reminders.error.list_not_found", comment: "")
        XCTAssertNotEqual(notFound, "apple_reminders.error.list_not_found")
        XCTAssertEqual(AppleRemindersError.listNotFound.errorDescription, String(format: notFound, Brand.appName))
    }

    @MainActor func testAppleRemindersErrorSyncFailed() {
        let underlyingError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error = AppleRemindersError.syncFailed(underlyingError)
        XCTAssertTrue(error.errorDescription?.contains("Test error") ?? false)
        let format = NSLocalizedString("apple_reminders.error.sync_failed", comment: "")
        XCTAssertNotEqual(format, "apple_reminders.error.sync_failed")
        XCTAssertEqual(error.errorDescription, String(format: format, "Test error"))
    }

    // MARK: - ReminderListLink Codable Tests

    @MainActor func testReminderListLinkEncodeDecode() throws {
        let original = ReminderListLink(
            astridListId: "encode-test",
            astridListName: "Encode Test List",
            reminderCalendarId: "cal-encode",
            reminderCalendarTitle: "Encoded Calendar",
            syncDirection: .bidirectional,
            createdAt: Date(timeIntervalSince1970: 1700000000),
            lastSyncedAt: Date(timeIntervalSince1970: 1700001000),
            includeCompletedTasks: false
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ReminderListLink.self, from: data)

        XCTAssertEqual(decoded.astridListId, original.astridListId)
        XCTAssertEqual(decoded.astridListName, original.astridListName)
        XCTAssertEqual(decoded.reminderCalendarId, original.reminderCalendarId)
        XCTAssertEqual(decoded.reminderCalendarTitle, original.reminderCalendarTitle)
        XCTAssertEqual(decoded.syncDirection, original.syncDirection)
        XCTAssertEqual(decoded.includeCompletedTasks, original.includeCompletedTasks)
    }

    // MARK: - Service State Tests

    @MainActor
    func testAppleRemindersServiceIsSingleton() {
        let service1 = AppleRemindersService.shared
        let service2 = AppleRemindersService.shared
        XCTAssertTrue(service1 === service2)
    }

    @MainActor
    func testIsListLinkedReturnsFalseForUnlinkedList() {
        let service = AppleRemindersService.shared
        // Random UUID should not be linked
        XCTAssertFalse(service.isListLinked(UUID().uuidString))
    }
}
