import Foundation
import UIKit
import Combine

/// GitHub Issues sync worker (Phase 2 of the multi-provider plan).
///
/// The CLIENT executes the sync; astrid.cc stores credentials + links and
/// proxies GitHub calls (tokens never reach the device). Astrid remains the
/// source of truth for task content — GitHub is a mirror.
///
/// Inbound writes go through the canonical service layer tagged
/// `source: .github` (completion through `TaskService.completeTask`, so
/// repeating tasks roll forward and the mirror is re-opened on the next push).
/// Echo suppression = source tag + per-link dual watermarks.
@MainActor
final class GitHubSyncService: ObservableObject {
    static let shared = GitHubSyncService()

    @Published var isConnected = false
    @Published var accountLogin: String?
    @Published var links: [ExternalListLinkDTO] = []
    @Published var isSyncing = false
    @Published var lastSyncedAt: Date?
    @Published var lastError: String?

    private let apiClient = AstridAPIClient.shared
    private var refreshObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var syncDebounce: _Concurrency.Task<Void, Never>?

    private init() {
        // Nudge from the server (GitHub webhook → SSE external_sync_refresh)
        refreshObserver = NotificationCenter.default.addObserver(
            forName: .externalSyncRefresh, object: nil, queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in self?.scheduleSync() }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in self?.scheduleSync() }
        }
    }

    // MARK: - Connection / links

    func refreshStatus() async {
        do {
            let integrations = try await apiClient.getSyncIntegrations().integrations
            let github = integrations.first { $0.provider == "GITHUB_ISSUES" }
            isConnected = github != nil
            accountLogin = github?.externalAccountId
            links = isConnected ? try await apiClient.getGitHubLinks().links : []
        } catch {
            // 503 = server not configured yet; 401 = not connected. Both fine.
            isConnected = false
            links = []
        }
    }

    func authorizeURL() async -> URL? {
        (try? await apiClient.getGitHubAuthorizeURL().url).flatMap { URL(string: $0) }
    }

    func disconnect() async {
        try? await apiClient.disconnectGitHub()
        await refreshStatus()
    }

    func linkList(_ listId: String, repo: String) async throws {
        _ = try await apiClient.createGitHubLink(astridListId: listId, repo: repo)
        await refreshStatus()
        scheduleSync()
    }

    func unlink(_ linkId: String) async {
        try? await apiClient.deleteGitHubLink(linkId: linkId)
        await refreshStatus()
    }

    // MARK: - Sync

    func scheduleSync() {
        guard isConnected, !links.isEmpty, !isSyncing else { return }
        syncDebounce?.cancel()
        syncDebounce = _Concurrency.Task { @MainActor [weak self] in
            try? await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000)
            guard !_Concurrency.Task.isCancelled else { return }
            await self?.syncAll()
        }
    }

    func syncAll() async {
        guard isConnected, !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        for link in links {
            do {
                try await sync(link: link)
            } catch {
                lastError = "\(link.remoteContainerId): \(error.localizedDescription)"
            }
        }
        lastSyncedAt = Date()
    }

    private func sync(link: ExternalListLinkDTO) async throws {
        let taskService = TaskService.shared
        var taskLinks = try await apiClient.getGitHubTaskLinks(listId: link.astridListId).links
        var byRemoteId = Dictionary(taskLinks.map { ($0.remoteId, $0) }, uniquingKeysWith: { a, _ in a })
        var byTaskId = Dictionary(taskLinks.map { ($0.astridTaskId, $0) }, uniquingKeysWith: { a, _ in a })

        // ── PULL: apply remote changes newer than our watermark ────────────
        let pulled = try await apiClient.pullGitHubIssues(linkId: link.id)
        let iso = ISO8601DateFormatter()
        for item in pulled.items {
            let remoteUpdated = iso.date(from: item.remoteUpdatedAt)
            if let existing = byRemoteId[item.remoteId] {
                // Echo/staleness guard: only apply if remote is newer than the
                // watermark we wrote at the last push/pull.
                if let ru = remoteUpdated, let watermark = existing.remoteUpdatedAt, ru <= watermark {
                    continue
                }
                guard let task = taskService.tasks.first(where: { $0.id == existing.astridTaskId }) else { continue }
                if task.completed != item.completed {
                    // Canonical completion — repeating tasks roll forward; the
                    // next push reopens/reschedules the issue.
                    _ = try? await taskService.completeTask(
                        id: task.id, completed: item.completed, task: task, source: .github)
                }
                if task.title != item.title || (item.notes ?? "") != task.description {
                    _ = try? await taskService.updateTask(
                        taskId: task.id, title: item.title,
                        description: item.notes ?? "", source: .github)
                }
                try? await apiClient.upsertGitHubTaskLink(ExternalTaskLinkUpsertRequest(
                    astridTaskId: existing.astridTaskId, remoteId: item.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: Date(), remoteUpdatedAt: item.remoteUpdatedAt,
                    metadata: item.metadata))
            } else {
                // New issue → new Astrid task in the linked list.
                let newTask = try await taskService.createTask(
                    listIds: [link.astridListId], title: item.title,
                    description: item.notes, source: .github)
                if item.completed {
                    _ = try? await taskService.completeTask(
                        id: newTask.id, completed: true, task: newTask, source: .github)
                }
                let newLink = ExternalTaskLinkUpsertRequest(
                    astridTaskId: newTask.id, remoteId: item.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: newTask.updatedAt, remoteUpdatedAt: item.remoteUpdatedAt,
                    metadata: item.metadata)
                try? await apiClient.upsertGitHubTaskLink(newLink)
                let dto = ExternalTaskLinkDTO(
                    astridTaskId: newTask.id, remoteId: item.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: newTask.updatedAt,
                    remoteUpdatedAt: remoteUpdated, metadata: item.metadata)
                byRemoteId[item.remoteId] = dto
                byTaskId[newTask.id] = dto
                taskLinks.append(dto)
            }
        }

        // ── PUSH: local tasks in the linked list not yet mirrored, or edited
        //          since the last push ─────────────────────────────────────
        let listTasks = taskService.tasks.filter {
            ($0.listIds ?? []).contains(link.astridListId)
                && $0.parentTaskId == nil            // subtasks are lossy on GitHub — v1 skips
                && !$0.id.hasPrefix("temp_")         // wait for the Outbox to sync the create
        }
        for task in listTasks {
            if let existing = byTaskId[task.id] {
                // Push only if the local task changed since our last recorded push.
                if let watermark = existing.astridUpdatedAt,
                   let updated = task.updatedAt, updated <= watermark { continue }
                let response = try await apiClient.pushGitHubIssue(GitHubIssuePushRequest(
                    linkId: link.id, title: task.title,
                    body: task.description.isEmpty ? nil : task.description,
                    state: task.completed ? "closed" : "open",
                    remoteId: existing.remoteId))
                try? await apiClient.upsertGitHubTaskLink(ExternalTaskLinkUpsertRequest(
                    astridTaskId: task.id, remoteId: existing.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: task.updatedAt, remoteUpdatedAt: response.remoteUpdatedAt,
                    metadata: nil))
            } else {
                let response = try await apiClient.pushGitHubIssue(GitHubIssuePushRequest(
                    linkId: link.id, title: task.title,
                    body: task.description.isEmpty ? nil : task.description,
                    state: nil, remoteId: nil))
                if task.completed {
                    _ = try? await apiClient.pushGitHubIssue(GitHubIssuePushRequest(
                        linkId: link.id, title: nil, body: nil,
                        state: "closed", remoteId: response.remoteId))
                }
                try? await apiClient.upsertGitHubTaskLink(ExternalTaskLinkUpsertRequest(
                    astridTaskId: task.id, remoteId: response.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: task.updatedAt, remoteUpdatedAt: response.remoteUpdatedAt,
                    metadata: nil))
            }
        }
    }
}

extension Notification.Name {
    /// Server nudge (GitHub webhook → SSE): external data changed, pull soon.
    static let externalSyncRefresh = Notification.Name("externalSyncRefresh")
}
