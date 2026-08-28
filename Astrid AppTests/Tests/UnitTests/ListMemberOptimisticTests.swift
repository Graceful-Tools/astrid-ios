import XCTest
@testable import Astrid_App

/// Task 33fc21fc — "adding and removing members doesn't show up immediately on iOS.
/// They should optimistic update then sync."
///
/// The online branches of `ListMemberService.addMember` / `removeMember` /
/// `updateMemberRole` awaited the network and never touched `membersByList`, so every
/// caller's "optimistic" update was gated behind the round-trip. `ListMemberService`
/// itself is a `@MainActor` singleton with no dependency injection — its integration
/// tests are all `XCTSkip`'d for that reason — so the state math lives in pure
/// functions and is pinned here.
final class ListMemberOptimisticTests: XCTestCase {

    private func member(_ userId: String, role: String = "member", email: String? = nil) -> ListMember {
        ListMember(
            id: userId,
            listId: "list-1",
            userId: userId,
            role: role,
            user: User(id: userId, email: email ?? "\(userId)@example.com", name: userId, image: nil)
        )
    }

    private func list(_ members: [ListMember]) -> TaskList {
        var l = TaskList(id: "list-1", name: "List One")
        l.listMembers = members
        return l
    }

    // MARK: - Add

    func testAddPlaceholderAppearsImmediately() {
        let roster = [member("u1")]
        let placeholder = ListMemberOptimistic.placeholder(
            id: "temp_1", listId: "list-1", email: "new@example.com", role: "admin"
        )
        let after = ListMemberOptimistic.applyingAdd(roster, member: placeholder)

        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after.last?.id, "temp_1")
        XCTAssertEqual(after.last?.role, "admin")
        XCTAssertEqual(after.last?.user?.email, "new@example.com",
                       "The row has to render before the server tells us the person's name")
    }

    func testAddIsIdempotentOnTheSameEmail() {
        // Double-tapping Add must not produce two rows for one person.
        let placeholder = ListMemberOptimistic.placeholder(
            id: "temp_1", listId: "list-1", email: "new@example.com", role: "member"
        )
        let once = ListMemberOptimistic.applyingAdd([member("u1")], member: placeholder)
        let twice = ListMemberOptimistic.applyingAdd(once, member: placeholder)
        XCTAssertEqual(twice.count, 2)
    }

    func testAddDoesNotDuplicateAnExistingMember() {
        let roster = [member("u1", email: "u1@example.com")]
        let placeholder = ListMemberOptimistic.placeholder(
            id: "temp_1", listId: "list-1", email: "u1@example.com", role: "admin"
        )
        let after = ListMemberOptimistic.applyingAdd(roster, member: placeholder)
        XCTAssertEqual(after.count, 1, "Re-adding an existing email must not create a second row")
        XCTAssertEqual(after.first?.userId, "u1", "The real member wins over the placeholder")
    }

    // MARK: - Reconcile

    func testReconcileSwapsThePlaceholderForTheServerRow() {
        let placeholder = ListMemberOptimistic.placeholder(
            id: "temp_1", listId: "list-1", email: "new@example.com", role: "member"
        )
        let roster = ListMemberOptimistic.applyingAdd([member("u1")], member: placeholder)
        let confirmed = member("u2", email: "new@example.com")

        let after = ListMemberOptimistic.reconcilingAdd(roster, placeholderId: "temp_1", confirmed: confirmed)

        XCTAssertEqual(after.count, 2)
        XCTAssertFalse(after.contains { $0.id == "temp_1" }, "The placeholder must not survive the swap")
        XCTAssertEqual(after.last?.userId, "u2")
        XCTAssertEqual(after.last?.user?.name, "u2", "The real name replaces the email-only stub")
    }

    func testReconcileKeepsThePlaceholderForAnInviteOnlyResponse() {
        // The server queued an invitation — nobody joined yet, but the pending row
        // must stay visible or the add looks like it did nothing.
        let placeholder = ListMemberOptimistic.placeholder(
            id: "temp_1", listId: "list-1", email: "new@example.com", role: "member"
        )
        let roster = ListMemberOptimistic.applyingAdd([], member: placeholder)
        let after = ListMemberOptimistic.reconcilingAdd(roster, placeholderId: "temp_1", confirmed: nil)

        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.id, "temp_1")
    }

    func testRollbackRemovesThePlaceholderWhenTheAddFails() {
        let placeholder = ListMemberOptimistic.placeholder(
            id: "temp_1", listId: "list-1", email: "new@example.com", role: "member"
        )
        let roster = ListMemberOptimistic.applyingAdd([member("u1")], member: placeholder)
        let after = ListMemberOptimistic.applyingRemoval(roster, memberId: "temp_1")

        XCTAssertEqual(after.map(\.userId), ["u1"])
    }

    // MARK: - Remove

    func testRemovalDropsTheRowImmediately() {
        let roster = [member("u1"), member("u2")]
        let after = ListMemberOptimistic.applyingRemoval(roster, userId: "u1")
        XCTAssertEqual(after.map(\.userId), ["u2"])
    }

    func testRemovalMatchesOnTheNestedUserIdToo() {
        // Server rosters key the row id off the membership, not the user, so a
        // removal that only compared `id` left the row on screen.
        var row = member("u1")
        row.id = "membership-abc"
        let after = ListMemberOptimistic.applyingRemoval([row, member("u2")], userId: "u1")
        XCTAssertEqual(after.map(\.userId), ["u2"])
    }

    // MARK: - Role change

    func testRoleChangeIsVisibleBeforeTheServerAnswers() {
        let roster = [member("u1", role: "member"), member("u2", role: "member")]
        let after = ListMemberOptimistic.applyingRoleChange(roster, userId: "u1", role: "admin")

        XCTAssertEqual(after.first(where: { $0.userId == "u1" })?.role, "admin")
        XCTAssertEqual(after.first(where: { $0.userId == "u2" })?.role, "member", "Only the target changes")
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after.map(\.userId), ["u1", "u2"], "Order must not shuffle under the user")
    }

    func testRoleChangeKeepsTheHydratedUser() {
        let roster = [member("u1", role: "member", email: "u1@example.com")]
        let after = ListMemberOptimistic.applyingRoleChange(roster, userId: "u1", role: "admin")
        XCTAssertEqual(after.first?.user?.email, "u1@example.com",
                       "Rebuilding the row must not blank the avatar and name")
    }

    // MARK: - TaskList mirror

    func testTaskListMirrorAddsToEveryRosterTheViewsRead() {
        var subject = list([member("u1")])
        subject.members = [User(id: "u1", email: "u1@example.com", name: "u1", image: nil)]
        subject.admins = []

        let placeholder = ListMemberOptimistic.placeholder(
            id: "temp_1", listId: "list-1", email: "new@example.com", role: "admin"
        )
        let after = ListMemberOptimistic.applyingAdd(subject, member: placeholder)

        XCTAssertEqual(after.listMembers?.count, 2)
        XCTAssertEqual(after.admins?.map(\.id), ["temp_1"], "An admin add shows up in `admins`")
        XCTAssertEqual(after.members?.map(\.id), ["u1"], "…and not in `members`")
    }

    func testTaskListMirrorRemovesFromEveryRoster() {
        var subject = list([member("u1"), member("u2", role: "admin")])
        subject.members = [User(id: "u1", email: "u1@example.com", name: "u1", image: nil)]
        subject.admins = [User(id: "u2", email: "u2@example.com", name: "u2", image: nil)]

        let after = ListMemberOptimistic.applyingRemoval(subject, userId: "u2")

        XCTAssertEqual(after.listMembers?.map(\.userId), ["u1"])
        XCTAssertEqual(after.admins?.count, 0)
        XCTAssertEqual(after.members?.map(\.id), ["u1"])
    }

    func testTaskListMirrorMovesThePersonBetweenRostersOnRoleChange() {
        var subject = list([member("u1", role: "member")])
        subject.members = [User(id: "u1", email: "u1@example.com", name: "u1", image: nil)]
        subject.admins = []

        let after = ListMemberOptimistic.applyingRoleChange(subject, userId: "u1", role: "admin")

        XCTAssertEqual(after.listMembers?.first?.role, "admin")
        XCTAssertEqual(after.admins?.map(\.id), ["u1"], "Promotion has to move the row, not copy it")
        XCTAssertEqual(after.members?.count, 0)
    }

    // MARK: - ListService cache

    /// The optimistic edit has to land in `lists` AND `cachedLists` together.
    /// `removeMemberFromCachedList` wrote both by hand; add and role-change had no
    /// equivalent at all, which is how a change could survive one screen and not the
    /// next (task 33fc21fc).
    @MainActor
    func testCachedListAndVisibleListMoveTogether() {
        let service = ListService.shared
        let saved = service.lists
        defer { service.lists = saved }

        service.lists = [list([member("u1")])]

        service.applyMemberChange(listId: "list-1") {
            ListMemberOptimistic.applyingRoleChange($0, userId: "u1", role: "admin")
        }

        XCTAssertEqual(service.lists.first?.listMembers?.first?.role, "admin")
        XCTAssertEqual(service.listsById["list-1"]?.listMembers?.first?.role, "admin",
                       "The cached copy is what survives a view dismissal")
    }

    @MainActor
    func testRemoveMemberFromCachedListStillWorksThroughTheSharedHelper() {
        let service = ListService.shared
        let saved = service.lists
        defer { service.lists = saved }

        var subject = list([member("u1"), member("u2")])
        subject.members = [
            User(id: "u1", email: "u1@example.com", name: "u1", image: nil),
            User(id: "u2", email: "u2@example.com", name: "u2", image: nil)
        ]
        service.lists = [subject]

        service.removeMemberFromCachedList(listId: "list-1", userId: "u2")

        XCTAssertEqual(service.lists.first?.listMembers?.map(\.userId), ["u1"])
        XCTAssertEqual(service.lists.first?.members?.map(\.id), ["u1"])
        XCTAssertEqual(service.listsById["list-1"]?.listMembers?.map(\.userId), ["u1"])
    }
}
