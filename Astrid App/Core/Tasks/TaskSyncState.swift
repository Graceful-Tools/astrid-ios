//  TaskSyncState.swift
//  Where the server's write-back to a list's backend stands (AITD-491, web spec §11.2).
//
//  A task made on a GitHub Projects board exists in Astrid before GitHub has all of it: the issue
//  is made first, and if adding it to the project or setting its fields fails, the server keeps
//  the task, marks it `pending` and finishes from a job. Until then the task is not yet what the
//  board on GitHub shows, and the row says so. Every classic list sends nothing here.

import Foundation

enum TaskSyncState {
    enum Mark: Equatable {
        case pending, failed
    }

    /// The mark a row carries, if any. Absent and null are settled — null is what the server
    /// sends for every settled task — and so are `synced` and any value this build does not know:
    /// a mark nobody can explain is worse than none.
    static func mark(for task: Task) -> Mark? {
        switch task.syncState {
        case "pending": return .pending
        case "error": return .failed
        default: return nil
        }
    }

    static func chipLabelKey(for mark: Mark) -> String {
        switch mark {
        case .pending: return "tasks.sync_pending_chip"
        case .failed: return "tasks.sync_failed_chip"
        }
    }
}
