//  MacBoardAddTests.swift
//  Astrid for Mac — Task db8aacda: mapping a board move plan to a new card's apply-actions.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacBoardAddTests: XCTestCase {

    func testStatusMovePlacesListsNoComplete() {
        let (ids, complete) = MacBoardAdd.apply(.setLists(["domain", "status"], statusRole: "ready"))
        XCTAssertEqual(ids, ["domain", "status"])
        XCTAssertFalse(complete)
    }

    func testDonePlanCompletes() {
        let (ids, complete) = MacBoardAdd.apply(.complete(["domain"], statusRole: ""))
        XCTAssertEqual(ids, ["domain"])
        XCTAssertTrue(complete)
    }

    func testUncompleteNeverCompletesNewCard() {
        // A brand-new task is already incomplete, so an .uncomplete plan just sets lists.
        let (ids, complete) = MacBoardAdd.apply(.uncomplete(["domain"], statusRole: ""))
        XCTAssertEqual(ids, ["domain"])
        XCTAssertFalse(complete)
    }

    func testNonePlanNoChange() {
        let (ids, complete) = MacBoardAdd.apply(.none)
        XCTAssertNil(ids)
        XCTAssertFalse(complete)
    }
}
#endif
