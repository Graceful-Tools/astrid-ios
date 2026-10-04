//  PickerAnswers.swift
//  Astrid — what the pickers offer, for iOS and Mac alike, answered by astrid-core (AITD-461).
//
//  The list, due-date and assignee pickers filled themselves from Swift copies of iOS's rules
//  (`ListFilingTargets`, `DueDateQuickPicks`, `AssigneeOptions`). The core's `listPicks`,
//  `dueDateOptions` and `assigneeOptions` now answer as iOS's pickers did (astrid-core CONTRACTS
//  D47, D48, D50), so the copies are gone and both apps ask the core.
//
//  The answer is asynchronous, so a picker must never draw "nothing" while it waits. Each answer is
//  kept under the question it answers, shared app-wide: a picker asks when its trigger appears —
//  before anyone opens it — and draws the last answer it had while a new question is out.

import AstridCore
import Combine
import Foundation

@MainActor
final class PickerAnswers<Answer: Decodable & Equatable & Sendable>: ObservableObject {
    @Published private(set) var answers: [String: Answer] = [:]
    private let session: CoreSession
    private var asking: Set<String> = []
    /// Each question asked, so every answer held can be asked again when what it read changes.
    private var questions: [String: CoreCommand] = [:]
    private var changed: AnyCancellable?

    /// - Parameter changed: when every answer held is asked again — the lists (and their rosters)
    ///   it was read from moved on. Nil for answers that read nothing that moves.
    init(session: CoreSession = AppCore.shared.session, changed: AnyPublisher<Void, Never>? = nil) {
        self.session = session
        self.changed = changed?
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.refreshAll() }
    }

    /// The answer to `key`, if the core has given one.
    func answer(_ key: String) -> Answer? { answers[key] }

    /// Ask the core `command`, remembered under `key`. A question already out is not asked twice.
    func ask(_ key: String, _ command: CoreCommand) async {
        questions[key] = command
        guard asking.insert(key).inserted else { return }
        defer { asking.remove(key) }
        do {
            let answer = try await session.run(command, as: Answer.self)
            if answers[key] != answer { answers[key] = answer }
        } catch {
            AppLog.debug("❌ [PickerAnswers] \(key): \((error as NSError).localizedDescription)")
        }
    }

    /// Ask every question held again; each keeps its last answer until the new one lands.
    func refreshAll() {
        for (key, command) in questions {
            _Concurrency.Task { await self.ask(key, command) }
        }
    }
}

/// When the lists — and the rosters they carry — change.
@MainActor
private var listsChanged: AnyPublisher<Void, Never> {
    ListService.shared.$lists.dropFirst().map { _ in () }.eraseToAnyPublisher()
}

// MARK: - Lists

/// The list picker's checklist (`listPicks`, `asToggles`; D50): every list a task can be filed in,
/// in the sidebar's order, matched by what was typed. Saved filters are never offered — they own
/// no tasks (D28).
nonisolated struct ListToggles: Equatable, Decodable, Sendable {
    nonisolated struct Toggle: Equatable, Decodable, Sendable {
        let id: String
        let name: String
        let isSelected: Bool
    }
    let options: [Toggle]
}

@MainActor
enum ListPicks {
    static let shared = PickerAnswers<ListToggles>(changed: listsChanged)

    /// What a search for `query` is remembered under. The answer does not depend on the selection
    /// (a picker marks its own ticks), so one answer serves every task.
    static func key(_ query: String) -> String { "lists|\(query)" }

    /// Ask for the lists matching `query`; asked again whenever the lists change.
    static func ask(_ query: String) async {
        await shared.ask(key(query), command(query))
    }

    nonisolated static func command(_ query: String) -> CoreCommand {
        var command = CoreCommand(kind: "listPicks")
        command.set("query", query)
        command.set("listIds", [String]())
        command.set("asToggles", true)
        return command
    }

    /// The lists `query` matched, as the caller's own copies, in the core's order.
    static func lists(_ query: String, in lists: [TaskList]) -> [TaskList]? {
        guard let answer = shared.answer(key(query)) else { return nil }
        let byId = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return answer.options.compactMap { byId[$0.id] }
    }
}

// MARK: - Due dates

/// The quick date and time picks (`dueDateOptions`; D26, D48): Today, Tomorrow, In 3 days, Next
/// week — each the reader's calendar day as an all-day date at UTC midnight — and Morning,
/// Afternoon, Evening, Night on the task's own day.
nonisolated struct DueOptions: Equatable, Decodable, Sendable {
    nonisolated struct DatePick: Equatable, Decodable, Sendable {
        let titleKey: String
        let daysFromToday: Int
        let dueDateTime: String
        let isSelected: Bool
        var date: Date? { WireDate.date(from: dueDateTime) }
    }
    nonisolated struct TimePick: Equatable, Decodable, Sendable {
        let titleKey: String
        let hour: Int
        let dueDateTime: String
        let isSelected: Bool
        var date: Date? { WireDate.date(from: dueDateTime) }
    }
    let dates: [DatePick]
    let times: [TimePick]
}

@MainActor
enum DuePicks {
    static let shared = PickerAnswers<DueOptions>()

    /// The picks for an editor holding `date` (nil: no date yet) — remembered per day, because
    /// "Today" moves at midnight.
    static func key(_ date: Date?, isAllDay: Bool, now: Date = Date()) -> String {
        let today = Calendar.current.dateComponents([.year, .month, .day], from: now)
        return "due|\(date.map(WireDate.dueDateString) ?? "none")|\(isAllDay)|\(today.year ?? 0)-\(today.month ?? 0)-\(today.day ?? 0)"
    }

    static func ask(_ date: Date?, isAllDay: Bool) async {
        await shared.ask(key(date, isAllDay: isAllDay), command(date, isAllDay: isAllDay))
    }

    nonisolated static func command(_ date: Date?, isAllDay: Bool) -> CoreCommand {
        var command = CoreCommand(kind: "dueDateOptions")
        var draft = CoreFields()
        draft.set("dueDateTime", date.map(WireDate.dueDateString))
        draft.set("isAllDay", isAllDay)
        command.set("draft", draft)
        return command
    }

    static func options(_ date: Date?, isAllDay: Bool) -> DueOptions? {
        shared.answer(key(date, isAllDay: isAllDay))
    }
}

// MARK: - Assignees

/// Who a task can be assigned to (`assigneeOptions`; D47): no one first, then agents, then you,
/// then everyone else by name — iOS's rule, from the task's lists, the people a search found and
/// the account's agents. Each option carries the person's record, to draw a face from.
nonisolated struct AssigneeAnswer: Equatable, Decodable, Sendable {
    nonisolated struct Option: Equatable, Decodable, Sendable {
        let userId: String?
        let isCurrentUser: Bool
        let isAgent: Bool
        let user: User?
    }
    let options: [Option]

    /// The people offered, in order — without the unassigned row, which each picker draws itself.
    var people: [User] { options.compactMap(\.user) }
}

/// What one picker holds when it asks: the task's lists as the editor has them, the people its
/// search found, the agents it keeps and who is signed in.
nonisolated struct AssigneeQuestion: Equatable, Sendable {
    var listIds: [String]
    var discovered: [User] = []
    var agents: [User] = []
    var currentUser: User?

    /// What the answer is remembered under. Whole records, not ids: a name that arrives later is
    /// a different answer.
    var key: String {
        func ids(_ users: [User]) -> String { users.map { "\($0.id):\($0.name ?? "")" }.joined(separator: ",") }
        return "assignee|\(listIds.joined(separator: ","))|\(ids(discovered))|\(ids(agents))|\(currentUser.map { ids([$0]) } ?? "")"
    }

    var command: CoreCommand {
        var command = CoreCommand(kind: "assigneeOptions")
        command.set("listIds", listIds)
        command.set("discovered", discovered)
        command.set("agents", agents)
        command.set("currentUser", currentUser)
        return command
    }
}

@MainActor
enum AssigneePicks {
    static let shared = PickerAnswers<AssigneeAnswer>(changed: listsChanged)

    static func ask(_ question: AssigneeQuestion) async {
        await shared.ask(question.key, question.command)
    }

    static func answer(_ question: AssigneeQuestion) -> AssigneeAnswer? {
        shared.answer(question.key)
    }
}
