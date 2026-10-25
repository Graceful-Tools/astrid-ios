//  TaskBlockerCandidatesTests.swift
//  The "waiting on" search, through TaskBlockerService on an in-memory core (AITD-540).
//
//  The core decides what is offerable — never the task itself, nothing it already depends on
//  (astrid-core `services::dependency::pickable`, tested there). On top of that the service drops
//  what the view already holds and the core has not seen yet, and sends nothing for a query too
//  short to mean anything. Offline, the core answers from its cache, which is what this exercises.

import XCTest
@testable import Astrid_App

@MainActor
final class TaskBlockerCandidatesTests: XCTestCase {
    private func task(_ id: String, _ title: String) -> Task {
        Task(id: id, title: title, completed: false)
    }

    func testTheTaskItselfAndWhatTheViewHoldsAreNotOffered() async throws {
        let me = task("me", "Alpha me")
        let core = try CoreSearchFixture.session(seeding: [me, task("open", "Alpha open"), task("held", "Alpha held")])
        let service = TaskBlockerService(core: { core })

        let hits = try await service.candidates(query: "Alpha", task: me, excludedIds: ["held"])

        XCTAssertEqual(hits.map(\.id), ["open"])
    }

    func testATooShortQueryAsksNothing() async throws {
        let me = task("me", "Alpha me")
        let core = try CoreSearchFixture.session(seeding: [me, task("open", "Alpha open")])
        let hits = try await TaskBlockerService(core: { core }).candidates(query: " ", task: me, excludedIds: [])
        XCTAssertTrue(hits.isEmpty)
    }
}
