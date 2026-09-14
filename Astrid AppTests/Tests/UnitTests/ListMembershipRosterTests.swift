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

    // MARK: - AITD-399: finding one person on the roster

    /// An agent is ADDED by email and REMOVED by user id, so this hop is unavoidable. Each
    /// membership tab used to make it by hand over its own roster source, which is exactly the
    /// kind of lookup that drifts.
    func testAITD399_MemberIdIsFoundFromTheEmailAnAgentWasInvitedWith() {
        let l = list(owner: user("u-own", "own@x.com"), ownerId: "u-own",
                     members: [member("ai-agent-claude", "claude@astrid.cc", role: "member")])
        XCTAssertEqual(ListMembershipRoster.memberId(forEmail: "claude@astrid.cc", in: l),
                       "ai-agent-claude")
    }

    /// On most lists the OWNER has no `listMembers` row at all, so a roster-only search would
    /// miss an agent that owns the list and the remove would silently do nothing.
    func testAITD399_MemberIdFindsTheOwnerWhoHasNoMemberRow() {
        let l = list(owner: user("ai-agent-claude", "claude@astrid.cc"), ownerId: "ai-agent-claude")
        XCTAssertEqual(ListMembershipRoster.memberId(forEmail: "claude@astrid.cc", in: l),
                       "ai-agent-claude")
    }

    /// The Mac reads `ListMemberService.membersByList`, which is not on the `TaskList` snapshot
    /// iOS reads — so the lookup has to accept a roster the list itself does not carry.
    func testAITD399_MemberIdFallsBackToASeparatelyFetchedRoster() {
        let l = list(owner: user("u-own", "own@x.com"), ownerId: "u-own")
        let fetched = [member("ai-agent-claude", "claude@astrid.cc", role: "member")]
        XCTAssertEqual(ListMembershipRoster.memberId(forEmail: "claude@astrid.cc", in: l, roster: fetched),
                       "ai-agent-claude")
    }

    /// Not on the list is a real answer, not an error — the agent was already removed, or never
    /// joined. Both tabs turned this into a bare `return`, so nothing was said either way.
    func testAITD399_MemberIdIsNilForSomebodyWhoIsNotOnTheList() {
        let l = list(owner: user("u-own", "own@x.com"), ownerId: "u-own",
                     members: [member("u-sam", "sam@x.com", role: "member")])
        XCTAssertNil(ListMembershipRoster.memberId(forEmail: "claude@astrid.cc", in: l))
    }

    func testAITD399_MembershipIsCheckedAgainstTheOwnerTheListRowsAndAFetchedRoster() {
        let l = list(owner: user("u-own", "own@x.com"), ownerId: "u-own",
                     members: [member("u-sam", "sam@x.com", role: "member")])
        XCTAssertTrue(ListMembershipRoster.isMember(email: "own@x.com", of: l))
        XCTAssertTrue(ListMembershipRoster.isMember(email: "sam@x.com", of: l))
        XCTAssertTrue(ListMembershipRoster.isMember(
            email: "claude@astrid.cc", of: l,
            roster: [member("ai-agent-claude", "claude@astrid.cc", role: "member")]))
        XCTAssertFalse(ListMembershipRoster.isMember(email: "nobody@x.com", of: l))
        XCTAssertFalse(ListMembershipRoster.isMember(email: nil, of: l))
    }

    /// iOS removes a row optimistically and remembers it, because a refresh already in flight can
    /// land with the old membership and put the row back. `excluding:` is that memory — without
    /// it the Add button would flip back to "already a member" for a second.
    func testAITD399_AMemberRemovedAMomentAgoIsNotStillAMember() {
        let l = list(owner: user("u-own", "own@x.com"), ownerId: "u-own",
                     members: [member("ai-agent-claude", "claude@astrid.cc", role: "member")])
        XCTAssertFalse(ListMembershipRoster.isMember(email: "claude@astrid.cc", of: l,
                                                     excluding: ["claude@astrid.cc"]))
    }

    /// An agent record with no email cannot be invited — there is nothing to invite. It used to
    /// be a silent `guard ... else { return }` on both platforms; now it is an error with copy.
    func testAITD399_AnAgentWithNoEmailReportsWhyItCannotBeAdded() async {
        let agent = User(id: "ai-agent-nameless", email: nil, name: "Nameless", image: nil)
        do {
            _ = try await ListMembershipActions.addAgent(agent, toList: "l1")
            XCTFail("AITD-399: an agent with no email must not reach the network")
        } catch let error as ListMembershipActions.AgentError {
            guard case .noEmail = error else { return XCTFail("wrong case: \(error)") }
            XCTAssertFalse(error.localizedDescription.isEmpty,
                           "AITD-399: the failure needs user-facing copy, not a silent return")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAITD399_RemovingAnAgentThatIsNotOnTheListSaysSo() async {
        let l = list(owner: user("u-own", "own@x.com"), ownerId: "u-own")
        let agent = User(id: "ai-agent-claude", email: "claude@astrid.cc", name: "Claude", image: nil)
        do {
            try await ListMembershipActions.removeAgent(agent, fromList: l, roster: [])
            XCTFail("AITD-399: there is no membership to remove")
        } catch let error as ListMembershipActions.AgentError {
            guard case .notAMember(let email) = error else { return XCTFail("wrong case: \(error)") }
            XCTAssertEqual(email, "claude@astrid.cc")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    /// Neither tab may re-grow its own wrappers: that is how they came to disagree.
    func testAITD399_NeitherMembershipTabCallsTheMemberServiceDirectly() throws {
        let root = RepositoryLocator.root
        for path in ["Astrid App/Views/Lists/ListMembershipTab.swift",
                     "Astrid Mac/Views/MacListMembershipTab.swift"] {
            let src = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            for call in ["memberService.addMember", "memberService.updateMemberRole",
                         "memberService.removeMember", "memberService.cancelInvitation",
                         "svc.addMember", "svc.updateMemberRole", "svc.removeMember",
                         "svc.cancelInvitation", "svc.updateInvitationRole"] {
                XCTAssertFalse(src.contains(call),
                               "\(path) should go through ListMembershipActions, not \(call)")
            }
        }
    }
}
