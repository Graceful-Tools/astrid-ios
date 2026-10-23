import XCTest
@testable import Astrid_App

/// What the task list says when it is empty — `EmptyStateMessage.decide`, the production
/// decision `TaskListView` draws (AITD-538). It used to live inline in the view, and these tests
/// read a key back from the test bundle instead of calling anything.
///
/// Aligns with `astrid-web/components/ui/astrid-empty-state.tsx`: one string per list type, no
/// completed-task threshold. A new variant goes to web first, then here.
final class EmptyStateMessageTests: XCTestCase {
    private func virtual(_ type: String?) -> TaskList {
        var list = TestHelpers.createTestList(isVirtual: true)
        list.virtualListType = type
        return list
    }

    private func decide(_ selectedListId: String? = nil, search: String = "",
                        list: TaskList? = nil) -> EmptyStateMessage {
        EmptyStateMessage.decide(selectedListId: selectedListId, searchText: search, list: list)
    }

    func testMyTasksHasOneMessageWhichEverWayItIsOpened_AITD538() {
        XCTAssertEqual(decide("my-tasks"), .myTasks)
        let saved = virtual("my-tasks")
        XCTAssertEqual(decide(saved.id, list: saved), .myTasks)
        XCTAssertEqual(EmptyStateMessage.myTasks.key, "empty_state.my_tasks")
    }

    func testTheMyTasksMessageResolvesInTheAppBundle_AITD538() {
        let text = EmptyStateMessage.myTasks.text
        XCTAssertFalse(text.isEmpty)
        XCTAssertNotEqual(text, "empty_state.my_tasks", "the key must have a string in Localizable.strings")
    }

    func testSearch_AITD538() {
        XCTAssertEqual(decide("search"), .searchPrompt, "nothing typed yet: prompt for a search")
        XCTAssertEqual(decide("search", search: "milk"), .default)
        XCTAssertEqual(decide("my-tasks", search: "milk"), .default,
                       "a sidebar search answers with the default, whatever list is open")
    }

    func testVirtualLists_AITD538() {
        XCTAssertEqual(decide(list: virtual("today")), .today)
        XCTAssertEqual(decide(list: virtual("overdue")), .default)
        XCTAssertEqual(decide(list: virtual(nil)), .default)
    }

    func testRegularListsByPrivacy_AITD538() {
        XCTAssertEqual(decide(list: TestHelpers.createTestList(privacy: .PUBLIC)), .publicList)
        XCTAssertEqual(decide(list: TestHelpers.createTestList(privacy: .SHARED)), .sharedList)
        let own = TestHelpers.createTestList(name: "Groceries", privacy: .PRIVATE)
        XCTAssertEqual(decide(list: own), .list(name: "Groceries"))
        XCTAssertTrue(EmptyStateMessage.list(name: "Groceries").text.contains("Groceries"))
        XCTAssertEqual(decide("some-list-id"), .default, "a list not loaded yet")
    }
}
