//  BoardAndOwnershipWritePathTests.swift
//  The board moves, multi-assignee writes and ownership transfer the 2026-10-22 coverage audit
//  found unexecuted (AITD-535), driven through TaskService and ListService as the views drive
//  them. The rules behind a move are the core's and CoreBoardFixture pins them (AITD-461); these
//  pin what the services do with the answer: which command a call becomes, and what the views
//  read afterwards. The unit-test host's core is offline, so online-only commands are refused.

import XCTest
@testable import Astrid_App

@MainActor
final class BoardAndOwnershipWritePathTests: XCTestCase {
    private var tasks: TaskService { TaskService.shared }
    private var lists: ListService { ListService.shared }

    private func name(_ base: String) -> String { "\(base) \(UUID().uuidString)" }

    /// A list on a board — the smallest thing a board move acts on.
    private func boardList() async throws -> TaskList {
        let list = try await lists.createList(name: name("Board"))
        return try await lists.updateListAdvanced(listId: list.id, updates: ["projectId": name("project")])
    }

    // MARK: moveToBoardColumn — a dragged card (with listId) and the state menu (without)

    func testADragToAColumnSetsItsRoleWhereTheViewsRead_AITD535() async throws {
        let board = try await boardList()
        let card = try await tasks.createTask(listIds: [board.id], title: name("Card"))

        let moved = try await tasks.moveToBoardColumn(taskId: card.id, columnId: "doing", listId: board.id)

        XCTAssertEqual(moved.statusRole, "doing")
        XCTAssertEqual(tasks.tasksById[card.id]?.statusRole, "doing", "the board redraws from the cache")
    }

    /// Without a list the move is the task's own board — the state menu's `setTaskStatus`.
    func testTheStateMenuMovesOnTheTasksOwnBoard_AITD535() async throws {
        let board = try await boardList()
        let card = try await tasks.createTask(listIds: [board.id], title: name("Card"))

        let moved = try await tasks.moveToBoardColumn(taskId: card.id, columnId: "waiting")

        XCTAssertEqual(moved.statusRole, "waiting")
        XCTAssertEqual(tasks.tasksById[card.id]?.statusRole, "waiting")
    }

    /// Done completes (through the completion service, CONTRACTS D45) and leaving it re-opens.
    func testDoneCompletesAndLeavingItReopens_AITD535() async throws {
        let board = try await boardList()
        let card = try await tasks.createTask(listIds: [board.id], title: name("Card"))

        let done = try await tasks.moveToBoardColumn(
            taskId: card.id, columnId: VIRTUAL_DONE_COLUMN_ID, listId: board.id)
        XCTAssertTrue(done.completed)
        XCTAssertEqual(tasks.tasksById[card.id]?.completed, true)

        let reopened = try await tasks.moveToBoardColumn(taskId: card.id, columnId: "ready", listId: board.id)
        XCTAssertFalse(reopened.completed)
        XCTAssertEqual(reopened.statusRole, "ready")
    }

    // MARK: dropOnBoard — the move, then the card's place in the board list's order

    func testADropMovesTheCardAndPutsItAtTheSlot_AITD535() async throws {
        let board = try await boardList()
        let first = try await tasks.createTask(listIds: [board.id], title: name("first"))
        let second = try await tasks.createTask(listIds: [board.id], title: name("second"))
        _ = try await tasks.dropOnBoard(taskId: first.id, columnId: "doing", listId: board.id, index: 0)

        let dropped = try await tasks.dropOnBoard(taskId: second.id, columnId: "doing", listId: board.id, index: 0)

        XCTAssertEqual(dropped.statusRole, "doing")
        XCTAssertEqual(tasks.tasksById[second.id]?.statusRole, "doing")
        let order = try XCTUnwrap(lists.getList(id: board.id)?.manualSortOrder,
                                  "the list the core answered with is adopted, so the board reads the new order")
        XCTAssertEqual(order.filter { [first.id, second.id].contains($0) }, [second.id, first.id])
    }

    // MARK: setAssignees — the whole list, primary first (AITD-491)

    func testSetAssigneesReplacesTheListPrimaryFirst_AITD535() async throws {
        let card = try await tasks.createTask(listIds: [], title: name("Shared"))

        let both = try await tasks.setAssignees(taskId: card.id, assigneeIds: ["user-a", "user-b"])
        XCTAssertEqual(both.assigneeIds, ["user-a", "user-b"])
        XCTAssertEqual(both.assigneeId, "user-a", "the first is the primary the single-assignee views show")

        let swapped = try await tasks.setAssignees(taskId: card.id, assigneeIds: ["user-b"])
        XCTAssertEqual(swapped.assigneeIds, ["user-b"])
        XCTAssertEqual(tasks.tasksById[card.id]?.assigneeId, "user-b")

        let none = try await tasks.setAssignees(taskId: card.id, assigneeIds: [])
        XCTAssertNil(none.assigneeId, "an empty list unassigns")
        XCTAssertEqual(none.assigneeIds ?? [], [])
    }

    // MARK: Ownership transfer (AITD-392) — online only

    /// No server to ask means no one to hand it to: the leave control must not offer a transfer.
    func testOwnershipTransferIsUnavailableWhenTheServerCannotBeAsked_AITD535() async throws {
        let list = try await lists.createList(name: name("Owned"))

        let availability = await lists.ownershipTransferAvailability(listId: list.id)

        XCTAssertEqual(availability, .unavailable)
    }

    /// A refused transfer throws and keeps the list — it is forgotten only once the server agreed.
    func testARefusedTransferKeepsTheList_AITD535() async throws {
        let list = try await lists.createList(name: name("Owned"))

        do {
            try await lists.transferOwnership(listId: list.id, to: "user-b")
            XCTFail("an offline transfer must throw")
        } catch {}

        XCTAssertNotNil(lists.getList(id: list.id))
        XCTAssertTrue(lists.lists.contains { $0.id == list.id })
    }
}
