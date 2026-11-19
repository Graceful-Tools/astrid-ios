import XCTest
@testable import Astrid_App

/// ADEV-128: Waiting leads the board and the inbox column is called "Ideas" — on every platform,
/// so the order and name come from astrid-core (web's ADEV-132, core PR #96). The column's id and
/// kind stay the inbox's; a phone still opens on it (`BoardInitialColumnTests`).
final class BoardWaitingFirstTests: XCTestCase {
    private func domainList() -> TaskList {
        var list = TaskList(id: "domain-1", name: "Work")
        list.listType = "list"
        list.projectId = "p1"
        return list
    }

    func testWaitingLeadsThenIdeas_ADEV128() {
        let columns = CoreBoardFixture.columns([domainList()])
        XCTAssertEqual(columns.map(\.id), ["waiting", VIRTUAL_INBOX_COLUMN_ID, "ready", "doing", VIRTUAL_DONE_COLUMN_ID])
        XCTAssertEqual(columns[1].kind, .inbox)
        XCTAssertEqual(columns[1].name, "Ideas")
    }

    func testTheInboxPillSaysIdeas_ADEV128() {
        XCTAssertEqual(NSLocalizedString("board.status.inbox", comment: ""), "Ideas")
    }
}
