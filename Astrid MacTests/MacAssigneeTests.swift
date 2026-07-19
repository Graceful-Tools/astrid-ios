//  MacAssigneeTests.swift
//  Astrid for Mac — Task 942e49df: show the assignee avatar only for tasks assigned to someone else.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacAssigneeTests: XCTestCase {

    func testShowsAvatarOnlyForOthers() {
        // Assigned to someone else → avatar.
        XCTAssertTrue(MacAssignee.showsAvatar(assigneeId: "other", currentUserId: "me"))
        // Assigned to me → checkbox (no avatar).
        XCTAssertFalse(MacAssignee.showsAvatar(assigneeId: "me", currentUserId: "me"))
        // Unassigned → checkbox.
        XCTAssertFalse(MacAssignee.showsAvatar(assigneeId: nil, currentUserId: "me"))
        XCTAssertFalse(MacAssignee.showsAvatar(assigneeId: "", currentUserId: "me"))
    }

    func testUnknownCurrentUserStillDistinguishes() {
        // Signed-out / unknown current user: an assigned task still shows the assignee.
        XCTAssertTrue(MacAssignee.showsAvatar(assigneeId: "someone", currentUserId: nil))
        XCTAssertFalse(MacAssignee.showsAvatar(assigneeId: nil, currentUserId: nil))
    }
}
#endif
