//  ListMemberServiceTests.swift
//  ListMemberService through astrid-core with the server unreachable (AITD-535). A membership
//  change is sent at once and queued ONLY when the network is what failed (CONTRACTS D31); the
//  unit-test host's server never answers, so this is the queued branch: an invitation made offline
//  shows as a pending `temp_…` invitation — never as a member — and stays editable until it is sent.

import XCTest
@testable import Astrid_App

@MainActor
final class ListMemberServiceTests: XCTestCase {
    private var members: ListMemberService { ListMemberService.shared }

    private func makeList() async throws -> TaskList {
        try await ListService.shared.createList(name: "Shared \(UUID().uuidString)")
    }

    func testAnInvitationMadeOfflineIsQueuedAsAPendingInvitation_AITD535() async throws {
        let list = try await makeList()

        let made = try await members.addMember(listId: list.id, email: "friend@example.com", role: "member")

        XCTAssertTrue(made.id.hasPrefix("temp_"), "queued offline, the row is a placeholder: \(made.id)")
        XCTAssertEqual(made.role, "member")
        XCTAssertEqual(made.user?.email, "friend@example.com")
        XCTAssertEqual(made.user?.isPending, true, "an invitation, never a member")

        let rows = try XCTUnwrap(members.membersByList[list.id])
        XCTAssertEqual(rows.map(\.id), [made.id])
        XCTAssertEqual(ListService.shared.getList(id: list.id)?.invitations?.map(\.email), ["friend@example.com"])
        XCTAssertEqual(ListService.shared.getList(id: list.id)?.listMembers?.count ?? 0, 0,
                       "a queued invitation is not a member on the cached list either")
    }

    /// The person who invited can still change their mind before it is sent.
    func testAQueuedInvitationsRoleCanChange_AITD535() async throws {
        let list = try await makeList()
        let made = try await members.addMember(listId: list.id, email: "editor@example.com", role: "member")

        try await members.updateInvitationRole(
            listId: list.id, invitationId: made.id, email: "editor@example.com", role: "admin")

        XCTAssertEqual(members.membersByList[list.id]?.first { $0.id == made.id }?.role, "admin")
        XCTAssertEqual(ListService.shared.getList(id: list.id)?.invitations?.first?.role, "admin")
    }

    func testAQueuedInvitationCanBeCancelled_AITD535() async throws {
        let list = try await makeList()
        let made = try await members.addMember(listId: list.id, email: "oops@example.com", role: "member")

        try await members.cancelInvitation(listId: list.id, invitationId: made.id, email: "oops@example.com")

        XCTAssertEqual(members.membersByList[list.id]?.map(\.id) ?? [], [])
        XCTAssertEqual(ListService.shared.getList(id: list.id)?.invitations?.count ?? 0, 0)
    }

    /// The rows the views draw: members first, then invitations — a server invitation as
    /// `invite_<id>`, a queued one under its own placeholder id.
    func testRowsListMembersThenInvitations_AITD535() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let list = try decoder.decode(TaskList.self, from: Data("""
        {"id":"l-1","name":"Rows",
         "listMembers":[{"id":"m-1","listId":"l-1","userId":"u-1","role":"admin",
                         "user":{"id":"u-1","email":"owner@example.com"}}],
         "invitations":[{"id":"inv-9","listId":"l-1","email":"sent@example.com","role":"member","token":"t1"},
                        {"id":"temp_abc","listId":"l-1","email":"queued@example.com","role":"member","token":""}]}
        """.utf8))

        let rows = ListMemberService.rows(for: list)

        XCTAssertEqual(rows.map(\.id), ["m-1", "invite_inv-9", "temp_abc"])
        XCTAssertEqual(rows.map { $0.user?.isPending ?? false }, [false, true, true])
        XCTAssertEqual(rows.map { $0.user?.email }, ["owner@example.com", "sent@example.com", "queued@example.com"])
    }
}
