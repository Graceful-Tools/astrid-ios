import Foundation

/// Pure echo-suppression rules shared by the external sync workers (GitHub,
/// Google). Dual watermarks per task link: `remoteUpdatedAt` guards the PULL
/// direction, `astridUpdatedAt` guards PUSH. Extracted for unit testing —
/// a wrong comparison here means either infinite echo loops or silently
/// dropped edits.
enum SyncSuppression {
    /// PULL: apply a remote change only if it's strictly newer than the
    /// watermark we wrote at the last push/pull. A missing timestamp on either
    /// side means we can't prove it's an echo — apply.
    static func shouldApplyRemote(remoteUpdatedAt: Date?, watermark: Date?) -> Bool {
        guard let remoteUpdatedAt, let watermark else { return true }
        return remoteUpdatedAt > watermark
    }

    /// The astrid-side watermark to record after processing a task in a pull
    /// pass: the task's OWN updatedAt — never wall-clock now(). A now() stamp
    /// swallows edits made while the pass runs (their timestamp lands before
    /// the watermark) and is exposed to device/server clock skew.
    static func pullWatermark(taskUpdatedAt: Date?) -> Date? {
        taskUpdatedAt
    }

    /// PUSH: push a local change only if it's strictly newer than the
    /// astrid-side watermark recorded when we last pushed/pulled this task.
    static func shouldPushLocal(localUpdatedAt: Date?, watermark: Date?) -> Bool {
        guard let localUpdatedAt, let watermark else { return true }
        return localUpdatedAt > watermark
    }
}

/// Google Tasks' lossy `due` mapping: Google stores DATE-ONLY due values
/// (RFC3339 at UTC midnight — matching Astrid's all-day convention), so a
/// timed Astrid due must never be clobbered by the date-only mirror.
enum GoogleDueMapping {
    static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Wire string for pushing a local due to Google: UTC start-of-day.
    static func pushDueString(for due: Date) -> String {
        var utc = Calendar.current
        utc.timeZone = TimeZone(identifier: "UTC")!
        return formatter.string(from: utc.startOfDay(for: due))
    }

    /// The due date to adopt locally from Google's date-only `due`, or nil to
    /// leave the local task untouched. Rules: never clobber a TIMED local due
    /// (the time can't round-trip through Google), and skip no-op writes.
    static func adoptedDue(remoteDue: Date?, localDue: Date?, localIsAllDay: Bool) -> Date? {
        guard let remoteDue else { return nil }
        guard localIsAllDay || localDue == nil else { return nil }
        guard localDue != remoteDue else { return nil }
        return remoteDue
    }
}

/// Orders pulled remote items so parents are processed before their children —
/// a child created in the same pass can then resolve its parent's fresh link.
/// Kahn-style: repeatedly emit items whose parent isn't among the remaining
/// items; anything cyclic/unresolvable is appended at the end (created
/// top-level rather than dropped).
enum SyncPullOrdering {
    static func parentsFirst<T>(
        _ items: [T],
        id: (T) -> String,
        parentId: (T) -> String?
    ) -> [T] {
        var remaining = items
        var remainingIds = Set(items.map(id))
        var ordered: [T] = []
        while !remaining.isEmpty {
            let ready = remaining.filter { item in
                guard let parent = parentId(item), !parent.isEmpty else { return true }
                return !remainingIds.contains(parent)
            }
            if ready.isEmpty {
                ordered.append(contentsOf: remaining)  // cycle — emit as-is
                break
            }
            ordered.append(contentsOf: ready)
            let readyIds = Set(ready.map(id))
            remaining.removeAll { readyIds.contains(id($0)) }
            remainingIds.subtract(readyIds)
        }
        return ordered
    }
}
