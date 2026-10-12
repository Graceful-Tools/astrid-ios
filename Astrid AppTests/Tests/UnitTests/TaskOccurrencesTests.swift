//  TaskOccurrencesTests.swift
//  Regression guard for AITD-491 — "[iOS/Mac] GitHub Projects boards, part 2", the occurrence
//  links: a task made by completing a repeating task on a spawning board links back to the
//  occurrence it followed, and that one links forward (web's AWTD-1219, item 2).

import XCTest
@testable import Astrid_App

final class TaskOccurrencesTests: XCTestCase {

    private func task(_ id: String, after previous: String? = nil) -> Task {
        var task = TestHelpers.createTestTask(id: id)
        task.previousOccurrenceId = previous
        return task
    }

    /// Every task on every ordinary list: no links, so no row.
    func testATaskOutsideAChainHasNoLinks() {
        let alone = task("a")
        let links = TaskOccurrences.links(for: alone, in: [alone, task("b")])
        XCTAssertNil(links.previousId)
        XCTAssertNil(links.nextId)
        XCTAssertTrue(links.isEmpty)
    }

    func testTheSpawnedTaskLinksBackToTheOneItFollowed() {
        let first = task("first")
        let second = task("second", after: "first")
        let links = TaskOccurrences.links(for: second, in: [first, second])
        XCTAssertEqual(links.previousId, "first")
        XCTAssertNil(links.nextId)
        XCTAssertFalse(links.isEmpty)
    }

    /// The server only says who came before; "next" is whichever loaded task points back.
    func testTheCompletedOccurrenceLinksForwardToItsSuccessor() {
        let first = task("first")
        let second = task("second", after: "first")
        let links = TaskOccurrences.links(for: first, in: [second, first])
        XCTAssertNil(links.previousId)
        XCTAssertEqual(links.nextId, "second")
    }

    func testTheMiddleOfAChainLinksBothWays() {
        let chain = [task("1"), task("2", after: "1"), task("3", after: "2")]
        let links = TaskOccurrences.links(for: chain[1], in: chain)
        XCTAssertEqual(links, TaskOccurrenceLinks(previousId: "1", nextId: "3"))
    }

    /// A completed occurrence is often not loaded. The link is still offered: opening a task
    /// by id fetches it.
    func testThePreviousLinkDoesNotNeedThatTaskLoaded() {
        let second = task("second", after: "first")
        XCTAssertEqual(TaskOccurrences.links(for: second, in: [second]).previousId, "first")
    }

    func testATaskIsNeverItsOwnOccurrence() {
        let loop = task("a", after: "a")
        XCTAssertTrue(TaskOccurrences.links(for: loop, in: [loop]).isEmpty)
    }
}
