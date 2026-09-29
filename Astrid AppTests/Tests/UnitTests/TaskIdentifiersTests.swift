//  TaskIdentifiersTests.swift
//  AITD-437 — task ids (`AWTD-123`) on board tasks, "Copy task id", and autolinking.
//
//  Every case comes from `Tests/Fixtures/task-identifiers.json`, a verbatim copy of astrid-web
//  `tests/fixtures/task-identifiers.json` (spec: docs/specs/TASK_IDENTIFIERS.md). Web and
//  Windows run the same file, so the three clients parse, link and show ids alike. Update it by
//  copying, never by editing here.

import AstridCore
import SwiftUI
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

    // MARK: - AITD-439 — the autolink wired into comments and chat

    /// The v1 projects payload carries `key` (Prisma returns every scalar); without it no id links.
    func testAITD439ProjectDecodesItsKey() throws {
        let json = #"{"id":"p1","name":"Web","key":"AWTD"}"#
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        XCTAssertEqual(project.key, "AWTD")
    }

    /// keys = every project the reader can see; projectKey = the board the text belongs to.
    func testAITD439LinkContextForATaskOnABoard() {
        let projects = [Project(id: "p1", name: "Web", key: "AWTD"),
                        Project(id: "p2", name: "iOS", key: "AITD"),
                        Project(id: "p3", name: "Old")]
        let lists = [TaskList(id: "b", name: "Board", projectId: "p2"), TaskList(id: "l", name: "Mine")]
        let task = Task(id: "t", title: "x", listIds: ["l", "b"], identifier: "AITD-1")
        let context = TaskIdentifiers.LinkContext.forTask(task, lists: lists, projects: projects)
        XCTAssertEqual(context.projectKey, "AITD")
        XCTAssertEqual(Set(context.keys), ["AWTD", "AITD"])

        let offBoard = TaskIdentifiers.LinkContext.forList(listId: "l", lists: lists, projects: projects)
        XCTAssertNil(offBoard.projectKey)
        XCTAssertEqual(Set(offBoard.keys), ["AWTD", "AITD"])
        XCTAssertEqual(TaskIdentifiers.LinkContext.forList(listId: "b", lists: lists, projects: projects).projectKey, "AITD")
    }

    /// The renderer links ids in prose — full form anywhere, `#N` on the board — and leaves code,
    /// existing links and `!` pills alone.
    func testAITD439RendererLinksIdsInProseOnly() {
        let context = TaskIdentifiers.LinkContext(projectKey: "AITD", keys: ["AWTD", "AITD"])
        let inlines: [MarkdownInline] = [
            .text(MarkdownRun(text: "see AWTD-12 and #3, ")),
            .text(MarkdownRun(text: "AWTD-13", code: true)),
            .text(MarkdownRun(text: " AWTD-14", link: "https://example.com")),
            .reference(.task, label: "AWTD-15", id: "uuid"),
            .text(MarkdownRun(text: " UTF-8")),
        ]
        let rendered = MarkdownRendering.attributed(inlines, defaultColor: .primary,
                                                    referenceFont: nil, identifiers: context)
        var linked: [String: URL] = [:]
        for run in rendered.runs where run.link != nil {
            linked[String(rendered[run.range].characters)] = run.link
        }
        XCTAssertEqual(linked["AWTD-12"], URL(string: "\(Brand.productionBaseURL)/t/AWTD-12"))
        XCTAssertEqual(linked["#3"], URL(string: "\(Brand.productionBaseURL)/t/AITD-3"))
        XCTAssertNil(linked["AWTD-13"], "code is never linked")
        XCTAssertEqual(linked[" AWTD-14"], URL(string: "https://example.com"), "an existing link wins")
        XCTAssertEqual(linked["!AWTD-15"], URL(string: "astrid://tasks/uuid"), "a pill keeps its target")
        XCTAssertNil(linked[" UTF-8"])
        XCTAssertEqual(linked.count, 4)

        // No context, no links — the default for every surface that is not a comment or chat.
        let plain = MarkdownRendering.attributed([.text(MarkdownRun(text: "AWTD-12"))], defaultColor: .primary,
                                                 referenceFont: nil)
        XCTAssertTrue(plain.runs.allSatisfy { $0.link == nil })
    }

    /// A tap on `/t/KEY-N` is recognised on the brand's hosts only.
    func testAITD439RecognisesAnIdentifierLink() {
        XCTAssertEqual(TaskIdentifiers.identifier(inLink: TaskIdentifiers.url(for: "AWTD-12")), "AWTD-12")
        XCTAssertEqual(TaskIdentifiers.identifier(inLink: URL(string: "https://www.\(Brand.host)/t/awtd-12")!), "AWTD-12")
        XCTAssertNil(TaskIdentifiers.identifier(inLink: URL(string: "https://example.com/t/AWTD-12")!))
        XCTAssertNil(TaskIdentifiers.identifier(inLink: URL(string: "\(Brand.productionBaseURL)/t/not-an-id-x")!))
        XCTAssertNil(TaskIdentifiers.identifier(inLink: URL(string: "\(Brand.productionBaseURL)/tasks/AWTD-12")!))
    }
}
