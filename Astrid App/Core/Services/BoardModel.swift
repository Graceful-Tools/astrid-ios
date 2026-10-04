//  BoardModel.swift
//  Astrid — a project board's columns and cards, for iOS and Mac alike, answered by astrid-core
//  (AITD-461).
//
//  Both apps built their boards from Swift copies of iOS's rules (`getProjectBoardColumns`,
//  `boardColumnTasksSorted`, `getProjectDomainTasks`, `resolveBoardReorder`). The core's `board`
//  now answers exactly as iOS's board drew — the same columns and names, top-level cards in the
//  opened list's manual order, Done holding recent work (astrid-core CONTRACTS D43–D44) — so the
//  copies are gone and both apps ask the core, the way list rows do (`ListRowsModel`, AITD-460).
//
//  The answer is asynchronous: the board keeps drawing while the core reads its cache. It is asked
//  again when the board changes (another list, the minute the Done window reads) and whenever the
//  tasks, lists or projects change; between answers a board shows its last columns, never an empty
//  one.

import AstridCore
import Combine
import Foundation

@MainActor
final class BoardModel: ObservableObject {
    /// Which board: the list it was opened from (its manual order and Done window arrange the
    /// cards) or, for a board whose list the shell has not got, the project alone.
    nonisolated struct Query: Equatable, Sendable {
        var listId: String?
        var projectId: String?
        /// The Done window reads the clock.
        var minute = Int(Date().timeIntervalSince1970 / 60)

        /// The board's identity — what an answer is remembered under.
        var key: String { listId ?? "project:\(projectId ?? "")" }
    }

    /// One column as the core answered it: what it is, and its cards' ids in order.
    nonisolated struct Column: Equatable, Identifiable, Decodable, Sendable {
        let id: String
        let name: String
        let description: String
        let kind: ProjectBoardColumnKind
        let ids: [String]

        var column: ProjectBoardColumn {
            ProjectBoardColumn(id: id, name: name, description: description, kind: kind)
        }
    }

    /// The columns the core answered with, in order.
    @Published private(set) var columns: [Column] = []
    /// The query `columns` answers — `nil` until the first answer.
    @Published private(set) var answered: Query?
    private(set) var query: Query?

    private let session: CoreSession
    private var running: _Concurrency.Task<Void, Never>?
    private var changed: AnyCancellable?
    /// Each board's last answer, so returning to a board — in this view or a new one — draws it
    /// at once and refreshes it behind the scenes rather than starting from nothing.
    private static var lastAnswers: [String: [Column]] = [:]

    /// - Parameters:
    ///   - session: the core to ask; the app's own by default.
    ///   - changed: when to ask again — a task moved, a list reordered, a column renamed.
    init(session: CoreSession = AppCore.shared.session,
         changed: AnyPublisher<Void, Never>? = nil) {
        self.session = session
        let changes = changed ?? Publishers.Merge3(
            TaskService.shared.$tasks.map { _ in () },
            ListService.shared.$lists.map { _ in () },
            ProjectService.shared.$projects.map { _ in () }
        ).eraseToAnyPublisher()
        self.changed = changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
    }

    /// Show the board for `query`: its last answer at once when there is one, the core's as soon
    /// as it lands.
    func update(_ query: Query) {
        guard query != self.query else { return }
        let sameBoard = self.query != nil && self.query?.key == query.key
        self.query = query
        if !sameBoard {
            let last = Self.lastAnswers[query.key] ?? []
            if last != columns { columns = last }
        }
        refresh()
    }

    /// Ask for `query` and wait for the answer.
    func load(_ query: Query) async {
        update(query)
        await running?.value
    }

    /// How many columns `listId`'s board drew last — the five every board has until it has drawn.
    /// For a layout that only needs the count (the Mac's chat side panel).
    static func columnCount(listId: String) -> Int {
        lastAnswers[listId]?.count ?? 5
    }

    /// The column a task's card is in, if the board draws it.
    func columnId(of taskId: String) -> String? {
        columns.first { $0.ids.contains(taskId) }?.id
    }

    /// A column's cards as the given tasks — the views' own copies, so a card draws what its
    /// service holds. An id the service no longer has is left out.
    static func cards(_ column: Column, in tasksById: [String: Task]) -> [Task] {
        column.ids.compactMap { tasksById[$0] }
    }

    private func refresh() {
        guard let query else { return }
        running?.cancel()
        running = _Concurrency.Task { [session] in
            guard let columns = await Self.columns(for: query, session: session) else { return }
            guard !_Concurrency.Task.isCancelled, query == self.query else { return }
            Self.lastAnswers[query.key] = columns
            if columns != self.columns { self.columns = columns }
            if self.answered != query { self.answered = query }
        }
    }

    /// The core's `board`, as each column's ids; nil when it failed, so a failure keeps the board
    /// on screen rather than emptying it.
    nonisolated static func columns(for query: Query, session: CoreSession) async -> [Column]? {
        struct Answer: Decodable { let columns: [Column] }
        do {
            return try await session.run(command(for: query), as: Answer.self).columns
        } catch {
            AppLog.debug("❌ [BoardModel] board failed: \((error as NSError).localizedDescription)")
            return nil
        }
    }

    nonisolated static func command(for query: Query) -> CoreCommand {
        var command = CoreCommand(kind: "board")
        command.set("listId", query.listId)
        command.set("projectId", query.projectId)
        command.set("idsOnly", true)
        return command
    }
}

/// The board-column choice for one task — its own board's columns, never Done, and which one it
/// is in — answered by the core's `taskStatusOptions` (AITD-461, D46). Shared by the iOS and Mac
/// state pickers. Each task's last answer is kept, so reopening a picker draws at once.
@MainActor
final class TaskStatusOptions: ObservableObject {
    static let shared = TaskStatusOptions()

    nonisolated struct Answer: Equatable, Decodable, Sendable {
        nonisolated struct Option: Equatable, Decodable, Identifiable, Sendable {
            let id: String
            let name: String
            let kind: ProjectBoardColumnKind
            var column: ProjectBoardColumn {
                ProjectBoardColumn(id: id, name: name, description: "", kind: kind)
            }
        }
        let current: String
        let columns: [Option]
    }

    @Published private(set) var answers: [String: Answer] = [:]
    private let session: CoreSession
    private var changed: AnyCancellable?

    /// - Parameter changed: when every answer held is asked again — a board's columns renamed or
    ///   added arrive with the projects and lists, not with the task.
    init(session: CoreSession = AppCore.shared.session,
         changed: AnyPublisher<Void, Never>? = nil) {
        self.session = session
        let changes = changed ?? Publishers.Merge(
            ProjectService.shared.$projects.map { _ in () },
            ListService.shared.$lists.map { _ in () }
        ).eraseToAnyPublisher()
        self.changed = changes
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                for taskId in self.answers.keys {
                    _Concurrency.Task { await self.refresh(taskId) }
                }
            }
    }

    /// Ask again for `task` — call when it opens and whenever the task changes.
    func refresh(_ taskId: String) async {
        var command = CoreCommand(kind: "taskStatusOptions")
        command.set("taskId", taskId)
        guard let answer = try? await session.run(command, as: Answer.self) else { return }
        if answers[taskId] != answer { answers[taskId] = answer }
    }
}
