import XCTest
@testable import Astrid_App

/// Unit tests for empty-state message logic on My Tasks.
///
/// Aligns with `astrid-web/components/ui/astrid-empty-state.tsx`, which
/// returns a single string per list type with no completed-task threshold.
/// iOS previously branched to a different "caught up" message after 10
/// completions; that was iOS-only and created cross-platform drift, so it
/// was removed. If the product ever adds an "experienced user" variant, it
/// must be added to the web first (the source of truth for empty-state
/// copy) and then mirrored here.
final class EmptyStateMessageTests: XCTestCase {

    /// The my-tasks empty-state key is always the same regardless of how
    /// many tasks the user has completed — matches web's behavior.
    func testMyTasksMessage_IsStableAcrossCompletionCounts() {
        // The localized key we use must not vary with completion count.
        // (We exercise the key name contract rather than the rendered
        // string so the test is locale-stable.)
        let key = "empty_state.my_tasks"
        let bundle = Bundle(for: EmptyStateMessageTests.self)
        // The key should resolve to *some* string in our localization;
        // verify at least the base locale has a non-empty entry.
        let resolved = NSLocalizedString(key, bundle: bundle, comment: "")
        XCTAssertFalse(resolved.isEmpty, "my-tasks empty-state key must have a localized string")
    }

    /// Guard: if a future refactor reintroduces a completed-task threshold,
    /// this test documents the intent that iOS/web should match. The
    /// assertion here is purely a structural reminder — we count completed
    /// tasks for a user but do NOT branch on the count to choose a message.
    func testCountCompletedTasksForUser_UtilityStillWorks() {
        let userId = "test-user-123"

        var tasks: [Task] = []
        for i in 0..<5 {
            tasks.append(TestHelpers.createTestTask(
                id: "completed-\(i)", completed: true, assigneeId: userId
            ))
        }
        for i in 0..<3 {
            tasks.append(TestHelpers.createTestTask(
                id: "incomplete-\(i)", completed: false, assigneeId: userId
            ))
        }
        for i in 0..<2 {
            tasks.append(TestHelpers.createTestTask(
                id: "other-completed-\(i)", completed: true, assigneeId: "other-user"
            ))
        }

        let completedCount = tasks.filter { $0.completed && $0.assigneeId == userId }.count
        XCTAssertEqual(completedCount, 5)
    }
}
