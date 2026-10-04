//  TaskSearchModelTests.swift
//  AITD-459 — the search box is astrid-core's `searchTasks`, on iOS and the Mac. These are iOS's
//  search rules (the deleted Swift `TaskSearch.results`), run against the core: the parity spec.

import XCTest
import Combine
import AstridCore
@testable import Astrid_App

@MainActor
final class TaskSearchModelTests: XCTestCase {

    private func task(_ id: String, _ title: String, notes: String = "",
                      priority: Task.Priority = .none) -> Task {
        var t = Task(id: id, title: title, completed: false)
        t.description = notes
        t.priority = priority
        return t
    }

    private func results(_ tasks: [Task], query: String) async throws -> [String] {
        let model = TaskSearchModel(session: try CoreSearchFixture.session(seeding: tasks),
                                    tasksChanged: Empty().eraseToAnyPublisher())
        await model.search(query)
        return model.resultIds
    }

    /// iOS searched from the first character; the core needed two.
    func testAITD459_oneCharacterIsASearch() async throws {
        let found = try await results([task("1", "Buy milk"), task("2", "Call Ann")], query: "b")
        XCTAssertEqual(found, ["1"])
    }

    func testAITD459_anEmptyQueryFindsNothing() async throws {
        let found = try await results([task("1", "Buy milk")], query: "")
        XCTAssertEqual(found, [])
    }

    /// The whole query, as typed — a trailing space included — in the title or description.
    func testAITD459_theQueryIsOnePhraseAsTyped() async throws {
        let tasks = [task("1", "Buy milk and bread"), task("2", "Buy milk"),
                     task("3", "Errand", notes: "MILK for the cat")]
        let split = try await results(tasks, query: "buy bread")
        XCTAssertEqual(split, [])
        let phrase = try await results(tasks, query: "milk and")
        XCTAssertEqual(phrase, ["1"])
        let trailing = try await results(tasks, query: "milk ")
        XCTAssertEqual(Set(trailing), ["1", "3"])
        let anyCase = try await results(tasks, query: "MiLk")
        XCTAssertEqual(Set(anyCase), ["1", "2", "3"])
    }

    func testAITD459_theAssigneesNameMatches() async throws {
        var t = task("1", "Call the bank")
        t.assigneeId = "u-dana"
        t.assignee = User(id: "u-dana", email: "dana@example.test", name: "Dana Diaz", image: nil)
        let found = try await results([t, task("2", "Other")], query: "diaz")
        XCTAssertEqual(found, ["1"])
    }

    /// The default completion window: open tasks, and tasks completed in the last 24 hours.
    func testAITD459_completedWorkFollowsTheDefaultWindow() async throws {
        var old = task("old", "milk")
        old.completed = true
        old.completedAt = Date().addingTimeInterval(-30 * 86_400)
        var recent = task("recent", "milk")
        recent.completed = true
        recent.completedAt = Date().addingTimeInterval(-3_600)
        let found = try await results([old, recent, task("open", "milk")], query: "milk")
        XCTAssertEqual(found, ["open", "recent"])
    }

    func testAITD459_subtasksAreNotResults() async throws {
        var sub = task("sub", "milk")
        sub.parentTaskId = "top"
        let found = try await results([task("top", "milk run"), sub], query: "milk")
        XCTAssertEqual(found, ["top"])
    }

    /// Highest priority first, open before done — not title-match-first or newest-first.
    func testAITD459_resultsSortByPriority() async throws {
        let low = task("low", "milk", priority: .low)
        let high = task("high", "Errand", notes: "milk", priority: .high)
        var done = task("done", "milk", priority: .high)
        done.completed = true
        done.completedAt = Date().addingTimeInterval(-60)
        let found = try await results([done, low, high], query: "milk")
        XCTAssertEqual(found, ["high", "low", "done"])
    }

    /// The rows are the service's own copies, in the core's order; an id it no longer has is
    /// left out rather than drawn from a stale answer.
    func testAITD459_resultsAreTheServicesTasks() async throws {
        let model = TaskSearchModel(
            session: try CoreSearchFixture.session(seeding: [task("a", "milk", priority: .high),
                                                             task("b", "milk")]),
            tasksChanged: Empty().eraseToAnyPublisher())
        await model.search("milk")
        var edited = task("a", "milk — edited", priority: .high)
        edited.description = "x"
        XCTAssertEqual(model.results(in: ["a": edited]).map(\.title), ["milk — edited"])
    }

    /// A change to the tasks asks again, so results follow an edit made while searching.
    func testAITD459_aChangeToTheTasksSearchesAgain() async throws {
        let session = try CoreSearchFixture.session(seeding: [task("a", "milk")])
        let changed = PassthroughSubject<Void, Never>()
        let model = TaskSearchModel(session: session, tasksChanged: changed.eraseToAnyPublisher())
        await model.search("milk")
        XCTAssertEqual(model.resultIds, ["a"])

        var command = CoreCommand(kind: "updateTask", taskId: "a")
        command.set("changes", ["title": "bread"])
        try await session.run(command)
        changed.send(())

        let deadline = Date().addingTimeInterval(5)
        while model.resultIds == ["a"], Date() < deadline {
            try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.resultIds, [])
    }
}
