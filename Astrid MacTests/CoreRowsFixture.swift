//  CoreRowsFixture.swift
//  A list's rows, asked of a throwaway astrid-core holding just the given tasks — the parity spec
//  for AITD-460, which runs the tests the Swift filters, sort and splice had against the core's
//  `rowsForList` and `listCounts`. The iOS test target has the same file.

#if os(macOS)
import AstridCore
import Foundation
@testable import Astrid_Mac

/// Where a detached wait leaves its answer; read only after the semaphore says it is there.
final class WaitBox<Answer>: @unchecked Sendable {
    var result: Result<Answer, Error>?
}

enum CoreRowsFixture {
    struct Answer: Decodable { let ids: [String]; let matched: Int }

    /// The rows `list` draws from `tasks`, in order. Subtasks stay out unless `subtaskDisplay`
    /// splices them in.
    static func rows(_ tasks: [Task], list: TaskList, currentUserId: String? = nil,
                     subtaskDisplay: String = "under_parent", sortBy: String? = nil) throws -> [String] {
        try answer(tasks, query: .init(listId: list.id, list: list, subtaskDisplay: subtaskDisplay,
                                       sortBy: sortBy, currentUserId: currentUserId)).ids
    }

    /// My Tasks' rows for `userId` under `preferences`.
    static func myTasks(_ tasks: [Task], userId: String?, preferences: MyTasksPreferences,
                        subtaskDisplay: String = "under_parent") throws -> [String] {
        try answer(tasks, query: .init(listId: ListRowsModel.myTasksId, myTasks: preferences,
                                       subtaskDisplay: subtaskDisplay, currentUserId: userId)).ids
    }

    /// My Tasks' rows as the given tasks — what the Mac's `MacMyTasks.filter` answered before it
    /// gave way to the core (AITD-460). A task's id seen twice is one row.
    static func myTasksTasks(_ tasks: [Task], userId: String?, preferences: MyTasksPreferences) -> [Task] {
        let byId = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ((try? myTasks(tasks, userId: userId, preferences: preferences)) ?? []).compactMap { byId[$0] }
    }

    /// `tasks` in the order `sortBy` puts them, nothing filtered out.
    static func sorted(_ tasks: [Task], sortBy: String, manualOrder: [String]? = nil) throws -> [String] {
        var shape = TaskList(id: "sorted", name: "")
        shape.isVirtual = true
        shape.filterCompletion = "all"
        shape.sortBy = sortBy
        shape.manualSortOrder = manualOrder
        return try rows(tasks, list: shape)
    }

    /// The sidebar's numbers for `lists`.
    static func counts(_ tasks: [Task], lists: [TaskList], currentUserId: String? = nil) throws -> [String: Int] {
        let session = try CoreSearchFixture.session(seeding: tasks)
        var command = CoreCommand(kind: "listCounts")
        command.set("lists", lists)
        command.set("currentUserId", currentUserId)
        return try wait(session, command, as: [String: Int].self)
    }

    static func answer(_ tasks: [Task], query: ListRowsModel.Query) throws -> Answer {
        let session = try CoreSearchFixture.session(seeding: tasks)
        return try wait(session, ListRowsModel.command(for: query), as: Answer.self)
    }

    /// Run `command` and wait here for the answer. `runBlocking` serves only the reads a launch
    /// needs before its first frame; a list's rows are asked with `run`, so a test that wants a
    /// plain return value waits on that instead.
    static func wait<Answer: Decodable & Sendable>(_ session: CoreSession, _ command: CoreCommand,
                                                   as answer: Answer.Type) throws -> Answer {
        let box = WaitBox<Answer>()
        let done = DispatchSemaphore(value: 0)
        _Concurrency.Task.detached {
            do { box.result = .success(try await session.run(command, as: answer)) } catch { box.result = .failure(error) }
            done.signal()
        }
        done.wait()
        return try box.result!.get()
    }
}
#endif
