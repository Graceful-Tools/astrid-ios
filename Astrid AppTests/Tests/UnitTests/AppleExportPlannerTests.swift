import XCTest
import EventKit
@testable import Astrid_App

/// Locks the fix for the "My Tasks flickers during background sync" loop.
///
/// The Apple export used to rewrite every mapped reminder on every pass:
/// each commit fired `EKEventStoreChanged` for our OWN write (rescheduling
/// auto-sync forever, even in airplane mode), and each rewrite bumped
/// `lastModifiedDate`, holding the import's "Reminders is newer" gate open so
/// disagreeing pairs re-applied every ~2s — repeating tasks ping-ponged
/// (re-complete → roll forward → due date marches), reshuffling the list.
///
/// Contract: a quiescent task↔reminder pair produces NO write. The dirty
/// check compares `AppleReminderSnapshot`s; `desiredSnapshot(for:)` must stay
/// field-for-field faithful to `updateReminder(_:from:)`, which the
/// round-trip test enforces with a real (in-memory) EKReminder.
@MainActor
final class AppleExportPlannerTests: XCTestCase {

    private func makeTask(
        title: String = "Water plants",
        description: String = "back porch too",
        completed: Bool = false,
        due: Date? = Date(timeIntervalSince1970: 1_800_000_000),
        isAllDay: Bool = false,
        repeating: Task.Repeating? = nil,
        reminderTime: Date? = nil
    ) -> Task {
        Task(id: UUID().uuidString, title: title, description: description,
             dueDateTime: due, isAllDay: isAllDay,
             reminderTime: reminderTime, repeating: repeating,
             priority: .high, listIds: ["list1"], completed: completed)
    }

    /// In-sync pair → no write. This is the loop-breaker: if this regresses,
    /// every auto-sync pass rewrites EventKit, re-fires EKEventStoreChanged,
    /// and the 2s flicker loop returns.
    func testQuiescentPairNeedsNoWrite() {
        let service = AppleRemindersService.shared
        let task = makeTask()
        let reminder = EKReminder(eventStore: EKEventStore())
        service.updateReminder(reminder, from: task)

        XCTAssertFalse(AppleExportPlanner.needsWrite(
            current: service.currentSnapshot(of: reminder),
            desired: service.desiredSnapshot(for: task)),
            "a reminder that already matches its task must not be re-written")
    }

    func testQuiescentPair_allDay_andRepeating_andAlarm() {
        let service = AppleRemindersService.shared
        for task in [
            makeTask(due: Date(timeIntervalSince1970: 1_800_000_000), isAllDay: true),
            makeTask(repeating: .weekly),
            makeTask(reminderTime: Date(timeIntervalSince1970: 1_799_990_000)),
            makeTask(description: "", due: nil),
            makeTask(completed: true),
        ] {
            let reminder = EKReminder(eventStore: EKEventStore())
            service.updateReminder(reminder, from: task)
            XCTAssertFalse(AppleExportPlanner.needsWrite(
                current: service.currentSnapshot(of: reminder),
                desired: service.desiredSnapshot(for: task)),
                "quiescent variant must not write: \(task.title)")
        }
    }

    func testEachFieldDriftIsDetected() {
        let service = AppleRemindersService.shared
        let base = makeTask()
        let reminder = EKReminder(eventStore: EKEventStore())
        service.updateReminder(reminder, from: base)
        let current = service.currentSnapshot(of: reminder)

        var titled = base; titled.title = "Water plants MORE"
        var completed = base; completed.completed = true
        var rescheduled = base; rescheduled.dueDateTime = Date(timeIntervalSince1970: 1_800_090_000)
        var described = base; described.description = "different notes"

        for (label, task) in [("title", titled), ("completed", completed),
                              ("due", rescheduled), ("notes", described)] {
            XCTAssertTrue(AppleExportPlanner.needsWrite(
                current: current, desired: service.desiredSnapshot(for: task)),
                "\(label) drift must trigger a write")
        }
    }

    func testDueKeyNormalization() {
        // Timed dues carry h:m; all-day dues don't. Calendar/timezone noise
        // EventKit attaches on read must not create phantom drift.
        var timed = DateComponents(year: 2027, month: 1, day: 15, hour: 9, minute: 30)
        XCTAssertEqual(AppleExportPlanner.dueKey(timed), "2027-1-15 9:30")
        timed.calendar = Calendar.current
        timed.timeZone = TimeZone(identifier: "America/Los_Angeles")
        XCTAssertEqual(AppleExportPlanner.dueKey(timed), "2027-1-15 9:30")

        let allDay = DateComponents(year: 2027, month: 1, day: 15)
        XCTAssertEqual(AppleExportPlanner.dueKey(allDay), "2027-1-15")
        XCTAssertNil(AppleExportPlanner.dueKey(nil))
    }
}
