//  ListPermissionsTests.swift
//  Regression guard for Task da56d096 — "[Mac] update the 'rename' list to 'edit', make sure it is
//  accessible to only people that can edit/rename…"
//
//  The Mac sidebar context menu gated nothing: Edit, Sharing and Delete were offered to every
//  member. Underneath, the same rule existed in three copies, and the Mac one was not equivalent —
//  it compared role strings against a separately-fetched roster while iOS asked the shared model.
//
//  Delete is deliberately a SEPARATE question from edit: deleting a shared list destroys other
//  people's work, so it stays with the owner even though an admin may change everything else.

import XCTest
@testable import Astrid_App

final class ListPermissionsTests: XCTestCase {

    private func list(ownerId: String, members: [(String, String)] = [],
                      privacy: TaskList.Privacy = .PRIVATE) -> TaskList {
        var l = TaskList(id: "l1", name: "L", privacy: privacy)
        l.ownerId = ownerId
        l.listMembers = members.map {
            ListMember(id: "m-\($0.0)", listId: "l1", userId: $0.0, role: $0.1)
        }
        return l
    }

    // MARK: - Editing

    func testTheOwnerCanEdit() {
        XCTAssertTrue(ListPermissions.canEditSettings(list(ownerId: "u1"), userId: "u1"))
    }

    func testAnAdminCanEdit() {
        let l = list(ownerId: "u1", members: [("u2", "admin")])
        XCTAssertTrue(ListPermissions.canEditSettings(l, userId: "u2"))
    }

    /// The case the Mac menu got wrong: a plain member could see Edit, Sharing and Delete.
    func testAPlainMemberCannotEdit() {
        let l = list(ownerId: "u1", members: [("u2", "member")])
        XCTAssertFalse(ListPermissions.canEditSettings(l, userId: "u2"))
    }

    func testSomeoneWithNoRelationshipCannotEdit() {
        XCTAssertFalse(ListPermissions.canEditSettings(list(ownerId: "u1"), userId: "stranger"))
    }

    /// Being able to SEE a public list is not being able to reconfigure it.
    func testAViewerOfAPublicListCannotEdit() {
        let l = list(ownerId: "u1", privacy: .PUBLIC)
        XCTAssertFalse(ListPermissions.canEditSettings(l, userId: "stranger"))
    }

    /// Signed out is not an edge case worth a crash or a shrug — it is simply "no".
    func testNoUserCannotEdit() {
        XCTAssertFalse(ListPermissions.canEditSettings(list(ownerId: "u1"), userId: nil))
    }

    // MARK: - Deleting is stricter

    func testOnlyTheOwnerCanDelete() {
        let l = list(ownerId: "u1", members: [("u2", "admin"), ("u3", "member")])
        XCTAssertTrue(ListPermissions.canDelete(l, userId: "u1"))
        XCTAssertFalse(ListPermissions.canDelete(l, userId: "u2"),
                       "An admin may edit everything, but deleting destroys other people's work")
        XCTAssertFalse(ListPermissions.canDelete(l, userId: "u3"))
        XCTAssertFalse(ListPermissions.canDelete(l, userId: nil))
    }

    // MARK: - One rule, not four copies

    /// Every call site must read the shared helper. The Mac copy comparing role STRINGS against a
    /// different roster is exactly how the two platforms answered this differently.
    func testNoCallSiteHandRollsTheRule() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for relative in ["Astrid App/Views/Lists/ListMembershipTab.swift",
                         "Astrid App/Views/Lists/ListSettingsModal.swift",
                         "Astrid Mac/Views/MacListMembersView.swift",
                         "Astrid Mac/App/MacRootView.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            XCTAssertTrue(source.contains("ListPermissions."),
                          "\(relative) must ask the shared rule")
            // Only the hand-rolled OWNER-OR-ADMIN forms are banned. Comparing a role string is
            // fine elsewhere — ListMembershipTab legitimately does it to render and toggle
            // ANOTHER member's role, which is a different question from "may I edit this list".
            for handRolled in ["role == .owner || role == .admin",
                               #"myRole == "owner""#] {
                XCTAssertFalse(source.contains(handRolled),
                               "\(relative) still hand-rolls the permission rule: \(handRolled)")
            }
        }
    }
}
