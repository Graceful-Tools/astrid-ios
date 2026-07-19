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
        XCTAssertEqual(targets.first?.label, "My Tasks only")
    }

    func testTargetIdentityStable() {
        // My Tasks target has a stable id even with a nil listId (for ForEach).
        XCTAssertEqual(MacCopyTarget(listId: nil, label: "My Tasks only").id, "__mytasks__")
        XCTAssertEqual(MacCopyTarget(listId: "abc", label: "Work").id, "abc")
    }
}
#endif
