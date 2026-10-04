//  TaskSearchModel.swift
//  Astrid — the search box, for iOS and Mac alike, answered by astrid-core (AITD-459).
//
//  Both apps searched with a Swift copy of iOS's rules (`TaskSearch`). The core's `searchTasks`
//  now answers exactly as that copy did — the query as one phrase as typed, from the first
//  character, over the title, the description and the assignee's name; top-level tasks only;
//  completed work as a list shows it by default; highest priority first — so the copy is gone and
//  both apps ask the core (astrid-core `services::search::search_tasks`, CONTRACTS "Search").
//
//  The answer is asynchronous: a view keeps drawing while the core reads its cache, and the
//  results follow the query and every change to the tasks.

import AstridCore
import Combine
import Foundation

@MainActor
final class TaskSearchModel: ObservableObject {
    /// The ids the core found for `query`, in its order.
    @Published private(set) var resultIds: [String] = []
    /// The query the results are for, or are being fetched for.
    private(set) var query = ""

    private let session: CoreSession
    private var running: _Concurrency.Task<Void, Never>?
    private var tasksChanged: AnyCancellable?

    /// - Parameters:
    ///   - session: the core to ask; the app's own by default.
    ///   - tasksChanged: when to ask again — a task edited, completed or synced can move into or
    ///     out of the results, or change place in them.
    init(session: CoreSession = AppCore.shared.session,
         tasksChanged: AnyPublisher<Void, Never>? = nil) {
        self.session = session
        let changes = tasksChanged ?? TaskService.shared.$tasks.map { _ in () }.eraseToAnyPublisher()
        self.tasksChanged = changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
    }

    /// Search for `query`. An empty query finds nothing at once: search is intentional.
    func update(query: String) {
        guard query != self.query else { return }
        self.query = query
        refresh()
    }

    /// Search for `query` and wait for the answer.
    func search(_ query: String) async {
        self.query = query
        refresh()
        await running?.value
    }

    /// The results as the given tasks — the views' own copies, so a row draws what its service
    /// holds. An id the service no longer has is left out.
    func results(in tasksById: [String: Task]) -> [Task] {
        resultIds.compactMap { tasksById[$0] }
    }

    private func refresh() {
        running?.cancel()
        let query = self.query
        guard !query.isEmpty else {
            if !resultIds.isEmpty { resultIds = [] }
            running = nil
            return
        }
        running = _Concurrency.Task { [session] in
            let ids = await Self.resultIds(for: query, session: session)
            guard !_Concurrency.Task.isCancelled, query == self.query else { return }
            if ids != self.resultIds { self.resultIds = ids }
        }
    }

    /// The core's `searchTasks`, read as the ids of the rows it answers with.
    nonisolated static func resultIds(for query: String, session: CoreSession) async -> [String] {
        guard !query.isEmpty else { return [] }
        var command = CoreCommand(kind: "searchTasks")
        command.set("query", query)
        struct Found: Decodable {
            struct Row: Decodable { let id: String }
            let rows: [Row]
        }
        do {
            return try await session.run(command, as: Found.self).rows.map(\.id)
        } catch {
            AppLog.debug("❌ [TaskSearchModel] searchTasks failed: \((error as NSError).localizedDescription)")
            return []
        }
    }
}
