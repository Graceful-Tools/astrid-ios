//  MacAssigneeTests.swift
//  Astrid for Mac — Task 942e49df: show the assignee avatar only for tasks assigned to someone else.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacAssigneeTests: XCTestCase {

    /// Delegates to the shared `TaskLeadingControl`: your own task is the checkbox, someone
    /// else's is their face, nobody's is the "U" (ADEV-70 removed the Project layout's own face).
    func testOnlySomeoneElsesTaskShowsAFace() {
        XCTAssertFalse(MacAssignee.showsAvatar(assigneeId: "me", currentUserId: "me", completed: false))
        XCTAssertTrue(MacAssignee.showsAvatar(assigneeId: "them", currentUserId: "me", completed: false))
        XCTAssertFalse(MacAssignee.showsAvatar(assigneeId: nil, currentUserId: "me", completed: false))
    }

    /// ADEV-147: a completed task is the checked box, even when it is someone else's.
    func testADEV147_aCompletedTaskShowsNoFace() {
        XCTAssertFalse(MacAssignee.showsAvatar(assigneeId: "them", currentUserId: "me", completed: true))
    }

}
#endif
