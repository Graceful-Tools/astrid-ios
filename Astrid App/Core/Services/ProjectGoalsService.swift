//  ProjectGoalsService.swift
//  ADEV-183 (web ADEV-179): a project's goals and guardrails — what it is for and what it must not
//  do, read by everyone working in it, people and agents.
//
//  `GET/PUT /api/v1/projects/{id}/goals` (astrid-web docs/API_CONTRACT.md). The server does all the
//  normalising — trimming, dropping blank rows, assigning `g1`/`r1` ids, defaulting `kind` — so
//  this only reads, shows and sends the whole value. astrid-core has no goals command yet, so the
//  call goes through `AstridAPIClient`. Saving is online only, like the board rows: it is project
//  metadata, not task data, so it doesn't go through the Outbox.

import AstridCore
import Combine
import Foundation

nonisolated struct ProjectGoal: Codable, Equatable, Hashable, Sendable {
    /// nil for a row the person just added: the server assigns one.
    var id: String?
    var statement: String
    var measure: String?
    var target: String?
    var current: String?
    /// Every key this build does not model — `metric`, `history`, and whatever web adds next —
    /// as it came, so a save sends it back rather than dropping it (ADEV-319).
    var unmodeled: [String: JSONValue] = [:]

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, statement, measure, target, current }

    init(id: String?, statement: String, measure: String? = nil, target: String? = nil, current: String? = nil) {
        self.id = id
        self.statement = statement
        self.measure = measure
        self.target = target
        self.current = current
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        statement = try c.decode(String.self, forKey: .statement)
        measure = try c.decodeIfPresent(String.self, forKey: .measure)
        target = try c.decodeIfPresent(String.self, forKey: .target)
        current = try c.decodeIfPresent(String.self, forKey: .current)
        unmodeled = try UnmodeledKeys.decode(from: decoder, except: CodingKeys.allCases.map(\.rawValue))
    }

    /// Leaves out a missing id and every empty optional field, so a new row is sent without an id
    /// and a cleared field as absent rather than "".
    func encode(to encoder: Encoder) throws {
        try UnmodeledKeys.encode(unmodeled, to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id.nonEmpty, forKey: .id)
        try c.encode(statement, forKey: .statement)
        try c.encodeIfPresent(measure.nonEmpty, forKey: .measure)
        try c.encodeIfPresent(target.nonEmpty, forKey: .target)
        try c.encodeIfPresent(current.nonEmpty, forKey: .current)
    }

    /// The editor's rows are keyed by what the person edits; the pass-through keys don't take part.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id); hasher.combine(statement); hasher.combine(measure)
        hasher.combine(target); hasher.combine(current)
    }
}

nonisolated struct ProjectGuardrail: Codable, Equatable, Hashable, Sendable {
    /// `stated`: people and agents judge it. `enforced`: a program checks it (web ADEV-182).
    enum Kind: String, Codable, Sendable, CaseIterable {
        case stated, enforced

        /// Anything this build does not know reads as stated, the server's default.
        init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .stated
        }
    }

    var id: String?
    var statement: String
    var kind: Kind = .stated
    /// Every key this build does not model — an enforced guardrail's `check` (web ADEV-182/277),
    /// and whatever comes next — as it came. The server keeps an omitted goal metric but not an
    /// omitted check, so dropping this unblocked what the guardrail blocked (ADEV-319).
    var unmodeled: [String: JSONValue] = [:]

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, statement, kind }

    init(id: String?, statement: String, kind: Kind = .stated) {
        self.id = id
        self.statement = statement
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        statement = try c.decode(String.self, forKey: .statement)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .stated
        unmodeled = try UnmodeledKeys.decode(from: decoder, except: CodingKeys.allCases.map(\.rawValue))
    }

    func encode(to encoder: Encoder) throws {
        var passThrough = unmodeled
        // Only an enforced guardrail may carry a check; the server answers 400 otherwise.
        if kind != .enforced { passThrough["check"] = nil }
        try UnmodeledKeys.encode(passThrough, to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id.nonEmpty, forKey: .id)
        try c.encode(statement, forKey: .statement)
        try c.encode(kind, forKey: .kind)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id); hasher.combine(statement); hasher.combine(kind)
    }
}

/// The keys of a JSON object other than the ones a type models, read and written as they are.
private nonisolated enum UnmodeledKeys {
    struct Key: CodingKey {
        let stringValue: String
        init(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    static func decode(from decoder: Decoder, except modeled: [String]) throws -> [String: JSONValue] {
        let c = try decoder.container(keyedBy: Key.self)
        var out: [String: JSONValue] = [:]
        for key in c.allKeys where !modeled.contains(key.stringValue) {
            out[key.stringValue] = try c.decode(JSONValue.self, forKey: key)
        }
        return out
    }

    static func encode(_ values: [String: JSONValue], to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        for (key, value) in values { try c.encode(value, forKey: Key(stringValue: key)) }
    }
}

/// The server's answer: the project's goals and guardrails, and whether this person may edit them.
nonisolated struct ProjectGoals: Codable, Equatable, Sendable {
    var projectId: String?
    var projectName: String?
    var goals: [ProjectGoal]
    var guardrails: [ProjectGuardrail]
    var canEdit: Bool

    private enum CodingKeys: String, CodingKey { case projectId, projectName, goals, guardrails, canEdit }

    init(projectId: String? = nil, projectName: String? = nil, goals: [ProjectGoal],
         guardrails: [ProjectGuardrail], canEdit: Bool = false) {
        self.projectId = projectId
        self.projectName = projectName
        self.goals = goals
        self.guardrails = guardrails
        self.canEdit = canEdit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        projectName = try c.decodeIfPresent(String.self, forKey: .projectName)
        goals = try c.decodeIfPresent([ProjectGoal].self, forKey: .goals) ?? []
        guardrails = try c.decodeIfPresent([ProjectGuardrail].self, forKey: .guardrails) ?? []
        canEdit = try c.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false
    }

    var isEmpty: Bool { goals.isEmpty && guardrails.isEmpty }
}

/// The PUT body: the whole value, replacing both lists.
nonisolated struct ProjectGoalsUpdate: Encodable, Equatable, Sendable {
    var goals: [ProjectGoal]
    var guardrails: [ProjectGuardrail]
}

private extension Optional where Wrapped == String {
    /// nil for nil or an all-whitespace string.
    var nonEmpty: String? {
        guard let self, !self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return self
    }
}

/// Each project's goals and guardrails, as last read.
@MainActor
final class ProjectGoalsService: ObservableObject {
    static let shared = ProjectGoalsService()

    typealias Fetch = @Sendable (String) async throws -> ProjectGoals
    typealias Save = @Sendable (String, ProjectGoalsUpdate) async throws -> ProjectGoals

    /// A missing key means not loaded yet.
    @Published private(set) var byProject: [String: ProjectGoals] = [:]

    private let fetch: Fetch
    private let saveRequest: Save

    /// - Parameters: how to read and write; the app's API client by default.
    init(fetch: Fetch? = nil, save: Save? = nil) {
        self.fetch = fetch ?? { try await AstridAPIClient.shared.getProjectGoals(projectId: $0) }
        self.saveRequest = save ?? { try await AstridAPIClient.shared.putProjectGoals(projectId: $0, $1) }
    }

    func goals(projectId: String) -> ProjectGoals? { byProject[projectId] }

    /// Read them. Failure leaves what was there.
    func load(projectId: String) async {
        do {
            byProject[projectId] = try await fetch(projectId)
        } catch {
            AppLog.debug("❌ [ProjectGoals] load failed: \((error as NSError).localizedDescription)")
        }
    }

    /// Replace them; true when the server took it. A refusal keeps what was there.
    @discardableResult
    func save(projectId: String, _ update: ProjectGoalsUpdate) async -> Bool {
        do {
            byProject[projectId] = try await saveRequest(projectId, update)
            return true
        } catch {
            AppLog.debug("❌ [ProjectGoals] save failed: \((error as NSError).localizedDescription)")
            return false
        }
    }

    /// Forget everything — on sign-out.
    func clear() { byProject = [:] }
}
