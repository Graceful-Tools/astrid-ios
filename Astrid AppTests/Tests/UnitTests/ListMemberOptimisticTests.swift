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

    // MARK: - TaskList roster

    func testTaskListAddLandsInTheRoster() {
        let subject = list([member("u1")])
        let placeholder = ListMemberOptimistic.placeholder(
            id: "temp_1", listId: "list-1", email: "new@example.com", role: "admin"
        )

        let after = ListMemberOptimistic.applyingAdd(subject, member: placeholder)

        XCTAssertEqual(after.listMembers?.map(\.userId), ["u1", "temp_1"])
        XCTAssertEqual(after.listMembers?.last?.role, "admin", "The role rides on the roster row")
    }

    func testTaskListRemovalDropsTheRosterRow() {
        let subject = list([member("u1"), member("u2", role: "admin")])

        let after = ListMemberOptimistic.applyingRemoval(subject, userId: "u2")

        XCTAssertEqual(after.listMembers?.map(\.userId), ["u1"])
    }

    func testTaskListRoleChangeMovesTheRowRatherThanCopyingIt() {
        let subject = list([member("u1", role: "member"), member("u2", role: "member")])

        let after = ListMemberOptimistic.applyingRoleChange(subject, userId: "u1", role: "admin")

        XCTAssertEqual(after.listMembers?.count, 2, "Promotion has to move the row, not copy it")
        XCTAssertEqual(after.listMembers?.map(\.userId), ["u1", "u2"], "…and not reorder it")
        XCTAssertEqual(after.listMembers?.first?.role, "admin")
        XCTAssertEqual(after.listMembers?.last?.role, "member", "Only the target changes")
    }

    // MARK: - The legacy arrays are never written (AITD-322)
    //
    // `admins[]` / `members[]` are not populated by the endpoints iOS consumes and nothing
    // reads them any more (ASTRID.md §8 row 3, pinned on the read side by
    // `ListPermissionsContractTests`). The optimistic edit used to mirror into them anyway,
    // which was the one remaining way a cached `TaskList` could carry NON-EMPTY legacy arrays
    // into a later build — the exact condition that turns a re-introduced legacy branch from
    // harmlessly dead into live and disagreeing with web.

    /// Legacy arrays full, `listMembers` holding the real roster: the same pathological shape
    /// `ListPermissionsContractTests` builds, seen from the write side.
    private func legacyArmed(_ members: [ListMember]) -> TaskList {
        var l = list(members)
        l.admins = [User(id: "legacy-admin", email: "legacy-admin@example.com", name: "legacy-admin", image: nil)]
        l.members = [User(id: "legacy-member", email: "legacy-member@example.com", name: "legacy-member", image: nil)]
        return l
    }

    private func assertLegacyArraysUntouched(_ list: TaskList,
                                             _ message: String,
                                             file: StaticString = #filePath,
                                             line: UInt = #line) {
        XCTAssertEqual(list.admins?.map(\.id), ["legacy-admin"], message, file: file, line: line)
        XCTAssertEqual(list.members?.map(\.id), ["legacy-member"], message, file: file, line: line)
    }

    func testAddDoesNotWriteTheLegacyArrays() {
        let placeholder = ListMemberOptimistic.placeholder(
            id: "temp_1", listId: "list-1", email: "new@example.com", role: "admin"
        )

        let after = ListMemberOptimistic.applyingAdd(legacyArmed([member("u1")]), member: placeholder)

        XCTAssertEqual(after.listMembers?.map(\.userId), ["u1", "temp_1"], "The roster still updates")
        assertLegacyArraysUntouched(after, "An optimistic add must not populate the dead arrays")
    }

    func testRemovalDoesNotWriteTheLegacyArrays() {
        // The removed person is also a legacy-array entry, which is what makes this bite:
        // the old code stripped them from `admins` / `members` by id as well.
        let armed = legacyArmed([member("u1"), member("legacy-admin")])

        let after = ListMemberOptimistic.applyingRemoval(armed, userId: "legacy-admin")

        XCTAssertEqual(after.listMembers?.map(\.userId), ["u1"], "The roster row still goes")
        assertLegacyArraysUntouched(after, "An optimistic removal must not rewrite the dead arrays")
    }

    func testRollingBackAFailedAddDoesNotWriteTheLegacyArrays() {
        let armed = legacyArmed([member("u1")])
        let placeholder = ListMemberOptimistic.placeholder(
            id: "temp_1", listId: "list-1", email: "new@example.com", role: "member"
        )
        let added = ListMemberOptimistic.applyingAdd(armed, member: placeholder)

        let after = ListMemberOptimistic.applyingRemoval(added, memberId: "temp_1")

        XCTAssertEqual(after.listMembers?.map(\.userId), ["u1"], "The placeholder is rolled back")
        assertLegacyArraysUntouched(after, "The rollback must not rewrite the dead arrays either")
    }

    func testRoleChangeDoesNotWriteTheLegacyArrays() {
        let after = ListMemberOptimistic.applyingRoleChange(legacyArmed([member("u1", role: "member")]),
                                                            userId: "u1", role: "admin")

        XCTAssertEqual(after.listMembers?.first?.role, "admin")
        assertLegacyArraysUntouched(after, "A promotion must not move anyone between the dead arrays")
    }

    func testRoleChangeForSomeoneOnlyInTheLegacyArraysDoesNothing() {
        // `applyingRoleChange` used to fall back to `list.admins` / `list.members` to find the
        // person, so promoting a legacy-only entry rewrote both arrays. Someone who is not in
        // `listMembers` is not on the list at all — the edit has nothing to apply.
        let armed = legacyArmed([member("u1")])

        let after = ListMemberOptimistic.applyingRoleChange(armed, userId: "legacy-member", role: "admin")

        XCTAssertEqual(after.listMembers?.map(\.userId), ["u1"], "Nobody is added to the roster")
        assertLegacyArraysUntouched(after, "A legacy-only entry stays exactly where it was")
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

        service.lists = [list([member("u1"), member("u2")])]

        service.removeMemberFromCachedList(listId: "list-1", userId: "u2")

        XCTAssertEqual(service.lists.first?.listMembers?.map(\.userId), ["u1"])
        XCTAssertEqual(service.listsById["list-1"]?.listMembers?.map(\.userId), ["u1"],
                       "The cached copy is what survives a view dismissal")
    }
}
