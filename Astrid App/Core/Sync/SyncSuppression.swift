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

    /// CONFLICT: when a pulled remote change passes the echo watermark, it may
    /// still race a fresher LOCAL edit (completed in Astrid seconds ago, pull
    /// carrying the pre-completion remote state). Last-write-wins: remote
    /// applies only when provably newer than the local task; an unprovable
    /// remote stamp never clobbers local state.
    ///
    /// CLOCK-SKEW CAVEAT: `remoteUpdatedAt` is stamped by the provider's server
    /// (GitHub/Google), `localUpdatedAt` by Astrid's — two independent clocks.
    /// Skew between them can, in a genuine simultaneous edit, tip the comparison
    /// the wrong way (older change "wins" by a few seconds). This is an accepted
    /// tradeoff: both are NTP-disciplined server clocks (sub-second skew in
    /// practice), the window is only the moment of a true concurrent edit, and
    /// the dual watermarks already suppress the common echo case. The strict `>`
    /// (never `>=`) also biases toward keeping local on an exact tie.
    static func remoteWins(remoteUpdatedAt: Date?, localUpdatedAt: Date?) -> Bool {
        guard let remoteUpdatedAt else { return false }
        guard let localUpdatedAt else { return true }
        return remoteUpdatedAt > localUpdatedAt
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

    /// Wire string for pushing a local due to Google (date-only).
    /// - All-day dues are STORED at UTC midnight — their UTC day is the day.
    /// - Timed dues are instants — the user's LOCAL day is the day (an 8pm due
    ///   west of UTC is "tomorrow" in UTC terms but must not shift a date).
    static func pushDueString(for due: Date, isAllDay: Bool, localTimeZone: TimeZone = .current) -> String {
        var utc = Calendar.current
        utc.timeZone = TimeZone(identifier: "UTC")!
        if isAllDay {
            return formatter.string(from: utc.startOfDay(for: due))
        }
        var local = Calendar.current
        local.timeZone = localTimeZone
        let day = local.dateComponents([.year, .month, .day], from: due)
        var comps = DateComponents()
        comps.year = day.year; comps.month = day.month; comps.day = day.day
        return formatter.string(from: utc.date(from: comps) ?? due)
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

/// RFC3339 parsing tolerant of fractional seconds — Google Tasks emits
/// `2026-07-03T00:00:00.000Z`, which a plain ISO8601DateFormatter rejects
/// (silently killing due-date import and the pull watermark).
enum RFC3339 {
    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return plain.date(from: s) ?? fractional.date(from: s)
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

/// Gradual import of completed remote history. Incomplete items sync first
/// and fast; completed ones trickle in newest-first under a per-pass budget —
/// useful for search/review, never allowed to delay the live sync.
nonisolated enum CompletedBackfill {
    struct Candidate: Equatable, Sendable {
        let remoteId: String
        let completed: Bool
        let deleted: Bool
        let updatedAt: String   // RFC3339 sorts lexically
    }

    static func select(
        _ items: [Candidate],
        linkedRemoteIds: Set<String>,
        tombstoned: Set<String>,
        budget: Int
    ) -> [Candidate] {
        Array(items
            .filter { $0.completed && !$0.deleted
                && !linkedRemoteIds.contains($0.remoteId)
                && !tombstoned.contains($0.remoteId) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(budget))
    }
}
