//  OrchestrationPolicy.swift
//  ADEV-333 (web AWTD-1693 `components/list-admin/OrchestrationPolicySection.tsx`,
//  `lib/orchestration-policy.ts`; core `astrid_rules::orchestration`, ADEV-273/281): the agent
//  policy a list's owner or admin edits — who takes unassigned Ready work, what an agent may do on
//  its own, who it asks, and the trade-off thresholds an estimate is labelled by.
//
//  The rules live in astrid-core. What a field inherits (the default, then the project's override,
//  then the list's) is asked of the core's `orchestrationPolicy` rule (`resolve`), never restated
//  here. This file only edits the STORED override, as web's `with*` helpers do: every key is
//  optional, an absent key inherits, an emptied group is dropped, and an override that says
//  nothing is `nil` (sent as `null`, so "nothing stored" stays one value). The server validates
//  every value with the core's own vocabulary.

import AstridCore
import Foundation

/// What an agent may do alone.
nonisolated enum PolicyAutonomy: String, CaseIterable, Sendable {
    case allowed, ask, never
}

/// The autonomy rows, in web's order (`AUTONOMY_FIELDS`). `migrate` holds two answers.
nonisolated enum PolicyAutonomyField: String, CaseIterable, Sendable {
    case merge, deploy, migrateAdditive, migrateDestructive, release, spend, promoteIdea, experimentStart, experimentStop

    fileprivate var path: [String] {
        switch self {
        case .migrateAdditive: return ["autonomy", "migrate", "additive"]
        case .migrateDestructive: return ["autonomy", "migrate", "destructive"]
        default: return ["autonomy", rawValue]
        }
    }
}

/// The three-step scale risk and confidence are written in.
nonisolated enum PolicyLevel: String, CaseIterable, Sendable {
    case low, medium, high
}

/// The trade-off thresholds, flattened one per row as web does (`TRADEOFF_LEVEL_FIELDS`, then
/// `TRADEOFF_PROBABILITY_FIELDS`).
nonisolated enum PolicyTradeoffField: String, CaseIterable, Sendable {
    case riskReviewAt, riskRefuseAt, confidenceBelow, experimentRiskAtLeast, minConfidenceToAct
    case guardrailReview, guardrailRefuse

    static let levels: [Self] = [.riskReviewAt, .riskRefuseAt, .confidenceBelow, .experimentRiskAtLeast, .minConfidenceToAct]
    static let probabilities: [Self] = [.guardrailReview, .guardrailRefuse]

    /// The breach probabilities offered; a stored one outside these is added so it can be read.
    static let probabilityChoices: [Double] = [5, 10, 25, 50, 75, 90].map { Double($0) / 100 }

    var isProbability: Bool { Self.probabilities.contains(self) }

    fileprivate var path: [String] {
        switch self {
        case .riskReviewAt: return ["tradeoff", "risk", "reviewAt"]
        case .riskRefuseAt: return ["tradeoff", "risk", "refuseAt"]
        case .confidenceBelow: return ["tradeoff", "experimentFirst", "confidenceBelow"]
        case .experimentRiskAtLeast: return ["tradeoff", "experimentFirst", "riskAtLeast"]
        case .minConfidenceToAct: return ["tradeoff", "minConfidenceToAct"]
        case .guardrailReview: return ["tradeoff", "guardrail", "reviewAtBreachProbability"]
        case .guardrailRefuse: return ["tradeoff", "guardrail", "refuseAtBreachProbability"]
        }
    }
}

/// Who a question goes to.
nonisolated enum PolicyEscalation: Equatable, Hashable, Sendable {
    case listOwner
    case taskCreator
    case people([String])

    init?(_ value: JSONValue?) {
        guard case .object(let object)? = value, case .string(let to)? = object["to"] else { return nil }
        switch to {
        case "listOwner": self = .listOwner
        case "taskCreator": self = .taskCreator
        case "people":
            guard case .array(let ids)? = object["userIds"] else { return nil }
            self = .people(ids.compactMap { if case .string(let id) = $0 { return id } else { return nil } })
        default: return nil
        }
    }

    var json: JSONValue {
        switch self {
        case .listOwner: return .object(["to": .string("listOwner")])
        case .taskCreator: return .object(["to": .string("taskCreator")])
        case .people(let ids): return .object(["to": .string("people"), "userIds": .array(ids.map(JSONValue.string))])
        }
    }
}

/// A policy in the wire shape: a stored override (every key optional) or a resolved policy (every
/// key present). The same readers serve both, because the paths are the same.
nonisolated struct PolicyDocument: Codable, Equatable, Sendable {
    var object: [String: JSONValue]

    init(_ object: [String: JSONValue] = [:]) { self.object = object }

    init(from decoder: Decoder) throws {
        object = try decoder.singleValueContainer().decode([String: JSONValue].self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(object)
    }

    // MARK: Reading

    private func value(at path: [String]) -> JSONValue? {
        var node: JSONValue? = .object(object)
        for key in path {
            guard case .object(let o)? = node else { return nil }
            node = o[key]
        }
        return node
    }

    private func contains(_ path: [String]) -> Bool {
        guard let last = path.last, case .object(let parent)? = value(at: Array(path.dropLast())) else { return false }
        return parent[last] != nil
    }

    func autonomy(_ field: PolicyAutonomyField) -> PolicyAutonomy? {
        if case .string(let raw)? = value(at: field.path) { return PolicyAutonomy(rawValue: raw) }
        return nil
    }

    /// `.some(nil)` is "any agent" (a value, overriding an inherited agent); `nil` inherits.
    var assignTo: String?? {
        guard contains(["routing", "assignTo"]) else { return nil }
        if case .string(let mailbox)? = value(at: ["routing", "assignTo"]) { return .some(mailbox) }
        return .some(nil)
    }

    var escalation: PolicyEscalation? { PolicyEscalation(value(at: ["escalation"])) }

    /// The document states a trade-off policy — even `{}`, which is a policy of the defaults.
    var tradeoffStated: Bool {
        if case .object? = object["tradeoff"] { return true }
        return false
    }

    func level(_ field: PolicyTradeoffField) -> PolicyLevel? {
        if case .string(let raw)? = value(at: field.path) { return PolicyLevel(rawValue: raw) }
        return nil
    }

    func probability(_ field: PolicyTradeoffField) -> Double? {
        if case .number(let number)? = value(at: field.path) { return number }
        return nil
    }

    /// The goals, most important first; `nil` inherits.
    var goalOrder: [String]? {
        guard case .array(let ids)? = value(at: ["tradeoff", "goalOrder"]) else { return nil }
        return ids.compactMap { if case .string(let id) = $0 { return id } else { return nil } }
    }

    // MARK: Editing (web's `with*`; each answers nil for an override that says nothing)

    func withAutonomy(_ field: PolicyAutonomyField, _ value: PolicyAutonomy?) -> PolicyDocument? {
        setting(field.path, value.map { .string($0.rawValue) })
    }

    /// `.some(nil)` routes to any agent; `nil` inherits.
    func withAssignTo(_ value: String??) -> PolicyDocument? {
        switch value {
        case .none: return setting(["routing", "assignTo"], nil)
        case .some(.none): return setting(["routing", "assignTo"], .null)
        case .some(.some(let mailbox)): return setting(["routing", "assignTo"], .string(mailbox))
        }
    }

    func withEscalation(_ value: PolicyEscalation?) -> PolicyDocument? {
        setting(["escalation"], value?.json)
    }

    /// State a trade-off policy (the defaults until a field is set), or state none.
    func withTradeoffStated(_ stated: Bool) -> PolicyDocument? {
        var copy = self
        if stated {
            if !tradeoffStated { copy.object["tradeoff"] = .object([:]) }
        } else {
            copy.object["tradeoff"] = nil
        }
        return copy.object.isEmpty ? nil : copy
    }

    /// Set one threshold, or inherit it. Setting one states a policy; clearing the last leaves
    /// `{}`, which still states one — only `withTradeoffStated(false)` takes it away.
    func withLevel(_ field: PolicyTradeoffField, _ value: PolicyLevel?) -> PolicyDocument? {
        stating(field.path, value.map { .string($0.rawValue) })
    }

    func withProbability(_ field: PolicyTradeoffField, _ value: Double?) -> PolicyDocument? {
        stating(field.path, value.map(JSONValue.number))
    }

    /// Set the goal order (most important first), or inherit it.
    func withGoalOrder(_ ids: [String]?) -> PolicyDocument? {
        stating(["tradeoff", "goalOrder"], ids.map { .array($0.map(JSONValue.string)) })
    }

    private func stating(_ path: [String], _ value: JSONValue?) -> PolicyDocument? {
        var copy = self
        if !copy.tradeoffStated { copy.object["tradeoff"] = .object([:]) }
        return copy.setting(path, value)
    }

    /// Put `value` at `path` (nil removes it), then drop every group the change emptied — all but
    /// `tradeoff`, whose `{}` still states a policy.
    private func setting(_ path: [String], _ value: JSONValue?) -> PolicyDocument? {
        func put(_ node: [String: JSONValue], _ path: ArraySlice<String>, depth: Int) -> [String: JSONValue] {
            var node = node
            guard let key = path.first else { return node }
            if path.count == 1 {
                node[key] = value
                return node
            }
            var child: [String: JSONValue] = [:]
            if case .object(let existing)? = node[key] { child = existing }
            let updated = put(child, path.dropFirst(), depth: depth + 1)
            let keepsEmpty = depth == 0 && key == "tradeoff"
            node[key] = updated.isEmpty && !keepsEmpty ? nil : .object(updated)
            return node
        }
        let next = put(object, path[...], depth: 0)
        return next.isEmpty ? nil : PolicyDocument(next)
    }
}

/// `GET /api/v1/lists/{id}/orchestration-policy`: both stored overrides, the effective policy the
/// server resolved through the core, and which of the two this person may edit.
nonisolated struct ListOrchestrationPolicyView: Codable, Equatable, Sendable {
    struct CanEdit: Codable, Equatable, Sendable {
        var list: Bool
        var project: Bool
    }

    var listId: String
    var projectId: String?
    var list: PolicyDocument?
    var project: PolicyDocument?
    var effective: PolicyDocument
    var canEdit: CanEdit

    /// The project first when there is one, as web lays them out.
    var scopes: [OrchestrationPolicyScope] { projectId == nil ? [.list] : [.project, .list] }

    var editsAnything: Bool { canEdit.list || canEdit.project }

    func override(_ scope: OrchestrationPolicyScope) -> PolicyDocument? {
        scope == .project ? project : list
    }

    func canEdit(_ scope: OrchestrationPolicyScope) -> Bool {
        scope == .project ? canEdit.project : canEdit.list
    }
}

nonisolated enum OrchestrationPolicyScope: String, CaseIterable, Sendable {
    case project, list
}

/// The core's `orchestrationPolicy` rule: the default, then the project's override, then the list's.
nonisolated enum OrchestrationPolicyRules {
    private struct Request: Encodable {
        let kind = "orchestrationPolicy"
        let project: PolicyDocument?
        let list: PolicyDocument?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(kind, forKey: .kind)
            try c.encodeIfPresent(project, forKey: .project)
            try c.encodeIfPresent(list, forKey: .list)
        }

        private enum CodingKeys: String, CodingKey { case kind, project, list }
    }

    /// The resolved policy, or nil if the core refused (a stored value it does not know).
    static func resolve(project: PolicyDocument?, list: PolicyDocument?) -> PolicyDocument? {
        try? CoreRules.ask(Request(project: project, list: list), as: PolicyDocument.self)
    }

    /// What a scope's unset field falls back to: the default for a project, the project's policy
    /// for a list.
    static func inherited(by scope: OrchestrationPolicyScope, in view: ListOrchestrationPolicyView) -> PolicyDocument? {
        scope == .project ? resolve(project: nil, list: nil) : resolve(project: view.project, list: nil)
    }

    /// What the trade-off thresholds take when a stated policy names less than all of it. Asked of
    /// the core by resolving a policy that states only `{}`.
    static func tradeoffDefaults() -> PolicyDocument? {
        resolve(project: nil, list: PolicyDocument(["tradeoff": .object([:])]))
    }
}
