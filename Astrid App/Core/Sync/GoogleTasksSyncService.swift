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
    @Published var syncMode: GoogleSyncMode = .manual
    @Published var listSuffix: String = ""


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
            syncMode = google?.metadata?.googleSyncMode.flatMap(GoogleSyncMode.init(rawValue:)) ?? .manual
            listSuffix = google?.metadata?.listSuffix ?? ""
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

    /// Persist the sync mode + suffix server-side (Integration.metadata) so the
    /// choice follows the account across devices, then sync (auto-link runs at
    /// the start of the pass).
    func setSyncMode(_ mode: GoogleSyncMode, suffix: String) async {
        syncMode = mode
        listSuffix = suffix
        try? await apiClient.updateIntegrationMetadata(
            provider: "GOOGLE_TASKS",
            metadata: ["googleSyncMode": mode.rawValue, "listSuffix": suffix])
        scheduleSync()
    }

    // MARK: - Sync

    func scheduleSync() {
        guard isConnected, !isSyncing else { return }
        guard !links.isEmpty || syncMode != .manual else { return }
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
        await autoLinkIfNeeded()
        for link in links {
            do {
                try await sync(link: link)
            } catch {
                lastError = "\(link.remoteContainerName ?? link.remoteContainerId): \(error.localizedDescription)"
            }
        }
        lastSyncedAt = Date()
    }

    /// Auto-link phase for the all-lists modes: create/adopt counterparts for
    /// anything unlinked, so new lists on either side flow in without manual
    /// linking. No-op in manual mode.
    private func autoLinkIfNeeded() async {
        guard syncMode != .manual else { return }
        guard let tasklists = try? await apiClient.getGoogleTasklists().tasklists else { return }
        let linkedTasklistIds = Set(links.map(\.remoteContainerId))
        let linkedListIds = Set(links.map(\.astridListId))
        let realLists = ListService.shared.lists
            .filter { !($0.isVirtual ?? false) && $0.listType != "status" && !$0.id.hasPrefix("temp_") }
        var didLink = false

        switch syncMode {
        case .manual:
            return
        case .allGoogleToAstrid:
            let actions = GoogleAutoLink.googleToAstridActions(
                tasklists: tasklists.map { .init(id: $0.id, name: $0.name) },
                linkedTasklistIds: linkedTasklistIds,
                unlinkedLists: realLists.filter { !linkedListIds.contains($0.id) }
                    .map { .init(id: $0.id, name: $0.name) },
                suffix: listSuffix)
            for action in actions {
                let listId: String
                if let adopt = action.adoptListId {
                    listId = adopt
                } else {
                    guard let created = try? await ListService.shared.createList(name: action.newListName),
                          !created.id.hasPrefix("temp_") else { continue }
                    listId = created.id
                }
                _ = try? await apiClient.createGoogleLink(astridListId: listId, tasklistId: action.tasklistId)
                didLink = true
            }
        case .allAstridToGoogle:
            let actions = GoogleAutoLink.astridToGoogleActions(
                lists: realLists.map { .init(id: $0.id, name: $0.name) },
                linkedListIds: linkedListIds,
                unlinkedTasklists: tasklists.filter { !linkedTasklistIds.contains($0.id) }
                    .map { .init(id: $0.id, name: $0.name) })
            for action in actions {
                let tasklistId: String
                if let adopt = action.adoptTasklistId {
                    tasklistId = adopt
                } else {
                    guard let created = try? await apiClient.createGoogleTasklist(title: action.newTasklistName) else { continue }
                    tasklistId = created.id
                }
                _ = try? await apiClient.createGoogleLink(astridListId: action.listId, tasklistId: tasklistId)
                didLink = true
            }
        }

        if didLink {
            links = (try? await apiClient.getGoogleLinks().links) ?? links
        }
    }

    private func sync(link: ExternalListLinkDTO) async throws {
        let taskService = TaskService.shared
        var taskLinks = try await apiClient.getGoogleTaskLinks(listId: link.astridListId).links
        var byRemoteId = Dictionary(taskLinks.map { ($0.remoteId, $0) }, uniquingKeysWith: { a, _ in a })
        var byTaskId = Dictionary(taskLinks.map { ($0.astridTaskId, $0) }, uniquingKeysWith: { a, _ in a })
        let iso = ISO8601DateFormatter()

        // ── PULL ────────────────────────────────────────────────────────────
        let pulled = try await apiClient.pullGoogleTasks(linkId: link.id)
        let pulledByRemoteId = Dictionary(pulled.items.map { ($0.remoteId, $0) }, uniquingKeysWith: { a, _ in a })
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
                // Adopt an existing UNLINKED same-title task in the list if one
                // exists (self-heals passes that created the task but couldn't
                // persist the link), else create one.
                let adopted = taskService.tasks.first {
                    ($0.listIds ?? []).contains(link.astridListId)
                        && !$0.id.hasPrefix("temp_") && byTaskId[$0.id] == nil
                        && $0.title == item.title
                }
                let newTask: Task
                if let adopted {
                    newTask = adopted
                } else {
                    newTask = try await taskService.createTask(
                        listIds: [link.astridListId], title: item.title,
                        description: item.notes,
                        whenDate: dueDate,
                        parentTaskId: parentTaskId, source: .google)
                }
                if item.completed, !newTask.completed {
                    _ = try? await taskService.completeTask(
                        id: newTask.id, completed: true, task: newTask, source: .google)
                }
                // The link row has an FK to the real Task id — resolve the
                // optimistic temp id before writing it, or the upsert silently
                // fails and the next pass duplicates the task.
                guard let realId = await resolveRealSyncTaskId(newTask.id) else { continue }
                try? await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                    astridTaskId: realId, remoteId: item.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: newTask.updatedAt, remoteUpdatedAt: item.remoteUpdatedAt,
                    metadata: item.metadata))
                let dto = ExternalTaskLinkDTO(
                    astridTaskId: realId, remoteId: item.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: newTask.updatedAt,
                    remoteUpdatedAt: remoteUpdated, metadata: item.metadata)
                byRemoteId[item.remoteId] = dto
                byTaskId[realId] = dto
                taskLinks.append(dto)
            }
        }

        // ── PUSH ────────────────────────────────────────────────────────────
        // Parents before children so parentRemoteId resolves within one pass.
        let listTasks = taskService.tasks
            .filter { ($0.listIds ?? []).contains(link.astridListId) && !$0.id.hasPrefix("temp_") }
            .sorted { ($0.parentTaskId == nil ? 0 : 1) < ($1.parentTaskId == nil ? 0 : 1) }
        var fullRemoteItems: [GoogleTaskItemDTO]?  // lazy, one cursor-free fetch per pass
        var pushErrors = 0
        for task in listTasks {
          do {
            let dueString: String? = task.dueDateTime.map { GoogleDueMapping.pushDueString(for: $0) }
            if let existing = byTaskId[task.id] {
                guard SyncSuppression.shouldPushLocal(
                    localUpdatedAt: task.updatedAt, watermark: existing.astridUpdatedAt) else { continue }
                // Content no-op guard: an unchanged PATCH still bumps the remote
                // updated stamp, which echoes back as a change. Advance the
                // watermark instead.
                if let remote = pulledByRemoteId[existing.remoteId],
                   remote.title == task.title,
                   (remote.notes ?? "") == task.description,
                   remote.completed == task.completed,
                   remote.dueDate == dueString {
                    try? await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                        astridTaskId: task.id, remoteId: existing.remoteId,
                        remoteContainerId: link.remoteContainerId,
                        astridUpdatedAt: task.updatedAt, remoteUpdatedAt: existing.remoteUpdatedAt.map { iso.string(from: $0) },
                        metadata: nil))
                    continue
                }
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
                // Push-side adopt guard: before CREATING a remote task for an
                // unlinked local one, scan the FULL remote list (cursor-free,
                // fetched once per pass) for an unlinked same-title item and
                // link to it instead of duplicating.
                if fullRemoteItems == nil {
                    fullRemoteItems = (try? await apiClient.pullGoogleTasks(linkId: link.id, full: true).items) ?? []
                }
                if let candidate = fullRemoteItems?.first(where: {
                    byRemoteId[$0.remoteId] == nil && $0.title == task.title
                }) {
                    try? await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                        astridTaskId: task.id, remoteId: candidate.remoteId,
                        remoteContainerId: link.remoteContainerId,
                        astridUpdatedAt: task.updatedAt, remoteUpdatedAt: candidate.remoteUpdatedAt,
                        metadata: candidate.metadata))
                    byRemoteId[candidate.remoteId] = ExternalTaskLinkDTO(
                        astridTaskId: task.id, remoteId: candidate.remoteId,
                        remoteContainerId: link.remoteContainerId,
                        astridUpdatedAt: task.updatedAt,
                        remoteUpdatedAt: iso.date(from: candidate.remoteUpdatedAt), metadata: candidate.metadata)
                    continue
                }
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
          } catch {
            // One task's push failing (e.g. its remote task was deleted)
            // must not abort the rest of the pass.
            pushErrors += 1
            print("⚠️ [GoogleSync] push failed for \(task.id): \(error)")
          }
        }
        if pushErrors > 0 {
            lastError = "\(link.remoteContainerName ?? link.remoteContainerId): \(pushErrors) task(s) failed to push"
        }
    }
}
