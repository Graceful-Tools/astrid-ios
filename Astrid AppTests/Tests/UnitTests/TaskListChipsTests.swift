import XCTest
@testable import Astrid_App

/// Pins the contract for which list memberships appear as chips on a
/// task row. Status lists must be filtered out so the regular list
/// stays visible inside TaskRowView's `prefix(2)` truncation.
final class TaskListChipsTests: XCTestCase {

    private func makeList(
        id: String,
        name: String,
        listType: String? = nil
    ) -> TaskList {
        var list = TaskList(id: id, name: name)
        list.privacy = .PRIVATE
        list.ownerId = "u-1"
        list.listType = listType
        return list
    }

    func test_nilLists_returnsEmpty() {
        XCTAssertEqual(chipListsForTaskRow(nil).count, 0)
    }

    func test_keepsRegularLists() {
        let ios = makeList(id: "ios", name: "iOS To-do", listType: "regular")
        let inbox = makeList(id: "inbox", name: "Inbox") // legacy nil listType
        let result = chipListsForTaskRow([ios, inbox])
        XCTAssertEqual(result.map { $0.id }, ["ios", "inbox"])
    }

    /// Bug 2026-05-12 #3: task in a board-backed list carries a status
    /// list. `prefix(2)` was pushing the regular chip out of the visible
    /// set so the user saw "Ready / Doing" but not "My Project List".
    func test_dropsStatusLists_preservingRegularOrder() {
        let ios = makeList(id: "ios", name: "iOS To-do", listType: "regular")
        let ready = makeList(id: "ready", name: "Ready", listType: "status")
        let doing = makeList(id: "doing", name: "Doing", listType: "status")
        let result = chipListsForTaskRow([ios, ready, doing])
        XCTAssertEqual(result.map { $0.id }, ["ios"])
    }
}
