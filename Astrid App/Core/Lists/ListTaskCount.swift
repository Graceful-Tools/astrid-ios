//  ListTaskCount.swift
//  Astrid — SHARED per-list task counts for the sidebar (AITD-414, promoted from the Mac's
//  `MacListCount`, task 74d6f6aa).
//
//  THE OFFLINE BUG (AITD-414: "Offline Astrid has 0" for the counts in the left side menu).
//  iOS counted a list's tasks with `task.lists?.contains { $0.id == list.id }` — the HYDRATED
//  list objects. `CDTask.toDomainModel()` restores `listIds` and sets `lists: nil`, so after a
//  cold launch with no network every regular list counted zero. The Mac had already hit this and
//  fixed it by checking BOTH representations; iOS kept its own private copy and did not.
//
//  So this is that rule, moved somewhere both platforms can reach rather than fixed twice. A
//  saved filter's number is what its filters keep, which astrid-core answers (`listCounts`,
//  AITD-460) by the same rules its rows are drawn with — so a saved-filter list cannot show one
//  number in the sidebar and a different set of tasks when opened. The iOS sidebar once had a
//  third copy of the filters inline that had drifted on exactly that.

import AstridCore
import Foundation

enum ListTaskCount {

    /// Counts for EVERY list in one pass, to be memoized by the view.
    ///
    /// Computing a badge per row per body evaluation is O(lists × tasks) — with 37 lists and 2k
    /// tasks that is ~77k inspections on every render. The My Tasks badge was memoized for
    /// exactly this reason (c38b177b); this keeps the sidebar honest to that lesson.
    ///
    /// `virtualCounts` is the core's answer for the saved filters (`virtualCounts(lists:…)`);
    /// a saved filter it has not answered for yet is left out rather than shown as 0.
    static func counts(_ tasks: [Task], lists: [TaskList], virtualCounts: [String: Int]) -> [String: Int] {
        // One membership pass for the real lists…
        var incompleteByList: [String: Int] = [:]
        for task in tasks where !task.completed {
            for id in task.listIds ?? [] { incompleteByList[id, default: 0] += 1 }
            for list in task.lists ?? [] where !(task.listIds?.contains(list.id) ?? false) {
                incompleteByList[list.id, default: 0] += 1
            }
        }
        // …then the exceptions, which cannot be derived from membership alone.
        var result: [String: Int] = [:]
        for list in lists {
            if list.privacy == .PUBLIC, let apiCount = list.taskCount {
                result[list.id] = apiCount
            } else if list.isVirtual == true {
                result[list.id] = virtualCounts[list.id]
            } else {
                result[list.id] = incompleteByList[list.id] ?? 0
            }
        }
        return result
    }

    static func count(_ tasks: [Task], list: TaskList, virtualCount: Int? = nil) -> Int {
        // A public list's membership is not fully local, so trust the server's number.
        if list.privacy == .PUBLIC, let apiCount = list.taskCount { return apiCount }

        if list.isVirtual == true {
            // The list's own filters decide what counts — including whether completed tasks do.
            return virtualCount ?? 0
        }
        return tasks.filter { belongs($0, to: list.id) && !$0.completed }.count
    }

    /// What each saved filter among `lists` keeps, asked of astrid-core in one call — the rules
    /// its rows are drawn with. Empty when the core cannot answer, so the badges wait rather
    /// than read 0.
    nonisolated static func virtualCounts(lists: [TaskList], currentUserId: String?,
                                          session: CoreSession) async -> [String: Int] {
        let saved = lists.filter { $0.isVirtual == true && !($0.privacy == .PUBLIC && $0.taskCount != nil) }
        guard !saved.isEmpty else { return [:] }
        var command = CoreCommand(kind: "listCounts")
        command.set("lists", saved)
        command.set("currentUserId", currentUserId)
        do {
            return try await session.run(command, as: [String: Int].self)
        } catch {
            AppLog.debug("❌ [ListTaskCount] listCounts failed: \((error as NSError).localizedDescription)")
            return [:]
        }
    }

    /// Membership by either representation — a task always carries `listIds`, and sometimes
    /// hydrated `lists`. Checking only one of them under-counts depending on where the task came
    /// from, and offline `lists` is the one that is missing (AITD-414).
    static func belongs(_ task: Task, to listId: String) -> Bool {
        (task.listIds?.contains(listId) ?? false)
            || (task.lists?.contains { $0.id == listId } ?? false)
    }
}
