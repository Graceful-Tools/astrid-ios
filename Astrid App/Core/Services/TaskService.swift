import AstridCore
import Foundation
import Combine

/// The tasks the views draw, and every way to change one — through astrid-core.
///
/// astrid-core (the shared Rust core the Windows app runs on) is the cache, the write journal
/// (Outbox), the sync pass and the live stream; see docs/CORE_MIGRATION.md. This service is the
/// face the views bind to: it publishes the core's tasks as `[Task]` in the API wire shape the
/// views have always read, turns each call into a core command, and reads back what the core says
/// moved. It decides nothing the core decides — not what a completion does, not how a pull merges
/// with an unsent edit, not when a write goes out.
///
/// Every write is local-first, exactly as before: the core updates its cache and journals the
/// write before answering, so the row changes at once and the server hears about it when it can.
@MainActor
class TaskService: ObservableObject {
    static let shared = TaskService()

    @Published var tasks: [Task] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Writes waiting to reach the server.
    @Published var pendingOperationsCount: Int = 0
    /// Writes the server refused for good (dead-lettered).
    @Published var failedOperationsCount: Int = 0
    @Published var isSyncingPendingOperations = false
    @Published var hasCompletedInitialLoad = false

    private let notificationManager = NotificationManager.shared
    private let badgeManager = BadgeManager.shared
    private var cachedTasks: [String: Task] = [:]
    /// O(1) id → task lookup (mirrors `tasks`). Lets callers avoid an O(n)
    /// `tasks.first(where:)` scan per lookup (e.g. subtask-depth walking).
    var tasksById: [String: Task] { cachedTasks }

    /// Temp ids the views may still hold, and the real ids they became. Learned from the core,
    /// which keeps the authoritative mapping; kept here so a lookup is synchronous.
    private var tempTaskIdMapping: [String: String] = [:]

    private var core: CoreSession { AppCore.shared.session }

    /// Avoids `NSError.description` expansion in logs.
    static func safeErrorSummary(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
    }

    private init() {
        // The tasks must be in memory before the first frame — offline, this is all there is to
        // show — so this one read waits on the calling thread. It is a cache read: no network.
        do {
            let loaded = try core.runBlocking(CoreCommand.tasks(), as: [Task].self)
            publish(loaded)
        } catch {
            AppLog.debug("❌ [TaskService] Failed to read cached tasks: \(Self.safeErrorSummary(error))")
        }
        hasCompletedInitialLoad = true
        refreshOutboxCounts()
    }

    // MARK: - Temp ids

    /// Real server id for a temporary (offline-created) task id, once it has synced; nil while it
    /// is still only local.
    func mappedRealTaskId(for tempId: String) -> String? {
        tempTaskIdMapping[tempId]
    }

    /// The id to act on: a temp id a view still holds, as the task it became.
    private func resolved(_ id: String) -> String {
        tempTaskIdMapping[id] ?? id
    }

    // MARK: - Reading back what the core says moved

    /// A change from the core: re-read what it names. The core already applied it to its cache —
    /// this only brings the published `[Task]` level with it.
    func coreDidChange(_ change: CoreChange) {
        switch change {
        case .task(let id):
            _Concurrency.Task { await self.reload(ids: [id]) }
        case .synced(let taskIds, _) where !taskIds.isEmpty:
            _Concurrency.Task { await self.reload(ids: taskIds) }
        case .synced, .unknown:
            _Concurrency.Task { await self.reloadAll() }
        case .needsSync:
            _Concurrency.Task { try? await self.core.run(CoreCommand(kind: "sync")) }
        default:
            break
        }
    }

    /// Re-read the named tasks. One that is no longer in the cache was deleted — here or elsewhere;
    /// a temporary id that became a real one reads as that task.
    private func reload(ids: [String]) async {
        let temps = ids.filter { $0.hasPrefix("temp_") }
        let moved = temps.isEmpty
            ? [:] : ((try? await core.run(CoreCommand.resolveIds(temps), as: [String: String].self)) ?? [:])
        let wanted = ids.map { moved[$0] ?? $0 }
        guard let found = try? await core.run(CoreCommand.tasks(ids: wanted), as: [Task].self) else { return }
        let foundIds = Set(found.map(\.id))

        // The echo of a write this service already showed: nothing to hydrate, sort or publish —
        // on a large account that is the whole task list, twice per write.
        let gone = wanted.filter { !foundIds.contains($0) && cachedTasks[$0] != nil }
        if moved.isEmpty, gone.isEmpty, found.allSatisfy({ cachedTasks[$0.id] == $0 }) {
            refreshOutboxCounts()
            return
        }

        var next = tasks
        for (temp, real) in moved {
            recordTempTaskMapping(tempId: temp, realId: real)
            next.removeAll { $0.id == temp }
        }
        next.removeAll { wanted.contains($0.id) && !foundIds.contains($0.id) }
        for task in found { upsert(task, into: &next) }
        publish(next)
        refreshOutboxCounts()
    }

    /// Read every cached task again: after a sync pass or a delivery that could not say what moved.
    ///
    /// A full read is slow on a large account, and a write shown while it was out is newer than
    /// what it read. When that happens it reads again, rather than publishing the older snapshot
    /// over the newer rows.
    func reloadAll() async {
        let temps = cachedTasks.keys.filter { $0.hasPrefix("temp_") }
        if !temps.isEmpty,
           let moved = try? await core.run(CoreCommand.resolveIds(Array(temps)), as: [String: String].self) {
            for (temp, real) in moved { recordTempTaskMapping(tempId: temp, realId: real) }
        }
        for _ in 0..<3 {
            let startedAt = publishCount
            guard let loaded = try? await core.run(CoreCommand.tasks(), as: [Task].self) else { return }
            if publishCount == startedAt {
                publish(loaded)
                break
            }
        }
        refreshOutboxCounts()
    }

    /// How many times `tasks` has been replaced — what `reloadAll` checks its read against.
    private var publishCount = 0

    /// Records that an offline-created task's temporary id became a real one, and tells the views
    /// that may hold it.
    func recordTempTaskMapping(tempId: String, realId: String) {
        guard tempId.hasPrefix("temp_"), tempId != realId, tempTaskIdMapping[tempId] != realId else { return }
        tempTaskIdMapping[tempId] = realId
        NotificationCenter.default.post(
            name: .taskTempIdResolved, object: nil, userInfo: ["tempId": tempId, "realId": realId])
    }

    private func upsert(_ task: Task, into list: inout [Task]) {
        if let index = list.firstIndex(where: { $0.id == task.id }) {
            list[index] = task
        } else {
            list.append(task)
        }
    }

    /// Publish a new set: joined with the lists they belong to, in the order every list draws
    /// from, and only when something actually changed — reassigning `@Published` re-renders every
    /// observer even for identical content.
    private func publish(_ next: [Task]) {
        let hydrated = TaskListHydration.hydrated(next, using: ListService.shared.lists)
        let sorted = hydrated.sorted(by: TaskOrdering.isOrderedBefore)
        guard sorted != tasks else { return }
        publishCount += 1
        tasks = sorted
        cachedTasks = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        _Concurrency.Task { await badgeManager.updateBadge(with: sorted) }
    }

    /// Join every task with its lists again — the lists changed under them.
    func rejoinLists() {
        publish(tasks)
    }

    /// Show a task the core just answered with, without waiting for its change to come round.
    private func show(_ task: Task) {
        var next = tasks
        upsert(task, into: &next)
        publish(next)
    }

    /// The Outbox's counts, for the "not synced yet" and "failed" indicators.
    func refreshOutboxCounts() {
        struct Stats: Decodable { let pending: Int; let running: Int; let failed: Int }
        _Concurrency.Task {
            guard let stats = try? await core.run(CoreCommand(kind: "outboxStats"), as: Stats.self) else { return }
            pendingOperationsCount = stats.pending + stats.running
            failedOperationsCount = stats.failed
        }
    }

    // MARK: - Task Operations

    func fetchTask(id: String, forceRefresh: Bool = false) async throws -> Task {
        if !forceRefresh, let cached = cachedTasks[resolved(id)] {
            return cached
        }
        if forceRefresh {
            try? await core.run(CoreCommand(kind: "sync"))
        }
        guard let task = try await core.run(CoreCommand.tasks(ids: [id]), as: [Task].self).first else {
            throw NSError(domain: "TaskService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task not found"])
        }
        show(task)
        return task
    }

    func createTask(
        listIds: [String],
        title: String,
        description: String? = nil,
        priority: Int? = nil,
        whenDate: Date? = nil,     // The date (all-day)
        whenTime: Date? = nil,     // The time (a timed task; nil for all-day)
        assigneeId: String? = nil,
        isPrivate: Bool? = nil,
        repeating: String? = nil,
        repeatingData: CustomRepeatingPattern? = nil,
        parentTaskId: String? = nil,
        statusRole: String? = nil,  // Board state when creating in a board column (task a2c58f53)
        source: SyncSource? = nil,  // Origin tag for provider echo suppression
        presumeCompletedAt: Date? = nil  // Sync history imports: born completed and backdated
    ) async throws -> Task {
        // A time makes it a timed task; a date alone, all-day; neither, no due date.
        let dueDateTime: String?
        let isAllDay: Bool
        if let whenTime {
            dueDateTime = WireDate.dueDateString(from: whenTime)
            isAllDay = false
        } else if let whenDate {
            dueDateTime = WireDate.dueDateString(from: Self.utcStartOfDay(whenDate))
            isAllDay = true
        } else {
            dueDateTime = nil
            isAllDay = false
        }

        var created = try await core.run(
            CoreCommand.createTask(
                title: title, description: description, listIds: listIds, priority: priority,
                dueDateTime: dueDateTime, isAllDay: isAllDay, assigneeId: assigneeId,
                parentTaskId: parentTaskId, statusRole: statusRole, repeating: repeating,
                repeatingData: repeatingData, isPrivate: isPrivate),
            as: Task.self)
        show(created)
        LocalMutation.note(source: source)

        // A history import is born completed and backdated, so the row never flashes open.
        if let presumeCompletedAt {
            created = try await completeTask(
                id: created.id, completed: true, source: source, completedAt: presumeCompletedAt)
        }
        refreshOutboxCounts()
        return created
    }

    func updateTask(
        taskId: String,
        title: String? = nil,
        description: String? = nil,
        priority: Int? = nil,
        when: Date? = nil,  // DEPRECATED: Use dueDateTime instead
        whenTime: Date? = nil,  // DEPRECATED: Use isAllDay instead
        dueDateTime: Date? = nil,  // The due date/time; `Date.distantPast` clears it
        isAllDay: Bool? = nil,  // All-day task flag
        assigneeId: String? = nil,  // "" unassigns
        repeating: String? = nil,
        repeatingData: CustomRepeatingPattern? = nil,
        repeatFrom: String? = nil,
        timerDuration: Int? = nil,
        lastTimerValue: String? = nil,
        listIds: [String]? = nil,
        task: Task? = nil,  // Kept for callers that pass what they see; the core has the task
        source: SyncSource? = nil,
        parentTaskId: String? = nil,  // Reparent (drag-to-indent → subtask); "" promotes, nil = no change
        // Board status as a state on the task (AWTD-566). Empty string CLEARS it, which is
        // how a card reaches Inbox or Done; nil leaves it untouched.
        statusRole: String? = nil
    ) async throws -> Task {
        var changes = TaskEdit()
        changes.set("title", title)
        changes.set("description", description)
        changes.set("priority", priority)

        // The due date: a new `dueDateTime`, or the legacy `when` / `whenTime` pair. An all-day
        // date is UTC midnight, as every all-day date is stored.
        if let dueDateTime {
            if dueDateTime == Date.distantPast {
                changes.clear("dueDateTime")
            } else {
                let normalized = isAllDay == true ? Self.utcStartOfDay(dueDateTime) : dueDateTime
                changes.set("dueDateTime", WireDate.dueDateString(from: normalized))
            }
            changes.set("isAllDay", isAllDay)
        } else if let when, when == Date.distantPast, let whenTime, whenTime == Date.distantPast {
            changes.clear("dueDateTime")
        } else if let when, when != Date.distantPast {
            if let whenTime, whenTime != Date.distantPast {
                changes.set("dueDateTime", WireDate.dueDateString(from: whenTime))
                changes.set("isAllDay", false)
            } else {
                changes.set("dueDateTime", WireDate.dueDateString(from: Self.utcStartOfDay(when)))
                changes.set("isAllDay", true)
            }
        } else if let whenTime, whenTime != Date.distantPast {
            changes.set("dueDateTime", WireDate.dueDateString(from: whenTime))
            changes.set("isAllDay", false)
        } else if let isAllDay {
            // An isAllDay-only edit still reaches the wire.
            changes.set("isAllDay", isAllDay)
        }

        if let assigneeId {
            assigneeId.isEmpty ? changes.clear("assigneeId") : changes.set("assigneeId", assigneeId)
        }
        changes.set("repeating", repeating)
        changes.set("repeatingData", repeatingData)
        changes.set("repeatFrom", repeatFrom)
        changes.set("timerDuration", timerDuration)
        changes.set("lastTimerValue", lastTimerValue)
        changes.set("listIds", listIds)
        if let parentTaskId {
            parentTaskId.isEmpty ? changes.clear("parentTaskId") : changes.set("parentTaskId", parentTaskId)
        }
        if let statusRole {
            statusRole.isEmpty ? changes.clear("statusRole") : changes.set("statusRole", statusRole)
        }
        return try await apply(changes, to: taskId, source: source)
    }

    /// One edit, through the core: its cache and journal first, the server when it can.
    private func apply(_ changes: TaskEdit, to taskId: String, source: SyncSource? = nil) async throws -> Task {
        let updated = try await core.run(
            CoreCommand.updateTask(taskId: resolved(taskId), changes: changes), as: Task.self)
        show(updated)
        LocalMutation.note(source: source)
        refreshOutboxCounts()
        return updated
    }

    /// Apply a priority change to what the views read — RIGHT NOW, with nothing awaited.
    ///
    /// The core answers a write in microseconds, but it still answers after an `await`; a view that
    /// shows a tap before starting the durable write calls this first. It does NOT replace
    /// `updateTask` — the caller still makes that call.
    ///
    /// Returns false only when the task is unknown.
    @discardableResult
    func applyOptimisticPriority(taskId: String, priority: Task.Priority) -> Bool {
        let resolvedId = resolved(taskId)
        guard var task = cachedTasks[resolvedId] else { return false }
        task.priority = priority
        task.updatedAt = Date()
        cachedTasks[resolvedId] = task
        if let index = tasks.firstIndex(where: { $0.id == resolvedId }) {
            tasks[index] = task
        }
        return true
    }

    /// Put a task into what the views read without touching the core. Tests only.
    func adoptForTesting(_ task: Task) {
        var next = tasks
        upsert(task, into: &next)
        tasks = next
        cachedTasks[task.id] = task
    }

    /// An edit given as a whole request — the reminder and privacy edits the detail view makes.
    /// Through the core like every other edit: cache and journal first, server when it can.
    func updateTaskOnServer(taskId: String, updates: UpdateTaskRequest) async throws -> Task {
        try await apply(TaskEdit(request: updates), to: taskId)
    }

    /// A public or featured list's tasks, as the server has them right now — for browsing a list
    /// that is not the reader's, which the cache does not hold.
    func fetchTasksForListFromServer(_ listId: String) async throws -> [Task] {
        try await AstridAPIClient.shared.getAllTasks(listId: listId)
    }

    /// Complete (or un-complete) a task — the only correct way to do either.
    ///
    /// What completing does is astrid-core's rule (`repeating::completion`): a repeating task rolls
    /// forward to its next occurrence and stays open; a series at its end stays completed with its
    /// repeat cleared. `task` is the task as the person sees it — pass it from any view that let
    /// them edit the due date or repeat first, because the rollover anchors on those fields.
    func completeTask(
        id: String, completed: Bool, task: Task? = nil, timerDuration: Int? = nil,
        lastTimerValue: String? = nil, source: SyncSource? = nil, completedAt: Date? = nil
    ) async throws -> Task {
        let taskId = resolved(id)
        guard task != nil || cachedTasks[taskId] != nil || !taskId.isEmpty else {
            throw NSError(domain: "TaskService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task not found"])
        }
        let done = try await core.run(
            CoreCommand.completeTask(
                taskId: taskId, completed: completed, task: task, timerDuration: timerDuration,
                lastTimerValue: lastTimerValue,
                // Through WireDate so the milliseconds survive (AITD-369); the core keeps them.
                completedAt: completedAt.map { WireDate.string(from: $0) },
                source: source?.rawValue),
            as: Task.self)
        show(done)
        LocalMutation.note(source: source)
        refreshOutboxCounts()
        return done
    }

    /// Where a repeating task goes next if it were completed now — the same answer
    /// `completeTask` acts on, from astrid-core. Holds no pattern math.
    ///
    /// Marked `internal` so tests can lock down the completion path.
    func calculateNextOccurrence(for task: Task) -> (nextDate: Date?, shouldTerminate: Bool) {
        var open = task
        open.completed = false
        switch (try? CoreRules.completion(of: open, completed: true, at: Date())) ?? .toggle(completed: true, clearClosedReason: false) {
        case .rollForward(let next, _, _): return (next, false)
        case .seriesEnded: return (nil, true)
        case .toggle: return (nil, false)
        }
    }

    func updateTaskLists(taskId: String, listIds: [String]) async throws -> Task {
        try await updateTask(taskId: taskId, listIds: listIds)
    }

    func deleteTask(id: String, task: Task? = nil) async throws {
        let resolvedId = resolved(id)

        // Any open detail view for this task must close (deletes can also arrive from external
        // sync, not just the view's own delete button).
        NotificationCenter.default.post(
            name: .astridTaskDeleted, object: nil,
            userInfo: ["taskId": id, "resolvedTaskId": resolvedId])
        // Providers that mirror tasks elsewhere note the twin before the task goes: the server
        // cascades its link rows away with it. Google included — its pass is still the Swift one
        // (docs/CORE_MIGRATION.md), which reads its own ledger, not the core's.
        await GoogleTasksSyncService.shared.noteTaskDeleted(taskId: resolvedId)
        await GitHubSyncService.shared.noteTaskDeleted(taskId: resolvedId)
        await AppleRemindersService.shared.noteTaskDeleted(taskId: resolvedId)

        try await core.run(CoreCommand(kind: "deleteTask", taskId: resolvedId))
        var next = tasks
        next.removeAll { $0.id == resolvedId }
        publish(next)
        LocalMutation.note()

        await notificationManager.cancelNotification(for: resolvedId)
        refreshOutboxCounts()
    }

    func copyTask(
        id: String,
        targetListId: String?,
        includeComments: Bool = false,
        preserveDueDate: Bool = false,
        preserveAssignee: Bool = false
    ) async throws -> Task {
        let originalTask = try await fetchTask(id: id)

        // "My Tasks (only)" is no list at all; otherwise the chosen list.
        let listIds: [String] = (targetListId?.isEmpty == false) ? [targetListId!] : []

        // Copied to a list it arrives unassigned; to My Tasks (only) it is the copier's, so it
        // shows up there.
        let copyAssigneeId: String? = listIds.isEmpty ? AuthManager.shared.userId : nil

        let copiedTask = try await createTask(
            listIds: listIds,
            title: originalTask.title,
            description: originalTask.description,
            priority: originalTask.priority.rawValue,
            whenDate: preserveDueDate ? (originalTask.isAllDay ? originalTask.dueDateTime : nil) : nil,
            whenTime: preserveDueDate ? (!originalTask.isAllDay ? originalTask.dueDateTime : nil) : nil,
            assigneeId: copyAssigneeId,
            isPrivate: originalTask.isPrivate,
            repeating: originalTask.repeating?.rawValue
        )

        if includeComments {
            do {
                let comments = try await CommentService.shared.fetchComments(taskId: id)
                // System comments (no author) stay with the original.
                for comment in comments where comment.authorId != nil {
                    _ = try? await CommentService.shared.createComment(
                        taskId: copiedTask.id, content: comment.content, type: comment.type,
                        authorId: comment.authorId)
                }
            } catch {
                AppLog.debug("⚠️ [TaskService] Failed to fetch comments for copying: \(Self.safeErrorSummary(error))")
            }
        }
        return copiedTask
    }

    // MARK: - Filtering

    func getTasksForList(_ listId: String) -> [Task] {
        tasks.filter { task in
            task.listIds?.contains(listId) == true || task.lists?.contains(where: { $0.id == listId }) == true
        }
    }

    // MARK: - Delivery

    /// Send what is waiting now rather than at the delivery loop's next turn — pull to refresh,
    /// the network coming back.
    func syncPendingOperations() async throws {
        guard !isSyncingPendingOperations else { return }
        isSyncingPendingOperations = true
        defer { isSyncingPendingOperations = false }
        try await core.run(CoreCommand(kind: "drain"))
        refreshOutboxCounts()
    }

    /// Give writes the server refused another go. The core dead-letters only what the server
    /// refused for good, so this sends them again rather than resetting a counter.
    func retryFailedOperations() async {
        try? await syncPendingOperations()
    }

    // MARK: - Cache

    /// Clear what the views read (sign-out; the core wipes its own cache there too).
    func clearCache() {
        tasks = []
        cachedTasks = [:]
        tempTaskIdMapping = [:]
        pendingOperationsCount = 0
        failedOperationsCount = 0
    }

    /// All-day dates are UTC midnight of the chosen day.
    private static func utcStartOfDay(_ date: Date) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.startOfDay(for: date)
    }
}

extension Notification.Name {
    /// Posted by TaskService.deleteTask so open detail views can close.
    static let astridTaskDeleted = Notification.Name("astridTaskDeleted")
}
