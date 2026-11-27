//  ListTradeoffPolicyService.swift
//  ADEV-321 (web ADEV-281 `hooks/use-list-tradeoff-policy.ts`; core ADEV-273/324): does a trade-off
//  policy apply to a list? That decides whether the Policy sort is offered. astrid-core already
//  sorts by `policy` from each row's stored sort key; with no policy stated nothing is labelled, so
//  there is nothing to sort by and no entry.
//
//  Read from `GET /api/v1/lists/{id}/orchestration-policy`, whose `effective` policy the server
//  resolves through the core. The core has no command for it, so the read goes through
//  `AstridAPIClient`, here and nowhere else (ASTRID.md §0 rule 1). False until the answer arrives
//  and on any failure, so the option stays hidden rather than flickering in.

import Combine
import Foundation

/// Only what the app asks of the list's orchestration policy.
nonisolated struct ListOrchestrationPolicy: Codable, Equatable, Sendable {
    /// The effective policy carries a `tradeoff` block.
    var tradeoffStated: Bool

    init(tradeoffStated: Bool) { self.tradeoffStated = tradeoffStated }

    private enum CodingKeys: String, CodingKey { case effective }
    private enum EffectiveKeys: String, CodingKey { case tradeoff }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.effective), try !c.decodeNil(forKey: .effective) else {
            tradeoffStated = false
            return
        }
        let effective = try c.nestedContainer(keyedBy: EffectiveKeys.self, forKey: .effective)
        tradeoffStated = effective.contains(.tradeoff) ? try !effective.decodeNil(forKey: .tradeoff) : false
    }

    /// The API client's decode path wants `Codable`; this writes back only what was read.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        var effective = c.nestedContainer(keyedBy: EffectiveKeys.self, forKey: .effective)
        if tradeoffStated { try effective.encode([String: String](), forKey: .tradeoff) }
    }
}

@MainActor
final class ListTradeoffPolicyService: ObservableObject {
    static let shared = ListTradeoffPolicyService()

    typealias Fetch = @Sendable (String) async throws -> ListOrchestrationPolicy

    @Published private(set) var statedByList: [String: Bool] = [:]
    private let fetch: Fetch

    init(fetch: Fetch? = nil) {
        self.fetch = fetch ?? { try await AstridAPIClient.shared.getListOrchestrationPolicy(listId: $0) }
    }

    /// Whether a trade-off policy applies to the list; false until read and after a failed read.
    func isStated(listId: String) -> Bool { statedByList[listId] ?? false }

    func load(listId: String) async {
        let stated = (try? await fetch(listId))?.tradeoffStated ?? false
        if statedByList[listId] != stated { statedByList[listId] = stated }
    }

    /// Forget everything — on sign-out.
    func clear() { statedByList = [:] }
}

/// The list sort values both platforms offer, in web's order (`SORT_BY_OPTIONS`). `policy` only
/// where a trade-off policy is stated (ADEV-281).
nonisolated enum ListSortOptions {
    static let policy = "policy"
    static let base = ["auto", "manual", "when", "priority", "createdAt", "completedAt"]

    static func values(policyStated: Bool) -> [String] {
        policyStated ? base + [policy] : base
    }
}
