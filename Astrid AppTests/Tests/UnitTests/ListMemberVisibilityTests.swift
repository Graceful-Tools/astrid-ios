//  ListMemberVisibilityTests.swift
//  Regression guard for Task 4a338b53 — the members endpoint no longer 403s a plain member.
//
//  Neither client gated the FETCH on admin/owner, so the section starts appearing on its own; that
//  half needed no change. What did need one is the case the change introduces:
//
//  A NON-MEMBER viewing a PUBLIC list now gets HTTP 200 with `{ members: [], user_role: "viewer" }`
//  — not a 403, and not the real list. The array is empty because the member payload carries EMAIL
//  ADDRESSES, so an outsider must not see it.
//
//  Two different situations therefore arrive as the same empty array:
//
//    - "this list genuinely has nobody on it"      → "No members yet" is right
//    - "you may look at the list, not at who is on it" → "No members yet" is a LIE
//
//  Only `user_role` separates them, and iOS did not read that field at all.

import XCTest
@testable import Astrid_App

final class ListMemberVisibilityTests: XCTestCase {

    // MARK: - The field has to survive decoding

    func testAViewerResponseDecodesItsRole() throws {
        let json = #"{"members":[],"user_role":"viewer","meta":{"apiVersion":"v1"}}"#
        let response = try JSONDecoder().decode(ListMembersResponse.self, from: Data(json.utf8))
        XCTAssertTrue(response.members.isEmpty)
        XCTAssertEqual(response.userRole, "viewer")
    }

    /// The field is absent on older payloads and on routes that never send it — that must decode,
    /// not throw, or the members screen breaks for everyone rather than degrading.
    func testAResponseWithoutTheRoleStillDecodes() throws {
        let json = #"{"members":[],"meta":{"apiVersion":"v1"}}"#
        let response = try JSONDecoder().decode(ListMembersResponse.self, from: Data(json.utf8))
        XCTAssertNil(response.userRole)
    }

    // MARK: - What the screen should say

    /// The lie this task exists to prevent.
    func testAViewerOfAPublicListIsNotToldTheListIsEmpty() {
        XCTAssertEqual(ListMemberVisibility.emptyState(userRole: "viewer"), .hiddenFromViewer,
                       "an empty array from a viewer means 'not shown to you', not 'nobody here'")
    }

    /// A real member looking at a list that genuinely has nobody else.
    func testAMemberSeeingNoOneIsAnEmptyList() {
        for role in ["member", "admin", "owner"] {
            XCTAssertEqual(ListMemberVisibility.emptyState(userRole: role), .genuinelyEmpty,
                           "\(role) sees the real list, so empty means empty")
        }
    }

    /// No role at all — an older server, or a payload that omits it. Prefer the honest, less
    /// specific message over asserting something we cannot know.
    func testAnUnknownRoleDoesNotClaimTheListIsEmpty() {
        XCTAssertEqual(ListMemberVisibility.emptyState(userRole: nil), .hiddenFromViewer)
        XCTAssertEqual(ListMemberVisibility.emptyState(userRole: "something-new"), .hiddenFromViewer)
    }

    /// And when there ARE members, the role is irrelevant — render them.
    func testTheEmptyStateOnlyAppliesWhenThereAreNoMembers() {
        XCTAssertFalse(ListMemberVisibility.showsEmptyState(memberCount: 1, userRole: "viewer"))
        XCTAssertFalse(ListMemberVisibility.showsEmptyState(memberCount: 3, userRole: "member"))
        XCTAssertTrue(ListMemberVisibility.showsEmptyState(memberCount: 0, userRole: "member"))
    }

    // MARK: - Viewing is not managing

    /// The change widened who may LOOK. It did not widen who may change anything, and the server
    /// still enforces that separately — so the mutating controls stay where they were.
    func testViewingDoesNotImplyManaging() {
        var list = TaskList(id: "l1", name: "L", privacy: .PUBLIC)
        list.ownerId = "owner"
        list.listMembers = [ListMember(id: "m1", listId: "l1", userId: "plain", role: "member")]

        XCTAssertFalse(ListPermissions.canEditSettings(list, userId: "plain"),
                       "a plain member may now SEE the roster but still not manage it")
        XCTAssertFalse(ListPermissions.canEditSettings(list, userId: "stranger"))
        XCTAssertTrue(ListPermissions.canEditSettings(list, userId: "owner"))
    }
}
