//  ProjectBoardRowsTests.swift
//  The multi-list project board (AITD-674, web AWTD-1660): which lists are rows, how a row's cards
//  sit under the project's columns, and the saved rows on the server.

import XCTest
@testable import Astrid_App

final class ProjectBoardRowsTests: XCTestCase {
    private func list(_ id: String, _ name: String? = nil, project: String? = nil,
                      type: String? = nil, virtual: Bool? = nil) -> TaskList {
        TaskList(id: id, name: name ?? id, isVirtual: virtual, projectId: project, listType: type)
    }

    private var lists: [TaskList] {
        [
            list("a", "Alpha", project: "p"),
            list("status-ready", "Ready", project: "p", type: "status"),
            list("b", "Beta", project: "p"),
            list("c", "Charlie", project: "q"),
            list("tag", "Bug", type: "label"),
            list("smart", "Smart", virtual: true),
            list("d", "Delta"),
        ]
    }

    // MARK: Rows

    func testNothingSavedShowsTheProjectsOwnDomainLists_AITD674() {
        XCTAssertEqual(ProjectBoardRows.defaultListIds(projectId: "p", lists: lists), ["a", "b"])
        XCTAssertEqual(ProjectBoardRows.resolve(saved: nil, projectId: "p", lists: lists).map(\.id), ["a", "b"])
    }

    func testSavedRowsDrawInSavedOrderDroppingUnseenRepeatsAndNonLists_AITD674() {
        let rows = ProjectBoardRows.resolve(saved: ["d", "gone", "b", "d", "tag", "status-ready", "c"],
                                            projectId: "p", lists: lists)
        XCTAssertEqual(rows.map(\.id), ["d", "b", "c"])
    }

    func testAnEmptiedBoardStaysEmpty_AITD674() {
        XCTAssertTrue(ProjectBoardRows.resolve(saved: [], projectId: "p", lists: lists).isEmpty)
    }

    func testAddAndRemove_AITD674() {
        XCTAssertEqual(ProjectBoardRows.add("c", to: ["a"]), ["a", "c"])
        XCTAssertEqual(ProjectBoardRows.add("a", to: ["a"]), ["a"])
        XCTAssertEqual(ProjectBoardRows.remove("a", from: ["a", "c"]), ["c"])
    }

    func testCandidatesAreUnusedRealListsByName_AITD674() {
        let names = ProjectBoardRows.candidates(lists: lists, rowIds: ["a"]).map(\.name)
        XCTAssertEqual(names, ["Beta", "Charlie", "Delta"])
    }

    // MARK: Cells

    private func task(_ id: String, in listIds: [String]) -> Task {
        Task(id: id, title: id, listIds: listIds)
    }

    func testARowKeepsOnlyItsOwnListsCardsAndACardShowsInEveryRowItIsOn_AITD674() {
        let tasks = ["t1": task("t1", in: ["a"]), "t2": task("t2", in: ["b"]), "t3": task("t3", in: ["a", "b"])]
        let core: [(id: String, ids: [String])] = [("ready", ["t1", "t2", "t3"]), (VIRTUAL_DONE_COLUMN_ID, [])]
        let columns = [VIRTUAL_INBOX_COLUMN_ID, "ready", VIRTUAL_DONE_COLUMN_ID]

        let rowA = ProjectBoardRows.cells(rowColumns: core, projectColumnIds: columns, listId: "a", tasksById: tasks)
        let rowB = ProjectBoardRows.cells(rowColumns: core, projectColumnIds: columns, listId: "b", tasksById: tasks)

        XCTAssertEqual(rowA["ready"], ["t1", "t3"])
        XCTAssertEqual(rowB["ready"], ["t2", "t3"])
        XCTAssertEqual(rowA[VIRTUAL_INBOX_COLUMN_ID], [])
    }

    func testAForeignBoardsColumnThisProjectLacksWaitsInTheInbox_AITD674() {
        let tasks = ["t1": task("t1", in: ["c"]), "t2": task("t2", in: ["c"])]
        let core: [(id: String, ids: [String])] = [("custom-review", ["t1"]), ("doing", ["t2"])]
        let columns = [VIRTUAL_INBOX_COLUMN_ID, "doing", VIRTUAL_DONE_COLUMN_ID]

        let row = ProjectBoardRows.cells(rowColumns: core, projectColumnIds: columns, listId: "c", tasksById: tasks)

        XCTAssertEqual(row[VIRTUAL_INBOX_COLUMN_ID], ["t1"])
        XCTAssertEqual(row["doing"], ["t2"])
    }

    // MARK: Drag payload

    func testAListDragIsToldApartFromATaskCard_AITD674() {
        XCTAssertEqual(ProjectBoardListDrag.listId(from: ProjectBoardListDrag.payload(listId: "a")), "a")
        XCTAssertNil(ProjectBoardListDrag.listId(from: "task-123"))
        XCTAssertNil(ProjectBoardListDrag.listId(from: ProjectBoardListDrag.prefix))
    }
}

/// The saved rows, through `StubURLProtocol` instead of the server.
@MainActor
final class ProjectBoardRowsServiceTests: XCTestCase {
    private var service: ProjectBoardRowsService!
    private let lists = [
        TaskList(id: "a", name: "A", projectId: "p"),
        TaskList(id: "b", name: "B", projectId: "p"),
        TaskList(id: "c", name: "C"),
    ]

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        service = ProjectBoardRowsService(client: AstridAPIClient(session: StubURLProtocol.session()))
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testNothingSavedReadsAsTheProjectsLists_AITD674() async {
        StubURLProtocol.respond = { _ in .json(#"{"listIds":null,"meta":{"apiVersion":"v1"}}"#) }

        await service.load(projectId: "p")

        XCTAssertEqual(StubURLProtocol.requests.first?.method, "GET")
        XCTAssertEqual(StubURLProtocol.requests.first?.path, "/api/v1/projects/p/board-rows")
        XCTAssertTrue(service.isLoaded("p"))
        XCTAssertEqual(service.rowIds(projectId: "p", lists: lists), ["a", "b"])
    }

    func testAddingARowPutsTheWholeOrderedList_AITD674() async throws {
        StubURLProtocol.respond = { request in
            request.httpMethod == "PUT" ? .json(#"{"listIds":["a","b","c"]}"#) : .json(#"{"listIds":null}"#)
        }
        await service.load(projectId: "p")

        await service.addRow(projectId: "p", listId: "c", lists: lists)

        let put = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(put.method, "PUT")
        XCTAssertEqual(put.jsonBody?["listIds"] as? [String], ["a", "b", "c"])
        XCTAssertEqual(service.rowIds(projectId: "p", lists: lists), ["a", "b", "c"])
        XCTAssertNil(service.saveFailed)
    }

    func testARefusedSaveGoesBackAndSaysSo_AITD674() async {
        StubURLProtocol.respond = { request in
            request.httpMethod == "PUT"
                ? .json(#"{"error":"You cannot see one or more of these lists"}"#, status: 403)
                : .json(#"{"listIds":["b"]}"#)
        }
        await service.load(projectId: "p")

        await service.removeRow(projectId: "p", listId: "b", lists: lists)

        XCTAssertEqual(service.rowIds(projectId: "p", lists: lists), ["b"])
        XCTAssertEqual(service.saveFailed, "p")
    }
}
