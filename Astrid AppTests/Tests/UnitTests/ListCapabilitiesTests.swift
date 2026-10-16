//  ListCapabilitiesTests.swift
//  The rest of `list.supports`, and a GitHub task's `remote` (AITD-491). The web sent them on
//  2026-10-15 (AWTD-1222); the model dropped every key it did not name, so no app could hide a
//  control a GitHub board refuses or draw the `repo#N` chip.

import XCTest
@testable import Astrid_App

@MainActor
final class ListCapabilitiesTests: XCTestCase {

    private func list(_ json: String) throws -> TaskList {
        try JSONDecoder().decode(TaskList.self, from: Data(json.utf8))
    }

    private func task(_ extra: String) throws -> Task {
        let wire = #"{"id":"t1","title":"x","description":"","priority":0,"isAllDay":true,"isPrivate":false,"completed":false\#(extra)}"#
        return try JSONDecoder().decode(Task.self, from: Data(wire.utf8))
    }

    // MARK: - supports

    func testEverySupportsKeyIsKept_AITD491() throws {
        let board = try list(#"{"id":"b","name":"Board","backend":"github_project","supports":{"multipleAssignees":true,"repeatMode":"spawn","privateTasks":false,"membership":false,"priority":false,"dueDate":false,"comments":true,"fields":true,"deleteTask":"remove_from_list"}}"#)
        let supports = try XCTUnwrap(board.supports)
        XCTAssertFalse(supports.privateTasks)
        XCTAssertFalse(supports.membership)
        XCTAssertFalse(supports.priority)
        XCTAssertFalse(supports.dueDate)
        XCTAssertTrue(supports.comments)
        XCTAssertTrue(supports.fields)
        XCTAssertEqual(supports.deleteTask, .removeFromList)
        let again = try JSONDecoder().decode(TaskList.self, from: JSONEncoder().encode(board))
        XCTAssertEqual(again.supports, board.supports)
    }

    /// An older server's `supports` names only the keys it had. Every other key is classic, so
    /// a server that predates a key never hides a control that works.
    func testAKeyTheServerLeavesOutIsClassic_AITD491() throws {
        let older = try XCTUnwrap(try list(#"{"id":"o","name":"Older","supports":{"multipleAssignees":true}}"#).supports)
        XCTAssertTrue(older.privateTasks)
        XCTAssertTrue(older.membership)
        XCTAssertTrue(older.priority)
        XCTAssertTrue(older.dueDate)
        XCTAssertTrue(older.comments)
        XCTAssertFalse(older.fields)
        XCTAssertEqual(older.deleteTask, .delete)
        let later = try XCTUnwrap(try list(#"{"id":"l","name":"Later","supports":{"deleteTask":"aModeFromLater"}}"#).supports)
        XCTAssertEqual(later.deleteTask, .delete)
    }

    // MARK: - The rule

    func testAControlIsOfferedUnlessAListTheTaskIsOnRefusesIt_AITD491() throws {
        let board = try list(#"{"id":"b","name":"Board","supports":{"priority":false,"dueDate":true}}"#)
        let home = try list(#"{"id":"h","name":"Home"}"#)
        let lists = [board, home]
        XCTAssertFalse(TaskCapabilities.allows(.priority, listIds: ["b"], lists: lists))
        XCTAssertFalse(TaskCapabilities.allows(.priority, listIds: ["h", "b"], lists: lists))
        XCTAssertTrue(TaskCapabilities.allows(.dueDate, listIds: ["b"], lists: lists))
        XCTAssertTrue(TaskCapabilities.allows(.priority, listIds: ["h"], lists: lists))
        // A list not loaded yet refuses nothing: hiding a working control is the worse mistake.
        XCTAssertTrue(TaskCapabilities.allows(.priority, listIds: ["unknown"], lists: lists))
        XCTAssertTrue(TaskCapabilities.allows(.dueDate, listIds: [], lists: lists))
    }

    func testTheIOSDetailAsksTheRuleForTheWhenAndPriorityRows_AITD491() throws {
        let source = try RepositoryLocator.source(at: "Astrid App/Views/Tasks/TaskDetailViewNew.swift")
        XCTAssertTrue(source.contains("TaskCapabilities.allows(.dueDate"))
        XCTAssertTrue(source.contains("TaskCapabilities.allows(.priority"))
    }

    // MARK: - remote

    func testATasksRemoteIsKeptAndNamesItsChip_AITD491() throws {
        let issue = try task(#","remote":{"kind":"issue","url":"https://github.com/o/r/issues/7","nodeId":"I_1","version":null,"repo":"o/r","number":7}"#)
        let remote = try XCTUnwrap(issue.remote)
        XCTAssertEqual(remote.chipLabel, "o/r#7")
        XCTAssertEqual(remote.pageURL?.absoluteString, "https://github.com/o/r/issues/7")
        let again = try JSONDecoder().decode(Task.self, from: JSONEncoder().encode(issue))
        XCTAssertEqual(again.remote, issue.remote)
    }

    /// A draft has no page of its own, so it draws no chip; a classic task has no remote at all.
    func testADraftAndAClassicTaskDrawNoChip_AITD491() throws {
        let draft = try task(#","remote":{"kind":"draft_issue","url":null,"nodeId":"D_1","version":null,"repo":null,"number":null}"#)
        XCTAssertNil(try XCTUnwrap(draft.remote).chipLabel)
        XCTAssertNil(try task("").remote)
    }

    func testBothRowsDrawTheRepoChip_AITD491() throws {
        for path in ["Astrid App/Views/Tasks/TaskRowView.swift", "Astrid Mac/Views/MacTaskRow.swift"] {
            let source = try RepositoryLocator.source(at: path)
            XCTAssertTrue(source.contains("task.remote?.chipLabel"), "\(path) does not draw the repo chip")
            XCTAssertTrue(source.contains("taskRow.remoteChip"), "\(path) does not identify the repo chip")
        }
    }
}
