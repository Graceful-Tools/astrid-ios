//  BoardModelTests.swift
//  AITD-461 — a project board and the pickers are astrid-core's (`board`, `dropBoardCard`,
//  `taskStatusOptions`, `listPicks`, `assigneeOptions`, `dueDateOptions`), on iOS and the Mac.
//  These pin what iOS drew where the core used to answer differently (CONTRACTS D43–D50) and how
//  the shared models ask: in the background, again when things change, never an empty board
//  between answers.

import XCTest
import Combine
import AstridCore
@testable import Astrid_App

@MainActor
final class BoardModelTests: XCTestCase {

    private func task(_ id: String, role: String? = nil, completed: Bool = false,
                      parent: String? = nil, updatedAgo: TimeInterval = 60) -> Task {
        var t = Task(id: id, title: id, completed: completed)
        t.listIds = ["board"]
        t.statusRole = role
        t.parentTaskId = parent
        t.updatedAt = Date().addingTimeInterval(-updatedAgo)
        return t
    }

    private func boardList(order: [String]? = nil) -> TaskList {
        var list = TaskList(id: "board", name: "Board")
        list.projectId = "p1"
        list.manualSortOrder = order
        return list
    }

    private func session(_ tasks: [Task], order: [String]? = nil, extra: [TaskList] = []) throws -> CoreSession {
        try CoreBoardFixture.session(tasks: tasks, lists: [boardList(order: order)] + extra,
                                     projects: [Project(id: "p1", name: "Board")])
    }

    private func ids(_ columns: [BoardModel.Column], _ id: String) -> [String] {
        columns.first { $0.id == id }?.ids ?? []
    }

    // MARK: - Where the core answered differently from iOS

    /// D43: top-level cards only, in the list's manual order, every one of them.
    func testAITD461_cardsAreTopLevelInTheManualOrderAndUncapped() throws {
        var tasks = [task("a"), task("b"), task("child", parent: "a")]
        tasks += (0..<60).map { task("doing-\($0)", role: "doing") }
        let columns = try CoreBoardFixture.drawn(try session(tasks, order: ["b", "a"]), listId: "board")
        XCTAssertEqual(ids(columns, VIRTUAL_INBOX_COLUMN_ID), ["b", "a"])
        XCTAssertEqual(ids(columns, "doing").count, 60, "the core sent 50 a column")
    }

    /// D43: Done holds what the window lets through — the default is the last day.
    func testAITD461_doneHoldsRecentWorkOnly() throws {
        let tasks = [task("recent", completed: true), task("old", completed: true, updatedAgo: 3 * 86_400)]
        let columns = try CoreBoardFixture.drawn(try session(tasks), listId: "board")
        XCTAssertEqual(ids(columns, VIRTUAL_DONE_COLUMN_ID), ["recent"])
    }

    /// D44: a cached status row still names its default column.
    func testAITD461_aCachedStatusRowNamesItsColumn() throws {
        var row = TaskList(id: "row", name: "In flight")
        row.listType = "status"
        row.statusRole = "doing"
        let columns = try CoreBoardFixture.drawn(try session([], extra: [row]), listId: "board")
        XCTAssertEqual(columns.first { $0.id == "doing" }?.name, "In flight")
    }

    /// A drop writes the move and the card's place, as iOS's drop did.
    func testAITD461_aDropRearrangesTheColumn() throws {
        let tasks = [task("a", role: "doing"), task("b", role: "doing"), task("x")]
        let session = try session(tasks, order: ["a", "b", "x"])
        var command = CoreCommand(kind: "dropBoardCard")
        command.set("taskId", "x")
        command.set("columnId", "doing")
        command.set("listId", "board")
        command.set("index", 1)
        struct Dropped: Decodable { let task: Task; let list: TaskList }
        let dropped = try CoreRowsFixture.wait(session, command, as: Dropped.self)
        XCTAssertEqual(dropped.task.statusRole, "doing")
        XCTAssertEqual(dropped.list.manualSortOrder, ["a", "x", "b"])
        XCTAssertEqual(dropped.list.sortBy, "manual")
        XCTAssertEqual(ids(try CoreBoardFixture.drawn(session, listId: "board"), "doing"), ["a", "x", "b"])
    }

    // MARK: - The model

    func testAITD461_theModelAnswersAndRemembers() async throws {
        let session = try session([task("a"), task("d", role: "doing")])
        let model = BoardModel(session: session, changed: Empty().eraseToAnyPublisher())
        await model.load(.init(listId: "board"))
        XCTAssertEqual(model.columns.map(\.id),
                       [VIRTUAL_INBOX_COLUMN_ID, "ready", "doing", "waiting", VIRTUAL_DONE_COLUMN_ID])
        XCTAssertEqual(model.columnId(of: "d"), "doing")
        XCTAssertEqual(BoardModel.cards(model.columns[2], in: ["d": task("d")]).map(\.id), ["d"])

        // A second view of the same board draws the last answer at once.
        let again = BoardModel(session: session, changed: Empty().eraseToAnyPublisher())
        again.update(.init(listId: "board"))
        XCTAssertEqual(again.columns.map(\.id), model.columns.map(\.id))
        XCTAssertEqual(BoardModel.columnCount(listId: "board"), 5)
    }

    /// A move asks again, so the board follows the card.
    func testAITD461_aChangeAsksAgain() async throws {
        let session = try session([task("a")])
        let changed = PassthroughSubject<Void, Never>()
        let model = BoardModel(session: session, changed: changed.eraseToAnyPublisher())
        await model.load(.init(listId: "board"))
        XCTAssertEqual(model.columnId(of: "a"), VIRTUAL_INBOX_COLUMN_ID)

        var command = CoreCommand(kind: "setTaskStatus")
        command.set("taskId", "a")
        command.set("columnId", "ready")
        try await session.run(command)
        changed.send(())

        let deadline = Date().addingTimeInterval(5)
        while model.columnId(of: "a") != "ready", Date() < deadline {
            try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.columnId(of: "a"), "ready")
    }

    // MARK: - The pickers

    /// D50: the list picker is a checklist of every list a task can be filed in, its own
    /// included, in the sidebar's order (favourites, then name), with no cap.
    func testAITD461_theListPickerIsIOSChecklist() throws {
        var lists = (0..<12).map { TaskList(id: "l\($0)", name: String(format: "List %02d", $0)) }
        var favourite = TaskList(id: "fav", name: "Zebra"); favourite.isFavorite = true
        var saved = TaskList(id: "saved", name: "Saved"); saved.isVirtual = true
        lists += [favourite, saved]
        let session = try CoreBoardFixture.session(lists: lists, projects: [])
        let all = try CoreRowsFixture.wait(session, ListPicks.command(""), as: ListToggles.self)
        XCTAssertEqual(all.options.count, 13, "every list but the saved filter, no cap of ten")
        XCTAssertEqual(all.options.first?.id, "fav")
        let found = try CoreRowsFixture.wait(session, ListPicks.command("ST 1"), as: ListToggles.self)
        XCTAssertEqual(found.options.map(\.id), ["l10", "l11"], "matched anywhere, without regard to case")
    }

    /// D47: who the assignee picker offers, as iOS's `AssigneeOptions.build` decided it.
    func testAITD461_theAssigneePickerOffersWhatIOSOffered() throws {
        var list = TaskList(id: "l1", name: "List")
        list.listMembers = [
            ListMember(id: "m1", listId: "l1", userId: "zoe", role: "member",
                       user: User(id: "zoe", email: nil, name: "Zoe", image: nil)),
            ListMember(id: "m2", listId: "l1", userId: "ghost", role: "member", user: nil),
        ]
        let me = User(id: "me", email: nil, name: "Jon", image: nil)
        var claude = User(id: "agent", email: nil, name: "Claude", image: nil)
        claude.isAIAgent = true
        let session = try CoreBoardFixture.session(lists: [list, TaskList(id: "empty", name: "Empty")], projects: [])
        let asked = AssigneeQuestion(listIds: ["l1"], discovered: [User(id: "amy", email: nil, name: "amy", image: nil)],
                                     agents: [claude], currentUser: me)
        let answer = try CoreRowsFixture.wait(session, asked.command, as: AssigneeAnswer.self)
        XCTAssertNil(answer.options.first?.userId, "no one, first")
        XCTAssertEqual(answer.people.map(\.id), ["agent", "zoe", "amy"],
                       "agents, then names as written; you are not added to a list that has people; "
                       + "a member with no record is left out")
        let nobody = AssigneeQuestion(listIds: ["empty"], currentUser: me)
        XCTAssertEqual(try CoreRowsFixture.wait(session, nobody.command, as: AssigneeAnswer.self).people.map(\.id),
                       ["me"], "AITD-413: a list that knows nobody still offers you")
    }

    // MARK: - The Swift copies are gone

    func testAITD461_theBoardsAndPickersAskTheCore() throws {
        func source(_ path: String) throws -> String {
            try String(contentsOf: RepositoryLocator.root.appendingPathComponent(path), encoding: .utf8)
        }
        for path in ["Astrid App/Views/Board/ProjectStatusBoardView.swift", "Astrid Mac/Views/MacBoardView.swift"] {
            XCTAssertTrue(try source(path).contains("BoardModel()"), "\(path) does not ask the core for its board")
        }
        let gone = ["getProjectBoardColumns", "boardColumnTasksSorted", "resolveBoardReorder", "planProjectColumnMove",
                    "ProjectStateMove", "ProjectStatePicker.", "MacBoardMove", "ListFilingTargets",
                    "DueDateQuickPicks", "AssigneeOptions.build"]
        for path in ["Astrid App/Views/Board/ProjectStatusBoardView.swift", "Astrid Mac/Views/MacBoardView.swift",
                     "Astrid App/Views/Components/ProjectStateQuickPicker.swift",
                     "Astrid Mac/Views/MacLeadingControlButton.swift",
                     "Astrid App/Views/Components/InlineListsPicker.swift", "Astrid Mac/Views/MacListPicker.swift",
                     "Astrid App/Views/Components/InlineDatePicker.swift", "Astrid Mac/Views/MacDueDatePicker.swift",
                     "Astrid App/Views/Components/InlineAssigneePicker.swift",
                     "Astrid Mac/Views/MacAssigneeOptions.swift"] {
            let text = try source(path)
            for name in gone {
                XCTAssertFalse(text.contains(name), "\(path) still calls the Swift \(name)")
            }
        }
    }
}
