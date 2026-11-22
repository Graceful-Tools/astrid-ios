import XCTest
@testable import Astrid_App

/// ADEV-128: Waiting moves to the left of Inbox on every platform, but the iPhone board still
/// opens on Inbox — Waiting is what a right swipe shows on the way back to the sidebar. So the
/// phone's first column is the Inbox column by kind, never simply the first column.
final class BoardInitialColumnTests: XCTestCase {

    private func column(_ id: String, _ kind: ProjectBoardColumnKind = .status) -> ProjectBoardColumn {
        ProjectBoardColumn(id: id, name: id, description: "", kind: kind)
    }

    private var waitingFirst: [ProjectBoardColumn] {
        [column("waiting"), column(VIRTUAL_INBOX_COLUMN_ID, .inbox), column("ready"),
         column("doing"), column(VIRTUAL_DONE_COLUMN_ID, .done)]
    }

    func testADEV128_phoneOpensOnInboxEvenWhenWaitingIsFirst() {
        XCTAssertEqual(initialBoardColumnId(waitingFirst, multiColumn: false), VIRTUAL_INBOX_COLUMN_ID)
    }

    func testADEV128_multiColumnStartsAtTheLeadingColumnSoWaitingIsVisible() {
        XCTAssertEqual(initialBoardColumnId(waitingFirst, multiColumn: true), "waiting")
    }

    func testADEV128_beforeColumnsLoadTheBoardAimsAtInbox() {
        XCTAssertEqual(initialBoardColumnId([], multiColumn: false), VIRTUAL_INBOX_COLUMN_ID)
        XCTAssertEqual(initialBoardColumnId([], multiColumn: true), VIRTUAL_INBOX_COLUMN_ID)
    }

    func testADEV128_aBoardWithNoInboxColumnOpensOnItsFirst() {
        XCTAssertEqual(initialBoardColumnId([column("ready"), column("doing")], multiColumn: false), "ready")
    }

    // MARK: - ADEV-212: the opening column is chosen when the columns ARRIVE

    /// The core answers the board asynchronously, so a first open draws no columns. Aiming
    /// `scrollPosition` at Inbox then did nothing once they landed — the binding never changed —
    /// and the phone opened on Waiting, hiding the Inbox card the quick-changer UI test taps.
    func testADEV212_noColumnsYetMeansNoOpeningScroll() {
        var opening = BoardOpening()
        XCTAssertNil(opening.columnToOpen(columns: [], multiColumn: false))
    }

    func testADEV212_columnsArrivingLaterStillOpenOnInbox() {
        var opening = BoardOpening()
        _ = opening.columnToOpen(columns: [], multiColumn: false)
        XCTAssertEqual(opening.columnToOpen(columns: waitingFirst, multiColumn: false),
                       VIRTUAL_INBOX_COLUMN_ID)
    }

    func testADEV212_theBoardOpensOnceAndThenLeavesTheUserWhereTheySwiped() {
        var opening = BoardOpening()
        XCTAssertEqual(opening.columnToOpen(columns: waitingFirst, multiColumn: false),
                       VIRTUAL_INBOX_COLUMN_ID)
        // A later answer (a task moved, a column renamed) must not yank the board back.
        XCTAssertNil(opening.columnToOpen(columns: waitingFirst, multiColumn: false))
    }

    func testADEV212_multiColumnOpensOnTheLeadingColumn() {
        var opening = BoardOpening()
        XCTAssertEqual(opening.columnToOpen(columns: waitingFirst, multiColumn: true), "waiting")
    }
}
