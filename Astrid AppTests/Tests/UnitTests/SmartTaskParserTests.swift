import XCTest
@testable import Astrid_App

/// Unit tests for SmartTaskParser - task title NLP parsing
/// Tests extraction of dates, priorities, hashtags, and repeating patterns from natural language task input
/// Matches web implementation in lib/task-manager-utils.ts
final class SmartTaskParserTests: XCTestCase {

    // MARK: - Test Data

    private var mockLists: [TaskList] = []

    override func setUp() {
        super.setUp()
        mockLists = [
            TestHelpers.createTestList(id: "list-1", name: "Shopping", ownerId: "user-1", isVirtual: false),
            TestHelpers.createTestList(id: "list-2", name: "Work Tasks", ownerId: "user-1", isVirtual: false),
            TestHelpers.createTestList(id: "virtual-1", name: "My Tasks", ownerId: "user-1", isVirtual: true)
        ]
    }

    // MARK: - Simple Repeating Pattern Tests

    func testParseDaily() {
        let result = SmartTaskParser.parse("daily exercise", lists: mockLists)

        XCTAssertEqual(result.title, "exercise")
        XCTAssertEqual(result.repeating, .daily)
        XCTAssertNil(result.customRepeatingData)
    }

    func testParseWeekly() {
        let result = SmartTaskParser.parse("weekly report", lists: mockLists)

        XCTAssertEqual(result.title, "report")
        XCTAssertEqual(result.repeating, .weekly)
        XCTAssertNil(result.customRepeatingData)
    }

    func testParseMonthly() {
        let result = SmartTaskParser.parse("monthly budget review", lists: mockLists)

        XCTAssertEqual(result.title, "budget review")
        XCTAssertEqual(result.repeating, .monthly)
        XCTAssertNil(result.customRepeatingData)
    }

    func testParseYearly() {
        let result = SmartTaskParser.parse("yearly tax filing", lists: mockLists)

        XCTAssertEqual(result.title, "tax filing")
        XCTAssertEqual(result.repeating, .yearly)
        XCTAssertNil(result.customRepeatingData)
    }

    func testParseAnnually() {
        let result = SmartTaskParser.parse("annually renew license", lists: mockLists)

        XCTAssertEqual(result.title, "renew license")
        XCTAssertEqual(result.repeating, .yearly)
        XCTAssertNil(result.customRepeatingData)
    }

    func testParseEveryDay() {
        let result = SmartTaskParser.parse("every day take vitamins", lists: mockLists)

        XCTAssertEqual(result.title, "take vitamins")
        XCTAssertEqual(result.repeating, .daily)
    }

    func testParseEveryWeek() {
        let result = SmartTaskParser.parse("every week clean house", lists: mockLists)

        XCTAssertEqual(result.title, "clean house")
        XCTAssertEqual(result.repeating, .weekly)
    }

    func testParseEveryMonth() {
        let result = SmartTaskParser.parse("every month pay rent", lists: mockLists)

        XCTAssertEqual(result.title, "pay rent")
        XCTAssertEqual(result.repeating, .monthly)
    }

    func testParseEveryYear() {
        let result = SmartTaskParser.parse("every year file taxes", lists: mockLists)

        XCTAssertEqual(result.title, "file taxes")
        XCTAssertEqual(result.repeating, .yearly)
    }

    // MARK: - Weekly with Specific Day Tests

    func testParseWeeklyMonday() {
        let result = SmartTaskParser.parse("weekly Monday exercise", lists: mockLists)

        XCTAssertEqual(result.title, "exercise")
        XCTAssertEqual(result.repeating, .custom)
        XCTAssertNotNil(result.customRepeatingData)
        XCTAssertEqual(result.customRepeatingData?.unit, "weeks")
        XCTAssertEqual(result.customRepeatingData?.interval, 1)
        XCTAssertEqual(result.customRepeatingData?.weekdays, ["monday"])
        XCTAssertNotNil(result.dueDateTime)
    }

    func testParseWeeklyTuesday() {
        let result = SmartTaskParser.parse("weekly Tuesday team meeting", lists: mockLists)

        XCTAssertEqual(result.title, "team meeting")
        XCTAssertEqual(result.repeating, .custom)
        XCTAssertEqual(result.customRepeatingData?.weekdays, ["tuesday"])
    }

    func testParseEveryWeekFriday() {
        let result = SmartTaskParser.parse("every week Friday review", lists: mockLists)

        XCTAssertEqual(result.title, "review")
        XCTAssertEqual(result.repeating, .custom)
        XCTAssertEqual(result.customRepeatingData?.weekdays, ["friday"])
    }

    func testParseCaseInsensitiveDayName() {
        let result = SmartTaskParser.parse("weekly MONDAY exercise", lists: mockLists)

        XCTAssertEqual(result.title, "exercise")
        XCTAssertEqual(result.repeating, .custom)
        XCTAssertEqual(result.customRepeatingData?.weekdays, ["monday"])
    }

    func testParseWeeklyDayInMiddle() {
        let result = SmartTaskParser.parse("go to weekly Monday exercise class", lists: mockLists)

        XCTAssertEqual(result.title, "go to exercise class")
        XCTAssertEqual(result.repeating, .custom)
        XCTAssertEqual(result.customRepeatingData?.weekdays, ["monday"])
    }

    // MARK: - Weekly with Multiple Days Tests

    func testParseWeeklyMondayAndWednesday() {
        let result = SmartTaskParser.parse("weekly Monday and Wednesday workout", lists: mockLists)

        XCTAssertEqual(result.title, "workout")
        XCTAssertEqual(result.repeating, .custom)
        XCTAssertNotNil(result.customRepeatingData?.weekdays)
        XCTAssertTrue(result.customRepeatingData?.weekdays?.contains("monday") ?? false)
        XCTAssertTrue(result.customRepeatingData?.weekdays?.contains("wednesday") ?? false)
        XCTAssertEqual(result.customRepeatingData?.weekdays?.count, 2)
    }

    func testParseWeeklyWithCommas() {
        let result = SmartTaskParser.parse("weekly Monday, Wednesday, Friday workout", lists: mockLists)

        XCTAssertEqual(result.title, "workout")
        XCTAssertEqual(result.repeating, .custom)
        XCTAssertNotNil(result.customRepeatingData?.weekdays)
        XCTAssertTrue(result.customRepeatingData?.weekdays?.contains("monday") ?? false)
        XCTAssertTrue(result.customRepeatingData?.weekdays?.contains("wednesday") ?? false)
        XCTAssertTrue(result.customRepeatingData?.weekdays?.contains("friday") ?? false)
        XCTAssertEqual(result.customRepeatingData?.weekdays?.count, 3)
    }

    // MARK: - Date Keyword Tests

    /// A parsed date is an all-day date: the person's calendar day, stored at UTC midnight. Read
    /// it back on the UTC calendar, as every all-day date is read.
    private func allDayDay(_ date: Date?) -> DateComponents? {
        guard let date else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    private func localDay(daysFromToday offset: Int) -> DateComponents {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date()))!
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = 0
        components.minute = 0
        return components
    }

    func testParseToday() {
        let result = SmartTaskParser.parse("Buy groceries today", lists: mockLists)

        XCTAssertEqual(result.title, "Buy groceries")
        XCTAssertEqual(allDayDay(result.dueDateTime), localDay(daysFromToday: 0),
                       "today on the person's calendar, at UTC midnight")
    }

    /// D12: a date word is the person's calendar day, stored at UTC midnight. The Swift parser
    /// stored LOCAL midnight, which east of UTC is the previous UTC day — so "tomorrow" typed in
    /// Paris landed on today once the server normalised it.
    func testADateWordIsTheCalendarDayAtUTCMidnight() {
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        // 00:30 on 29 September in Paris is still 28 September in UTC.
        let justAfterMidnightInParis = paris.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 0, minute: 30))!
        let result = SmartTaskParser.parse("Call mom tomorrow", lists: mockLists, today: justAfterMidnightInParis)
        XCTAssertNotNil(result.dueDateTime)
        XCTAssertEqual(result.dueDateTime.map { ISO8601DateFormatter().string(from: $0) }.map { $0.hasSuffix("T00:00:00Z") }, true,
                       "an all-day date sits at UTC midnight, whatever the device's zone")
    }

    func testParseTomorrow() {
        let result = SmartTaskParser.parse("Call mom tomorrow", lists: mockLists)

        XCTAssertEqual(result.title, "Call mom")
        XCTAssertEqual(allDayDay(result.dueDateTime), localDay(daysFromToday: 1))
    }

    func testParseDayName() {
        let result = SmartTaskParser.parse("Meeting Monday", lists: mockLists)

        XCTAssertEqual(result.title, "Meeting")
        XCTAssertNotNil(result.dueDateTime)
        // Should be next Monday — on the UTC calendar, where an all-day date lives
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(utc.component(.weekday, from: result.dueDateTime!), 2) // Monday = 2
    }

    // MARK: - Priority Keyword Tests

    func testParseHighestPriority() {
        let result = SmartTaskParser.parse("Fix bug highest priority", lists: mockLists)

        XCTAssertEqual(result.title, "Fix bug")
        XCTAssertEqual(result.priority, 3)
    }

    func testParseUrgent() {
        let result = SmartTaskParser.parse("urgent deploy fix", lists: mockLists)

        XCTAssertEqual(result.title, "deploy fix")
        XCTAssertEqual(result.priority, 3)
    }

    func testParseAsap() {
        let result = SmartTaskParser.parse("asap reply to email", lists: mockLists)

        XCTAssertEqual(result.title, "reply to email")
        XCTAssertEqual(result.priority, 3)
    }

    func testParseHighPriority() {
        let result = SmartTaskParser.parse("Review PR high priority", lists: mockLists)

        XCTAssertEqual(result.title, "Review PR")
        XCTAssertEqual(result.priority, 2)
    }

    func testParseMediumPriority() {
        let result = SmartTaskParser.parse("Update docs medium priority", lists: mockLists)

        XCTAssertEqual(result.title, "Update docs")
        XCTAssertEqual(result.priority, 1)
    }

    func testParseLowPriority() {
        let result = SmartTaskParser.parse("Clean up code low priority", lists: mockLists)

        XCTAssertEqual(result.title, "Clean up code")
        // "low" is priority 0, which the web reads as no priority at all (`priority || undefined`):
        // the words leave the title and the picker or list default decides (smart.json fixture).
        XCTAssertNil(result.priority)
    }

    // MARK: - Hashtag Tests

    func testParseSingleHashtag() {
        let result = SmartTaskParser.parse("Buy groceries #shopping", lists: mockLists)

        XCTAssertEqual(result.title, "Buy groceries")
        XCTAssertTrue(result.listIds.contains("list-1"))
        XCTAssertEqual(result.listIds.count, 1)
    }

    func testParseHashtagWithDash() {
        let result = SmartTaskParser.parse("Complete report #work-tasks", lists: mockLists)

        XCTAssertEqual(result.title, "Complete report")
        XCTAssertTrue(result.listIds.contains("list-2"))
    }

    func testParseHashtagCaseInsensitive() {
        let result = SmartTaskParser.parse("Buy milk #SHOPPING", lists: mockLists)

        XCTAssertEqual(result.title, "Buy milk")
        XCTAssertTrue(result.listIds.contains("list-1"))
    }

    func testParseMultipleHashtags() {
        let result = SmartTaskParser.parse("Task #shopping #work-tasks", lists: mockLists)

        XCTAssertEqual(result.title, "Task")
        XCTAssertTrue(result.listIds.contains("list-1"))
        XCTAssertTrue(result.listIds.contains("list-2"))
        XCTAssertEqual(result.listIds.count, 2)
    }

    func testParseHashtagVirtualListIgnored() {
        let result = SmartTaskParser.parse("Task #my-tasks", lists: mockLists)

        XCTAssertEqual(result.title, "Task")
        XCTAssertFalse(result.listIds.contains("virtual-1"))
    }

    // MARK: - Combined Feature Tests

    func testParseRepeatingWithPriority() {
        let result = SmartTaskParser.parse("daily exercise high priority", lists: mockLists)

        XCTAssertEqual(result.title, "exercise")
        XCTAssertEqual(result.repeating, .daily)
        XCTAssertEqual(result.priority, 2)
    }

    func testParseRepeatingWithHashtag() {
        let result = SmartTaskParser.parse("weekly report #shopping", lists: mockLists)

        XCTAssertEqual(result.title, "report")
        XCTAssertEqual(result.repeating, .weekly)
        XCTAssertTrue(result.listIds.contains("list-1"))
    }

    func testParseWeeklyDayWithPriority() {
        let result = SmartTaskParser.parse("weekly Monday exercise high priority", lists: mockLists)

        XCTAssertEqual(result.title, "exercise")
        XCTAssertEqual(result.repeating, .custom)
        XCTAssertEqual(result.customRepeatingData?.weekdays, ["monday"])
        XCTAssertEqual(result.priority, 2)
    }

    func testParseDateWithPriority() {
        let result = SmartTaskParser.parse("Call client today urgent", lists: mockLists)

        XCTAssertEqual(result.title, "Call client")
        XCTAssertNotNil(result.dueDateTime)
        XCTAssertEqual(result.priority, 3)
    }

    func testParseAllFeatures() {
        let result = SmartTaskParser.parse("weekly Monday exercise high priority #shopping", lists: mockLists)

        XCTAssertEqual(result.title, "exercise")
        XCTAssertEqual(result.repeating, .custom)
        XCTAssertEqual(result.customRepeatingData?.weekdays, ["monday"])
        XCTAssertEqual(result.priority, 2)
        XCTAssertTrue(result.listIds.contains("list-1"))
    }

    // MARK: - Position Tests

    func testParseRepeatingAtBeginning() {
        let result = SmartTaskParser.parse("daily take vitamins", lists: mockLists)

        XCTAssertEqual(result.title, "take vitamins")
        XCTAssertEqual(result.repeating, .daily)
    }

    func testParseRepeatingInMiddle() {
        let result = SmartTaskParser.parse("take daily vitamins", lists: mockLists)

        XCTAssertEqual(result.title, "take vitamins")
        XCTAssertEqual(result.repeating, .daily)
    }

    func testParseRepeatingAtEnd() {
        let result = SmartTaskParser.parse("take vitamins daily", lists: mockLists)

        XCTAssertEqual(result.title, "take vitamins")
        XCTAssertEqual(result.repeating, .daily)
    }

    // MARK: - Edge Cases

    func testParseEmptyInput() {
        let result = SmartTaskParser.parse("", lists: mockLists)

        XCTAssertEqual(result.title, "")
        XCTAssertNil(result.repeating)
        XCTAssertNil(result.priority)
        XCTAssertNil(result.dueDateTime)
    }

    func testParseOnlyKeyword() {
        let result = SmartTaskParser.parse("daily", lists: mockLists)

        // Title falls back to original if it becomes empty
        XCTAssertEqual(result.title, "daily")
        XCTAssertEqual(result.repeating, .daily)
    }

    func testParseBiweeklyNotMatched() {
        // "biweekly" should NOT match "weekly"
        let result = SmartTaskParser.parse("biweekly meeting", lists: mockLists)

        XCTAssertEqual(result.title, "biweekly meeting")
        XCTAssertNil(result.repeating)
    }

    func testParseNoMatchingList() {
        let result = SmartTaskParser.parse("Task #nonexistent", lists: mockLists)

        XCTAssertEqual(result.title, "Task")
        XCTAssertEqual(result.listIds.count, 0)
    }

    // MARK: - Original Bug Scenario Test

    func testOriginalBugWeeklyMondayExercise() {
        // This is the exact scenario from the bug report:
        // "weekly Monday exercise" should set up weekly repeating on Monday
        let result = SmartTaskParser.parse("weekly Monday exercise", lists: mockLists)

        XCTAssertEqual(result.title, "exercise")
        XCTAssertEqual(result.repeating, .custom)
        XCTAssertNotNil(result.customRepeatingData)
        XCTAssertEqual(result.customRepeatingData?.type, "custom")
        XCTAssertEqual(result.customRepeatingData?.unit, "weeks")
        XCTAssertEqual(result.customRepeatingData?.interval, 1)
        XCTAssertEqual(result.customRepeatingData?.weekdays, ["monday"])
        XCTAssertEqual(result.customRepeatingData?.endCondition, "never")
        XCTAssertNotNil(result.dueDateTime) // Should set due date to next Monday
    }
}
