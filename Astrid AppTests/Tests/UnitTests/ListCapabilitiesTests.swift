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

    /// Project mode keeps priority behind the leading control's popover, which still offered it
    /// on a board that refuses the write.
    func testTheIOSQuickChangerAsksTheRuleForPriority_AITD491() throws {
        let source = try RepositoryLocator.source(at: "Astrid App/Views/Tasks/TaskDetailLeadingControl.swift")
        XCTAssertTrue(source.contains("TaskCapabilities.allows(.priority"),
                      "the popover still offers priority on a board that refuses it")
    }

    // MARK: - Membership

    /// On a GitHub board the roster is GitHub's (`supports.membership == false`), so an owner
    /// who may edit everything else is still not offered invites, role changes or removals.
    func testAGitHubBoardsRosterIsNotManagedInAstrid_AITD491() throws {
        let board = try list(#"{"id":"b","name":"Board","ownerId":"me","supports":{"membership":false}}"#)
        let home = try list(#"{"id":"h","name":"Home","ownerId":"me"}"#)
        XCTAssertTrue(ListPermissions.canEditSettings(board, userId: "me"))
        XCTAssertFalse(ListPermissions.canManageMembers(board, userId: "me"))
        XCTAssertTrue(ListPermissions.canManageMembers(home, userId: "me"))
        // Membership support never grants what the role does not.
        XCTAssertFalse(ListPermissions.canManageMembers(home, userId: "someone-else"))
    }

    func testBothMembershipTabsAskTheRosterRule_AITD491() throws {
        for path in ["Astrid App/Views/Lists/ListMembershipTab.swift",
                     "Astrid Mac/Views/MacListMembershipTab.swift"] {
            let source = try RepositoryLocator.source(at: path)
            XCTAssertTrue(source.contains("ListPermissions.canManageMembers("),
                          "\(path) still offers invites on a GitHub board")
        }
    }

    // MARK: - Delete wording

    /// On a GitHub board an Astrid delete removes the item from the project and the issue stays,
    /// so "Delete this task?" promised more than happens.
    func testAGitHubBoardSaysRemoveFromBoard_AITD491() throws {
        let board = try list(#"{"id":"b","name":"Board","supports":{"deleteTask":"remove_from_list"}}"#)
        let older = try list(#"{"id":"o","name":"Older","supports":{"multipleAssignees":true}}"#)
        let home = try list(#"{"id":"h","name":"Home"}"#)
        let lists = [board, older, home]
        let remove = TaskCapabilities.deleteWording(listIds: ["b"], lists: lists)
        XCTAssertEqual(remove, .removeFromBoard)
        XCTAssertEqual(remove.actionKey, "tasks.remove_from_board")
        XCTAssertEqual(remove.confirmKey, "tasks.remove_from_board_confirm")
        XCTAssertEqual(remove.buttonKey, "actions.remove")
        // A list not loaded yet does not turn a removal back into a delete.
        XCTAssertEqual(TaskCapabilities.deleteWording(listIds: ["b", "unknown"], lists: lists), .removeFromBoard)
        // A task also on a list that deletes really is deleted from Astrid.
        XCTAssertEqual(TaskCapabilities.deleteWording(listIds: ["b", "h"], lists: lists), .delete)
        XCTAssertEqual(TaskCapabilities.deleteWording(listIds: ["o"], lists: lists), .delete)
        XCTAssertEqual(TaskCapabilities.deleteWording(listIds: ["unknown"], lists: lists), .delete)
        XCTAssertEqual(TaskCapabilities.deleteWording(listIds: [], lists: lists), .delete)
        let classic = TaskCapabilities.Deletion.delete
        XCTAssertEqual(classic.actionKey, "tasks.delete_task")
        XCTAssertEqual(classic.confirmKey, "tasks.delete_confirm")
        XCTAssertEqual(classic.buttonKey, "actions.delete")
    }

    func testEveryDeleteSurfaceAsksTheWording_AITD491() throws {
        for path in ["Astrid App/Views/Tasks/TaskActionsView.swift",
                     "Astrid App/Views/Tasks/TaskDetailViewNew.swift",
                     "Astrid App/Views/Tasks/TaskDetailHeaderBar.swift",
                     "Astrid Mac/Views/MacTaskDetailView.swift",
                     "Astrid Mac/Views/MacTaskRowMenu.swift"] {
            let source = try RepositoryLocator.source(at: path)
            XCTAssertTrue(source.contains("TaskCapabilities.deleteWording("), "\(path) still says Delete on a GitHub board")
        }
    }

    func testTheRemoveStringsExistInEveryLanguage_AITD491() throws {
        for language in ["en", "de", "es", "fr", "it", "ja", "ko", "nl", "pt", "ru", "zh-Hans", "zh-Hant"] {
            let strings = try RepositoryLocator.source(at: "Astrid App/Resources/Localizations/\(language).lproj/Localizable.strings")
            for key in ["tasks.remove_from_board", "tasks.remove_from_board_confirm", "actions.remove"] {
                XCTAssertTrue(strings.contains("\"\(key)\" ="), "\(language) lacks \(key)")
            }
        }
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

    // MARK: - New tasks

    /// Quick add sends the list's default priority and date, and smart parsing turns "!!" or
    /// "tomorrow" into them. On a board that refuses either, the create carried a value the
    /// server rejects, so a new task never reached the board.
    func testANewTaskDropsWhatItsBoardRefuses_AITD491() throws {
        let board = try list(#"{"id":"b","name":"Board","supports":{"priority":false,"dueDate":false}}"#)
        let datesOnly = try list(#"{"id":"d","name":"Dates","supports":{"priority":false,"dueDate":true}}"#)
        let home = try list(#"{"id":"h","name":"Home"}"#)
        let lists = [board, datesOnly, home]
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let time = day.addingTimeInterval(3600)

        let onBoard = TaskCapabilities.admitted(priority: 2, whenDate: day, whenTime: time,
                                                listIds: ["b"], lists: lists)
        XCTAssertNil(onBoard.priority)
        XCTAssertNil(onBoard.whenDate)
        XCTAssertNil(onBoard.whenTime)

        let onDates = TaskCapabilities.admitted(priority: 2, whenDate: day, whenTime: time,
                                                listIds: ["d"], lists: lists)
        XCTAssertNil(onDates.priority)
        XCTAssertEqual(onDates.whenDate, day)
        XCTAssertEqual(onDates.whenTime, time)

        // A classic list, and a list not loaded yet, keep everything.
        for ids in [["h"], ["unknown"], []] {
            let kept = TaskCapabilities.admitted(priority: 2, whenDate: day, whenTime: time,
                                                 listIds: ids, lists: lists)
            XCTAssertEqual(kept.priority, 2)
            XCTAssertEqual(kept.whenDate, day)
            XCTAssertEqual(kept.whenTime, time)
        }
    }

    /// Every create goes through the service, so that is where the rule is asked: quick add on
    /// both apps, the board column, the list's defaults and smart parsing all pass through it.
    func testEveryNewTaskAsksTheRule_AITD491() throws {
        let service = try RepositoryLocator.source(at: "Astrid App/Core/Services/TaskService.swift")
        XCTAssertTrue(service.contains("TaskCapabilities.admitted("), "createTask does not drop refused values")
    }

    /// The quick-add pickers do not offer a priority the board would drop.
    func testBothQuickAddPickersAskTheRuleForPriority_AITD491() throws {
        let ios = try RepositoryLocator.source(at: "Astrid App/Views/Tasks/QuickAddPickerSheet.swift")
        XCTAssertTrue(ios.contains("TaskCapabilities.allows(.priority"), "the iOS quick-add sheet still offers priority")
        let mac = try RepositoryLocator.source(at: "Astrid Mac/Views/MacQuickAddBar.swift")
        XCTAssertTrue(mac.contains("TaskCapabilities.allows(.priority"), "the Mac add bar still offers priority")
    }
}
