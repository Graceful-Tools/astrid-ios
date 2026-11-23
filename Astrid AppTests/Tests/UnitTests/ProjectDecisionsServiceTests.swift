//  ProjectDecisionsServiceTests.swift
//  ADEV-189 (web ADEV-180): a project's decisions read from `GET /api/v1/projects/{id}/decisions`,
//  started with `POST`, and decided with `POST …/decide`.

import XCTest
@testable import Astrid_App

@MainActor
final class ProjectDecisionsServiceTests: XCTestCase {

    nonisolated private static func decision(_ id: String, chosen: Int? = nil) -> ProjectDecision {
        ProjectDecision(id: id, title: id, prompt: "Which?",
                        options: [.init(number: 1, text: "A", recommended: true), .init(number: 2, text: "B")],
                        status: chosen == nil ? "open" : "decided",
                        chosen: chosen.map { .init(number: $0, text: $0 == 1 ? "A" : "B") })
    }

    func testADEV189_decodesTheServersDecisionView() throws {
        let json = """
        {"projectId":"p1","decisions":[{"id":"t1","identifier":"ADEV-9","title":"Which fund?",
         "prompt":"Which fund?","options":[{"number":1,"text":"Option 1","recommended":true},
         {"number":2,"text":"Option 2","recommended":false}],"status":"decided",
         "chosen":{"number":2,"text":"Option 2"},"assigneeId":null,"createdAt":"2026-11-22T00:00:00.000Z"}],
         "meta":{"apiVersion":"v1"}}
        """
        let response = try JSONDecoder().decode(ProjectDecisionsResponse.self, from: Data(json.utf8))
        let d = try XCTUnwrap(response.decisions.first)
        XCTAssertEqual(d.identifier, "ADEV-9")
        XCTAssertEqual(d.options.map(\.recommended), [true, false])
        XCTAssertEqual(d.chosen, .init(number: 2, text: "Option 2"))
        XCTAssertTrue(d.isDecided)
    }

    func testADEV189_openDecisionsComeFirst() async {
        let service = ProjectDecisionsService(fetch: { _ in [Self.decision("done", chosen: 1), Self.decision("new")] })
        await service.load(projectId: "p1")
        XCTAssertEqual(service.decisions(projectId: "p1")?.map(\.id), ["new", "done"])
    }

    func testADEV189_decidingMovesItToTheDecidedOnes() async {
        let service = ProjectDecisionsService(
            fetch: { _ in [Self.decision("a"), Self.decision("b")] },
            decide: { _, _, option in .init(number: option, text: "B") })
        await service.load(projectId: "p1")
        let ok = await service.decide(projectId: "p1", decisionId: "a", option: 2)
        XCTAssertTrue(ok)
        XCTAssertEqual(service.decisions(projectId: "p1")?.map(\.id), ["b", "a"])
        XCTAssertEqual(service.decisions(projectId: "p1")?.last?.chosen?.number, 2)
    }

    func testADEV189_aRefusedChoiceChangesNothing() async {
        struct Refused: Error {}
        let service = ProjectDecisionsService(fetch: { _ in [Self.decision("a")] },
                                              decide: { _, _, _ in throw Refused() })
        await service.load(projectId: "p1")
        let ok = await service.decide(projectId: "p1", decisionId: "a", option: 1)
        XCTAssertFalse(ok)
        XCTAssertNil(service.decisions(projectId: "p1")?.first?.chosen)
    }

    func testADEV189_startingOneSendsTheTitleTrimmedAndRereads() async {
        let sent = LockedBox<NewProjectDecisionRequest?>(nil)
        let service = ProjectDecisionsService(
            fetch: { _ in [Self.decision("t9")] },
            create: { _, body in
                sent.value = body
                return NewProjectDecisionResponse(task: .init(id: "t9", identifier: nil, title: "Which?"))
            })
        let id = await service.create(projectId: "p1", title: "  Which?  ")
        XCTAssertEqual(id, "t9")
        XCTAssertEqual(sent.value?.title, "Which?")
        XCTAssertEqual(service.decisions(projectId: "p1")?.map(\.id), ["t9"])
        _ = await service.create(projectId: "p1", title: "   ")
        XCTAssertNil(sent.value?.title, "a blank title lets the server name it")
    }

    func testADEV189_theChosenLineNamesTheNumberAndTheWords() {
        XCTAssertTrue(ProjectDecisionsView.chosenText(.init(number: 2, text: "Cabin")).contains("2 — Cabin"))
        XCTAssertTrue(ProjectDecisionsView.chosenText(.init(number: 3, text: "")).contains("3"))
    }
}

/// A value a `@Sendable` closure can set.
private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
