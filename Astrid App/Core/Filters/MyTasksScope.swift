//  MyTasksScope.swift
//  Astrid — whose tasks My Tasks shows, for iOS and Mac alike (astrid-core CONTRACTS D25).
//
//  My Tasks is the tasks ASSIGNED TO the signed-in person. iOS always scoped it that way, inline in
//  TaskListView; the Mac had its own copy that also took unassigned tasks, so the same account
//  counted My Tasks differently on the two apps. Jon, 2026-10-03: on disagreement follow iOS — so
//  the rule moved here and both apps call it. Nobody signed in means nothing is "mine".

import Foundation

enum MyTasksScope {
    /// The tasks assigned to `userId`, each once (a task reached through two lists is one row).
    static func tasks(_ tasks: [Task], userId: String?) -> [Task] {
        guard let userId else { return [] }
        var seen = Set<String>()
        return tasks.filter { $0.assigneeId == userId && seen.insert($0.id).inserted }
    }
}
