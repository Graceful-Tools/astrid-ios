//  TaskOccurrencesTests.swift
//  Regression guard for AITD-491 — "[iOS/Mac] GitHub Projects boards, part 2", the occurrence
//  links: a task made by completing a repeating task on a spawning board links back to the
//  occurrence it followed, and that one links forward (web's AWTD-1219, item 2) — and for
//  AITD-492, the forward link read from the server's `nextOccurrenceId` when it is known.

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

    // MARK: - The server's own word on "next" (AITD-492)

    /// The case the derived link misses: the successor is not on this device, so no loaded
    /// task points back, but the server has said which task it is.
    func test_aitd492_theNextLinkComesFromTheServerWhenTheSuccessorIsNotLoaded() {
        var first = task("first")
        first.nextOccurrenceId = "second"
        XCTAssertEqual(TaskOccurrences.links(for: first, in: [first]).nextId, "second")
    }

    /// nil is "not known here" on a task that came from a list page, never "there is none",
    /// so the loaded task that points back still supplies the link.
    func test_aitd492_withoutTheServersWordTheLoadedSuccessorStillLinks() {
        let first = task("first")
        let second = task("second", after: "first")
        XCTAssertEqual(TaskOccurrences.links(for: first, in: [first, second]).nextId, "second")
    }

    func test_aitd492_theServersWordWinsOverALoadedTaskThatPointsBack() {
        var first = task("first")
        first.nextOccurrenceId = "real"
        let other = task("other", after: "first")
        XCTAssertEqual(TaskOccurrences.links(for: first, in: [first, other]).nextId, "real")
    }

    /// The two links are independent: neither is inferred from the other.
    func test_aitd492_aNextLinkDoesNotInventAPreviousOne() {
        var first = task("first")
        first.nextOccurrenceId = "second"
        XCTAssertNil(TaskOccurrences.links(for: first, in: [first]).previousId)
    }

    func test_aitd492_anEmptyOrSelfNamingNextIdFallsBack() {
        var loop = task("a")
        loop.nextOccurrenceId = "a"
        XCTAssertTrue(TaskOccurrences.links(for: loop, in: [loop]).isEmpty)
        var blank = task("b")
        blank.nextOccurrenceId = ""
        XCTAssertEqual(TaskOccurrences.links(for: blank, in: [blank, task("c", after: "b")]).nextId, "c")
    }

    func test_aitd492_nextOccurrenceId_decodes_andIsNilWhenAbsentOrNull() throws {
        let decoder = JSONDecoder()
        let base = #""id":"t1","title":"x","description":"","priority":0,"isAllDay":true,"isPrivate":false,"completed":false"#
        let decode = { (extra: String) in try decoder.decode(Task.self, from: Data("{\(base)\(extra)}".utf8)) }
        XCTAssertEqual(try decode(#","nextOccurrenceId":"t2""#).nextOccurrenceId, "t2")
        XCTAssertNil(try decode(#","nextOccurrenceId":null"#).nextOccurrenceId)
        XCTAssertNil(try decode("").nextOccurrenceId)
    }

    func testATaskIsNeverItsOwnOccurrence() {
        let loop = task("a", after: "a")
        XCTAssertTrue(TaskOccurrences.links(for: loop, in: [loop]).isEmpty)
    }
}
