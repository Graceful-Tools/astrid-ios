//  ListMembershipRosterTests.swift
//  Tests for AITD-388 — bringing the Mac's list membership up to what iOS and Web already do.
//
//  Both rules here existed only inside an iOS view, so the Mac had no copy and behaved
//  differently: it rendered pending invitations as though they were full members, and offered no
//  way to leave a list at all.

import XCTest
@testable import Astrid_App

final class ListMembershipRosterTests: XCTestCase {

    private let me = "u-me"

    private func user(_ id: String, _ email: String) -> User {
        User(id: id, email: email, name: id, image: nil)
    }

    private func member(_ id: String, _ email: String, role: String) -> ListMember {
        ListMember(id: "lm-\(id)", listId: "l1", userId: id, role: role, user: user(id, email))
    }

    private func invite(_ email: String, role: String = "member") -> ListInvite {
        ListInvite(id: "inv-\(email)", listId: "l1", email: email, role: role, token: "t")
    }

    private func list(owner: User?, ownerId: String?, members: [ListMember] = [],
                      invitations: [ListInvite] = [], privacy: TaskList.Privacy = .SHARED) -> TaskList {
        var l = TaskList(id: "l1", name: "Work", privacy: privacy)
        l.owner = owner
        l.ownerId = ownerId
        l.listMembers = members
        l.invitations = invitations
        return l
    }

    // MARK: - Pending invitations

    /// The bug this rule prevents: an invitation row survives being accepted, so an unfiltered
    /// list shows someone who joined days ago as permanently "pending" — twice on screen, once as
    /// a member and once as an invitation.
    func testAnAcceptedInvitationIsNoLongerPending() {
        let l = list(owner: user("u-own", "own@x.com"), ownerId: "u-own",
                     members: [member("u-sam", "sam@x.com", role: "member")],
                     invitations: [invite("sam@x.com")])
        XCTAssertTrue(ListMembershipRoster.pendingInvitations(in: l).isEmpty,
                      "AITD-388: sam already joined — that invitation is history, not a pending row")
    }

    func testAnUnacceptedInvitationIsPending() {
        let l = list(owner: user("u-own", "own@x.com"), ownerId: "u-own",
                     members: [member("u-sam", "sam@x.com", role: "member")],
                     invitations: [invite("newcomer@x.com", role: "admin")])
        let pending = ListMembershipRoster.pendingInvitations(in: l)
        XCTAssertEqual(pending.map(\.email), ["newcomer@x.com"])
        XCTAssertEqual(pending.first?.role, "admin", "the invited role has to survive to the row")
    }

    /// An owner who invited themselves before creating the list must not be pending on their own
    /// list.
    func testTheOwnerIsNeverPendingOnTheirOwnList() {
        let l = list(owner: user("u-own", "own@x.com"), ownerId: "u-own",
                     invitations: [invite("own@x.com")])
        XCTAssertTrue(ListMembershipRoster.pendingInvitations(in: l).isEmpty)
    }

    func testNoInvitationsIsEmptyNotACrash() {
        XCTAssertTrue(ListMembershipRoster.pendingInvitations(
            in: list(owner: nil, ownerId: "u-own")).isEmpty)
    }

    // MARK: - Leaving

    /// An owner is never offered a plain "Leave" — ownership is what `canDelete` keys on, so it
    /// has to be handed over deliberately rather than implied by whoever remains.
    func testTheOwnerIsOfferedTransferRatherThanLeave() {
        let l = list(owner: user(me, "me@x.com"), ownerId: me,
                     members: [member("u-sam", "sam@x.com", role: "admin")])
        XCTAssertEqual(ListMembershipRoster.leaveOption(for: l, userId: me), .transferOwnership)
    }

    func testAPlainMemberCanAlwaysLeave() {
        let l = list(owner: user("u-own", "own@x.com"), ownerId: "u-own",
                     members: [member(me, "me@x.com", role: "member")])
        XCTAssertEqual(ListMembershipRoster.leaveOption(for: l, userId: me), .leave)
    }

    /// A non-owner admin leaving still leaves the owner behind, so it is allowed.
    func testAnAdminMayLeaveWhileAnOwnerRemains() {
        let l = list(owner: user("u-own", "own@x.com"), ownerId: "u-own",
                     members: [member(me, "me@x.com", role: "admin")])
        XCTAssertEqual(ListMembershipRoster.leaveOption(for: l, userId: me), .leave)
    }

    /// The guard that matters: never strand a list with nobody who can administer it.
    func testTheLastAdministratorMayNotLeave() {
        var l = list(owner: nil, ownerId: nil,
                     members: [member(me, "me@x.com", role: "admin"),
                               member("u-sam", "sam@x.com", role: "member")])
        l.ownerId = nil
        XCTAssertEqual(ListMembershipRoster.leaveOption(for: l, userId: me), .none,
                       "AITD-388: leaving would leave nobody able to invite, rename or delete it")
    }

    func testAnAdminMayLeaveWhenAnotherAdminRemains() {
        let l = list(owner: nil, ownerId: nil,
                     members: [member(me, "me@x.com", role: "admin"),
                               member("u-sam", "sam@x.com", role: "admin")])
        XCTAssertEqual(ListMembershipRoster.leaveOption(for: l, userId: me), .leave)
    }

    /// Looking at a public list you never joined. There is nothing to leave.
    func testAViewerOfAPublicListIsOfferedNothing() {
        let l = list(owner: user("u-own", "own@x.com"), ownerId: "u-own", privacy: .PUBLIC)
        XCTAssertEqual(ListMembershipRoster.leaveOption(for: l, userId: me), .none)
    }

    func testASignedOutUserIsOfferedNothing() {
        let l = list(owner: user("u-own", "own@x.com"), ownerId: "u-own")
        XCTAssertEqual(ListMembershipRoster.leaveOption(for: l, userId: nil), .none)
    }

    // MARK: - The owner counts as an administrator

    /// On most lists the owner is not a `listMembers` row at all, so missing them would tell the
    /// single admin of a perfectly healthy list that they are trapped.
    func testTheOwnerCountsEvenWhenNotAMemberRow() {
        let l = list(owner: user("u-own", "own@x.com"), ownerId: "u-own",
                     members: [member(me, "me@x.com", role: "admin")])
        XCTAssertTrue(ListMembershipRoster.hasAnotherAdministrator(l, excluding: me))
    }
}
