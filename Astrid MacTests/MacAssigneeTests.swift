//  MacAssigneeTests.swift
//  Astrid for Mac — Task 942e49df: show the assignee avatar only for tasks assigned to someone else.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacAssigneeTests: XCTestCase {

    /// PROJECT mode shows YOUR face too (task 132d7b3f). This helper used to spell the rule
    /// itself — "assigned, and not to me" — so the mode could not reach it; it now delegates
    /// to the shared `TaskLeadingControl`, and this is the case that proves the delegation is
    /// real rather than a rename.
    func testProjectModeShowsYourOwnFace() {
        XCTAssertTrue(MacAssignee.showsAvatar(assigneeId: "me", currentUserId: "me", displayMode: .project))
    }

}
#endif
