import AstridCore
import Foundation
import Combine

/// The lists the views draw, and every way to change one — through astrid-core.
///
/// Like `TaskService`, this is the face the views bind to over the shared core (the cache, the
/// write journal, sync, the live stream; docs/CORE_MIGRATION.md). Every write is local-first and
/// journaled — list edits included, which the Swift layer only ever half-queued (AITD-410).
@MainActor
class ListService: ObservableObject {
    static let shared = ListService()

    @Published var lists: [TaskList] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Lists created here that the server has not seen yet.
    @Published var pendingListsCount: Int = 0
    @Published var isSyncingPendingLists = false
    @Published var hasCompletedInitialLoad = false

    private var cachedLists: [String: TaskList] = [:]
    /// O(1) id → list lookup (mirrors TaskService.tasksById) — used by row chips etc.
    var listsById: [String: TaskList] { cachedLists }

    private var core: CoreSession { AppCore.shared.session }
    /// Set once the first read is in: before that, telling `TaskService` would build it while
    /// this service is still being built, and it reads this one.
    private var isReady = false

    private init() {
        // Lists must be in memory before the first frame — offline they are all there is — so
        // this one cache read waits on the calling thread.
        if let loaded = try? core.runBlocking(CoreCommand(kind: "lists"), as: [TaskList].self) {
            publish(loaded)
        }
        hasCompletedInitialLoad = true
        isReady = true
    }

    // MARK: - Reading back what the core says moved

    func coreDidChange(_ change: CoreChange) {
        switch change {
        case .list, .synced, .delivered, .unknown, .settings:
            _Concurrency.Task { await self.reload() }
        default:
            break
        }
    }

    /// Read every cached list again. Cheap — an account has tens of lists, not thousands.
    func reload() async {
        guard let loaded = try? await core.run(CoreCommand(kind: "lists"), as: [TaskList].self) else { return }
        publish(loaded)
    }

    /// Publish a new set in the one sidebar order, only when something changed.
    private func publish(_ next: [TaskList]) {
        let sorted = next.sorted(by: ListOrdering.isOrderedBefore)
        // `@Published` fires on every assignment, equal or not — and every list row observes this.
        let pending = sorted.filter { $0.id.hasPrefix("temp_") }.count
        if pending != pendingListsCount { pendingListsCount = pending }
        guard sorted != lists else { return }
        lists = sorted
        cachedLists = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        // A task's list chips are joined from these lists: a rename or a new colour has to reach
        // the rows too.
        if isReady { TaskService.shared.rejoinLists() }
    }

    /// Show a list another service's core command answered with — a board drop's reordered list.
    func adopt(_ list: TaskList) { show(list) }

    /// Show a list the core just answered with, without waiting for its change to come round.
    private func show(_ list: TaskList) {
        var next = lists
        if let index = next.firstIndex(where: { $0.id == list.id }) {
            next[index] = list
        } else {
            next.append(list)
        }
        publish(next)
    }

    private func forget(_ listId: String) {
        publish(lists.filter { $0.id != listId })
    }

    // MARK: - Reads

    /// Pull the lists from the server now (pull to refresh, a settings screen opening), then show
    /// what the cache holds. Never throws: offline, the cached lists are the answer.
    func fetchLists() async throws -> [TaskList] {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await core.run(CoreCommand(kind: "sync"))
        } catch {
            errorMessage = error.localizedDescription
        }
        await reload()
        return lists
    }

    // MARK: - Writes

    func createList(
        name: String,
        description: String? = nil,
        privacy: String = "PRIVATE",
        color: String? = nil
    ) async throws -> TaskList {
        var command = CoreCommand(kind: "createList", ["name": .value(name), "privacy": .value(privacy)])
        command.set("color", color ?? "#3b82f6")
        command.set("description", description)
        let list = try await core.run(command, as: TaskList.self)
        show(list)
        LocalMutation.note()
        return list
    }

    /// Apply an optimistic membership edit to the cached list so the change survives a view
    /// dismissal and every surface reading `ListService.lists` sees it at once (task 33fc21fc).
    /// `ListMemberOptimistic` owns what each edit means; this only decides where it is written.
    func applyMemberChange(listId: String, _ transform: (TaskList) -> TaskList) {
        guard let current = lists.first(where: { $0.id == listId }) ?? cachedLists[listId] else { return }
        show(transform(current))
    }

    /// Remove a member from the cached list so the change persists across view dismissals.
    func removeMemberFromCachedList(listId: String, userId: String) {
        applyMemberChange(listId: listId) {
            ListMemberOptimistic.applyingRemoval($0, userId: userId)
        }
    }

    /// Restore a list as it was (a membership edit the server refused).
    func restoreCachedList(listId: String, from original: TaskList) {
        show(original)
    }

    func updateList(listId: String, name: String? = nil, description: String? = nil) async throws -> TaskList {
        var changes = CoreFields()
        changes.set("name", name)
        changes.set("description", description)
        return try await apply(changes, to: listId)
    }

    /// Any list settings, as the settings screens build them: `NSNull` clears a field.
    func updateListAdvanced(listId: String, updates: [String: Any]) async throws -> TaskList {
        try await apply(Self.fields(from: updates), to: listId)
    }

    /// A list edit given as a whole request.
    @discardableResult
    func updateListOnServer(listId: String, updates: UpdateListRequest) async throws -> TaskList {
        try await apply((try? CoreFields(encoding: updates)) ?? CoreFields(), to: listId)
    }

    private func apply(_ changes: CoreFields, to listId: String) async throws -> TaskList {
        let list = try await core.run(
            CoreCommand(kind: "updateList", ["listId": .value(listId), "changes": .value(changes)]),
            as: TaskList.self)
        show(list)
        LocalMutation.note()
        return list
    }

    func deleteList(listId: String) async throws {
        // Capture a Google sync link BEFORE the delete (the server cascades it away) so the
        // all-lists auto-link does not immediately re-create the list.
        let googleLink = GoogleTasksSyncService.shared.links.first { $0.astridListId == listId }
        try await core.run(CoreCommand(kind: "deleteList", ["listId": .value(listId)]))
        forget(listId)
        LocalMutation.note()
        if let googleLink {
            await GoogleTasksSyncService.shared.noteMirroredListDeleted(tasklistId: googleLink.remoteContainerId)
            await GoogleTasksSyncService.shared.refreshStatus()
        }
    }

    func updateManualOrder(listId: String, order: [String]) async throws {
        // The core reconciles the order against what is off screen, as the server would, so the
        // row does not jump when the server's answer lands (CONTRACTS D17).
        let list = try await core.run(
            CoreCommand(kind: "setManualOrder", ["listId": .value(listId), "order": .value(order)]),
            as: TaskList.self)
        show(list)
        LocalMutation.note()
    }

    /// isFavorite is a field on the list, not a sub-resource: v1 has no /lists/{id}/favorite, and
    /// the core's `setListFavorite` is an ordinary list edit (AITD-349) — journaled, like the rest.
    func toggleFavorite(listId: String, isFavorite: Bool) async throws {
        let list = try await core.run(
            CoreCommand(kind: "setListFavorite", ["listId": .value(listId), "favorite": .value(isFavorite)]),
            as: TaskList.self)
        show(list)
    }

    /// Toggle, then hand back the updated list — the shape `ListRowView` wants.
    func favoriteList(listId: String, favorite: Bool) async throws -> TaskList {
        try await toggleFavorite(listId: listId, isFavorite: favorite)
        guard let list = getList(id: listId) else {
            throw NSError(domain: "ListService", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "List not found after favorite toggle"])
        }
        return list
    }

    /// Leave a shared list. Online only: the server decides who may, and a list left offline
    /// would reappear on the next pull.
    func leaveList(listId: String) async throws {
        try await core.run(CoreCommand(kind: "leaveList", ["listId": .value(listId)]))
        forget(listId)
    }

    /// Who this list may be handed to, as the state the leave control should show (AITD-392) —
    /// the core's reading of the probe.
    func ownershipTransferAvailability(listId: String) async -> ListOwnershipTransfer.Availability {
        (try? await core.run(
            CoreCommand(kind: "eligibleNewOwners", ["listId": .value(listId)]),
            as: ListOwnershipTransfer.Availability.self)) ?? .unavailable
    }

    /// Hand this list to someone else and stop being a member of it (AITD-392) — ONE server call:
    /// the transfer and the leave are a single transaction.
    func transferOwnership(listId: String, to newOwnerId: String) async throws {
        try await core.run(CoreCommand(
            kind: "transferListOwnership",
            ["listId": .value(listId), "newOwnerId": .value(newOwnerId)]))
        forget(listId)
    }

    /// Choose the AI agent that answers in this list's chat and comments, or nil for the account
    /// default (AITD-380). The body comes from `ListAgentSettings` because `aiAgentConfig` replaces
    /// the stored config wholesale — the list's enabled types have to be carried through.
    @discardableResult
    func setListDefaultAgent(listId: String, agentId: String?) async throws -> TaskList {
        guard let list = getList(id: listId) else {
            throw NSError(domain: "ListService", code: 404, userInfo: [NSLocalizedDescriptionKey: "List not found"])
        }
        return try await updateListOnServer(
            listId: listId, updates: ListAgentSettings.updateRequest(settingDefaultAgent: agentId, on: list))
    }

    // MARK: - Helpers

    func getList(id: String) -> TaskList? {
        cachedLists[id]
    }

    var favoriteLists: [TaskList] {
        lists.filter { $0.isFavorite == true }
            .sorted { ($0.favoriteOrder ?? Int.max) < ($1.favoriteOrder ?? Int.max) }
    }

    /// Clear what the views read (sign-out; the core wipes its own cache there too).
    func clearCache() {
        lists = []
        cachedLists = [:]
        pendingListsCount = 0
    }

    /// Send list writes waiting in the journal now rather than at the delivery loop's next turn.
    func syncPendingLists() async throws {
        guard !isSyncingPendingLists else { return }
        isSyncingPendingLists = true
        defer { isSyncingPendingLists = false }
        try await core.run(CoreCommand(kind: "drain"))
        await reload()
    }

    /// A settings dictionary as edit fields: `NSNull` clears, anything JSON can say is kept.
    static func fields(from updates: [String: Any]) -> CoreFields {
        var fields = CoreFields()
        for (key, value) in updates {
            if value is NSNull {
                fields.clear(key)
            } else if JSONSerialization.isValidJSONObject(["v": value]),
                      let data = try? JSONSerialization.data(withJSONObject: ["v": value]),
                      let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data),
                      let json = decoded["v"] {
                fields.set(key, json)
            }
        }
        return fields
    }
}
