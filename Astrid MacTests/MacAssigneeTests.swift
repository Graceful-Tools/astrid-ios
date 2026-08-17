//  MacAssigneeTests.swift
//  Astrid for Mac — Task 942e49df: show the assignee avatar only for tasks assigned to someone else.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacAssigneeTests: XCTestCase {

    func testShowsAvatarOnlyForOthersInListMode() {
        // Assigned to someone else → avatar.
        XCTAssertTrue(MacAssignee.showsAvatar(assigneeId: "other", currentUserId: "me", displayMode: .list))
        // Assigned to me → checkbox (no avatar), because in list mode the checkbox is how you
        // complete the task.
        XCTAssertFalse(MacAssignee.showsAvatar(assigneeId: "me", currentUserId: "me", displayMode: .list))
        // Unassigned → checkbox.
        XCTAssertFalse(MacAssignee.showsAvatar(assigneeId: nil, currentUserId: "me", displayMode: .list))
        XCTAssertFalse(MacAssignee.showsAvatar(assigneeId: "", currentUserId: "me", displayMode: .list))
    }

    /// PROJECT mode shows YOUR face too (task 132d7b3f). This helper used to spell the rule
    /// itself — "assigned, and not to me" — so the mode could not reach it; it now delegates
    /// to the shared `TaskLeadingControl`, and this is the case that proves the delegation is
    /// real rather than a rename.
    func testProjectModeShowsYourOwnFace() {
        XCTAssertTrue(MacAssignee.showsAvatar(assigneeId: "me", currentUserId: "me", displayMode: .project))
    }

    /// The mode changes exactly one case: unassigned still has no face to show.
    func testProjectModeStillHasNoFaceForAnUnassignedTask() {
        XCTAssertFalse(MacAssignee.showsAvatar(assigneeId: nil, currentUserId: "me", displayMode: .project))
        XCTAssertFalse(MacAssignee.showsAvatar(assigneeId: "", currentUserId: "me", displayMode: .project))
    }

    func testUnknownCurrentUserStillDistinguishes() {
        // Signed-out / unknown current user: an assigned task still shows the assignee, and
        // project mode must not invent a "you" to show a face for.
        for mode in TaskDisplayMode.allCases {
            XCTAssertTrue(MacAssignee.showsAvatar(assigneeId: "someone", currentUserId: nil, displayMode: mode))
            XCTAssertFalse(MacAssignee.showsAvatar(assigneeId: nil, currentUserId: nil, displayMode: mode))
        }
    }
}
#endif
