//  MacAssigneeTests.swift
//  Astrid for Mac — Task 942e49df: show the assignee avatar only for tasks assigned to someone else.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacAssigneeTests: XCTestCase {

    /// Delegates to the shared `TaskLeadingControl`: your own task is the checkbox, someone
    /// else's is their face, nobody's is the "U" (ADEV-70 removed the Project layout's own face).
    func testOnlySomeoneElsesTaskShowsAFace() {
        XCTAssertFalse(MacAssignee.showsAvatar(assigneeId: "me", currentUserId: "me"))
        XCTAssertTrue(MacAssignee.showsAvatar(assigneeId: "them", currentUserId: "me"))
        XCTAssertFalse(MacAssignee.showsAvatar(assigneeId: nil, currentUserId: "me"))
    }

}
#endif
