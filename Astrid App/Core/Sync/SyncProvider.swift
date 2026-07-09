import Foundation

/// Where a mutation originated. Threaded through the write path so provider
/// fan-out never echoes a change back to the system it came from (loop
/// avoidance layer 1; layer 2 is the per-link dual watermarks).
enum SyncSource: String, Codable, Sendable {
    case astrid   // native app/web edit
    case apple    // Apple Reminders import
    case google   // Google Tasks (Phase 3)
    case github   // GitHub Issues (Phase 2)
}

/// Where a provider's sync logic executes.
enum SyncPlacement: Sendable {
    /// On this device (Apple Reminders — EventKit is device-local).
    case clientDevice
    /// Via the astrid.cc `/api/v1/sync` proxy with server-stored credentials
    /// (GitHub Issues, Google Tasks). The client is still the sync worker.
    case serverProxied
}

/// Tracks whether every required mutation from an incremental pull was
/// durably applied. A cursor is an acknowledgement, not a best-effort
/// watermark: one failed task mutation or link write must keep the entire
/// window replayable.
struct SyncPassAcknowledgement: Sendable {
    private(set) var canCommitCursor = true
    private(set) var appliedItemCount = 0

    mutating func recordAppliedItem() { appliedItemCount += 1 }
    mutating func recordFailure() { canCommitCursor = false }
}

/// Testable cursor lifecycle boundary shared by provider services. Returning
/// false means there was nothing safe to acknowledge; commit errors propagate
/// so the same incremental window is replayed on the next pass.
enum ProviderCursorCommitter {
    static func commitIfSafe(
        acknowledgement: SyncPassAcknowledgement,
        cursor: String?,
        commit: (String) async throws -> Void
    ) async throws -> Bool {
        guard acknowledgement.canCommitCursor,
              let cursor, !cursor.isEmpty else { return false }
        try await commit(cursor)
        return true
    }
}

/// Creation is safe only when a complete remote listing proves that no twin
/// already exists. Failed and truncated scans mean "unknown", never "empty".
enum SyncAdoptionSafety {
    nonisolated static func mayCreateRemote(
        fullListingAvailable: Bool,
        listingTruncated: Bool,
        matchingTwinExists: Bool
    ) -> Bool {
        fullListingAvailable && !listingTruncated && !matchingTwinExists
    }
}

/// Filters Outbox mutation notifications so a provider does not schedule a
/// fresh pass for writes produced by its own active pass. Cross-provider and
/// user edits still fan out normally.
enum SyncMutationNudge {
    enum Provider: String, Sendable { case github, google }

    nonisolated static func shouldSchedule(provider: Provider, mutationSource: String?) -> Bool {
        mutationSource != provider.rawValue
    }
}

/// Shared time gate for expensive complete remote listings. Only successful,
/// non-truncated pulls update the stored timestamp at the call site.
enum FullPullThrottle {
    nonisolated static func isDue(
        lastSuccess: Date?, now: Date, interval: TimeInterval
    ) -> Bool {
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= interval
    }
}

/// Per-pass O(1) lookup for completed-history self-healing. Ambiguous titles
/// are deliberately not adopted; successful candidates are consumed so one
/// local task can never satisfy two remote items in the same pass.
struct BackfillAdoptionIndex: Sendable {
    struct Candidate: Sendable, Equatable {
        let taskId: String
        let title: String
    }

    private var byTitle: [String: [String]]

    init(candidates: [Candidate]) {
        byTitle = Dictionary(grouping: candidates, by: \.title)
            .mapValues { $0.map(\.taskId) }
    }

    mutating func takeUniqueTaskId(title: String) -> String? {
        guard let ids = byTitle[title], ids.count == 1, let id = ids.first else { return nil }
        byTitle.removeValue(forKey: title)
        return id
    }
}

/// A remote container of items — an Apple Reminders calendar, a GitHub repo,
/// a Google Tasks tasklist.
struct RemoteContainer: Equatable, Sendable {
    let id: String
    let name: String
}

/// A remote item in provider-neutral, already-field-mapped form. Provider
/// extras with no Astrid home (labels, milestone, issue #, parent…) ride in
/// `metadata` and round-trip via the external-link mapping.
struct RemoteItem: Equatable, Sendable {
    let remoteId: String
    var title: String
    var notes: String?
    var completed: Bool
    var dueDateTime: Date?
    var isAllDay: Bool
    var remoteUpdatedAt: Date?
    var metadata: [String: String] = [:]
}

/// A sync provider mirrors Astrid tasks to an external system. Astrid's server
/// stays the collaboration source of truth for task CONTENT; providers are
/// mirrors. Inbound writes MUST go through the canonical service layer
/// (`TaskService.createTask/updateTask`, completion through
/// `TaskService.completeTask(task:)` — the repeating-rollover control point),
/// tagged with the provider's `source` for echo suppression.
///
/// Direction of travel (unified plan Phase 0): `AppleReminderProvider` wraps the
/// existing EventKit code as the first conformer; `GitHubIssuesProvider` and
/// `GoogleTasksProvider` call the astrid-web sync proxy.
protocol SyncProvider {
    /// Stable identifier, also used as the mapping-table discriminator.
    var id: String { get }
    var source: SyncSource { get }
    var placement: SyncPlacement { get }

    /// Ensure credentials/permission (EventKit authorization; OAuth connect).
    func ensureAuthorized() async throws

    /// The remote containers available to link (calendars / repos / tasklists).
    func remoteContainers() async throws -> [RemoteContainer]
    func createRemoteContainer(named name: String) async throws -> RemoteContainer

    /// Push one Astrid task to the remote container. `existingRemoteId` nil =
    /// create; non-nil = update. Returns the remote id.
    func push(task: Task, containerId: String, existingRemoteId: String?) async throws -> String
    func delete(remoteId: String, containerId: String) async throws

    /// Pull items changed since `cursor` (nil = full). Returns the items plus
    /// the next cursor (Google syncToken / GitHub since-watermark / nil).
    func pull(containerId: String, since cursor: String?) async throws -> (items: [RemoteItem], cursor: String?)
}

/// Resolve an optimistic temp task id (from the Outbox-authoritative
/// `createTask`) to its real server id. `ExternalTaskLink.astridTaskId` has a
/// foreign key to the real Task row, so a link written with a temp id is
/// silently rejected — which made every sync pass re-create pulled tasks.
/// Draining the Outbox runs the createTask handler (sync only runs online),
/// after which the temp→real map has the answer.
@MainActor
func resolveRealSyncTaskId(_ id: String) async -> String? {
    guard id.hasPrefix("temp_") else { return id }
    for attempt in 0..<6 {
        await OutboxManager.shared.drain()
        if let real = TaskService.shared.mappedRealTaskId(for: id), !real.hasPrefix("temp_") {
            return real
        }
        if attempt < 5 {
            try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
        }
    }
    return nil
}
