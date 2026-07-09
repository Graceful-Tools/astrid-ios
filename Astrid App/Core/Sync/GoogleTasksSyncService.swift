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
    /// Tasklists the user opted OUT of (deleted their mirrored Astrid list
    /// while an all-lists mode was on) — auto-link must not resurrect them.
    @Published var excludedTasklistIds: Set<String> = []


    private let apiClient = AstridAPIClient.shared
    private var observers: [NSObjectProtocol] = []
    private var syncDebounce: _Concurrency.Task<Void, Never>?
    private let deletionLedger = SyncDeletionLedger(provider: "google")
    private var taskLinkCache: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "googleTaskLinkCache") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "googleTaskLinkCache") }
    }

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
        ) { [weak self] note in
            let source = note.userInfo?[OutboxManager.mutationSourceUserInfoKey] as? String
            guard SyncMutationNudge.shouldSchedule(provider: .google, mutationSource: source) else { return }
            _Concurrency.Task { @MainActor in self?.scheduleSync() }
        })
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in self?.scheduleSync() }
        })
        // Local writes nudge a debounced sync pass so pushes don't wait for
        // foreground/refresh. Suppress our OWN sync-originated mutations
        // (completed-backfill imports, remote-apply writes tagged source: .google):
        // re-arming a pass on those creates a self-sustaining ~2s loop until the
        // whole history is imported.
        observers.append(center.addObserver(
            forName: OutboxManager.didEnqueueMutation, object: nil, queue: .main
        ) { [weak self] note in
            let source = note.userInfo?[OutboxManager.mutationSourceUserInfoKey] as? String
            guard SyncMutationNudge.shouldSchedule(provider: .google, mutationSource: source) else { return }
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
            excludedTasklistIds = Set((google?.metadata?.excludedTasklists ?? "").split(separator: ",").map(String.init))
            // Server-recorded tombstones (tasks deleted on web/other clients)
            // merge into the SEPARATE server store (union with local tombstones)
            // so a large server set can't evict this device's own tombstones.
            deletionLedger.mergeServerTombstones(
                (google?.metadata?.tombstonedRemoteIds ?? "").split(separator: ",").map(String.init))
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
        // Manually linking clears any earlier opt-out for this tasklist.
        if excludedTasklistIds.contains(tasklistId) {
            excludedTasklistIds.remove(tasklistId)
            try? await apiClient.updateIntegrationMetadata(
                provider: "GOOGLE_TASKS",
                metadata: ["excludedTasklists": excludedTasklistIds.joined(separator: ",")])
        }
        await refreshStatus()
        scheduleSync()
    }

    /// Called when the user deletes an Astrid list that was linked to a Google
    /// tasklist: remember the tasklist as opted-out so the all-lists auto-link
    /// doesn't immediately resurrect the deleted list.
    func noteMirroredListDeleted(tasklistId: String) async {
        excludedTasklistIds.insert(tasklistId)
        try? await apiClient.updateIntegrationMetadata(
            provider: "GOOGLE_TASKS",
            metadata: ["excludedTasklists": excludedTasklistIds.joined(separator: ",")])
    }

    /// The user deleted a mirrored task: record the remote twin for deletion +
    /// permanent tombstone (the server-side link row cascades away with the task).
    func noteTaskDeleted(taskId: String) async {
        guard let cached = taskLinkCache[taskId] else { return }
        let parts = cached.split(separator: "|", maxSplits: 1)
        guard parts.count == 2 else { return }
        let remoteId = String(parts[0])
        guard !deletionLedger.tombstonedRemoteIds.contains(remoteId) else { return }
        deletionLedger.recordPending(remoteId: remoteId, containerId: String(parts[1]))
        var cache = taskLinkCache
        cache.removeValue(forKey: taskId)
        taskLinkCache = cache
        scheduleSync()
    }

    /// Sign-out: drop all in-memory state for the departing account.
    func resetForSignOut() {
        isConnected = false
        accountEmail = nil
        links = []
        isSyncing = false
        lastSyncedAt = nil
        lastError = nil
        syncMode = .manual
        listSuffix = ""
        excludedTasklistIds = []
        defaultTasklistId = nil  // else it leaks to the next account after re-login
        syncDebounce?.cancel()
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

    private var rerunAfterPass = false

    func scheduleSync() {
        guard isConnected else { return }
        guard !links.isEmpty || syncMode != .manual else { return }
        if isSyncing { rerunAfterPass = true; return }  // don't drop mid-pass nudges
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
        defer {
            isSyncing = false
            if rerunAfterPass { rerunAfterPass = false; scheduleSync() }
        }
        await autoLinkIfNeeded()
        for link in links {
            do {
                try await sync(link: link)
            } catch {
                lastError = "\(link.remoteContainerName ?? link.remoteContainerId): \(error.localizedDescription)"
            }
        }
        // My Tasks ↔ Google default list: unlisted tasks assigned to me. Only in
        // the all-lists modes, and skipped when a legacy setup list-linked the
        // default tasklist (the link sync above already covers it).
        if let defaultId = defaultTasklistId,
           GoogleAutoLink.myTasksPhaseActive(
               mode: syncMode, defaultTasklistId: defaultId,
               linkedTasklistIds: Set(links.map(\.remoteContainerId))) {
            do {
                try await syncMyTasks(tasklistId: defaultId)
            } catch {
                lastError = "My Tasks: \(error.localizedDescription)"
            }
        }
        lastSyncedAt = Date()
    }

    /// Auto-link phase for the all-lists modes: create/adopt counterparts for
    /// anything unlinked, so new lists on either side flow in without manual
    /// linking. No-op in manual mode.
    /// Real id of Google's default tasklist ("@default") — mirrors Astrid's
    /// My Tasks (unlisted, assigned-to-me). Captured during auto-link.
    private(set) var defaultTasklistId: String?

    private func autoLinkIfNeeded() async {
        guard syncMode != .manual else { return }
        guard let tasklistsResponse = try? await apiClient.getGoogleTasklists() else { return }
        defaultTasklistId = tasklistsResponse.defaultId
        let linkedTasklistIds = Set(links.map(\.remoteContainerId))
        // The default tasklist pairs with My Tasks (unlisted tasks), not with an
        // Astrid list — keep it out of auto-link UNLESS a legacy setup already
        // linked it to a list (then the list link stays authoritative).
        let tasklists = GoogleAutoLink.autoLinkCandidates(
            tasklists: tasklistsResponse.tasklists.map { .init(id: $0.id, name: $0.name) },
            defaultTasklistId: tasklistsResponse.defaultId,
            linkedTasklistIds: linkedTasklistIds)
        let linkedListIds = Set(links.map(\.astridListId))
        let realLists = ListService.shared.lists
            .filter { !($0.isVirtual ?? false) && $0.listType != "status" && !$0.id.hasPrefix("temp_") }
        var didLink = false

        switch syncMode {
        case .manual:
            return
        case .allBidirectional:
            let plan = GoogleAutoLink.bidirectionalActions(
                tasklists: tasklists.filter { !excludedTasklistIds.contains($0.id) }
                    .map { .init(id: $0.id, name: $0.name) },
                lists: realLists.map { .init(id: $0.id, name: $0.name) },
                linkedTasklistIds: linkedTasklistIds,
                linkedListIds: linkedListIds,
                suffix: listSuffix)
            for action in plan.googleToAstrid {
                do {
                    let listId: String
                    if let adopt = action.adoptListId {
                        listId = adopt
                    } else {
                        let created = try await ListService.shared.createList(name: action.newListName)
                        guard !created.id.hasPrefix("temp_") else { continue }
                        listId = created.id
                    }
                    _ = try await apiClient.createGoogleLink(astridListId: listId, tasklistId: action.tasklistId)
                    didLink = true
                } catch {
                    lastError = "Auto-link failed: \(error.localizedDescription)"
                }
            }
            for action in plan.astridToGoogle {
                do {
                    let tasklistId = try await apiClient.createGoogleTasklist(title: action.newTasklistName).id
                    _ = try await apiClient.createGoogleLink(astridListId: action.listId, tasklistId: tasklistId)
                    didLink = true
                } catch {
                    lastError = "Auto-link failed: \(error.localizedDescription)"
                }
            }
        case .allGoogleToAstrid:
            let actions = GoogleAutoLink.googleToAstridActions(
                tasklists: tasklists.filter { !excludedTasklistIds.contains($0.id) }
                    .map { .init(id: $0.id, name: $0.name) },
                linkedTasklistIds: linkedTasklistIds,
                unlinkedLists: realLists.filter { !linkedListIds.contains($0.id) }
                    .map { .init(id: $0.id, name: $0.name) },
                suffix: listSuffix)
            for action in actions {
                do {
                    let listId: String
                    if let adopt = action.adoptListId {
                        listId = adopt
                    } else {
                        let created = try await ListService.shared.createList(name: action.newListName)
                        guard !created.id.hasPrefix("temp_") else {
                            lastError = "Couldn't create list \"\(action.newListName)\" (offline?)"
                            continue
                        }
                        listId = created.id
                    }
                    _ = try await apiClient.createGoogleLink(astridListId: listId, tasklistId: action.tasklistId)
                    didLink = true
                } catch {
                    lastError = "Auto-link failed: \(error.localizedDescription)"
                }
            }
        case .allAstridToGoogle:
            let actions = GoogleAutoLink.astridToGoogleActions(
                lists: realLists.map { .init(id: $0.id, name: $0.name) },
                linkedListIds: linkedListIds,
                unlinkedTasklists: tasklists.filter { !linkedTasklistIds.contains($0.id) }
                    .map { .init(id: $0.id, name: $0.name) })
            for action in actions {
                do {
                    let tasklistId: String
                    if let adopt = action.adoptTasklistId {
                        tasklistId = adopt
                    } else {
                        tasklistId = try await apiClient.createGoogleTasklist(title: action.newTasklistName).id
                    }
                    _ = try await apiClient.createGoogleLink(astridListId: action.listId, tasklistId: tasklistId)
                    didLink = true
                } catch {
                    lastError = "Auto-link failed: \(error.localizedDescription)"
                }
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

        // Refresh the delete-capture cache for this container's tasks.
        var cache = taskLinkCache
        for tl in taskLinks where tl.remoteContainerId == link.remoteContainerId {
            cache[tl.astridTaskId] = "\(tl.remoteId)|\(tl.remoteContainerId)"
        }
        taskLinkCache = cache

        // Execute pending remote deletions (tasks deleted in Astrid).
        for (remoteId, containerId) in deletionLedger.pending where containerId == link.remoteContainerId {
            do {
                try await apiClient.deleteGoogleTask(linkId: link.id, remoteId: remoteId)
                deletionLedger.clearPending(remoteId: remoteId)
            } catch {
                if error.syncRemoteAlreadyGone {
                    deletionLedger.clearPending(remoteId: remoteId)
                }
            }
        }

        // ── PULL ────────────────────────────────────────────────────────────
        // Defer the cursor: commit it only after the whole pass applies, so a
        // kill mid-pass re-pulls this window instead of skipping remote edits.
        let pulled = try await apiClient.pullGoogleTasks(linkId: link.id, deferCursor: true)
        var pullAcknowledgement = SyncPassAcknowledgement()
        let pulledByRemoteId = Dictionary(pulled.items.map { ($0.remoteId, $0) }, uniquingKeysWith: { a, _ in a })
        // Parents before children so a subtask created in the same pass can
        // resolve its parent's fresh link.
        let orderedItems = SyncPullOrdering.parentsFirst(
            pulled.items,
            id: { $0.remoteId },
            parentId: { item in
                (item.metadata?["parent"]).flatMap { $0.isEmpty ? nil : "\(link.remoteContainerId):\($0)" }
            })
        for item in orderedItems {
            if item.metadata?["deleted"] == "1" {
                // Explicitly deleted in Google → delete the linked local twin.
                if let existing = byRemoteId[item.remoteId],
                   (taskService.tasksById[existing.astridTaskId] != nil) {
                    deletionLedger.recordTombstone(item.remoteId)  // no echo back
                    do {
                        try await taskService.deleteTask(id: existing.astridTaskId)
                    } catch {
                        pullAcknowledgement.recordFailure()
                    }
                }
                continue
            }
            if deletionLedger.tombstonedRemoteIds.contains(item.remoteId), byRemoteId[item.remoteId] == nil {
                continue  // never re-import a twin we deleted for a local deletion
            }
            let remoteUpdated = RFC3339.parse(item.remoteUpdatedAt)
            let dueDate = RFC3339.parse(item.dueDate)

            if let existing = byRemoteId[item.remoteId] {
                guard SyncSuppression.shouldApplyRemote(
                    remoteUpdatedAt: remoteUpdated, watermark: existing.remoteUpdatedAt) else { continue }
                guard let task = taskService.tasksById[existing.astridTaskId] else {
                    pullAcknowledgement.recordFailure()
                    continue
                }
                // Last-write-wins: a remote change that lost the race to a
                // fresher local edit must not clobber it — the push side will
                // carry the local state out instead.
                // Remote applies when provably newer than local — or when local
                // hasn't changed since our last sync point (nothing to lose).
                let localUnchanged = !SyncSuppression.shouldPushLocal(
                    localUpdatedAt: task.updatedAt, watermark: existing.astridUpdatedAt)
                guard SyncSuppression.remoteWins(
                    remoteUpdatedAt: remoteUpdated, localUpdatedAt: task.updatedAt) || localUnchanged else { continue }
                if task.completed != item.completed {
                    do {
                        _ = try await taskService.completeTask(
                            id: task.id, completed: item.completed, task: task, source: .google,
                            completedAt: RFC3339.parse(item.completedAt))
                    } catch {
                        pullAcknowledgement.recordFailure()
                        continue
                    }
                }
                if task.title != item.title || (item.notes ?? "") != task.description {
                    do {
                        _ = try await taskService.updateTask(
                            taskId: task.id, title: item.title,
                            description: item.notes ?? "", source: .google)
                    } catch {
                        pullAcknowledgement.recordFailure()
                        continue
                    }
                }
                // Only adopt Google's date-only due if the task isn't holding a
                // TIMED due (Google can't express the time — don't clobber it).
                if let adopted = GoogleDueMapping.adoptedDue(
                    remoteDue: dueDate, localDue: task.dueDateTime, localIsAllDay: task.isAllDay) {
                    do {
                        _ = try await taskService.updateTask(
                            taskId: task.id, dueDateTime: adopted, isAllDay: true, source: .google)
                    } catch {
                        pullAcknowledgement.recordFailure()
                        continue
                    }
                }
                do {
                    let appliedTask = taskService.tasksById[existing.astridTaskId] ?? task
                    try await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                        astridTaskId: existing.astridTaskId, remoteId: item.remoteId,
                        remoteContainerId: link.remoteContainerId,
                        astridUpdatedAt: SyncSuppression.pullWatermark(taskUpdatedAt: appliedTask.updatedAt),
                        remoteUpdatedAt: item.remoteUpdatedAt,
                        metadata: item.metadata))
                } catch {
                    pullAcknowledgement.recordFailure()
                    continue
                }
            } else {
                // Real subtask nesting: Google `parent` (a google task id) →
                // Astrid parentTaskId via the remoteId map, when already synced.
                var parentTaskId: String?
                if let parent = item.metadata?["parent"], !parent.isEmpty {
                    parentTaskId = byRemoteId["\(link.remoteContainerId):\(parent)"]?.astridTaskId
                }
                // Never IMPORT an already-completed item as a new task: an
                // all-lists link would flood Astrid with years of old completed
                // tasks (completion still syncs for linked pairs).
                if item.completed { continue }
                // Adopt an existing UNLINKED same-title task in the list only
                // when EXACTLY one exists (self-heals passes that created the
                // task but couldn't persist the link); ambiguous matches create
                // rather than mislink to an arbitrary twin.
                let adoptCandidates = taskService.tasks.filter {
                    ($0.listIds ?? []).contains(link.astridListId)
                        && !$0.id.hasPrefix("temp_") && byTaskId[$0.id] == nil
                        && $0.title == item.title
                }
                let adopted = adoptCandidates.count == 1 ? adoptCandidates.first : nil
                let newTask: Task
                if let adopted {
                    newTask = adopted
                } else {
                    // Google Tasks has no assignees — a pulled task belongs to
                    // the syncing user, so assign it to them (unassigned tasks
                    // otherwise vanish from My Tasks).
                    newTask = try await taskService.createTask(
                        listIds: [link.astridListId], title: item.title,
                        description: item.notes,
                        whenDate: dueDate,
                        assigneeId: AuthManager.shared.userId,
                        parentTaskId: parentTaskId, source: .google)
                }
                // The link row has an FK to the real Task id — resolve the
                // optimistic temp id before writing it, or the upsert silently
                // fails and the next pass duplicates the task.
                guard let realId = await resolveRealSyncTaskId(newTask.id) else {
                    pullAcknowledgement.recordFailure()
                    continue
                }
                do {
                    try await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                        astridTaskId: realId, remoteId: item.remoteId,
                        remoteContainerId: link.remoteContainerId,
                        astridUpdatedAt: newTask.updatedAt, remoteUpdatedAt: item.remoteUpdatedAt,
                        metadata: item.metadata))
                } catch {
                    pullAcknowledgement.recordFailure()
                    continue
                }
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
        var fullListingTruncated = true             // trust only an explicit server flag
        var fullListingUnavailable = false
        var pushErrors = 0
        // Remote ids we pushed this pass — drift repair must skip them (their
        // pass-start snapshot is stale by construction).
        var pushedRemoteIds: Set<String> = []
        for task in listTasks {
          do {
            let dueString: String? = task.dueDateTime.map { GoogleDueMapping.pushDueString(for: $0, isAllDay: task.isAllDay) }
            if let existing = byTaskId[task.id] {
                // Cross-container guard: a link for a different tasklist (task in
                // two linked lists, or moved) would PATCH the wrong tasklist and
                // 404-loop. Its own tasklist's pass handles it.
                guard SyncContainerGuard.mayPush(
                    linkContainerId: existing.remoteContainerId,
                    passContainerId: link.remoteContainerId) else { continue }
                guard SyncSuppression.shouldPushLocal(
                    localUpdatedAt: task.updatedAt, watermark: existing.astridUpdatedAt) else { continue }
                // Content no-op guard: an unchanged PATCH still bumps the remote
                // updated stamp, which echoes back as a change. Advance the
                // watermark instead.
                if let remote = pulledByRemoteId[existing.remoteId],
                   remote.title == task.title,
                   (remote.notes ?? "") == task.description,
                   remote.completed == task.completed,
                   RFC3339.parse(remote.dueDate) == RFC3339.parse(dueString) {
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
                // Skip drift for this pair (pushed this pass) and refresh the
                // in-memory watermark so localUnchanged reads true afterward.
                pushedRemoteIds.insert(existing.remoteId)
                let refreshed = ExternalTaskLinkDTO(
                    astridTaskId: task.id, remoteId: existing.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: task.updatedAt,
                    remoteUpdatedAt: RFC3339.parse(response.remoteUpdatedAt), metadata: nil)
                byTaskId[task.id] = refreshed
                byRemoteId[existing.remoteId] = refreshed
            } else {
                // Push-side adopt guard: before CREATING a remote task for an
                // unlinked local one, scan the FULL remote list (cursor-free,
                // fetched once per pass) for an unlinked same-title item and
                // link to it instead of duplicating.
                if fullRemoteItems == nil {
                    if let fullPull = try? await apiClient.pullGoogleTasks(linkId: link.id, full: true) {
                        fullRemoteItems = fullPull.items
                        fullListingTruncated = fullPull.truncated ?? true
                    } else {
                        fullListingUnavailable = true
                    }
                }
                let candidate = fullRemoteItems?.first(where: {
                    byRemoteId[$0.remoteId] == nil && $0.title == task.title
                })
                if let candidate {
                    try? await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                        astridTaskId: task.id, remoteId: candidate.remoteId,
                        remoteContainerId: link.remoteContainerId,
                        astridUpdatedAt: task.updatedAt, remoteUpdatedAt: candidate.remoteUpdatedAt,
                        metadata: candidate.metadata))
                    byRemoteId[candidate.remoteId] = ExternalTaskLinkDTO(
                        astridTaskId: task.id, remoteId: candidate.remoteId,
                        remoteContainerId: link.remoteContainerId,
                        astridUpdatedAt: task.updatedAt,
                        remoteUpdatedAt: RFC3339.parse(candidate.remoteUpdatedAt), metadata: candidate.metadata)
                    continue
                }
                guard SyncAdoptionSafety.mayCreateRemote(
                    fullListingAvailable: !fullListingUnavailable && fullRemoteItems != nil,
                    listingTruncated: fullListingTruncated,
                    matchingTwinExists: candidate != nil
                ) else {
                    pushErrors += 1
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
                    remoteUpdatedAt: RFC3339.parse(response.remoteUpdatedAt),
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

        // ── DRIFT REPAIR: linked pairs whose completion disagrees, where the
        // local task hasn't changed since our last sync point, adopt remote
        // truth. Old items never re-enter the cursor window, so without this a
        // botched pass leaves permanent drift (the imported-open flood).
        if let fullItems = fullRemoteItems {
            for item in fullItems where item.metadata?["deleted"] != "1" {
                // A pair we pushed this pass has a stale snapshot here — skip it,
                // or a just-reopened repeating task gets re-completed (double
                // rollover) and an un-completion gets reverted.
                guard !pushedRemoteIds.contains(item.remoteId) else { continue }
                guard let existing = byRemoteId[item.remoteId],
                      let task = taskService.tasksById[existing.astridTaskId]
                else { continue }
                let localUnchanged = !SyncSuppression.shouldPushLocal(
                    localUpdatedAt: task.updatedAt, watermark: existing.astridUpdatedAt)
                guard CompletionDriftPolicy.shouldAdoptRemote(
                    remoteCompleted: item.completed, localCompleted: task.completed,
                    localCompletedAt: task.completedAt, localUnchanged: localUnchanged,
                    isRepeating: (task.repeating ?? .never) != .never)
                else { continue }
                _ = try? await taskService.completeTask(
                    id: task.id, completed: item.completed, task: task, source: .google,
                    completedAt: RFC3339.parse(item.completedAt))
            }
        }

        // ── DELETIONS: task gone remotely → delete the local twin ──────────
        // Complete-listing guard: skipped when the fetch failed or hit the
        // page limit (SyncDeletionPolicy invariant).
        let fullPullKey = "googleLastFullPull:\(link.remoteContainerId)"
        let lastFullPull = UserDefaults.standard.object(forKey: fullPullKey) as? Date
        let fullPullDue = FullPullThrottle.isDue(
            lastSuccess: lastFullPull, now: Date(), interval: 300)
        if fullRemoteItems == nil, fullPullDue {
            if let fullPull = try? await apiClient.pullGoogleTasks(linkId: link.id, full: true) {
                fullRemoteItems = fullPull.items
                fullListingTruncated = fullPull.truncated ?? true
            }
        }
        if fullRemoteItems != nil, !fullListingTruncated {
            UserDefaults.standard.set(Date(), forKey: fullPullKey)
        }
        if let fullItems = fullRemoteItems {
            let present = Set(fullItems.filter { $0.metadata?["deleted"] != "1" }.map(\.remoteId))
            let deletionLinks = taskLinks
                .filter { $0.remoteContainerId == link.remoteContainerId }
                .map { SyncDeletionPolicy.Link(taskId: $0.astridTaskId, remoteId: $0.remoteId) }
            let listingTruncated = fullListingTruncated
            let toDelete = await _Concurrency.Task.detached(priority: .utility) {
                SyncDeletionPolicy.localDeletions(
                    links: deletionLinks, fullRemoteIds: present,
                    truncated: listingTruncated, explicitlyDeletedRemoteIds: [])
            }.value
            for del in toDelete where (taskService.tasksById[del.taskId] != nil) {
                deletionLedger.recordTombstone(del.remoteId)  // no echo back
                try? await taskService.deleteTask(id: del.taskId)
            }
        }

        // ── COMPLETED BACKFILL (lowest priority, runs last): import completed
        // history gradually so it's searchable/reviewable without ever
        // delaying live items. Budgeted per pass; the full listing re-offers
        // the remainder next pass.
        if let fullItems = fullRemoteItems {
            var adoptionIndex = BackfillAdoptionIndex(candidates: taskService.tasks.compactMap { task in
                guard (task.listIds ?? []).contains(link.astridListId),
                      !task.id.hasPrefix("temp_"), byTaskId[task.id] == nil,
                      task.completed else { return nil }
                return .init(taskId: task.id, title: task.title)
            })
            let backfillCandidates = fullItems.map { CompletedBackfill.Candidate(
                    remoteId: $0.remoteId, completed: $0.completed,
                    deleted: $0.metadata?["deleted"] == "1",
                    updatedAt: $0.remoteUpdatedAt) }
            let linkedRemoteIds = Set(byRemoteId.keys)
            let tombstonedRemoteIds = deletionLedger.tombstonedRemoteIds
            let batch = await _Concurrency.Task.detached(priority: .utility) {
                CompletedBackfill.select(
                    backfillCandidates, linkedRemoteIds: linkedRemoteIds,
                    tombstoned: tombstonedRemoteIds, budget: 20)
            }.value
            let byId = Dictionary(fullItems.map { ($0.remoteId, $0) }, uniquingKeysWith: { a, _ in a })
            for candidate in batch {
                guard let item = byId[candidate.remoteId] else { continue }
                let backdated = RFC3339.parse(item.completedAt) ?? RFC3339.parse(item.remoteUpdatedAt) ?? Date()
                // Self-heal a prior backfill pass that created the task but
                // couldn't persist the link: adopt the still-unlinked completed
                // twin instead of duplicating it every pass (see GitHub backfill).
                let newTask: Task
                if let taskId = adoptionIndex.takeUniqueTaskId(title: item.title),
                   let twin = taskService.tasksById[taskId] {
                    newTask = twin
                } else {
                    guard let created = try? await taskService.createTask(
                        listIds: [link.astridListId], title: item.title,
                        description: item.notes,
                        whenDate: RFC3339.parse(item.dueDate),
                        assigneeId: AuthManager.shared.userId,
                        source: .google, presumeCompletedAt: backdated) else { continue }
                    _ = try? await taskService.completeTask(
                        id: created.id, completed: true, task: created, source: .google,
                        completedAt: backdated)
                    newTask = created
                }
                guard let realId = await resolveRealSyncTaskId(newTask.id) else { continue }
                try? await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                    astridTaskId: realId, remoteId: item.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: Date(), remoteUpdatedAt: item.remoteUpdatedAt,
                    metadata: item.metadata))
                let dto = ExternalTaskLinkDTO(
                    astridTaskId: realId, remoteId: item.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: Date(),
                    remoteUpdatedAt: RFC3339.parse(item.remoteUpdatedAt), metadata: item.metadata)
                byRemoteId[item.remoteId] = dto
                byTaskId[realId] = dto
            }
        }

        // Pass fully applied — commit the pulled cursor (client-acknowledged).
        _ = try await ProviderCursorCommitter.commitIfSafe(
            acknowledgement: pullAcknowledgement, cursor: pulled.cursor
        ) { cursor in
            try await apiClient.commitGoogleCursor(linkId: link.id, cursor: cursor)
        }
    }

    /// My Tasks ↔ Google default tasklist. Same pipeline as sync(link:) but in
    /// "direct" mode: no ExternalListLink row, the pull is always the full
    /// listing (per-item watermarks make re-applies no-ops), and the local set
    /// is "assigned to me, in no list".
    private func syncMyTasks(tasklistId: String) async throws {
        let taskService = TaskService.shared
        guard let myUserId = AuthManager.shared.userId else { return }
        let pullEnabled = syncMode == .allGoogleToAstrid || syncMode == .allBidirectional
        let pushEnabled = syncMode == .allAstridToGoogle || syncMode == .allBidirectional

        var taskLinks = try await apiClient.getGoogleTaskLinksByContainer(containerId: tasklistId).links
        var byRemoteId = Dictionary(taskLinks.map { ($0.remoteId, $0) }, uniquingKeysWith: { a, _ in a })
        var byTaskId = Dictionary(taskLinks.map { ($0.astridTaskId, $0) }, uniquingKeysWith: { a, _ in a })
        let iso = ISO8601DateFormatter()

        var cache = taskLinkCache
        for tl in taskLinks where tl.remoteContainerId == tasklistId {
            cache[tl.astridTaskId] = "\(tl.remoteId)|\(tl.remoteContainerId)"
        }
        taskLinkCache = cache

        // Locally-deleted twins propagate in every active mode — same behavior
        // as linked lists.
        for (remoteId, containerId) in deletionLedger.pending where containerId == tasklistId {
            do {
                try await apiClient.deleteGoogleTaskDirect(tasklistId: tasklistId, remoteId: remoteId)
                deletionLedger.clearPending(remoteId: remoteId)
            } catch {
                if error.syncRemoteAlreadyGone {
                    deletionLedger.clearPending(remoteId: remoteId)
                }
            }
        }

        // ── PULL (always the full listing in direct mode) ──────────────────
        let pulled = try await apiClient.pullGoogleTasksDirect(tasklistId: tasklistId)
        let fullRemoteItems = pulled.items
        let fullListingTruncated = pulled.truncated ?? true
        let pulledByRemoteId = Dictionary(pulled.items.map { ($0.remoteId, $0) }, uniquingKeysWith: { a, _ in a })

        if pullEnabled {
            let orderedItems = SyncPullOrdering.parentsFirst(
                pulled.items,
                id: { $0.remoteId },
                parentId: { item in
                    (item.metadata?["parent"]).flatMap { $0.isEmpty ? nil : "\(tasklistId):\($0)" }
                })
            for item in orderedItems {
                if item.metadata?["deleted"] == "1" {
                    if let existing = byRemoteId[item.remoteId],
                       (taskService.tasksById[existing.astridTaskId] != nil) {
                        deletionLedger.recordTombstone(item.remoteId)
                        try? await taskService.deleteTask(id: existing.astridTaskId)
                    }
                    continue
                }
                if deletionLedger.tombstonedRemoteIds.contains(item.remoteId), byRemoteId[item.remoteId] == nil {
                    continue
                }
                let remoteUpdated = RFC3339.parse(item.remoteUpdatedAt)
                let dueDate = RFC3339.parse(item.dueDate)

                if let existing = byRemoteId[item.remoteId] {
                    guard SyncSuppression.shouldApplyRemote(
                        remoteUpdatedAt: remoteUpdated, watermark: existing.remoteUpdatedAt) else { continue }
                    guard let task = taskService.tasksById[existing.astridTaskId] else { continue }
                    let localUnchanged = !SyncSuppression.shouldPushLocal(
                        localUpdatedAt: task.updatedAt, watermark: existing.astridUpdatedAt)
                    guard SyncSuppression.remoteWins(
                        remoteUpdatedAt: remoteUpdated, localUpdatedAt: task.updatedAt) || localUnchanged else { continue }
                    if task.completed != item.completed {
                        _ = try? await taskService.completeTask(
                            id: task.id, completed: item.completed, task: task, source: .google,
                            completedAt: RFC3339.parse(item.completedAt))
                    }
                    if task.title != item.title || (item.notes ?? "") != task.description {
                        _ = try? await taskService.updateTask(
                            taskId: task.id, title: item.title,
                            description: item.notes ?? "", source: .google)
                    }
                    if let adopted = GoogleDueMapping.adoptedDue(
                        remoteDue: dueDate, localDue: task.dueDateTime, localIsAllDay: task.isAllDay) {
                        _ = try? await taskService.updateTask(
                            taskId: task.id, dueDateTime: adopted, isAllDay: true, source: .google)
                    }
                    try? await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                        astridTaskId: existing.astridTaskId, remoteId: item.remoteId,
                        remoteContainerId: tasklistId,
                        astridUpdatedAt: SyncSuppression.pullWatermark(taskUpdatedAt: task.updatedAt),
                        remoteUpdatedAt: item.remoteUpdatedAt,
                        metadata: item.metadata))
                } else {
                    var parentTaskId: String?
                    if let parent = item.metadata?["parent"], !parent.isEmpty {
                        parentTaskId = byRemoteId["\(tasklistId):\(parent)"]?.astridTaskId
                    }
                    if item.completed { continue }
                    let adoptCandidates = taskService.tasks.filter {
                        ($0.listIds ?? []).isEmpty && $0.assigneeId == myUserId
                            && !$0.id.hasPrefix("temp_") && byTaskId[$0.id] == nil
                            && $0.title == item.title
                    }
                    let adopted = adoptCandidates.count == 1 ? adoptCandidates.first : nil
                    let newTask: Task
                    if let adopted {
                        newTask = adopted
                    } else {
                        newTask = try await taskService.createTask(
                            listIds: [], title: item.title,
                            description: item.notes,
                            whenDate: dueDate,
                            assigneeId: myUserId,
                            parentTaskId: parentTaskId, source: .google)
                    }
                    guard let realId = await resolveRealSyncTaskId(newTask.id) else { continue }
                    try? await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                        astridTaskId: realId, remoteId: item.remoteId,
                        remoteContainerId: tasklistId,
                        astridUpdatedAt: newTask.updatedAt, remoteUpdatedAt: item.remoteUpdatedAt,
                        metadata: item.metadata))
                    let dto = ExternalTaskLinkDTO(
                        astridTaskId: realId, remoteId: item.remoteId,
                        remoteContainerId: tasklistId,
                        astridUpdatedAt: newTask.updatedAt,
                        remoteUpdatedAt: remoteUpdated, metadata: item.metadata)
                    byRemoteId[item.remoteId] = dto
                    byTaskId[realId] = dto
                    taskLinks.append(dto)
                }
            }
        }

        // Remote ids pushed this pass — drift repair (below) must skip them.
        var pushedRemoteIds: Set<String> = []
        // ── PUSH: unlisted tasks assigned to me ─────────────────────────────
        if pushEnabled {
            let myTasks = taskService.tasks
                .filter { ($0.listIds ?? []).isEmpty && $0.assigneeId == myUserId && !$0.id.hasPrefix("temp_") }
                .sorted { ($0.parentTaskId == nil ? 0 : 1) < ($1.parentTaskId == nil ? 0 : 1) }
            var pushErrors = 0
            for task in myTasks {
              do {
                let dueString: String? = task.dueDateTime.map { GoogleDueMapping.pushDueString(for: $0, isAllDay: task.isAllDay) }
                if let existing = byTaskId[task.id] {
                    guard SyncSuppression.shouldPushLocal(
                        localUpdatedAt: task.updatedAt, watermark: existing.astridUpdatedAt) else { continue }
                    if let remote = pulledByRemoteId[existing.remoteId],
                       remote.title == task.title,
                       (remote.notes ?? "") == task.description,
                       remote.completed == task.completed,
                       RFC3339.parse(remote.dueDate) == RFC3339.parse(dueString) {
                        try? await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                            astridTaskId: task.id, remoteId: existing.remoteId,
                            remoteContainerId: tasklistId,
                            astridUpdatedAt: task.updatedAt, remoteUpdatedAt: existing.remoteUpdatedAt.map { iso.string(from: $0) },
                            metadata: nil))
                        continue
                    }
                    let response = try await apiClient.pushGoogleTask(GoogleTaskPushRequest(
                        tasklistId: tasklistId, title: task.title,
                        notes: task.description.isEmpty ? nil : task.description,
                        dueDate: dueString, completed: task.completed,
                        remoteId: existing.remoteId, parentRemoteId: nil))
                    try? await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                        astridTaskId: task.id, remoteId: existing.remoteId,
                        remoteContainerId: tasklistId,
                        astridUpdatedAt: task.updatedAt, remoteUpdatedAt: response.remoteUpdatedAt,
                        metadata: nil))
                    pushedRemoteIds.insert(existing.remoteId)
                    let refreshed = ExternalTaskLinkDTO(
                        astridTaskId: task.id, remoteId: existing.remoteId,
                        remoteContainerId: tasklistId,
                        astridUpdatedAt: task.updatedAt,
                        remoteUpdatedAt: RFC3339.parse(response.remoteUpdatedAt), metadata: nil)
                    byTaskId[task.id] = refreshed
                    byRemoteId[existing.remoteId] = refreshed
                } else {
                    // Never CREATE a remote twin for an already-completed local
                    // task — only live items belong in the mirror going forward.
                    if task.completed { continue }
                    if let candidate = fullRemoteItems.first(where: {
                        byRemoteId[$0.remoteId] == nil && $0.title == task.title
                    }) {
                        try? await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                            astridTaskId: task.id, remoteId: candidate.remoteId,
                            remoteContainerId: tasklistId,
                            astridUpdatedAt: task.updatedAt, remoteUpdatedAt: candidate.remoteUpdatedAt,
                            metadata: candidate.metadata))
                        byRemoteId[candidate.remoteId] = ExternalTaskLinkDTO(
                            astridTaskId: task.id, remoteId: candidate.remoteId,
                            remoteContainerId: tasklistId,
                            astridUpdatedAt: task.updatedAt,
                            remoteUpdatedAt: RFC3339.parse(candidate.remoteUpdatedAt), metadata: candidate.metadata)
                        continue
                    }
                    let parentRemoteId = task.parentTaskId.flatMap { byTaskId[$0]?.remoteId }
                    let response = try await apiClient.pushGoogleTask(GoogleTaskPushRequest(
                        tasklistId: tasklistId, title: task.title,
                        notes: task.description.isEmpty ? nil : task.description,
                        dueDate: dueString, completed: task.completed,
                        remoteId: nil, parentRemoteId: parentRemoteId))
                    try? await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                        astridTaskId: task.id, remoteId: response.remoteId,
                        remoteContainerId: tasklistId,
                        astridUpdatedAt: task.updatedAt, remoteUpdatedAt: response.remoteUpdatedAt,
                        metadata: nil))
                    let dto = ExternalTaskLinkDTO(
                        astridTaskId: task.id, remoteId: response.remoteId,
                        remoteContainerId: tasklistId,
                        astridUpdatedAt: task.updatedAt,
                        remoteUpdatedAt: RFC3339.parse(response.remoteUpdatedAt),
                        metadata: nil)
                    byTaskId[task.id] = dto
                    byRemoteId[response.remoteId] = dto
                }
              } catch {
                pushErrors += 1
                print("⚠️ [GoogleSync] My Tasks push failed for \(task.id): \(error)")
              }
            }
            if pushErrors > 0 {
                lastError = "My Tasks: \(pushErrors) task(s) failed to push"
            }

            // ── RETIRE ORPHAN TWINS ─────────────────────────────────────────
            // A task that LEFT My Tasks — gained a list, or lost the "assigned
            // to me" that put it here — still holds a link in the default
            // tasklist, so its Google twin lingers as a SECOND source of truth
            // (drift repair keeps syncing it, and the deletion pass below would
            // read the still-present remote as "gone locally" only after the
            // twin is removed). The task now lives in its list; close out the
            // default-tasklist twin so it has one home. Deleted tasks are
            // handled by the pending-deletion path, not here.
            let qualifyingIds = Set(taskService.tasks
                .filter { ($0.listIds ?? []).isEmpty && $0.assigneeId == myUserId }
                .map { $0.id })
            var retiredRemoteIds: Set<String> = []
            for existing in taskLinks where existing.remoteContainerId == tasklistId {
                guard taskService.tasksById[existing.astridTaskId] != nil,   // still exists locally
                      !qualifyingIds.contains(existing.astridTaskId),         // but no longer My Tasks
                      !pushedRemoteIds.contains(existing.remoteId) else { continue }
                do {
                    try await apiClient.deleteGoogleTaskDirect(tasklistId: tasklistId, remoteId: existing.remoteId)
                } catch {
                    guard error.syncRemoteAlreadyGone else { continue }  // real error → retry next pass
                }
                deletionLedger.recordTombstone(existing.remoteId)  // never re-import this twin
                byRemoteId.removeValue(forKey: existing.remoteId)
                byTaskId.removeValue(forKey: existing.astridTaskId)
                retiredRemoteIds.insert(existing.remoteId)
            }
            // Drop retired links so the deletion pass can't read them as
            // "remote gone" and delete the (still-valid) local task.
            if !retiredRemoteIds.isEmpty {
                taskLinks.removeAll { retiredRemoteIds.contains($0.remoteId) }
            }
        }

        if pullEnabled {
            // ── DRIFT REPAIR ────────────────────────────────────────────────
            for item in fullRemoteItems where item.metadata?["deleted"] != "1" {
                guard !pushedRemoteIds.contains(item.remoteId) else { continue }
                guard let existing = byRemoteId[item.remoteId],
                      let task = taskService.tasksById[existing.astridTaskId]
                else { continue }
                let localUnchanged = !SyncSuppression.shouldPushLocal(
                    localUpdatedAt: task.updatedAt, watermark: existing.astridUpdatedAt)
                guard CompletionDriftPolicy.shouldAdoptRemote(
                    remoteCompleted: item.completed, localCompleted: task.completed,
                    localCompletedAt: task.completedAt, localUnchanged: localUnchanged,
                    isRepeating: (task.repeating ?? .never) != .never)
                else { continue }
                _ = try? await taskService.completeTask(
                    id: task.id, completed: item.completed, task: task, source: .google,
                    completedAt: RFC3339.parse(item.completedAt))
            }

            // ── DELETIONS: gone remotely → delete the local twin ────────────
            let present = Set(fullRemoteItems.filter { $0.metadata?["deleted"] != "1" }.map(\.remoteId))
            let deletionLinks = taskLinks
                .filter { $0.remoteContainerId == tasklistId }
                .map { SyncDeletionPolicy.Link(taskId: $0.astridTaskId, remoteId: $0.remoteId) }
            let listingTruncated = fullListingTruncated
            let toDelete = await _Concurrency.Task.detached(priority: .utility) {
                SyncDeletionPolicy.localDeletions(
                    links: deletionLinks, fullRemoteIds: present,
                    truncated: listingTruncated, explicitlyDeletedRemoteIds: [])
            }.value
            for del in toDelete where (taskService.tasksById[del.taskId] != nil) {
                deletionLedger.recordTombstone(del.remoteId)
                try? await taskService.deleteTask(id: del.taskId)
            }

            // ── COMPLETED BACKFILL ──────────────────────────────────────────
            // Build the adoption index once (unlisted, assigned-to-me, completed,
            // unlinked twins) instead of re-scanning all tasks per candidate, and
            // offload the pure selection off MainActor — mirrors the linked-list
            // backfill path above.
            var adoptionIndex = BackfillAdoptionIndex(candidates: taskService.tasks.compactMap { task in
                guard (task.listIds ?? []).isEmpty, task.assigneeId == myUserId,
                      !task.id.hasPrefix("temp_"), byTaskId[task.id] == nil,
                      task.completed else { return nil }
                return .init(taskId: task.id, title: task.title)
            })
            let backfillCandidates = fullRemoteItems.map { CompletedBackfill.Candidate(
                    remoteId: $0.remoteId, completed: $0.completed,
                    deleted: $0.metadata?["deleted"] == "1",
                    updatedAt: $0.remoteUpdatedAt) }
            let linkedRemoteIds = Set(byRemoteId.keys)
            let tombstonedRemoteIds = deletionLedger.tombstonedRemoteIds
            let batch = await _Concurrency.Task.detached(priority: .utility) {
                CompletedBackfill.select(
                    backfillCandidates, linkedRemoteIds: linkedRemoteIds,
                    tombstoned: tombstonedRemoteIds, budget: 20)
            }.value
            let byId = Dictionary(fullRemoteItems.map { ($0.remoteId, $0) }, uniquingKeysWith: { a, _ in a })
            for candidate in batch {
                guard let item = byId[candidate.remoteId] else { continue }
                let backdated = RFC3339.parse(item.completedAt) ?? RFC3339.parse(item.remoteUpdatedAt) ?? Date()
                // Self-heal a prior backfill pass that created the task but
                // couldn't persist the link: adopt the still-unlinked completed
                // twin (assigned-to-me, no list) instead of duplicating it.
                let newTask: Task
                if let taskId = adoptionIndex.takeUniqueTaskId(title: item.title),
                   let twin = taskService.tasksById[taskId] {
                    newTask = twin
                } else {
                    guard let created = try? await taskService.createTask(
                        listIds: [], title: item.title,
                        description: item.notes,
                        whenDate: RFC3339.parse(item.dueDate),
                        assigneeId: myUserId,
                        source: .google, presumeCompletedAt: backdated) else { continue }
                    _ = try? await taskService.completeTask(
                        id: created.id, completed: true, task: created, source: .google,
                        completedAt: backdated)
                    newTask = created
                }
                guard let realId = await resolveRealSyncTaskId(newTask.id) else { continue }
                try? await apiClient.upsertGoogleTaskLink(ExternalTaskLinkUpsertRequest(
                    astridTaskId: realId, remoteId: item.remoteId,
                    remoteContainerId: tasklistId,
                    astridUpdatedAt: Date(), remoteUpdatedAt: item.remoteUpdatedAt,
                    metadata: item.metadata))
                let dto = ExternalTaskLinkDTO(
                    astridTaskId: realId, remoteId: item.remoteId,
                    remoteContainerId: tasklistId,
                    astridUpdatedAt: Date(),
                    remoteUpdatedAt: RFC3339.parse(item.remoteUpdatedAt), metadata: item.metadata)
                byRemoteId[item.remoteId] = dto
                byTaskId[realId] = dto
            }
        }
    }
}
