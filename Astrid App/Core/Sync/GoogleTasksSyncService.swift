import Foundation
import UIKit
import Combine

/// Google Tasks sync worker (Phase 3). Mirrors GitHubSyncService, with the
/// Google-specific lossy mapping: `due` is DATE-ONLY (timed Astrid tasks mirror
/// as all-day; the time survives locally), no priority/recurrence/reminders on
/// the Google side, and REAL subtask nesting via the `parent` insert param.
/// Google has no webhooks — pulls happen on foreground / SSE nudge / manual.
@MainActor
final class GoogleTasksSyncService: ObservableObject {
    static let shared = GoogleTasksSyncService()

    @Published var isConnected = false
    @Published var accountEmail: String?
    @Published var links: [ExternalListLinkDTO] = []
    @Published var isSyncing = false
    @Published var lastSyncedAt: Date?
    @Published var lastError: String?

    private let apiClient = AstridAPIClient.shared
    private var observers: [NSObjectProtocol] = []
    private var syncDebounce: _Concurrency.Task<Void, Never>?

    /// RFC3339 date-only at UTC midnight (Google Tasks `due` convention —
    /// matches Astrid's all-day UTC-midnight convention).
    private static let dueFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .externalSyncRefresh, object: nil, queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in self?.scheduleSync() }
        })
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in self?.scheduleSync() }
        })
    }

    // MARK: - Connection / links

    func refreshStatus() async {
        do {
            let integrations = try await apiClient.getSyncIntegrations().integrations
            let google = integrations.first { $0.provider == "GOOGLE_TASKS" }
            isConnected = google != nil
            accountEmail = google?.externalAccountId
            links = isConnected ? try await apiClient.getGoogleLinks().links : []
        } catch {
            isConnected = false
            links = []
        }
    }

    func authorizeURL() async -> URL? {
        (try? await apiClient.getGoogleAuthorizeURL().url).flatMap { URL(string: $0) }
    }

    func disconnect() async {
        try? await apiClient.disconnectGoogle()
        await refreshStatus()
    }

    func linkList(_ listId: String, tasklistId: String) async throws {
        _ = try await apiClient.createGoogleLink(astridListId: listId, tasklistId: tasklistId)
        await refreshStatus()
        scheduleSync()
    }

    func unlink(_ linkId: String) async {
        try? await apiClient.deleteGoogleLink(linkId: linkId)
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
                lastError = "\(link.remoteContainerName ?? link.remoteContainerId): \(error.localizedDescription)"
            }
        }
        lastSyncedAt = Date()
    }

    private func sync(link: ExternalListLinkDTO) async throws {
        let taskService = TaskService.shared
        var taskLinks = try await apiClient.getGoogleTaskLinks(listId: link.astridListId).links
        var byRemoteId = Dictionary(taskLinks.map { ($0.remoteId, $0) }, uniquingKeysWith: { a, _ in a })
        var byTaskId = Dictionary(taskLinks.map { ($0.astridTaskId, $0) }, uniquingKeysWith: { a, _ in a })
        let iso = ISO8601DateFormatter()

        // ── PULL ────────────────────────────────────────────────────────────
        let pulled = try await apiClient.pullGoogleTasks(linkId: link.id)
        for item in pulled.items {
            if item.metadata?["deleted"] == "1" { continue }  // v1: don't mirror deletions
            let remoteUpdated = iso.date(from: item.remoteUpdatedAt)
            let dueDate = item.dueDate.flatMap { Self.dueFormatter.date(from: $0) }

            if let existing = byRemoteId[item.remoteId] {
                guard SyncSuppression.shouldApplyRemote(
                    remoteUpdatedAt: remoteUpdated, watermark: existing.remoteUpdatedAt) else { continue }
                guard let task = taskService.tasks.first(where: { $0.id == existing.astridTaskId }) else { continue }
                if task.completed != item.completed {
                    _ = try? await taskService.completeTask(
                        id: task.id, completed: item.completed, task: task, source: .google)
                }
                if task.title != item.title || (item.notes ?? "") != task.description {
                    _ = try? await taskService.updateTask(
                        taskId: task.id, title: item.title,
                        description: item.notes ?? "", source: .google)
                }
                // Only adopt Google's date-only due if the task isn't holding a
                // TIMED due (Google can't express the time — don't clobber it).
                if let adopted = GoogleDueMapping.adoptedDue(
                    remoteDue: dueDate, localDue: task.dueDateTime, localIsAllDay: task.isAllDay) {
                    _ = try? await taskService.updateTask(
                        taskId: task.id, dueDateTime: adopted, isAllDay: true, source: .google)
                }
                try? await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                    astridTaskId: existing.astridTaskId, remoteId: item.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: Date(), remoteUpdatedAt: item.remoteUpdatedAt,
                    metadata: item.metadata))
            } else {
                // Real subtask nesting: Google `parent` (a google task id) →
                // Astrid parentTaskId via the remoteId map, when already synced.
                var parentTaskId: String?
                if let parent = item.metadata?["parent"], !parent.isEmpty {
                    parentTaskId = byRemoteId["\(link.remoteContainerId):\(parent)"]?.astridTaskId
                }
                let newTask = try await taskService.createTask(
                    listIds: [link.astridListId], title: item.title,
                    description: item.notes,
                    whenDate: dueDate,
                    parentTaskId: parentTaskId, source: .google)
                if item.completed {
                    _ = try? await taskService.completeTask(
                        id: newTask.id, completed: true, task: newTask, source: .google)
                }
                try? await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                    astridTaskId: newTask.id, remoteId: item.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: newTask.updatedAt, remoteUpdatedAt: item.remoteUpdatedAt,
                    metadata: item.metadata))
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

        // ── PUSH ────────────────────────────────────────────────────────────
        // Parents before children so parentRemoteId resolves within one pass.
        let listTasks = taskService.tasks
            .filter { ($0.listIds ?? []).contains(link.astridListId) && !$0.id.hasPrefix("temp_") }
            .sorted { ($0.parentTaskId == nil ? 0 : 1) < ($1.parentTaskId == nil ? 0 : 1) }
        for task in listTasks {
            let dueString: String? = task.dueDateTime.map { GoogleDueMapping.pushDueString(for: $0) }
            if let existing = byTaskId[task.id] {
                guard SyncSuppression.shouldPushLocal(
                    localUpdatedAt: task.updatedAt, watermark: existing.astridUpdatedAt) else { continue }
                let response = try await apiClient.pushGoogleTask(GoogleTaskPushRequest(
                    linkId: link.id, title: task.title,
                    notes: task.description.isEmpty ? nil : task.description,
                    dueDate: dueString, completed: task.completed,
                    remoteId: existing.remoteId, parentRemoteId: nil))
                try? await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                    astridTaskId: task.id, remoteId: existing.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: task.updatedAt, remoteUpdatedAt: response.remoteUpdatedAt,
                    metadata: nil))
            } else {
                let parentRemoteId = task.parentTaskId.flatMap { byTaskId[$0]?.remoteId }
                let response = try await apiClient.pushGoogleTask(GoogleTaskPushRequest(
                    linkId: link.id, title: task.title,
                    notes: task.description.isEmpty ? nil : task.description,
                    dueDate: dueString, completed: task.completed,
                    remoteId: nil, parentRemoteId: parentRemoteId))
                try? await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                    astridTaskId: task.id, remoteId: response.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: task.updatedAt, remoteUpdatedAt: response.remoteUpdatedAt,
                    metadata: nil))
                let dto = ExternalTaskLinkDTO(
                    astridTaskId: task.id, remoteId: response.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: task.updatedAt,
                    remoteUpdatedAt: response.remoteUpdatedAt.flatMap { iso.date(from: $0) },
                    metadata: nil)
                byTaskId[task.id] = dto
                byRemoteId[response.remoteId] = dto
            }
        }
    }
}
