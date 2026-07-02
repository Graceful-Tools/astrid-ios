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
