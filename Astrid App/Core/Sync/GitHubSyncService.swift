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
    private var mutationObserver: NSObjectProtocol?
    private var syncDebounce: _Concurrency.Task<Void, Never>?
    private let deletionLedger = SyncDeletionLedger(provider: "github")
    /// taskId → "remoteId|containerId", persisted so a delete can capture its
    /// link even before the first sync pass after relaunch.
    private var taskLinkCache: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "githubTaskLinkCache") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "githubTaskLinkCache") }
    }

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
        // Local writes (title/description edits, completions, comments) nudge a
        // debounced sync pass so pushes don't wait for foreground/refresh.
        mutationObserver = NotificationCenter.default.addObserver(
            forName: OutboxManager.didEnqueueMutation, object: nil, queue: .main
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
            // Server-recorded tombstones (tasks deleted on web/other clients)
            // merge into the local ledger so pulls never resurrect them.
            for remoteId in (github?.metadata?.tombstonedRemoteIds ?? "").split(separator: ",") {
                deletionLedger.recordTombstone(String(remoteId))
            }
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

    /// The user deleted a mirrored task: record the remote twin for close +
    /// permanent tombstone (the server-side link row cascades away with the
    /// task, so this must be captured now).
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
        accountLogin = nil
        links = []
        isSyncing = false
        lastSyncedAt = nil
        lastError = nil
        syncDebounce?.cancel()
    }

    func unlink(_ linkId: String) async {
        try? await apiClient.deleteGitHubLink(linkId: linkId)
        await refreshStatus()
    }

    // MARK: - Sync

    private var rerunAfterPass = false

    func scheduleSync() {
        guard isConnected, !links.isEmpty else { return }
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

        // Refresh the delete-capture cache for this container's tasks.
        var cache = taskLinkCache
        for tl in taskLinks where tl.remoteContainerId == link.remoteContainerId {
            cache[tl.astridTaskId] = "\(tl.remoteId)|\(tl.remoteContainerId)"
        }
        taskLinkCache = cache

        // Execute pending remote deletions (tasks deleted in Astrid): GitHub
        // can't delete issues via REST, so the twin is CLOSED; the tombstone
        // keeps the pull from ever re-importing it.
        for (remoteId, containerId) in deletionLedger.pending where containerId == link.remoteContainerId {
            do {
                _ = try await apiClient.pushGitHubIssue(GitHubIssuePushRequest(
                    linkId: link.id, title: nil, body: nil, state: "closed", remoteId: remoteId))
                deletionLedger.clearPending(remoteId: remoteId)
            } catch {
                // 404/410 = already gone — done; anything else retries next pass.
                if "\(error)".contains("404") || "\(error)".contains("410") {
                    deletionLedger.clearPending(remoteId: remoteId)
                }
            }
        }

        // ── PULL: apply remote changes newer than our watermark ────────────
        let pulled = try await apiClient.pullGitHubIssues(linkId: link.id)
        let pulledByRemoteId = Dictionary(pulled.items.map { ($0.remoteId, $0) }, uniquingKeysWith: { a, _ in a })
        let iso = ISO8601DateFormatter()
        // Parents before children so a sub-issue created in the same pass can
        // resolve its parent's fresh link. metadata.parent = parent issue number.
        let orderedItems = SyncPullOrdering.parentsFirst(
            pulled.items,
            id: { $0.remoteId },
            parentId: { item in
                (item.metadata?["parent"]).flatMap { $0.isEmpty ? nil : "\(link.remoteContainerId)#\($0)" }
            })
        for item in orderedItems {
            let remoteUpdated = RFC3339.parse(item.remoteUpdatedAt)
            if let existing = byRemoteId[item.remoteId] {
                // Echo/staleness guard: only apply if remote is newer than the
                // watermark we wrote at the last push/pull.
                guard SyncSuppression.shouldApplyRemote(
                    remoteUpdatedAt: remoteUpdated, watermark: existing.remoteUpdatedAt) else { continue }
                guard let task = taskService.tasks.first(where: { $0.id == existing.astridTaskId }) else { continue }
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
                    // Canonical completion — repeating tasks roll forward; the
                    // next push reopens/reschedules the issue.
                    _ = try? await taskService.completeTask(
                        id: task.id, completed: item.completed, task: task, source: .github,
                        completedAt: RFC3339.parse(item.completedAt))
                }
                if task.title != item.title || (item.notes ?? "") != task.description {
                    _ = try? await taskService.updateTask(
                        taskId: task.id, title: item.title,
                        description: item.notes ?? "", source: .github)
                }
                // Assignee: GitHub assignees resolve server-side to an Astrid
                // user (via each user's connected login). Empty = unassigned.
                if let mapped = item.metadata?["assigneeUserId"] {
                    let newAssignee = mapped.isEmpty ? "" : mapped
                    if (task.assigneeId ?? "") != newAssignee {
                        _ = try? await taskService.updateTask(
                            taskId: task.id, assigneeId: newAssignee, source: .github)
                    }
                }
                try? await apiClient.upsertGitHubTaskLink(ExternalTaskLinkUpsertRequest(
                    astridTaskId: existing.astridTaskId, remoteId: item.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: SyncSuppression.pullWatermark(taskUpdatedAt: task.updatedAt),
                    remoteUpdatedAt: item.remoteUpdatedAt,
                    metadata: item.metadata))
            } else {
                // Never re-import a remote twin we closed for a local deletion.
                if deletionLedger.tombstonedRemoteIds.contains(item.remoteId) { continue }
                // Never IMPORT an already-closed issue as a new task — linking
                // a mature repo would flood Astrid with its closed history
                // (state still syncs for linked pairs).
                if item.completed { continue }
                // New issue → adopt an existing UNLINKED same-title task in the
                // list if one exists (self-heals passes that created the task
                // but couldn't persist the link), else create one.
                let adopted = taskService.tasks.first {
                    ($0.listIds ?? []).contains(link.astridListId)
                        && !$0.id.hasPrefix("temp_") && byTaskId[$0.id] == nil
                        && $0.title == item.title
                }
                // Sub-issue → Astrid subtask: resolve the parent issue's task
                // via the link map (parents ordered first, so same-pass parents
                // are already there).
                var parentTaskId: String?
                if let parentNumber = item.metadata?["parent"], !parentNumber.isEmpty {
                    parentTaskId = byRemoteId["\(link.remoteContainerId)#\(parentNumber)"]?.astridTaskId
                }
                let newTask: Task
                if let adopted {
                    newTask = adopted
                } else {
                    let mappedAssignee = (item.metadata?["assigneeUserId"]).flatMap { $0.isEmpty ? nil : $0 }
                    newTask = try await taskService.createTask(
                        listIds: [link.astridListId], title: item.title,
                        description: item.notes,
                        assigneeId: mappedAssignee,
                        parentTaskId: parentTaskId, source: .github)
                }
                // The link row has an FK to the real Task id — resolve the
                // optimistic temp id before writing it, or the upsert silently
                // fails and the next pass duplicates the task.
                guard let realId = await resolveRealSyncTaskId(newTask.id) else { continue }
                let newLink = ExternalTaskLinkUpsertRequest(
                    astridTaskId: realId, remoteId: item.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: newTask.updatedAt, remoteUpdatedAt: item.remoteUpdatedAt,
                    metadata: item.metadata)
                try? await apiClient.upsertGitHubTaskLink(newLink)
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

        // ── PUSH: local tasks in the linked list not yet mirrored, or edited
        //          since the last push ─────────────────────────────────────
        // Parents before children so a subtask's parentRemoteId resolves
        // within one pass (sub-issues sync as real GitHub sub-issues).
        let listTasks = taskService.tasks
            .filter {
                ($0.listIds ?? []).contains(link.astridListId)
                    && !$0.id.hasPrefix("temp_")     // wait for the Outbox to sync the create
            }
            .sorted { ($0.parentTaskId == nil ? 0 : 1) < ($1.parentTaskId == nil ? 0 : 1) }
        var fullRemoteItems: [GitHubIssueItemDTO]?  // lazy, one cursor-free fetch per pass
        var fullListingTruncated = true             // trust only an explicit server flag
        var pushErrors = 0
        // Remote ids pushed this pass — drift repair must skip their stale snapshot.
        var pushedRemoteIds: Set<String> = []
        for task in listTasks {
          do {
            if let existing = byTaskId[task.id] {
                // Cross-container guard: this link may belong to another repo
                // (task shared across / moved between linked lists). Pushing it
                // here would PATCH the wrong repo's issue #. Its own repo's pass
                // handles it.
                guard SyncContainerGuard.mayPush(
                    linkContainerId: existing.remoteContainerId,
                    passContainerId: link.remoteContainerId) else { continue }
                // Push only if the local task changed since our last recorded push.
                guard SyncSuppression.shouldPushLocal(
                    localUpdatedAt: task.updatedAt, watermark: existing.astridUpdatedAt) else { continue }
                // Content no-op guard: a PATCH that changes nothing still bumps
                // the issue's updated_at, which echoes back as a webhook nudge.
                // Advance the watermark instead so this task stops qualifying.
                if let remote = pulledByRemoteId[existing.remoteId],
                   remote.title == task.title,
                   (remote.notes ?? "") == task.description,
                   remote.completed == task.completed,
                   (remote.metadata?["assigneeUserId"] ?? "") == (task.assigneeId ?? "") {
                    try? await apiClient.upsertGitHubTaskLink(ExternalTaskLinkUpsertRequest(
                        astridTaskId: task.id, remoteId: existing.remoteId,
                        remoteContainerId: link.remoteContainerId,
                        astridUpdatedAt: task.updatedAt, remoteUpdatedAt: existing.remoteUpdatedAt.map { iso.string(from: $0) },
                        metadata: nil))
                    continue
                }
                let response = try await apiClient.pushGitHubIssue(GitHubIssuePushRequest(
                    linkId: link.id, title: task.title,
                    body: task.description.isEmpty ? nil : task.description,
                    state: task.completed ? "closed" : "open",
                    remoteId: existing.remoteId,
                    assigneeUserId: task.assigneeId ?? ""))
                try? await apiClient.upsertGitHubTaskLink(ExternalTaskLinkUpsertRequest(
                    astridTaskId: task.id, remoteId: existing.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: task.updatedAt, remoteUpdatedAt: response.remoteUpdatedAt,
                    metadata: nil))
                pushedRemoteIds.insert(existing.remoteId)
                let refreshed = ExternalTaskLinkDTO(
                    astridTaskId: task.id, remoteId: existing.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: task.updatedAt,
                    remoteUpdatedAt: RFC3339.parse(response.remoteUpdatedAt), metadata: nil)
                byTaskId[task.id] = refreshed
                byRemoteId[existing.remoteId] = refreshed
            } else {
                // Push-side adopt guard: before CREATING a remote issue for an
                // unlinked task, scan the FULL remote list (cursor-free, fetched
                // once per pass) for an unlinked same-title issue and link to it
                // instead. Without this, a task whose link row was lost gets
                // re-pushed as a duplicate issue.
                if fullRemoteItems == nil {
                    if let fullPull = try? await apiClient.pullGitHubIssues(linkId: link.id, full: true) {
                        fullRemoteItems = fullPull.items
                        fullListingTruncated = fullPull.truncated ?? true
                    } else {
                        fullRemoteItems = []
                    }
                }
                if let candidate = fullRemoteItems?.first(where: {
                    byRemoteId[$0.remoteId] == nil && $0.title == task.title
                }) {
                    try? await apiClient.upsertGitHubTaskLink(ExternalTaskLinkUpsertRequest(
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
                let response = try await apiClient.pushGitHubIssue(GitHubIssuePushRequest(
                    linkId: link.id, title: task.title,
                    body: task.description.isEmpty ? nil : task.description,
                    state: nil, remoteId: nil,
                    parentRemoteId: task.parentTaskId.flatMap { byTaskId[$0]?.remoteId },
                    assigneeUserId: task.assigneeId))
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
          } catch {
            // One task's push failing (e.g. its issue was deleted remotely)
            // must not abort the rest of the pass.
            pushErrors += 1
            print("⚠️ [GitHubSync] push failed for \(task.id): \(error)")
          }
        }
        if pushErrors > 0 {
            lastError = "\(link.remoteContainerId): \(pushErrors) task(s) failed to push"
        }

        // ── DRIFT REPAIR: linked pairs whose state disagrees, where the local
        // task hasn't changed since our last sync point, adopt remote truth.
        if let fullItems = fullRemoteItems {
            for item in fullItems {
                guard !pushedRemoteIds.contains(item.remoteId) else { continue }
                guard let existing = byRemoteId[item.remoteId],
                      let task = taskService.tasks.first(where: { $0.id == existing.astridTaskId })
                else { continue }
                let localUnchanged = !SyncSuppression.shouldPushLocal(
                    localUpdatedAt: task.updatedAt, watermark: existing.astridUpdatedAt)
                guard CompletionDriftPolicy.shouldAdoptRemote(
                    remoteCompleted: item.completed, localCompleted: task.completed,
                    localCompletedAt: task.completedAt, localUnchanged: localUnchanged,
                    isRepeating: (task.repeating ?? .never) != .never)
                else { continue }
                _ = try? await taskService.completeTask(
                    id: task.id, completed: item.completed, task: task, source: .github,
                    completedAt: RFC3339.parse(item.completedAt))
            }
        }

        // ── DELETIONS: issue gone remotely → delete the local twin ─────────
        // Requires a COMPLETE listing (cursor-free); skipped when the fetch
        // failed or hit the page limit (SyncDeletionPolicy invariant).
        if fullRemoteItems == nil {
            if let fullPull = try? await apiClient.pullGitHubIssues(linkId: link.id, full: true) {
                fullRemoteItems = fullPull.items
                fullListingTruncated = fullPull.truncated ?? true  // old server = can't trust completeness
            }
        }
        if let fullItems = fullRemoteItems {
            let deletionLinks = taskLinks
                .filter { $0.remoteContainerId == link.remoteContainerId }
                .map { SyncDeletionPolicy.Link(taskId: $0.astridTaskId, remoteId: $0.remoteId) }
            let toDelete = SyncDeletionPolicy.localDeletions(
                links: deletionLinks,
                fullRemoteIds: Set(fullItems.map(\.remoteId)),
                truncated: fullListingTruncated,
                explicitlyDeletedRemoteIds: [])
            for del in toDelete where taskService.tasks.contains(where: { $0.id == del.taskId }) {
                deletionLedger.recordTombstone(del.remoteId)  // no echo back
                try? await taskService.deleteTask(id: del.taskId)
            }
        }

        // ── COMPLETED BACKFILL (lowest priority): import closed-issue history
        // gradually — searchable/reviewable, never delaying live items.
        if let fullItems = fullRemoteItems {
            let batch = CompletedBackfill.select(
                fullItems.map { .init(
                    remoteId: $0.remoteId, completed: $0.completed,
                    deleted: false,
                    updatedAt: $0.remoteUpdatedAt) },
                linkedRemoteIds: Set(byRemoteId.keys),
                tombstoned: deletionLedger.tombstonedRemoteIds,
                budget: 20)
            let byId = Dictionary(fullItems.map { ($0.remoteId, $0) }, uniquingKeysWith: { a, _ in a })
            for candidate in batch {
                guard let item = byId[candidate.remoteId] else { continue }
                let mappedAssignee = (item.metadata?["assigneeUserId"]).flatMap { $0.isEmpty ? nil : $0 }
                let backdated = RFC3339.parse(item.completedAt) ?? RFC3339.parse(item.remoteUpdatedAt) ?? Date()
                guard let newTask = try? await taskService.createTask(
                    listIds: [link.astridListId], title: item.title,
                    description: item.notes,
                    assigneeId: mappedAssignee,
                    source: .github, presumeCompletedAt: backdated) else { continue }
                _ = try? await taskService.completeTask(
                    id: newTask.id, completed: true, task: newTask, source: .github,
                    completedAt: backdated)
                guard let realId = await resolveRealSyncTaskId(newTask.id) else { continue }
                try? await apiClient.upsertGitHubTaskLink(ExternalTaskLinkUpsertRequest(
                    astridTaskId: realId, remoteId: item.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: Date(), remoteUpdatedAt: item.remoteUpdatedAt,
                    metadata: item.metadata))
                byRemoteId[item.remoteId] = ExternalTaskLinkDTO(
                    astridTaskId: realId, remoteId: item.remoteId,
                    remoteContainerId: link.remoteContainerId,
                    astridUpdatedAt: Date(),
                    remoteUpdatedAt: RFC3339.parse(item.remoteUpdatedAt), metadata: item.metadata)
            }
        }

        // ── COMMENTS: two-way per linked task ──────────────────────────────
        // Original taskLinks carry the persisted commentMap (fresh pull upserts
        // send issue metadata; the server merges, but local DTO copies don't).
        let commentMaps = Dictionary(
            (try? await apiClient.getGitHubTaskLinks(listId: link.astridListId).links.map {
                ($0.remoteId, CommentSyncPlanner.decodeEntries($0.metadata?["commentMap"]))
            }) ?? [], uniquingKeysWith: { a, _ in a })
        for (remoteId, dto) in byRemoteId {
            let entries = commentMaps[remoteId] ?? []
            let mappedLocalIds = Set(entries.map(\.localId))
            let remoteCommentCount = Int(pulledByRemoteId[remoteId]?.metadata?["commentCount"] ?? "") ?? 0
            let localComments = CommentService.shared.cachedComments[dto.astridTaskId] ?? []
            let hasUnmappedLocal = localComments.contains {
                $0.authorId != nil && !$0.id.hasPrefix("temp_") && !mappedLocalIds.contains($0.id)
            }
            // Sync when: new remote comments, unmapped local comments, a local
            // deletion of a mapped comment (cache present = authoritative view),
            // or the issue changed at all (a comment EDIT bumps the issue too).
            let issueChanged = pulledByRemoteId[remoteId] != nil
            let cachePresent = CommentService.shared.cachedComments[dto.astridTaskId] != nil
            let mappedLocalMissing = cachePresent && entries.contains { entry in
                !localComments.contains(where: { $0.id == entry.localId })
            }
            guard remoteCommentCount > entries.count || hasUnmappedLocal || mappedLocalMissing
                || (issueChanged && !entries.isEmpty) else { continue }
            await syncComments(taskId: dto.astridTaskId, remoteId: remoteId, link: link, entries: entries)
        }
    }

    /// Two-way comment sync for one linked task. Planning is pure
    /// (CommentSyncPlanner, red-green tested); the mapping persists in the task
    /// link's metadata (server merges, so other keys survive).
    private func syncComments(
        taskId: String, remoteId: String,
        link: ExternalListLinkDTO, entries initial: [CommentSyncPlanner.MapEntry]
    ) async {
        var entries = initial
        do {
            let remoteDTOs = try await apiClient.getGitHubIssueComments(linkId: link.id, remoteId: remoteId).comments
            // A FAILED local fetch must abort — coercing it to [] made deletePlan
            // treat every mapped local comment as gone and delete ALL
            // Astrid-authored mirrors on the issue (transient-failure mass
            // delete). Throw so the do/catch below skips this task's pass.
            let localModels = try await CommentService.shared.fetchComments(taskId: taskId, useCache: false)
            let remote = remoteDTOs.map { CommentSyncPlanner.RemoteComment(id: $0.id, body: $0.body, author: $0.author) }
            let local = localModels.map { CommentSyncPlanner.LocalComment(
                id: $0.id, content: $0.content, isSystem: $0.authorId == nil,
                attachmentNames: ($0.secureFiles ?? []).map { file in file.name }) }
            // Deletes first: the canonical side's absence removes the mirror,
            // and dead entries drop before create/edit planning.
            let deletePlan = CommentSyncPlanner.deletePlan(
                remoteIds: Set(remote.map(\.id)),
                localIds: Set(local.map(\.id)),
                entries: entries)
            for localId in deletePlan.deleteLocalIds {
                try? await CommentService.shared.deleteComment(id: localId)
            }
            for ghId in deletePlan.deleteRemoteIds {
                try? await apiClient.deleteGitHubIssueComment(linkId: link.id, commentId: ghId)
            }
            entries = deletePlan.survivingEntries

            // The snapshots predate the deletions just executed — filter them,
            // or the create planner resurrects what was just deleted (a locally
            // deleted comment re-pulls; a remotely deleted one re-pushes).
            let deletedRemote = Set(deletePlan.deleteRemoteIds)
            let deletedLocal = Set(deletePlan.deleteLocalIds)
            let liveRemote = remote.filter { !deletedRemote.contains($0.id) }
            let liveLocal = local.filter { !deletedLocal.contains($0.id) }

            let mapping = Dictionary(entries.map { ($0.remoteId, $0.localId) }, uniquingKeysWith: { a, _ in a })
            let plan = CommentSyncPlanner.plan(remote: liveRemote, local: liveLocal, mapping: mapping)

            // GitHub → Astrid creates (attributed; resolve the Outbox temp id so
            // the mapping survives — a temp id would push back later).
            for remoteComment in plan.pullCreates {
                let created = try await CommentService.shared.createComment(
                    taskId: taskId,
                    content: CommentSyncPlanner.pulledContent(author: remoteComment.author, body: remoteComment.body),
                    type: .MARKDOWN,
                    authorId: AuthManager.shared.userId)
                await OutboxManager.shared.drain()
                let realId = CommentService.shared.mappedRealCommentId(for: created.id) ?? created.id
                guard !realId.hasPrefix("temp_") else { continue }
                entries.append(.init(remoteId: remoteComment.id, localId: realId, pushed: false))
            }

            // Astrid → GitHub creates
            for localComment in plan.pushCreates {
                let ghId = try await apiClient.createGitHubIssueComment(
                    linkId: link.id, remoteId: remoteId,
                    body: CommentSyncPlanner.pushBody(
                        content: localComment.content,
                        attachmentNames: localComment.attachmentNames))
                entries.append(.init(remoteId: ghId, localId: localComment.id, pushed: true))
            }

            // Edits on mapped pairs: converge the non-canonical side.
            let edits = CommentSyncPlanner.editPlan(remote: liveRemote, local: liveLocal, entries: entries)
            for update in edits.pullUpdates {
                _ = try? await CommentService.shared.updateComment(id: update.localId, content: update.content)
            }
            for update in edits.pushUpdates {
                try await apiClient.updateGitHubIssueComment(
                    linkId: link.id, commentId: update.remoteId, body: update.body)
            }
        } catch {
            lastError = "Comment sync failed: \(error.localizedDescription)"
        }

        if entries != initial {
            try? await apiClient.upsertGitHubTaskLink(ExternalTaskLinkUpsertRequest(
                astridTaskId: taskId, remoteId: remoteId,
                remoteContainerId: link.remoteContainerId,
                astridUpdatedAt: nil, remoteUpdatedAt: nil,
                metadata: ["commentMap": CommentSyncPlanner.encodeEntries(entries)]))
        }
    }
}

extension Notification.Name {
    /// Server nudge (GitHub webhook → SSE): external data changed, pull soon.
    static let externalSyncRefresh = Notification.Name("externalSyncRefresh")
}
