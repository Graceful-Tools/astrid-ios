//  MacTaskCopyTests.swift
//  Astrid for Mac — Task 1171030d: task Copy-target list (My Tasks first, real lists only).

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacTaskCopyTests: XCTestCase {

    func testMyTasksIsFirstAndEmptyListsHandled() {
        let targets = MacTaskCopy.targets(lists: [])
        XCTAssertEqual(targets.count, 1)
        XCTAssertNil(targets.first?.listId)
        XCTAssertEqual(targets.first?.label, NSLocalizedString("mac.my_tasks_only", comment: ""))
        XCTAssertNotEqual(targets.first?.label, "mac.my_tasks_only")
    }

    /// AITD-506: a GitHub sprint, milestone or label is a tag, never a copy destination.
    func testAITD506CopyTargetsNeverOfferATag() {
        var sprint = TaskList(id: "s4", name: "Sprint 4"); sprint.listType = "iteration"
        var label = TaskList(id: "bug", name: "Bug"); label.listType = "label"
        let targets = MacTaskCopy.targets(lists: [TaskList(id: "a", name: "Work"), sprint, label])
        XCTAssertEqual(targets.map(\.listId), [nil, "a"])
    }

    func testTargetIdentityStable() {
        // My Tasks target has a stable id even with a nil listId (for ForEach).
        XCTAssertEqual(MacCopyTarget(listId: nil, label: "My Tasks only").id, "__mytasks__")
        XCTAssertEqual(MacCopyTarget(listId: "abc", label: "Work").id, "abc")
    }
}
#endif
