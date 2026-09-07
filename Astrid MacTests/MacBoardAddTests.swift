//  MacBoardAddTests.swift
//  Astrid for Mac — Task db8aacda, rewritten for AITD-328.
//
//  THE BUG: a card typed into a column's "＋ Add task" field was created bare and then moved into
//  the column, and the mapping that applied the move returned only `(listIds, complete)` — it
//  dropped the status role. Since the board resolves a card's column from `Task.statusRole` first
//  (AWTD-562/566), the card resolved to Inbox and appeared there. Every column except Inbox was
//  affected, which is exactly what `MacBoardMove.Plan`'s own doc comment warns about for the drag
//  path: "a plan that described only the membership left the role behind, and the resolver put the
//  card straight back where it came from."
//
//  Each test below names the column a card is typed into and asserts it is CREATED for that
//  column — no follow-up move to lose the role in.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacBoardAddTests: XCTestCase {

    private let domainList = "domain"

    private func column(_ id: String, kind: ProjectBoardColumnKind) -> ProjectBoardColumn {
        ProjectBoardColumn(id: id, name: id.capitalized, description: "", kind: kind)
    }

    private func newCard(in column: ProjectBoardColumn) -> MacBoardAdd.NewCard {
        MacBoardAdd.newCard(in: column, domainListId: domainList, lists: [])
    }

    // MARK: - The reported bug, column by column

    func testACardTypedIntoReadyIsCreatedReady() {
        XCTAssertEqual(newCard(in: column("ready", kind: .status)).statusRole, "ready")
    }

    func testACardTypedIntoDoingIsCreatedDoing() {
        XCTAssertEqual(newCard(in: column("doing", kind: .status)).statusRole, "doing")
    }

    func testACardTypedIntoWaitingIsCreatedWaiting() {
        XCTAssertEqual(newCard(in: column("waiting", kind: .status)).statusRole, "waiting")
    }

    func testACardTypedIntoACustomStateGetsThatCustomState() {
        // The column id IS the role (task e5c74b5e) — never the backing row's id, which must not
        // reach the wire.
        XCTAssertEqual(newCard(in: column("custom-design-review", kind: .status)).statusRole,
                       "custom-design-review")
    }

    func testNoColumnEverCreatesACardWithNoRoleExceptInboxAndDone() {
        for id in ["ready", "doing", "waiting", "custom-x"] {
            XCTAssertNotNil(newCard(in: column(id, kind: .status)).statusRole,
                            "A card typed into \(id) with no role resolves to Inbox — the bug")
        }
    }

    // MARK: - The two columns that carry no status

    func testACardTypedIntoInboxCarriesNoRole() {
        let card = newCard(in: column(VIRTUAL_INBOX_COLUMN_ID, kind: .inbox))

        XCTAssertNil(card.statusRole)
        XCTAssertFalse(card.complete)
    }

    func testACardTypedIntoDoneIsCreatedThenCompleted() {
        let card = newCard(in: column(VIRTUAL_DONE_COLUMN_ID, kind: .done))

        XCTAssertTrue(card.complete)
        XCTAssertNil(card.statusRole, "Done carries no status — the card is done, not 'in Done'")
    }

    func testNoStatusColumnCompletesTheCard() {
        for id in ["ready", "doing", "waiting", "custom-x"] {
            XCTAssertFalse(newCard(in: column(id, kind: .status)).complete)
        }
    }

    // MARK: - Where the card lives

    func testTheCardIsCreatedInTheBoardsOwnList() {
        for column in [column("ready", kind: .status),
                       column(VIRTUAL_INBOX_COLUMN_ID, kind: .inbox),
                       column(VIRTUAL_DONE_COLUMN_ID, kind: .done)] {
            XCTAssertEqual(newCard(in: column).listIds, [domainList],
                           "A card must stay in the board's list whatever column it went into")
        }
    }

    func testStatusIsNeverWrittenAsAListMembership() {
        // Status stopped being a list membership in AWTD-562; writing one would send an id for a
        // row that may no longer exist.
        let ready = ProjectBoardColumn(id: "ready", name: "Ready", description: "", kind: .status)
        let statusList = TaskList(id: "status-row", name: "Ready", listType: "status", statusRole: "ready")

        let card = MacBoardAdd.newCard(in: ready, domainListId: domainList, lists: [statusList])

        XCTAssertEqual(card.listIds, [domainList])
    }
}
#endif
