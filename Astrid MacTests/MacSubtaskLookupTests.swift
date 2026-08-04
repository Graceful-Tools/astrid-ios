//  MacSubtaskLookupTests.swift
//  Regression tests for Task effc7112 — "[mac] fix add sub task on mac app".
//
//  The Mac detail found a task's subtasks by walking the PARENT'S LISTS:
//
//      subtasks = (task.listIds ?? []).flatMap { taskService.getTasksForList($0) }
//                                     .filter { $0.parentTaskId == task.id }
//
//  A parent with no list flatMaps over an empty array, so it can never have subtasks: you add
//  one, it is created, and nothing appears. That is the whole bug, and a task with no list is
//  not an edge case — it is every task added from My Tasks.
//
//  iOS never had this because it asks the question directly:
//  `TaskService.shared.tasks.filter { $0.parentTaskId == task.id }`. Parentage is a property of
//  the child, so looking it up through the parent's list membership was answering a different
//  question that happened to agree most of the time.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacSubtaskLookupTests: XCTestCase {

    private func task(_ id: String, parent: String? = nil, lists: [String]? = nil) -> Task {
        var t = Task(id: id, title: id)
        t.parentTaskId = parent
        t.listIds = lists
        return t
    }

    /// THE BUG: a parent with no list membership must still find its children.
    func testAParentWithNoListStillFindsItsSubtasks() {
        let parent = task("parent", lists: nil)
        let all = [parent, task("sub-1", parent: "parent"), task("other", parent: nil)]

        XCTAssertEqual(MacSubtasks.of(parent: parent, in: all).map(\.id), ["sub-1"],
                       "a listless parent found nothing — every task added from My Tasks")
    }

    /// A subtask that does not share the parent's lists is still its subtask.
    func testASubtaskInADifferentListIsStillFound() {
        let parent = task("parent", lists: ["list-a"])
        let all = [parent, task("sub-1", parent: "parent", lists: ["list-b"])]

        XCTAssertEqual(MacSubtasks.of(parent: parent, in: all).map(\.id), ["sub-1"])
    }

    /// The ordinary case keeps working.
    func testFindsSubtasksSharingTheParentsList() {
        let parent = task("parent", lists: ["list-a"])
        let all = [parent, task("sub-1", parent: "parent", lists: ["list-a"]),
                   task("sub-2", parent: "parent", lists: ["list-a"])]

        XCTAssertEqual(MacSubtasks.of(parent: parent, in: all).map(\.id), ["sub-1", "sub-2"])
    }

    /// Someone else's children must not appear, and neither must the parent itself.
    func testExcludesOtherParentsChildrenAndTheParent() {
        let parent = task("parent", lists: ["list-a"])
        let all = [parent,
                   task("sub-1", parent: "parent", lists: ["list-a"]),
                   task("cousin", parent: "another-parent", lists: ["list-a"]),
                   task("loose", parent: nil, lists: ["list-a"])]

        XCTAssertEqual(MacSubtasks.of(parent: parent, in: all).map(\.id), ["sub-1"])
    }

    /// No children is an empty list, not a crash or the whole list.
    func testAParentWithNoSubtasksFindsNone() {
        let parent = task("parent", lists: ["list-a"])
        let all = [parent, task("loose", parent: nil, lists: ["list-a"])]

        XCTAssertTrue(MacSubtasks.of(parent: parent, in: all).isEmpty)
    }

    /// Each subtask appears once even when the parent belongs to several lists — the old
    /// flatMap over lists could yield the same task twice.
    func testASubtaskIsNotDuplicatedWhenTheParentIsInSeveralLists() {
        let parent = task("parent", lists: ["list-a", "list-b"])
        let all = [parent, task("sub-1", parent: "parent", lists: ["list-a", "list-b"])]

        XCTAssertEqual(MacSubtasks.of(parent: parent, in: all).map(\.id), ["sub-1"])
    }
}
#endif
