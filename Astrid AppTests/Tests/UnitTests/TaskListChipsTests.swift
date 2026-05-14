import XCTest
@testable import Astrid_App

/// Pins the contract for which list memberships appear as chips on a
/// task row. Status lists must be filtered out so the regular list
/// stays visible inside TaskRowView's `prefix(2)` truncation.
final class TaskListChipsTests: XCTestCase {

    private func makeList(
        id: String,
        name: String,
        listType: String? = nil
    ) -> TaskList {
        var list = TaskList(id: id, name: name)
        list.privacy = .PRIVATE
        list.ownerId = "u-1"
        list.listType = listType
        return list
    }

    func test_nilLists_returnsEmpty() {
        XCTAssertEqual(chipListsForTaskRow(nil).count, 0)
    }

    func test_keepsRegularLists() {
        let ios = makeList(id: "ios", name: "iOS To-do", listType: "regular")
        let inbox = makeList(id: "inbox", name: "Inbox") // legacy nil listType
        let result = chipListsForTaskRow([ios, inbox])
        XCTAssertEqual(result.map { $0.id }, ["ios", "inbox"])
    }

    /// Bug 2026-05-12 #3: task in a board-backed list carries a status
    /// list. `prefix(2)` was pushing the regular chip out of the visible
    /// set so the user saw "Ready / Doing" but not "My Project List".
    func test_dropsStatusLists_preservingRegularOrder() {
        let ios = makeList(id: "ios", name: "iOS To-do", listType: "regular")
        let ready = makeList(id: "ready", name: "Ready", listType: "status")
        let doing = makeList(id: "doing", name: "Doing", listType: "status")
        let result = chipListsForTaskRow([ios, ready, doing])
        XCTAssertEqual(result.map { $0.id }, ["ios"])
    }

    // MARK: - hiddenListIds (context-aware chip filter)
    //
    // The list/board view that's *already* showing the task knows which
    // list-context the user is in. Surfacing that same list as a chip
    // is redundant noise. Same idea for the board column's status list:
    // the column header already says "Ready"/"Doing" — no need to label
    // each card.

    /// 2026-05-13: hide the chip for the list the user is currently
    /// viewing — there's no point telling them "this is in iOS To-do"
    /// when they're looking AT the iOS To-do list view.
    func test_hidesCurrentlyViewedListChip() {
        let ios = makeList(id: "ios", name: "iOS To-do", listType: "regular")
        let groceries = makeList(id: "groc", name: "Groceries", listType: "regular")
        let result = chipListsForTaskRow([ios, groceries], hiddenListIds: ["ios"])
        XCTAssertEqual(result.map { $0.id }, ["groc"])
    }

    /// 2026-05-13: in board view, hide the chip for the column's
    /// status list (the column header already conveys that status).
    func test_hidesStatusListIdInBoardContext_evenIfNotMarkedAsStatusType() {
        // Defensive: even if listType isn't yet "status" (stale data),
        // an explicit hidden id still removes the chip.
        let ios = makeList(id: "ios", name: "iOS To-do", listType: "regular")
        let doing = makeList(id: "doing", name: "Doing")
        let result = chipListsForTaskRow([ios, doing], hiddenListIds: ["doing"])
        XCTAssertEqual(result.map { $0.id }, ["ios"])
    }

    /// Hide BOTH the project's domain list (because the board itself
    /// implies the project) AND the column's status list. Result:
    /// only OTHER lists the task is shared into are shown — and in
    /// the common single-list-per-project case, no chips at all.
    func test_boardHidesDomainAndStatus_leavesOnlyForeignLists() {
        let ios = makeList(id: "ios", name: "iOS To-do", listType: "regular")
        let doing = makeList(id: "doing", name: "Doing", listType: "status")
        let shared = makeList(id: "shared", name: "Shared with Alice", listType: "regular")
        let result = chipListsForTaskRow(
            [ios, doing, shared],
            hiddenListIds: ["ios", "doing"]
        )
        XCTAssertEqual(result.map { $0.id }, ["shared"])
    }

    /// Empty hiddenListIds — backwards-compatible behavior (existing
    /// callers that haven't been updated still work).
    func test_emptyHiddenListIds_matchesUnaryOverload() {
        let ios = makeList(id: "ios", name: "iOS To-do", listType: "regular")
        let inbox = makeList(id: "inbox", name: "Inbox")
        XCTAssertEqual(
            chipListsForTaskRow([ios, inbox], hiddenListIds: []).map { $0.id },
            chipListsForTaskRow([ios, inbox]).map { $0.id }
        )
    }

    /// Unknown id in hiddenListIds — no-op, not an error.
    func test_unknownHiddenIdIsNoOp() {
        let ios = makeList(id: "ios", name: "iOS To-do", listType: "regular")
        let result = chipListsForTaskRow([ios], hiddenListIds: ["nonexistent"])
        XCTAssertEqual(result.map { $0.id }, ["ios"])
    }
}
