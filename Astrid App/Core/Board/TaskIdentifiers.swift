//  TaskIdentifiers.swift
//  Task ids — `AWTD-1007` — parsed, shown and autolinked (AITD-437; web AWTD-1010 / AWTD-1017).
//  Spec of record: astrid-web docs/specs/TASK_IDENTIFIERS.md.
//
//  The server is the only minter: a task's id arrives as `Task.identifier` and is never derived
//  here. What IS here is the three rules every client shares — parse, show, autolink — ported
//  from web's lib/task-identifier-core.ts and lib/task-identifier-links.ts and pinned to the
//  shared fixture (`TaskIdentifiersTests`). Views ask this; none of them open-codes the rule.

import Foundation

enum TaskIdentifiers {

    // MARK: - Parse (web `parseIdentifier`)

    struct Parsed: Equatable {
        let key: String
        let sequence: Int
    }

    /// `KEY-N`: a 2–5 character key starting with a letter, and N ≥ 1. Case-insensitive in,
    /// uppercase out — `awtd-12` must not resolve differently from `AWTD-12`. `#12` is not an
    /// identifier; it is an autolink rule.
    static func parse(_ value: String?) -> Parsed? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let match = identifierPattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let keyRange = Range(match.range(at: 1), in: trimmed),
              let numberRange = Range(match.range(at: 2), in: trimmed),
              let sequence = Int(trimmed[numberRange]), sequence >= 1 else { return nil }
        return Parsed(key: trimmed[keyRange].uppercased(), sequence: sequence)
    }

    // MARK: - Where it is shown (spec §7)

    enum Surface {
        /// Task details, next to the lists.
        case details
        /// A row or card on a board view — muted.
        case boardRow
        /// A row in an ordinary list view — never.
        case listRow
    }

    /// The SF Symbol beside a task id. Not "number": "#" is a list here, and "!" is priority
    /// (AITD-484).
    static let symbolName = "ticket"

    /// Shown when the task has an id AND sits on at least one list belonging to a project. A
    /// task moved out of every project keeps its id for links, but stops showing it.
    static func shows(identifier: String?, listProjectIds: [String?], on surface: Surface) -> Bool {
        guard surface != .listRow, let identifier, !identifier.isEmpty else { return false }
        return listProjectIds.contains { $0 != nil }
    }

    /// The same rule for a `Task`, with each list's `projectId` looked up in `lists` (the lists
    /// the app has loaded) — the task's own embedded lists often omit it.
    static func shows(_ task: Task, lists: [TaskList], on surface: Surface) -> Bool {
        let membership = taskListMembershipIds(task)
        let known = Dictionary(lists.map { ($0.id, $0.projectId) }, uniquingKeysWith: { first, _ in first })
        let projectIds = membership.map { id in
            known[id] ?? task.lists?.first(where: { $0.id == id })?.projectId
        }
        return shows(identifier: task.identifier, listProjectIds: projectIds, on: surface)
    }

    /// A board card's muted id. A card is only ever drawn on a project board, so the task is on
    /// a project list by construction; what is left of the rule is "has an id".
    static func boardCardLabel(for task: Task) -> String? {
        shows(identifier: task.identifier, listProjectIds: ["board"], on: .boardRow) ? task.identifier : nil
    }

    /// "Copy task id" is offered whenever there is one — even off a board.
    static func canCopy(identifier: String?) -> Bool {
        !(identifier ?? "").isEmpty
    }

    // MARK: - Autolink (web `findIdentifierLinks`)

    struct Link: Equatable {
        /// As written: `AWTD-12` or `#12`.
        let match: String
        /// Always the full `KEY-N`.
        let identifier: String
        /// Where `match` sits in the text, in UTF-16 units (NSString / NSAttributedString).
        let range: NSRange
    }

    /// The task references in `text` that should link.
    ///
    /// - `keys`: project keys the reader can see. Only these link, which keeps `UTF-8` and
    ///   `COVID-19` prose and never links a project the reader cannot open.
    /// - `projectKey`: the project the text belongs to; enables `#N`. Nil outside a project.
    /// - `hidden`: ids known to be hidden from the reader — plain text, never a dead link.
    ///
    /// Uppercase full form only, on word boundaries, never inside a URL or code.
    static func links(in text: String, projectKey: String?, keys: [String], hidden: [String] = []) -> [Link] {
        let keySet = Set(keys.map { $0.uppercased() })
        guard !text.isEmpty, !keySet.isEmpty else { return [] }
        let hiddenSet = Set(hidden.map { $0.uppercased() })
        let masked = mask(text) as NSString
        let whole = NSRange(location: 0, length: masked.length)
        let source = text as NSString
        var links: [Link] = []

        for m in fullForm.matches(in: masked as String, range: whole) {
            let key = masked.substring(with: m.range(at: 1))
            guard keySet.contains(key), let sequence = Int(masked.substring(with: m.range(at: 2))), sequence >= 1 else { continue }
            let identifier = "\(key)-\(sequence)"
            if !hiddenSet.contains(identifier) {
                links.append(Link(match: source.substring(with: m.range), identifier: identifier, range: m.range))
            }
        }
        if let projectKey = projectKey?.uppercased(), keySet.contains(projectKey) {
            for m in shortForm.matches(in: masked as String, range: whole) {
                guard let sequence = Int(masked.substring(with: m.range(at: 1))), sequence >= 1 else { continue }
                let identifier = "\(projectKey)-\(sequence)"
                if !hiddenSet.contains(identifier) {
                    links.append(Link(match: source.substring(with: m.range), identifier: identifier, range: m.range))
                }
            }
        }
        return links.sorted { $0.range.location < $1.range.location }
    }

    // MARK: - Wiring the autolink into comments and chat (AITD-439)

    /// What the reader can see, which decides what links. astrid-core's `LinkContext`, and what
    /// its comment and chat rows are rendered with.
    struct LinkContext: Equatable {
        /// The board the text belongs to — a task's, or the chat's list's. Enables `#N`.
        var projectKey: String?
        /// Keys of every project the reader can see.
        var keys: [String]
        var hidden: [String] = []

        /// A task's comments: `#N` means the key of the first board the task sits on.
        static func forTask(_ task: Task, lists: [TaskList], projects: [Project]) -> LinkContext {
            let known = Dictionary(lists.map { ($0.id, $0.projectId) }, uniquingKeysWith: { first, _ in first })
            let projectId = taskListMembershipIdsInOrder(task).lazy.compactMap { id in
                known[id] ?? task.lists?.first(where: { $0.id == id })?.projectId
            }.first
            return LinkContext(projectKey: key(of: projectId, in: projects), keys: keys(of: projects))
        }

        /// A list's chat: `#N` means the key of the list's board, if it is on one.
        static func forList(listId: String?, lists: [TaskList], projects: [Project]) -> LinkContext {
            let projectId = lists.first(where: { $0.id == listId })?.projectId
            return LinkContext(projectKey: key(of: projectId, in: projects), keys: keys(of: projects))
        }

        private static func keys(of projects: [Project]) -> [String] {
            projects.compactMap { $0.key }.filter { !$0.isEmpty }
        }

        private static func key(of projectId: String?, in projects: [Project]) -> String? {
            projectId.flatMap { id in projects.first(where: { $0.id == id })?.key }
        }
    }

    /// Where an id links: the web's `/t/KEY-N`, which resolves and redirects. The app opens it
    /// in place when it can (`identifier(inLink:)`); anywhere else it still lands on the task.
    static func url(for identifier: String) -> URL {
        URL(string: "\(Brand.productionBaseURL)/t/\(identifier)")!
    }

    /// The id a tapped link names, when it is one of ours — `nil` for any other URL.
    static func identifier(inLink url: URL) -> String? {
        guard url.scheme == "https", let host = url.host, Brand.webHosts.contains(host) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "t", let parsed = parse(parts[1]) else { return nil }
        return "\(parsed.key)-\(parsed.sequence)"
    }

    // MARK: - Patterns — web's, character for character

    private static let identifierPattern = try! NSRegularExpression(pattern: "^([A-Za-z][A-Za-z0-9]{1,4})-(\\d+)$")

    /// Not after a word character, hyphen, slash, dot or `#` (URLs, paths, `XAWTD-1`), not before one.
    private static let fullForm = try! NSRegularExpression(
        pattern: "(?<![A-Za-z0-9_\\-/.#])([A-Z][A-Z0-9]{1,4})-(\\d+)(?![A-Za-z0-9_\\-])")

    /// `#N` — not an HTML entity (`&#12;`), not a heading (`# 12`).
    private static let shortForm = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9_&#/])#(\\d+)(?![A-Za-z0-9_])")

    /// Code and URLs become spaces of the same UTF-16 length, so offsets stay true to the input.
    private static let masks = [
        try! NSRegularExpression(pattern: "```[\\s\\S]*?```"),
        try! NSRegularExpression(pattern: "`[^`\\n]*`"),
        try! NSRegularExpression(pattern: "\\bhttps?://\\S+"),
    ]

    private static func mask(_ text: String) -> String {
        masks.reduce(text) { acc, pattern in
            let mutable = NSMutableString(string: acc)
            for m in pattern.matches(in: acc, range: NSRange(location: 0, length: mutable.length)).reversed() {
                mutable.replaceCharacters(in: m.range, with: String(repeating: " ", count: m.range.length))
            }
            return mutable as String
        }
    }
}
