import XCTest
@testable import Astrid_App

/// AITD-441 — a reminder opens a triage deck: one task per screen, a swipe per decision.
///
/// The deck, the swipe → action map, the "Tomorrow" date and which agent "Astrid" is are all
/// rules, so they are pinned here rather than left to live inside a gesture handler.
final class ReminderTriageTests: XCTestCase {

    private let me = "user-me"
    private let someoneElse = "user-other"

    private func utcMidnight(daysFromToday days: Int, now: Date = Date()) -> Date {
        let local = Calendar.current.dateComponents([.year, .month, .day],
                                                    from: Calendar.current.date(byAdding: .day, value: days, to: now)!)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: local)!
    }

    // MARK: - Deck

    func testDeckIsTheBadgeSet_myIncompleteTasksDueTodayOrOverdue_AITD441() {
        let overdue = TestHelpers.createTestTask(id: "overdue", dueDateTime: utcMidnight(daysFromToday: -2), isAllDay: true, assigneeId: me)
        let today = TestHelpers.createTestTask(id: "today", dueDateTime: utcMidnight(daysFromToday: 0), isAllDay: true, assigneeId: me)
        let future = TestHelpers.createTestTask(id: "future", dueDateTime: utcMidnight(daysFromToday: 3), isAllDay: true, assigneeId: me)
        let noDate = TestHelpers.createTestTask(id: "nodate", assigneeId: me)
        let done = TestHelpers.createTestTask(id: "done", completed: true, dueDateTime: utcMidnight(daysFromToday: -1), isAllDay: true, assigneeId: me)
        let theirs = TestHelpers.createTestTask(id: "theirs", dueDateTime: utcMidnight(daysFromToday: -1), isAllDay: true, assigneeId: someoneElse)
        let unassigned = TestHelpers.createTestTask(id: "unassigned", dueDateTime: utcMidnight(daysFromToday: -1), isAllDay: true)

        let deck = ReminderTriage.deck(from: [today, future, noDate, done, theirs, unassigned, overdue],
                                       currentUserId: me, remindedTaskId: nil)

        XCTAssertEqual(deck.map(\.id), ["overdue", "today"], "oldest due first; only what the badge counts")
    }

    func testRemindedTaskLeadsTheDeckEvenWhenNotDueYet_AITD441() {
        let overdue = TestHelpers.createTestTask(id: "overdue", dueDateTime: utcMidnight(daysFromToday: -1), isAllDay: true, assigneeId: me)
        let reminded = TestHelpers.createTestTask(id: "reminded", dueDateTime: utcMidnight(daysFromToday: 2), isAllDay: true, assigneeId: me)

        let deck = ReminderTriage.deck(from: [overdue, reminded], currentUserId: me, remindedTaskId: "reminded")

        XCTAssertEqual(deck.map(\.id), ["reminded", "overdue"])
    }

    func testRemindedTaskAppearsOnceWhenAlsoDue_AITD441() {
        let a = TestHelpers.createTestTask(id: "a", dueDateTime: utcMidnight(daysFromToday: -3), isAllDay: true, assigneeId: me)
        let b = TestHelpers.createTestTask(id: "b", dueDateTime: utcMidnight(daysFromToday: -1), isAllDay: true, assigneeId: me)

        let deck = ReminderTriage.deck(from: [a, b], currentUserId: me, remindedTaskId: "b")

        XCTAssertEqual(deck.map(\.id), ["b", "a"])
    }

    func testSomeoneElsesRemindedTaskIsNotTriaged_AITD441() {
        // Completing someone else's task needs a confirmation (AITD-375); a swipe is not one.
        let theirs = TestHelpers.createTestTask(id: "theirs", dueDateTime: utcMidnight(daysFromToday: 0), isAllDay: true, assigneeId: someoneElse)

        XCTAssertTrue(ReminderTriage.deck(from: [theirs], currentUserId: me, remindedTaskId: "theirs").isEmpty)
    }

    // MARK: - Swipes

    func testSwipeDirectionsMapToTheFourDecisions_AITD441() {
        XCTAssertEqual(ReminderTriage.action(forDragX: 0, y: -200), .assignToAssistant)
        XCTAssertEqual(ReminderTriage.action(forDragX: 0, y: 200), .keep)
        XCTAssertEqual(ReminderTriage.action(forDragX: -200, y: 0), .complete)
        XCTAssertEqual(ReminderTriage.action(forDragX: 200, y: 0), .postpone)
    }

    func testShortOrDiagonalDragsDecideNothing_AITD441() {
        XCTAssertNil(ReminderTriage.action(forDragX: 40, y: 10), "below the threshold")
        XCTAssertNil(ReminderTriage.action(forDragX: 150, y: 140), "too diagonal to call")
        XCTAssertEqual(ReminderTriage.action(forDragX: -150, y: 40), .complete, "clearly horizontal")
    }

    // MARK: - Tomorrow

    func testPostponeAllDayLandsOnTomorrowAtUTCMidnight_AITD441() {
        let now = Date()
        let task = TestHelpers.createTestTask(dueDateTime: utcMidnight(daysFromToday: -5, now: now), isAllDay: true, assigneeId: me)

        XCTAssertEqual(ReminderTriage.postponedDueDate(for: task, now: now), utcMidnight(daysFromToday: 1, now: now),
                       "tomorrow from TODAY, not the old due date plus one")
    }

    func testPostponeTimedKeepsTimeOfDayOnTomorrow_AITD441() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 20))!
        let due = cal.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 9, minute: 30))!
        let task = TestHelpers.createTestTask(dueDateTime: due, isAllDay: false, assigneeId: me)

        XCTAssertEqual(ReminderTriage.postponedDueDate(for: task, now: now, calendar: cal),
                       cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 9, minute: 30)))
    }

    func testPostponeWithoutDueDateIsAllDayTomorrow_AITD441() {
        let now = Date()
        let task = TestHelpers.createTestTask(dueDateTime: nil, isAllDay: false, assigneeId: me)

        XCTAssertEqual(ReminderTriage.postponedDueDate(for: task, now: now), utcMidnight(daysFromToday: 1, now: now))
        XCTAssertTrue(ReminderTriage.postponedIsAllDay(for: task))
    }

    // MARK: - Astrid

    func testAssistantIsFoundByServiceNotByAddress_AITD441() {
        let claude = User(id: "c", email: "claude@astrid.cc", name: "Claude", image: nil, createdAt: nil,
                          defaultDueTime: nil, isPending: nil, isAIAgent: true, aiAgentType: "claude")
        let assistant = User(id: "a", email: "helper@partner.example", name: "Helper", image: nil, createdAt: nil,
                             defaultDueTime: nil, isPending: nil, isAIAgent: true,
                             aiAgentType: AvailableAgent.defaultAssistantService)

        XCTAssertEqual(ReminderTriage.assistant(in: [claude, assistant])?.id, "a")
        XCTAssertNil(ReminderTriage.assistant(in: [claude]))
    }
}
