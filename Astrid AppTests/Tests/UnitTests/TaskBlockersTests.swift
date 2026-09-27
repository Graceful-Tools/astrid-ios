//  TaskBlockersTests.swift
//  Regression guard for AITD-429 — "[iOS] Waiting on: show the row in task details for tasks
//  on project boards" (the iOS half of web's AWTD-1002; Mac is AITD-430).
//
//  The rules are web's, copied rather than re-decided: `showsTaskBlockers` in
//  astrid-web lib/task-detail-project-state.ts and `rankBlockerCandidates` in
//  lib/task-dependencies.ts. Each test below names the web behaviour it pins.

import XCTest
@testable import Astrid_App

final class TaskBlockersTests: XCTestCase {

    // MARK: - When the row appears (web `showsTaskBlockers`)

    func testHiddenForATaskThatIsNotOnAProjectBoard() {
        XCTAssertFalse(TaskBlockers.showsRow(isInProject: false, isReadOnly: false, hasBlockers: true))
        XCTAssertFalse(TaskBlockers.showsRow(isInProject: false, isReadOnly: false, hasBlockers: false))
    }

    /// A reader still learns the task is blocked; the controls are what hide for them.
    func testShownToAReaderWhenThereAreBlockers() {
        XCTAssertTrue(TaskBlockers.showsRow(isInProject: true, isReadOnly: true, hasBlockers: true))
    }

    /// With nothing to show, only someone who could add the first blocker sees the row.
    func testEmptyRowIsShownOnlyToAnEditor() {
        XCTAssertTrue(TaskBlockers.showsRow(isInProject: true, isReadOnly: false, hasBlockers: false))
        XCTAssertFalse(TaskBlockers.showsRow(isInProject: true, isReadOnly: true, hasBlockers: false))
    }

    // MARK: - What the picker offers (web `rankBlockerCandidates`)

    private func hit(_ id: String, lists: [String] = []) -> BlockerSearchHit {
        BlockerSearchHit(id: id, title: id, completed: false,
                         lists: lists.map { BlockerSearchHit.ListRef(id: $0) })
    }

    func testDropsTheTaskItselfLinkedBlockersAndDependents() {
        let ranked = TaskBlockers.rankCandidates(
            hits: [hit("self"), hit("linked"), hit("dependent"), hit("ok")],
            taskId: "self", taskListIds: [], excludedIds: ["linked", "dependent"])
        XCTAssertEqual(ranked.map(\.id), ["ok"])
    }

    /// Ranking, not filtering: same-board tasks first, search order kept inside each group.
    func testPutsSameBoardTasksFirstKeepingSearchOrder() {
        let ranked = TaskBlockers.rankCandidates(
            hits: [hit("a", lists: ["other"]), hit("b", lists: ["board"]),
                   hit("c"), hit("d", lists: ["board", "other"])],
            taskId: "self", taskListIds: ["board"], excludedIds: [])
        XCTAssertEqual(ranked.map(\.id), ["b", "d", "a", "c"])
    }

    func testSearchStartsAtTwoCharacters() {
        XCTAssertFalse(TaskBlockers.shouldSearch(" a "))
        XCTAssertTrue(TaskBlockers.shouldSearch("ab"))
    }

    // MARK: - The wire (V1BlockersResponse)

    /// A hidden blocker still blocks: it decodes, counts, and is never dropped.
    func testAHiddenBlockerDecodesAndStillCounts() throws {
        let json = """
        {"blockedBy":[{"id":"t1","title":"Ship it","identifier":"AITD-1","completed":true},
                      {"id":"t2","hidden":true}],
         "blocks":[],"dependentIds":["t9"],"meta":{"apiVersion":"v1"}}
        """
        let response = try JSONDecoder().decode(TaskBlockersResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.blockedBy.count, 2)
        XCTAssertFalse(response.blockedBy[0].isHidden)
        XCTAssertTrue(response.blockedBy[0].isCompleted)
        XCTAssertTrue(response.blockedBy[1].isHidden)
        XCTAssertEqual(response.dependentIds, ["t9"])
    }

    /// 409 `dependency_cycle` is the one refusal with its own message.
    func testRecognisesTheCycleRefusal() {
        let cycle = AstridAPIError.httpError(
            statusCode: 409,
            message: #"{"error":"Would create a cycle","reason":"dependency_cycle"}"#)
        XCTAssertTrue(TaskBlockers.isCycleRefusal(cycle))
        XCTAssertFalse(TaskBlockers.isCycleRefusal(AstridAPIError.httpError(statusCode: 403, message: "")))
    }

    // MARK: - How a blocker reads in the row (AITD-438)

    /// AITD-438: "Waiting on … and a list of short task ids". A chip names its task by the
    /// server's identifier; the title is only the fallback for a task that has none.
    func testAITD438ChipShowsTheShortTaskIdBeforeTheTitle() {
        let withId = TaskBlocker(id: "t1", title: "Ship the release notes", identifier: "AITD-12",
                                 completed: false, hidden: nil)
        XCTAssertEqual(TaskBlockers.chipLabel(for: withId), "AITD-12")

        let noId = TaskBlocker(id: "t2", title: "A personal task", identifier: nil,
                               completed: false, hidden: nil)
        XCTAssertEqual(TaskBlockers.chipLabel(for: noId), "A personal task")
    }

    /// A task the reader cannot see still says so, and never leaks an id.
    func testAITD438HiddenChipSaysSoRatherThanNamingTheTask() {
        let hidden = TaskBlocker(id: "t3", title: nil, identifier: "AITD-99", completed: nil, hidden: true)
        XCTAssertEqual(TaskBlockers.chipLabel(for: hidden),
                       NSLocalizedString("tasks.waitingOn.hidden", comment: ""))
    }

    /// AITD-438: the empty row reads like the empty date ("No due date"), in Jon's words.
    func testAITD438EmptyRowSaysNothingToWaitFor() {
        XCTAssertEqual(NSLocalizedString("tasks.waitingOn.empty", comment: ""), "Nothing to wait for")
    }
}
