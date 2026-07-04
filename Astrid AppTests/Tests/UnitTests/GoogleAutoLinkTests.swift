import XCTest
@testable import Astrid_App

/// Auto-link planning for the Google Tasks all-lists sync modes: which
/// containers get created vs adopted. Wrong answers here mean duplicate lists
/// on one side or another on every sync pass.
final class GoogleAutoLinkTests: XCTestCase {
    private func ref(_ id: String, _ name: String) -> GoogleAutoLink.ListRef {
        .init(id: id, name: name)
    }

    // MARK: - Mode 1: all Google → Astrid

    func testGoogleToAstrid_createsForUnlinkedTasklists_withSuffix() {
        let actions = GoogleAutoLink.googleToAstridActions(
            tasklists: [ref("g1", "Groceries"), ref("g2", "Work")],
            linkedTasklistIds: [],
            unlinkedLists: [],
            suffix: "[GT]"
        )
        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions[0].newListName, "Groceries [GT]")
        XCTAssertNil(actions[0].adoptListId)
        XCTAssertEqual(actions[1].newListName, "Work [GT]")
    }

    func testGoogleToAstrid_skipsAlreadyLinkedTasklists() {
        let actions = GoogleAutoLink.googleToAstridActions(
            tasklists: [ref("g1", "Groceries"), ref("g2", "Work")],
            linkedTasklistIds: ["g1"],
            unlinkedLists: [],
            suffix: ""
        )
        XCTAssertEqual(actions.map(\.tasklistId), ["g2"])
    }

    func testGoogleToAstrid_adoptsSameNameList_insteadOfDuplicating() {
        let actions = GoogleAutoLink.googleToAstridActions(
            tasklists: [ref("g1", "Groceries")],
            linkedTasklistIds: [],
            unlinkedLists: [ref("a1", "Groceries")],
            suffix: "[GT]"
        )
        XCTAssertEqual(actions[0].adoptListId, "a1")
    }

    func testGoogleToAstrid_adoptsSuffixedNameToo() {
        let actions = GoogleAutoLink.googleToAstridActions(
            tasklists: [ref("g1", "Groceries")],
            linkedTasklistIds: [],
            unlinkedLists: [ref("a1", "Groceries [GT]")],
            suffix: "[GT]"
        )
        XCTAssertEqual(actions[0].adoptListId, "a1")
    }

    func testGoogleToAstrid_eachLocalListAdoptedAtMostOnce() {
        // Two same-name tasklists must not adopt the SAME local list.
        let actions = GoogleAutoLink.googleToAstridActions(
            tasklists: [ref("g1", "Inbox"), ref("g2", "Inbox")],
            linkedTasklistIds: [],
            unlinkedLists: [ref("a1", "Inbox")],
            suffix: ""
        )
        XCTAssertEqual(actions[0].adoptListId, "a1")
        XCTAssertNil(actions[1].adoptListId)
    }

    func testGoogleToAstrid_emptySuffixUsesPlainName() {
        XCTAssertEqual(GoogleAutoLink.astridName(for: "Work", suffix: ""), "Work")
        XCTAssertEqual(GoogleAutoLink.astridName(for: "Work", suffix: "  "), "Work")
        XCTAssertEqual(GoogleAutoLink.astridName(for: "Work", suffix: "[GT]"), "Work [GT]")
    }

    // MARK: - Mode 2: all Astrid → Google (backup)

    func testAstridToGoogle_createsForUnlinkedLists() {
        let actions = GoogleAutoLink.astridToGoogleActions(
            lists: [ref("a1", "Groceries"), ref("a2", "Work")],
            linkedListIds: ["a2"],
            unlinkedTasklists: []
        )
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].listId, "a1")
        XCTAssertEqual(actions[0].newTasklistName, "Groceries")
        XCTAssertNil(actions[0].adoptTasklistId)
    }

    func testAstridToGoogle_adoptsSameTitleTasklist() {
        let actions = GoogleAutoLink.astridToGoogleActions(
            lists: [ref("a1", "Groceries")],
            linkedListIds: [],
            unlinkedTasklists: [ref("g1", "Groceries")]
        )
        XCTAssertEqual(actions[0].adoptTasklistId, "g1")
    }

    func testAstridToGoogle_skipsTempLists() {
        let actions = GoogleAutoLink.astridToGoogleActions(
            lists: [ref("temp_abc", "Offline list"), ref("a1", "Real")],
            linkedListIds: [],
            unlinkedTasklists: []
        )
        XCTAssertEqual(actions.map(\.listId), ["a1"])
    }

    // MARK: - Bidirectional (a + b)

    func testBidirectional_sameNamePairAdoptsOnce_neverDuplicates() {
        let plan = GoogleAutoLink.bidirectionalActions(
            tasklists: [ref("g1", "Groceries"), ref("g2", "Work")],
            lists: [ref("a1", "Groceries"), ref("a2", "Personal")],
            linkedTasklistIds: [], linkedListIds: [], suffix: "")
        XCTAssertEqual(plan.googleToAstrid.count, 2)
        XCTAssertEqual(plan.googleToAstrid.first { $0.tasklistId == "g1" }?.adoptListId, "a1")
        // The adopted pair must NOT also flow out as a new tasklist.
        XCTAssertEqual(plan.astridToGoogle.map(\.listId), ["a2"])
        XCTAssertNil(plan.astridToGoogle.first?.adoptTasklistId)
    }

    func testBidirectional_fullyLinkedGoogleSide_leavesOnlyAstridOnlyLists() {
        let plan = GoogleAutoLink.bidirectionalActions(
            tasklists: [ref("g1", "Groceries")],
            lists: [ref("a1", "Groceries"), ref("a2", "Personal")],
            linkedTasklistIds: ["g1"], linkedListIds: ["a1"], suffix: "")
        XCTAssertTrue(plan.googleToAstrid.isEmpty)
        XCTAssertEqual(plan.astridToGoogle.map(\.listId), ["a2"])
    }

    func testBidirectional_fullyLinkedBothSides_isNoOp() {
        let plan = GoogleAutoLink.bidirectionalActions(
            tasklists: [ref("g1", "A")], lists: [ref("a1", "A")],
            linkedTasklistIds: ["g1"], linkedListIds: ["a1"], suffix: "")
        XCTAssertTrue(plan.googleToAstrid.isEmpty && plan.astridToGoogle.isEmpty)
    }

    // MARK: - My Tasks ↔ Google default tasklist phase

    func testMyTasksPhase_activeInAllListsModes() {
        for mode: GoogleSyncMode in [.allGoogleToAstrid, .allAstridToGoogle, .allBidirectional] {
            XCTAssertTrue(GoogleAutoLink.myTasksPhaseActive(
                mode: mode, defaultTasklistId: "gdef", linkedTasklistIds: []), "\(mode)")
        }
    }

    func testMyTasksPhase_inactiveInManualMode() {
        XCTAssertFalse(GoogleAutoLink.myTasksPhaseActive(
            mode: .manual, defaultTasklistId: "gdef", linkedTasklistIds: []))
    }

    func testMyTasksPhase_inactiveWithoutDefaultId() {
        XCTAssertFalse(GoogleAutoLink.myTasksPhaseActive(
            mode: .allBidirectional, defaultTasklistId: nil, linkedTasklistIds: []))
    }

    func testMyTasksPhase_skippedWhenDefaultAlreadyListLinked() {
        // Legacy setups list-linked the default tasklist — the list link stays
        // authoritative; the phase must not double-sync.
        XCTAssertFalse(GoogleAutoLink.myTasksPhaseActive(
            mode: .allBidirectional, defaultTasklistId: "gdef", linkedTasklistIds: ["gdef"]))
    }

    func testAutoLinkCandidates_excludesUnlinkedDefaultTasklist() {
        let out = GoogleAutoLink.autoLinkCandidates(
            tasklists: [ref("gdef", "My Tasks"), ref("g1", "Work")],
            defaultTasklistId: "gdef", linkedTasklistIds: [])
        XCTAssertEqual(out.map(\.id), ["g1"])
    }

    func testAutoLinkCandidates_keepsLegacyLinkedDefaultTasklist() {
        let out = GoogleAutoLink.autoLinkCandidates(
            tasklists: [ref("gdef", "My Tasks"), ref("g1", "Work")],
            defaultTasklistId: "gdef", linkedTasklistIds: ["gdef"])
        XCTAssertEqual(out.map(\.id), ["gdef", "g1"])
    }

    func testAutoLinkCandidates_noDefaultIdPassesThrough() {
        let out = GoogleAutoLink.autoLinkCandidates(
            tasklists: [ref("g1", "Work")], defaultTasklistId: nil, linkedTasklistIds: [])
        XCTAssertEqual(out.map(\.id), ["g1"])
    }

    func testFullyLinkedStateProducesNoActions() {
        XCTAssertTrue(GoogleAutoLink.googleToAstridActions(
            tasklists: [ref("g1", "A")], linkedTasklistIds: ["g1"],
            unlinkedLists: [], suffix: "").isEmpty)
        XCTAssertTrue(GoogleAutoLink.astridToGoogleActions(
            lists: [ref("a1", "A")], linkedListIds: ["a1"],
            unlinkedTasklists: []).isEmpty)
    }
}
