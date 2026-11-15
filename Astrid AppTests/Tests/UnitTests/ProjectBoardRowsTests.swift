//  ProjectBoardRowsTests.swift
//  The multi-list project board (AITD-674), now answered by astrid-core (AITD-676). The rows
//  arithmetic (defaults, saved order, dropped ids, candidates, cells) is the core's and its
//  fixture `contracts/fixtures/board-rows.json` covers it. These pin how the app asks: one row
//  through `projectBoardRow`, and the saved rows through `projectBoardRows` /
//  `saveProjectBoardRows`.

import XCTest
import AstridCore
@testable import Astrid_App

@MainActor
final class ProjectBoardRowsTests: XCTestCase {

    private func task(_ id: String, on listId: String, role: String? = nil) -> Task {
        var t = Task(id: id, title: id)
        t.listIds = [listId]
        t.statusRole = role
        t.updatedAt = Date().addingTimeInterval(-60)
        return t
    }

    /// Project `p1` with its own list `board`, and `home`, a list on no project.
    private func session(_ tasks: [Task]) throws -> CoreSession {
        var board = TaskList(id: "board", name: "Board")
        board.projectId = "p1"
        let home = TaskList(id: "home", name: "Home")
        return try CoreBoardFixture.session(tasks: tasks, lists: [board, home],
                                            projects: [Project(id: "p1", name: "Board")])
    }

    private func ids(_ columns: [BoardModel.Column]?, _ id: String) -> [String] {
        columns?.first { $0.id == id }?.ids ?? []
    }

    /// AITD-676, CONTRACTS D67: a list with no board of its own drew an EMPTY row on the Mac,
    /// because its own `board` came back with no columns. Now it draws its cards under the project's.
    func testAITD676_aListWithNoBoardOfItsOwnDrawsItsCards() async throws {
        let session = try session([task("h1", on: "home"), task("h2", on: "home", role: "doing"),
                                   task("b1", on: "board")])
        let columns = await BoardModel.columns(for: BoardModel.Query(listId: "home", rowOfProjectId: "p1"),
                                               session: session)
        XCTAssertEqual(ids(columns, VIRTUAL_INBOX_COLUMN_ID), ["h1"])
        XCTAssertEqual(ids(columns, "doing"), ["h2"])
    }

    /// D67: a role the project has no column for waits in the Inbox, never dropped.
    func testAITD676_aRoleTheProjectLacksWaitsInTheInbox() async throws {
        let session = try session([task("q", on: "home", role: "qa")])
        let columns = await BoardModel.columns(for: BoardModel.Query(listId: "home", rowOfProjectId: "p1"),
                                               session: session)
        XCTAssertEqual(ids(columns, VIRTUAL_INBOX_COLUMN_ID), ["q"])
    }

    func testAITD676_aRowIsRememberedApartFromItsListsOwnBoard() {
        XCTAssertNotEqual(BoardModel.Query(listId: "home", rowOfProjectId: "p1").key,
                          BoardModel.Query(listId: "home").key)
    }

    func testAListDragIsToldApartFromATaskCard_AITD674() {
        XCTAssertEqual(ProjectBoardListDrag.listId(from: ProjectBoardListDrag.payload(listId: "a")), "a")
        XCTAssertNil(ProjectBoardListDrag.listId(from: "task-123"))
        XCTAssertNil(ProjectBoardListDrag.listId(from: ProjectBoardListDrag.prefix))
    }
}

/// The saved rows, through a stand-in for the core.
@MainActor
final class ProjectBoardRowsServiceTests: XCTestCase {
    private final class Core: @unchecked Sendable {
        var commands: [[String: Any]] = []
        var answer: (([String: Any]) throws -> ProjectBoardRowsService.Answer)!

        func run(_ command: CoreCommand) throws -> ProjectBoardRowsService.Answer {
            let data = try JSONEncoder().encode(command)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            commands.append(json)
            return try answer(json)
        }
    }

    private struct Refused: Error {}

    private func answer(_ rows: [String], candidates: [String] = ["c"], canAdd: Bool = true,
                        saved: [String]? = nil) -> ProjectBoardRowsService.Answer {
        .init(projectId: "p", savedListIds: saved, rowListIds: rows, candidateListIds: candidates,
              canAddRow: canAdd, fromCache: false)
    }

    private func service(_ core: Core) -> ProjectBoardRowsService {
        ProjectBoardRowsService(run: { command in try core.run(command) })
    }

    func testLoadAsksTheCoreAndDrawsItsRows_AITD676() async {
        let core = Core()
        core.answer = { _ in self.answer(["a", "b"]) }
        let service = service(core)

        await service.load(projectId: "p")

        XCTAssertEqual(core.commands.first?["kind"] as? String, "projectBoardRows")
        XCTAssertEqual(core.commands.first?["projectId"] as? String, "p")
        XCTAssertTrue(service.isLoaded("p"))
        XCTAssertEqual(service.rowIds(projectId: "p"), ["a", "b"])
        XCTAssertEqual(service.candidateIds(projectId: "p"), ["c"])
        XCTAssertTrue(service.canAddRow(projectId: "p"))
    }

    func testAddingARowSendsTheCoreTheListToAdd_AITD676() async throws {
        let core = Core()
        core.answer = { json in
            json["kind"] as? String == "saveProjectBoardRows"
                ? self.answer(["a", "b", "c"], candidates: [], saved: ["a", "b", "c"]) : self.answer(["a", "b"])
        }
        let service = service(core)
        await service.load(projectId: "p")

        await service.addRow(projectId: "p", listId: "c")

        let save = try XCTUnwrap(core.commands.last)
        XCTAssertEqual(save["kind"] as? String, "saveProjectBoardRows")
        XCTAssertEqual(save["addListId"] as? String, "c")
        XCTAssertNil(save["listIds"])
        XCTAssertEqual(service.rowIds(projectId: "p"), ["a", "b", "c"])
        XCTAssertNil(service.saveFailed)
    }

    func testARefusedSaveGoesBackAndSaysSo_AITD676() async throws {
        let core = Core()
        core.answer = { json in
            if json["kind"] as? String == "saveProjectBoardRows" { throw Refused() }
            return self.answer(["b"])
        }
        let service = service(core)
        await service.load(projectId: "p")

        await service.removeRow(projectId: "p", listId: "b")

        XCTAssertEqual(core.commands.last?["removeListId"] as? String, "b")
        XCTAssertEqual(service.rowIds(projectId: "p"), ["b"])
        XCTAssertEqual(service.saveFailed, "p")
    }
}
