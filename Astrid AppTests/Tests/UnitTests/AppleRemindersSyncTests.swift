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

    @MainActor func testSyncDirectionDisplayNames() {
        XCTAssertEqual(SyncDirection.export.displayName, "Export to Reminders")
        XCTAssertEqual(SyncDirection.import_.displayName, "Import from Reminders")
        XCTAssertEqual(SyncDirection.bidirectional.displayName, "Two-way Sync")
    }

    @MainActor func testSyncDirectionDescriptions() {
        XCTAssertEqual(SyncDirection.export.description, "Push Astrid tasks to Apple Reminders")
        XCTAssertEqual(SyncDirection.import_.description, "Pull Apple Reminders into Astrid")
        XCTAssertEqual(SyncDirection.bidirectional.description, "Keep both apps in sync")
    }

    @MainActor func testSyncDirectionAllCases() {
        XCTAssertEqual(SyncDirection.allCases.count, 3)
        XCTAssertTrue(SyncDirection.allCases.contains(.export))
        XCTAssertTrue(SyncDirection.allCases.contains(.import_))
        XCTAssertTrue(SyncDirection.allCases.contains(.bidirectional))
    }

    // MARK: - AppleRemindersError Tests

    @MainActor func testAppleRemindersErrorDescriptions() {
        XCTAssertEqual(
            AppleRemindersError.notAuthorized.errorDescription,
            "Reminders access not authorized. Please enable in Settings."
        )
        XCTAssertEqual(
            AppleRemindersError.noCalendarSource.errorDescription,
            "No calendar source available for creating reminders."
        )
        XCTAssertEqual(
            AppleRemindersError.listNotFound.errorDescription,
            "Astrid list not found."
        )
        XCTAssertEqual(
            AppleRemindersError.listNotLinked.errorDescription,
            "List is not linked to Apple Reminders."
        )
        XCTAssertEqual(
            AppleRemindersError.calendarNotFound.errorDescription,
            "Linked Reminders calendar not found."
        )
    }

    @MainActor func testAppleRemindersErrorSyncFailed() {
        let underlyingError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error = AppleRemindersError.syncFailed(underlyingError)
        XCTAssertTrue(error.errorDescription?.contains("Test error") ?? false)
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
