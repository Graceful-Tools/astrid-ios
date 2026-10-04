//  ListRowsModel.swift
//  Astrid — a list's rows, for iOS and Mac alike, answered by astrid-core (AITD-460).
//
//  Both apps filtered, sorted and spliced their lists with Swift copies of iOS's rules
//  (`filterTasksForList`, `sortTasksByListSetting`, `spliceSubtasks`, `MyTasksScope`, the
//  completion window). The core's `rowsForList` now answers exactly as iOS's list did — the same
//  filters, the same sort with ties falling the same way, subtasks spliced from every cached task
//  by the view's completion filter alone (astrid-core CONTRACTS D40–D42) — so the copies are gone
//  and both apps ask the core, the way search does (`TaskSearchModel`, AITD-459).
//
//  The answer is asynchronous: a view keeps drawing while the core reads its cache. It is asked
//  again when the query changes (another list, an edited filter, a new sort) and whenever the
//  tasks change; between answers a list shows its last rows, never an empty screen.

import AstridCore
import Combine
import Foundation

@MainActor
final class ListRowsModel: ObservableObject {
    /// Which rows: everything the core reads to answer, plus the minute for the filters that read
    /// the clock ("today", the recently-completed window).
    struct Query: Equatable {
        /// A list id, `myTasksId`, or `everythingId`.
        var listId: String
        /// The list as the shell holds it — wins over the cache's, and is the only copy of a
        /// public list the reader is not a member of.
        var list: TaskList?
        /// The tasks to draw from when the cache does not hold them (that public list).
        var tasks: [Task]?
        /// My Tasks' filters as the shell holds them (ahead of the core by its 300 ms debounce).
        var myTasks: MyTasksPreferences?
        var subtaskDisplay: String?
        /// A device-local sort for a view with no list row to save one on (the Mac's sort menu).
        var sortBy: String?
        var currentUserId: String?
        var minute = Int(Date().timeIntervalSince1970 / 60)
    }

    /// The core's id for My Tasks.
    nonisolated static let myTasksId = "virtual:my-tasks"
    /// iOS's view with no list chosen: every task, the default completion window, highest
    /// priority first. A shape, not a list row.
    nonisolated static let everythingId = "virtual:all"
    nonisolated static var everything: TaskList {
        var shape = TaskList(id: everythingId, name: "")
        shape.isVirtual = true
        shape.sortBy = "priority"
        shape.filterCompletion = "default"
        return shape
    }

    /// The ids the core answered with, in its order.
    @Published private(set) var rowIds: [String] = []
    /// The query `rowIds` answers — `nil` until the first answer, and a different list's while a
    /// new one is being asked for the first time.
    @Published private(set) var answered: Query?
    private(set) var query: Query?

    private let session: CoreSession
    private var running: _Concurrency.Task<Void, Never>?
    private var tasksChanged: AnyCancellable?
    /// Each list's last answer, so returning to a list draws its rows at once and refreshes them
    /// behind the scenes rather than starting from nothing.
    private var lastAnswers: [String: [String]] = [:]

    /// - Parameters:
    ///   - session: the core to ask; the app's own by default.
    ///   - tasksChanged: when to ask again — a task edited, completed or synced can move into or
    ///     out of a list, or change place in it.
    init(session: CoreSession = AppCore.shared.session,
         tasksChanged: AnyPublisher<Void, Never>? = nil) {
        self.session = session
        let changes = tasksChanged ?? TaskService.shared.$tasks.map { _ in () }.eraseToAnyPublisher()
        self.tasksChanged = changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
    }

    /// Show the rows for `query`: its last answer at once when there is one, the core's as soon as
    /// it lands.
    func update(_ query: Query) {
        guard query != self.query else { return }
        let sameList = self.query?.listId == query.listId
        self.query = query
        if !sameList {
            // Never another list's rows under this one's title: its own last answer, or nothing
            // until the core answers (`hasAnswer` tells the view not to call that empty).
            let last = lastAnswers[query.listId] ?? []
            if last != rowIds { rowIds = last }
        }
        refresh()
    }

    /// Ask for `query` and wait for the answer.
    func load(_ query: Query) async {
        update(query)
        await running?.value
    }

    /// The rows to draw for `listId`: the answer for it, or its last one while a new one is on
    /// its way. `nil` when the core has never answered for that list — "not answered yet", which
    /// a view must not draw as "this list is empty".
    func ids(for listId: String) -> [String]? {
        if answered?.listId == listId, query?.listId == listId { return rowIds }
        return lastAnswers[listId]
    }

    /// `ids` as the given tasks — the views' own copies, so a row draws what its service holds.
    /// An id the service no longer has is left out; a task only the query carried (a public
    /// list's) is found there.
    func rows(_ ids: [String], in tasksById: [String: Task]) -> [Task] {
        let carried = query?.tasks.map { Dictionary($0.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
        return ids.compactMap { tasksById[$0] ?? carried?[$0] }
    }

    private func refresh() {
        guard let query else { return }
        running?.cancel()
        running = _Concurrency.Task { [session] in
            guard let ids = await Self.rowIds(for: query, session: session) else { return }
            guard !_Concurrency.Task.isCancelled, query == self.query else { return }
            self.lastAnswers[query.listId] = ids
            if ids != self.rowIds { self.rowIds = ids }
            if self.answered != query { self.answered = query }
        }
    }

    /// The core's `rowsForList`, as the ids of the rows it answers with; nil when it failed, so a
    /// failure keeps the rows on screen rather than emptying them.
    nonisolated static func rowIds(for query: Query, session: CoreSession) async -> [String]? {
        do {
            return try await session.run(command(for: query), as: IdsAnswer.self).ids
        } catch {
            AppLog.debug("❌ [ListRowsModel] rowsForList failed: \((error as NSError).localizedDescription)")
            return nil
        }
    }

    /// How many tasks `query`'s filters keep, subtasks included — a sidebar badge. No rows
    /// cross: the window is empty.
    nonisolated static func matched(for query: Query, session: CoreSession) async -> Int? {
        try? await session.run(command(for: query, limit: 0), as: IdsAnswer.self).matched
    }

    nonisolated static func command(for query: Query, limit: Int? = nil) -> CoreCommand {
        var command = CoreCommand(kind: "rowsForList")
        command.set("limit", limit)
        command.set("listId", query.listId)
        command.set("list", query.list)
        command.set("tasks", query.tasks)
        command.set("myTasks", query.myTasks)
        command.set("subtaskDisplay", query.subtaskDisplay)
        command.set("sortBy", query.sortBy)
        command.set("currentUserId", query.currentUserId)
        command.set("idsOnly", true)
        return command
    }

    nonisolated struct IdsAnswer: Decodable {
        let ids: [String]
        let matched: Int
    }
}
