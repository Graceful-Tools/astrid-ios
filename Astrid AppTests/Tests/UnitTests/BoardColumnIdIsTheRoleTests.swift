import XCTest
@testable import Astrid_App

/// Task e5c74b5e — "Drop the status-list membership fallback and dual-write —
/// the rows are deleted."
///
/// Web's migration `20260821000000_drop_status_lists` deleted every
/// `listType: 'status'` row and nothing recreates them. The stated contract on
/// both platforms is now:
///
///   A column id IS the role — `ready`, `doing`, `waiting`, or a custom role.
///   NEVER a list id.
///
/// A session that was open across the deploy still has those rows in its cache,
/// and while iOS keyed columns off `list.id` whenever a row happened to be
/// cached, that cache decided the board's shape. Two clients then disagreed
/// about the same card, and — worse — a membership derived from a deleted row
/// went out on the wire, where `PUT /tasks/[id]` rejects the ENTIRE write when
/// one id in `listIds` does not exist.
final class BoardColumnIdIsTheRoleTests: XCTestCase {

    private let project = "p1"

    private func domainList() -> TaskList {
        var list = TaskList(id: "domain-1", name: "Work")
        list.listType = "list"
        list.projectId = project
        return list
    }

    /// A row of the kind the migration deleted, still sitting in a client's cache.
    private func staleStatusRow(_ role: String, _ id: String, _ name: String,
                                order: Int = 0, projectId: String? = nil) -> TaskList {
        var list = TaskList(id: id, name: name)
        list.listType = "status"
        list.statusRole = role
        list.statusOrder = order
        list.projectId = projectId
        return list
    }

    private func task(statusRole: String?, listIds: [String] = ["domain-1"]) -> Task {
        var t = Task(id: "t1", title: "Card", description: "", creatorId: "u1")
        t.statusRole = statusRole
        t.listIds = listIds
        return t
    }

    // MARK: - Columns

    func testEveryDefaultColumnIdIsItsRoleEvenWithAStaleRowCached() {
        let lists = [domainList(),
                     staleStatusRow("ready", "l-ready", "Ready"),
                     staleStatusRow("doing", "l-doing", "Doing"),
                     staleStatusRow("waiting", "l-waiting", "Waiting")]
        let columns = getProjectBoardColumns(lists, projectId: project)

        XCTAssertEqual(columns.filter { $0.kind == .status }.map(\.id), ["ready", "doing", "waiting"])
    }

    func testACustomColumnIdIsItsRoleNotItsListId() {
        let blocked = staleStatusRow("custom-blocked", "l-blocked", "Blocked", order: 5, projectId: project)
        let columns = getProjectBoardColumns([domainList(), blocked], projectId: project)

        XCTAssertEqual(columns.first { $0.name == "Blocked" }?.id, "custom-blocked")
    }

    func testNoColumnIdIsEverAListId() {
        let lists = [domainList(),
                     staleStatusRow("ready", "l-ready", "Ready"),
                     staleStatusRow("custom-blocked", "l-blocked", "Blocked", order: 5, projectId: project)]
        let listIds = Set(lists.map(\.id))

        for column in getProjectBoardColumns(lists, projectId: project) {
            XCTAssertFalse(listIds.contains(column.id),
                           "Column \"\(column.name)\" is keyed by a list id — the rows are deleted")
        }
    }

    func testTheColumnShapeIsIdenticalWithAndWithoutTheStaleRows() {
        // The deletion has to be a no-op. Two clients, one with a cache from
        // before the deploy and one without, must render the same board.
        let withRows = getProjectBoardColumns(
            [domainList(), staleStatusRow("ready", "l-ready", "Ready"), staleStatusRow("doing", "l-doing", "Doing")],
            projectId: project
        )
        let withoutRows = getProjectBoardColumns([domainList()], projectId: project)

        XCTAssertEqual(withRows.map(\.id), withoutRows.map(\.id))
        XCTAssertEqual(withRows.map(\.name), withoutRows.map(\.name))
    }

    // MARK: - Card → column

    func testACardResolvesToItsRoleNotToACachedRowsId() {
        let lists = [domainList(), staleStatusRow("doing", "l-doing", "Doing")]

        XCTAssertEqual(getTaskProjectColumnId(task(statusRole: "doing"), lists: lists), "doing")
    }

    func testACardLandsInARenderedColumnWhicheverCacheItHas() {
        // The failure this prevents: the card resolves to "l-doing" while the
        // column is "doing", so it matches NO column and vanishes from the board.
        let stale = [domainList(), staleStatusRow("doing", "l-doing", "Doing")]
        let fresh = [domainList()]

        for lists in [stale, fresh] {
            let columns = getProjectBoardColumns(lists, projectId: project)
            let resolved = getTaskProjectColumnId(task(statusRole: "doing"), lists: lists)
            XCTAssertTrue(columns.contains { $0.id == resolved },
                          "Card resolved to \"\(resolved)\", which is not a rendered column")
        }
    }

    func testACustomRoleResolvesToItsRole() {
        let blocked = staleStatusRow("custom-blocked", "l-blocked", "Blocked", order: 5, projectId: project)
        let lists = [domainList(), blocked]

        XCTAssertEqual(getTaskProjectColumnId(task(statusRole: "custom-blocked"), lists: lists), "custom-blocked")
    }

    func testAnUnknownCustomRoleStillFallsToInbox() {
        // A card whose column id matches no rendered column is in NONE of them —
        // gone from the board while still in the list view. Inbox is recoverable.
        XCTAssertEqual(
            getTaskProjectColumnId(task(statusRole: "custom-nowhere"), lists: [domainList()]),
            VIRTUAL_INBOX_COLUMN_ID
        )
    }

    // MARK: - Moves

    func testAMoveOntoABackedColumnWritesTheRoleAndNoMembership() {
        let ready = staleStatusRow("ready", "l-ready", "Ready")
        let lists = [domainList(), ready]
        let columns = getProjectBoardColumns(lists, projectId: project)
        let readyColumn = try! XCTUnwrap(columns.first { $0.name == "Ready" })

        let move = resolveProjectColumnMove(task(statusRole: nil), targetColumn: readyColumn, lists: lists)

        XCTAssertEqual(move.statusRole, "ready")
        XCTAssertEqual(move.listIds, ["domain-1"], "A deleted row's id must never go out on the wire")
    }

    func testAMoveStripsAStaleStatusMembershipTheCardIsCarrying() {
        // The strip is the one piece that STAYS. A card still carrying the old
        // membership keeps rendering in its old column for anything that reads it.
        let ready = staleStatusRow("ready", "l-ready", "Ready")
        let lists = [domainList(), ready]
        let columns = getProjectBoardColumns(lists, projectId: project)
        let doingColumn = try! XCTUnwrap(columns.first { $0.name == "Doing" })
        let carrying = task(statusRole: "ready", listIds: ["domain-1", "l-ready"])

        let move = resolveProjectColumnMove(carrying, targetColumn: doingColumn, lists: lists)

        XCTAssertEqual(move.listIds, ["domain-1"])
        XCTAssertEqual(move.statusRole, "doing")
    }

    func testEveryColumnRoundTripsThroughAMove() {
        let lists = [domainList(), staleStatusRow("ready", "l-ready", "Ready")]
        let columns = getProjectBoardColumns(lists, projectId: project)
        let start = task(statusRole: "ready", listIds: ["domain-1", "l-ready"])

        for column in columns {
            let move = resolveProjectColumnMove(start, targetColumn: column, lists: lists)
            let moved = start.applyingBoardMove(move)
            XCTAssertEqual(getTaskProjectColumnId(moved, lists: lists), column.id,
                           "Moving to \"\(column.name)\" did not land there")
        }
    }
}
