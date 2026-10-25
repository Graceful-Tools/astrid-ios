import XCTest
import SwiftUI
@testable import Astrid_App

@MainActor
final class TaskPresenterTests: XCTestCase {

    func testShowTaskWithObject() {
        // Given: A TaskPresenter instance and a mock task
        let presenter = TaskPresenter.shared
        let mockTask = Task(
            id: "test-task-123",
            title: "Test Task",
            description: "Test Description",
            creatorId: "user-123",
            isAllDay: true,
            repeating: .never,
            priority: .medium,
            isPrivate: false,
            completed: false
        )

        // When: showTask is called with the task object
        presenter.showTask(mockTask)

        // Then: The presenter should update its state
        XCTAssertEqual(presenter.taskToShow?.id, mockTask.id, "taskToShow should be set to the provided task")
        XCTAssertTrue(presenter.isShowingTask, "isShowingTask should be true")
    }

    func testDismissClearsState() {
        // Given: A TaskPresenter with an active task
        let presenter = TaskPresenter.shared
        let mockTask = Task(
            id: "test-task-456",
            title: "Another Test Task",
            description: "",
            creatorId: "user-123",
            isAllDay: false,
            repeating: .never,
            priority: .none,
            isPrivate: false,
            completed: false
        )
        presenter.showTask(mockTask)

        // Verify initial state
        XCTAssertNotNil(presenter.taskToShow)
        XCTAssertTrue(presenter.isShowingTask)

        // When: dismiss is called
        presenter.dismiss()

        // Then: The state should be cleared
        XCTAssertNil(presenter.taskToShow, "taskToShow should be nil after dismiss")
        XCTAssertFalse(presenter.isShowingTask, "isShowingTask should be false after dismiss")
    }
}
