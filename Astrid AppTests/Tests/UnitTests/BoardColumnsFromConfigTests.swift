import XCTest
@testable import Astrid_App

/// iOS builds board columns from CONFIG, not from the status-list rows
/// (task 2e41c645 item 3 / web a1722040 step 4).
///
/// Web made this move first: the three defaults come from a config table,
/// backed by a list when one exists, so deleting the `listType:'status'` rows
/// is a no-op rather than a cliff. Until iOS does the same, those rows cannot
/// be deleted at all — iOS derived the entire board from them, so the day they
/// go the phone renders Inbox and Done and nothing else.
///
/// The custom states come from the project-scoped status lists iOS already
/// syncs. There is no need to wait for `Project.customStates`: web itself reads
/// custom states from those rows today, so mirroring that is parity, and
/// waiting for a field nothing writes would have blocked this indefinitely.
final class BoardColumnsFromConfigTests: XCTestCase {

    private let project = "p1"

    private func domainList() -> TaskList {
        var list = TaskList(id: "domain-1", name: "Work")
        list.listType = "list"
        list.projectId = project
        return list
    }

    private func statusList(_ role: String, _ id: String, _ name: String,
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

    // MARK: - The end state: no status lists at all

    func testRendersTheThreeDefaultsWithNoStatusListsAtAll() {
        let columns = getProjectBoardColumns([domainList()], projectId: project)

        XCTAssertEqual(columns.map { $0.name }, ["Inbox", "Ready", "Doing", "Waiting", "Done"])
    }

    func testPlacesACardByItsRoleAloneWithNoListsAndNoMembership() {
        let columns = getProjectBoardColumns([domainList()], projectId: project)
        let doing = try! XCTUnwrap(columns.first { $0.name == "Doing" })

        XCTAssertEqual(getTaskProjectColumnId(task(statusRole: "doing"), lists: [domainList()]), doing.id)
    }

    func testNoRoleStillMeansInbox() {
        XCTAssertEqual(
            getTaskProjectColumnId(task(statusRole: nil), lists: [domainList()]),
            VIRTUAL_INBOX_COLUMN_ID
        )
    }

    func testMoveOntoAnUnbackedColumnAddsNoPhantomMembership() {
        // The column id IS the role when nothing backs it; persisting that in
        // listIds would be a membership in a list that does not exist.
        let lists = [domainList()]
        let columns = getProjectBoardColumns(lists, projectId: project)
        let doing = try! XCTUnwrap(columns.first { $0.name == "Doing" })

        let move = resolveProjectColumnMove(task(statusRole: nil), targetColumn: doing, lists: lists)

        XCTAssertEqual(move.statusRole, "doing")
        XCTAssertEqual(move.listIds, ["domain-1"])
    }

    // MARK: - While the rows still exist

    func testABackedRoleIsStillKeyedByItsRole() {
        // This asserted `readyColumn.id == "l-ready"` while the dual-write needed
        // the list id. The rows are deleted, so the id is the role whether or not
        // a client still has one cached — see BoardColumnIdIsTheRoleTests (e5c74b5e).
        let ready = statusList("ready", "l-ready", "Ready")
        let columns = getProjectBoardColumns([domainList(), ready], projectId: project)
        let readyColumn = try! XCTUnwrap(columns.first { $0.name == "Ready" })

        XCTAssertEqual(readyColumn.id, "ready")
    }

    func testABackedMoveDoesNotPersistStatusMembership() {
        let ready = statusList("ready", "l-ready", "Ready")
        let lists = [domainList(), ready]
        let columns = getProjectBoardColumns(lists, projectId: project)
        let readyColumn = try! XCTUnwrap(columns.first { $0.name == "Ready" })

        let move = resolveProjectColumnMove(task(statusRole: nil), targetColumn: readyColumn, lists: lists)

        XCTAssertEqual(move.statusRole, "ready")
        XCTAssertEqual(move.listIds, ["domain-1"])
    }

    func testARenamedDefaultKeepsItsListName() {
        let renamed = statusList("ready", "l-ready", "Backlog")
        let columns = getProjectBoardColumns([domainList(), renamed], projectId: project)

        XCTAssertEqual(columns.map { $0.name }, ["Inbox", "Backlog", "Doing", "Waiting", "Done"])
    }

    // MARK: - Custom states belong to one board

    func testACustomStateRendersOnItsOwnBoard() {
        let blocked = statusList("custom-blocked", "l-blocked", "Blocked", order: 5, projectId: project)
        let columns = getProjectBoardColumns([domainList(), blocked], projectId: project)

        XCTAssertEqual(columns.map { $0.name }, ["Inbox", "Ready", "Doing", "Waiting", "Blocked", "Done"])
    }

    func testACustomStateDoesNotLeakOntoAnotherBoard() {
        // Task 109d8a91 scoped custom states to their project on web. iOS has to
        // agree, or board A's custom column shows up on board B.
        let blocked = statusList("custom-blocked", "l-blocked", "Blocked", order: 5, projectId: "other-project")
        let columns = getProjectBoardColumns([domainList(), blocked], projectId: project)

        XCTAssertEqual(columns.map { $0.name }, ["Inbox", "Ready", "Doing", "Waiting", "Done"])
    }
}
