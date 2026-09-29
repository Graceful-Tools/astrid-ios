import AstridCore
import Foundation
import Combine

/// Pull what changed, on request — through astrid-core.
///
/// The sync pass itself is the core's: it sends what is waiting in the journal first, then pulls
/// lists, tasks, comments and projects and merges them with any edit the server has not seen yet
/// (docs/CORE_MIGRATION.md). It also runs on its own, every minute, and the live stream keeps the
/// cache current between passes — so this is only the person-facing half: pull to refresh, the
/// app coming back to the foreground, a sign-in.
@MainActor
class SyncManager: ObservableObject {
    static let shared = SyncManager()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var hasCompletedInitialSync = false

    private let lastSyncKey = "last_sync_timestamp"
    private var core: CoreSession { AppCore.shared.session }

    private init() {
        lastSyncDate = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    }

    // MARK: - Passes

    /// Run a sync pass now.
    ///
    /// - Parameter isUserInitiated: true when a person asked for it (pull to refresh). Such a pass
    ///   WAITS for an in-flight one rather than returning silently — a refresh that landed during
    ///   the background pass used to fetch nothing, with only the spinner to suggest otherwise
    ///   (Task: 3173727d).
    func performFullSync(includeUserTasks: Bool = false, isUserInitiated: Bool = true) async throws {
        switch SyncPassPolicy.admission(isSyncing: isSyncing, isUserInitiated: isUserInitiated) {
        case .start:
            break
        case .skip:
            return
        case .waitForInFlight:
            guard await waitForInFlightPass() else { return }
        }
        guard !isSyncing else { return }
        isSyncing = true
        defer {
            isSyncing = false
            // Mark as complete even on error, so a first launch offline does not block forever.
            hasCompletedInitialSync = true
        }

        do {
            try await core.run(CoreCommand(kind: "sync"))
        } catch {
            AppLog.debug("⚠️ [SyncManager] Sync pass failed (offline?): \(error)")
            return
        }

        await ListService.shared.reload()
        await TaskService.shared.reloadAll()
        guardDataIsolation()

        // Pictures for the people on screen, off the critical path.
        let lists = ListService.shared.lists
        let tasks = TaskService.shared.tasks
        _Concurrency.Task.detached(priority: .utility) {
            await UserImageCache.shared.cacheFromLists(lists)
            await UserImageCache.shared.cacheFromTasks(tasks)
        }

        let syncTime = Date()
        lastSyncDate = syncTime
        UserDefaults.standard.set(syncTime, forKey: lastSyncKey)
    }

    /// Push what is waiting in the journal now, without pulling — to get local changes out at
    /// once without a full refresh.
    func performQuickSync() async throws {
        try await core.run(CoreCommand(kind: "drain"))
        TaskService.shared.refreshOutboxCounts()
    }

    /// Wait for the in-flight pass to finish. False if it outlived the wait.
    private func waitForInFlightPass(timeout: TimeInterval = 15) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while isSyncing, Date() < deadline {
            try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        }
        return !isSyncing
    }

    /// A pull that brought tasks none of which belong to the signed-in person is a server mixing
    /// up accounts, not data to show. Hide it and say so; the next pass decides again.
    private func guardDataIsolation() {
        guard let userId = AuthManager.shared.userId else { return }
        let tasks = TaskService.shared.tasks
        guard !tasks.isEmpty,
              !tasks.contains(where: { $0.creatorId == userId || $0.assigneeId == userId }) else { return }
        AppLog.debug("❌ [SyncManager] \(SyncError.dataIsolationViolation(expectedUserId: userId, receivedTaskCount: tasks.count).localizedDescription)")
        // The rows are in the core's cache, not only on screen: clearing the arrays alone let the
        // next change read them straight back. The core forgets them and the next pass is full.
        _Concurrency.Task { _ = try? await core.run(CoreCommand(kind: "clearCache")) }
        TaskService.shared.clearCache()
        ListService.shared.clearCache()
        hasCompletedInitialSync = false
    }

    // MARK: - The background pass

    /// Forget when the last pass ran (sign-out). The core resets its own cursor with its cache.
    func resetSyncState() {
        lastSyncDate = nil
        hasCompletedInitialSync = false
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
        // The per-entity stamps the Swift sync kept; a signed-out device holds none of them.
        for key in ["last_task_sync_timestamp", "last_list_sync_timestamp",
                    "last_comment_sync_timestamp", "last_project_sync_timestamp"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case dataIsolationViolation(expectedUserId: String, receivedTaskCount: Int)
    case unauthorized
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .dataIsolationViolation(let expectedUserId, let receivedTaskCount):
            return "Data isolation violation: Received \(receivedTaskCount) tasks that don't belong to user \(expectedUserId). Please sign out and sign in again."
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
