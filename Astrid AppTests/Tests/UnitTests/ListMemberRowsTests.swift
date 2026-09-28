//  ListMemberRowsTests.swift
//  The roster lives on the cached list now (astrid-core keeps `listMembers` and `invitations`
//  there); `ListMemberService.rows(for:)` is how a list becomes the rows the member screens draw.
//  Invitations keep the ids the screens key their pending styling on: `invite_…` for the server's,
//  `temp_…` for one made offline and still queued (CONTRACTS D31).

import XCTest
@testable import Astrid_App

@MainActor
final class ListMemberRowsTests: XCTestCase {
    private func list(members: [ListMember], invitations: [ListInvite]) throws -> TaskList {
        let json: [String: Any] = ["id": "l1", "name": "Shared"]
        var list = try JSONDecoder().decode(TaskList.self, from: JSONSerialization.data(withJSONObject: json))
        list.listMembers = members
        list.invitations = invitations
        return list
    }

    func testMembersComeFirstThenInvitationsAsPendingRows() throws {
        let dana = ListMember(id: "m1", listId: "l1", userId: "dana", role: "admin",
                              user: User(id: "dana", email: "dana@example.com", name: "Dana", image: nil))
        let sent = ListInvite(id: "i1", listId: "l1", email: "ada@example.com", role: "member", token: "")
        let queued = ListInvite(id: "temp_q", listId: "l1", email: "bo@example.com", role: "admin", token: "")

        let rows = ListMemberService.rows(for: try list(members: [dana], invitations: [sent, queued]))
        XCTAssertEqual(rows.map(\.id), ["m1", "invite_i1", "temp_q"])
        XCTAssertEqual(rows[1].user?.email, "ada@example.com")
        XCTAssertEqual(rows[1].user?.isPending, true)
        XCTAssertEqual(rows[2].role, "admin")
        XCTAssertTrue(ListMemberOptimistic.isPlaceholder(rows[2].id), "a queued invitation draws as pending")
    }
}
