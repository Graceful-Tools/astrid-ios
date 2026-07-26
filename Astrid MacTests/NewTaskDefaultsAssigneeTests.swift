//  NewTaskDefaultsAssigneeTests.swift
//  RED-first: `defaultAssigneeId` has three meanings on the wire (documented in ListDefaults):
//    nil          → "task_creator": the new task goes to whoever creates it
//    "unassigned" → nobody
//    an id        → that person
//  Mac was collapsing nil and "unassigned" into "no assignee", so a list whose default is the
//  creator produced UNASSIGNED tasks — and the quick-add showed "??" for a user it could not name.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class NewTaskDefaultsAssigneeTests: XCTestCase {

    private let me = "user-me"

    func testNilMeansTheTaskCreator() {
        XCTAssertEqual(NewTaskDefaults.assignee(nil, currentUserId: me), me,
                       "nil is 'task_creator', not 'no assignee'")
    }

    func testExplicitUnassignedMeansNobody() {
        XCTAssertNil(NewTaskDefaults.assignee("unassigned", currentUserId: me))
    }

    func testASpecificIdIsHonoured() {
        XCTAssertEqual(NewTaskDefaults.assignee("user-9", currentUserId: me), "user-9")
    }

    /// Signed out, "task creator" cannot be resolved — better unassigned than a bogus id.
    func testNoCurrentUserFallsBackToUnassigned() {
        XCTAssertNil(NewTaskDefaults.assignee(nil, currentUserId: nil))
    }

    /// An empty string is an ABSENT value, not the literal "unassigned" — so it means the same as
    /// nil: task creator. (I first asserted the opposite here; treating "" as unassigned would
    /// make a degenerate value behave differently from a missing one, which is not what the wire
    /// contract says.)
    func testEmptyStringIsTreatedAsAbsentNotUnassigned() {
        XCTAssertEqual(NewTaskDefaults.assignee("", currentUserId: me), me)
    }
}
#endif
