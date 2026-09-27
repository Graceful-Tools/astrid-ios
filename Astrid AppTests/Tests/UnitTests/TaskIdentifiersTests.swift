//  TaskIdentifiersTests.swift
//  AITD-437 — task ids (`AWTD-123`) on board tasks, "Copy task id", and autolinking.
//
//  Every case comes from `Tests/Fixtures/task-identifiers.json`, a verbatim copy of astrid-web
//  `tests/fixtures/task-identifiers.json` (spec: docs/specs/TASK_IDENTIFIERS.md). Web and
//  Windows run the same file, so the three clients parse, link and show ids alike. Update it by
//  copying, never by editing here.

import XCTest
@testable import Astrid_App

final class TaskIdentifiersTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Parse: Decodable {
            struct Expected: Decodable { let key: String; let sequence: Int }
            let input: String
            let expected: Expected?
        }
        struct Autolink: Decodable {
            struct Case: Decodable {
                struct Context: Decodable { let projectKey: String?; let keys: [String]; let hidden: [String] }
                struct Link: Decodable { let match: String; let identifier: String; let href: String }
                let name: String
                let text: String
                let context: Context
                let links: [Link]
            }
            let cases: [Case]
        }
        struct ShowRule: Decodable {
            struct Case: Decodable {
                struct ListRef: Decodable { let projectId: String? }
                let name: String
                let identifier: String?
                let lists: [ListRef]
                let show: [String: Bool]
                let copy: Bool
            }
            let cases: [Case]
        }
        let version: Int
        let parse: [Parse]
        let autolink: Autolink
        let showRule: ShowRule
    }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "task-identifiers", withExtension: "json"),
                                "task-identifiers.json is missing from the test bundle")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testAITD437FixtureIsTheVersionThisCodeImplements() throws {
        XCTAssertEqual(try fixture().version, 1)
    }

    func testAITD437ParsesEveryFixtureCase() throws {
        for c in try fixture().parse {
            let parsed = TaskIdentifiers.parse(c.input)
            XCTAssertEqual(parsed?.key, c.expected?.key, "parse(\"\(c.input)\")")
            XCTAssertEqual(parsed?.sequence, c.expected?.sequence, "parse(\"\(c.input)\")")
        }
    }

    func testAITD437AutolinksEveryFixtureCase() throws {
        for c in try fixture().autolink.cases {
            let links = TaskIdentifiers.links(in: c.text,
                                              projectKey: c.context.projectKey,
                                              keys: c.context.keys,
                                              hidden: c.context.hidden)
            XCTAssertEqual(links.map(\.match), c.links.map(\.match), c.name)
            XCTAssertEqual(links.map(\.identifier), c.links.map(\.identifier), c.name)
            XCTAssertEqual(links.map { "/t/\($0.identifier)" }, c.links.map(\.href), c.name)
            for link in links {
                XCTAssertEqual((c.text as NSString).substring(with: link.range), link.match, c.name)
            }
        }
    }

    func testAITD437ShowRuleForEveryFixtureCase() throws {
        let surfaces: [String: TaskIdentifiers.Surface] = ["details": .details, "row-board": .boardRow, "row-list": .listRow]
        for c in try fixture().showRule.cases {
            for (name, expected) in c.show {
                let surface = try XCTUnwrap(surfaces[name], "unknown surface \(name)")
                XCTAssertEqual(TaskIdentifiers.shows(identifier: c.identifier,
                                                     listProjectIds: c.lists.map(\.projectId),
                                                     on: surface),
                               expected, "\(c.name) — \(name)")
            }
            XCTAssertEqual(TaskIdentifiers.canCopy(identifier: c.identifier), c.copy, c.name)
        }
    }

    /// The Task-level question views ask: membership comes from the task, `projectId` from the
    /// lists the app knows.
    func testAITD437TaskOnABoardShowsItsIdInDetails() {
        let board = TaskList(id: "b", name: "Board", projectId: "p1")
        let personal = TaskList(id: "l", name: "Mine")
        var task = Task(id: "t", title: "x", listIds: ["b"], identifier: "AWTD-1")
        XCTAssertTrue(TaskIdentifiers.shows(task, lists: [board, personal], on: .details))
        task.listIds = ["l"]
        XCTAssertFalse(TaskIdentifiers.shows(task, lists: [board, personal], on: .details))
    }
}
