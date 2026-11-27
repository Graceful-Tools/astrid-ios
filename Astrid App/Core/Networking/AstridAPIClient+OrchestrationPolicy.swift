//  AstridAPIClient+OrchestrationPolicy.swift
//  A list's and a project's orchestration policy (web AWTD-1693). astrid-core resolves the policy
//  (`CoreRules`, `orchestrationPolicy`) but has no command to read or store the overrides, so these
//  go to the server — called only by `ListTradeoffPolicyService` (ADEV-321) and
//  `OrchestrationPolicyService` (ADEV-333), never from a view (ASTRID.md §0 rule 1). The server
//  refuses a write from an agent or from anyone but the owner or an admin.

import Foundation

extension AstridAPIClient {
    /// A list's orchestration policy, for whether a trade-off policy applies (ADEV-321).
    func getListOrchestrationPolicy(listId: String) async throws -> ListOrchestrationPolicy {
        try await request(method: "GET", path: "/api/v1/lists/\(listId)/orchestration-policy")
    }

    /// Both stored overrides, the effective policy and what this person may edit (ADEV-333).
    func getListOrchestrationPolicyView(listId: String) async throws -> ListOrchestrationPolicyView {
        try await request(method: "GET", path: "/api/v1/lists/\(listId)/orchestration-policy")
    }

    /// Store the list's override; `nil` clears it. Answers the list's view.
    func putListOrchestrationPolicy(listId: String, policy: PolicyDocument?) async throws -> ListOrchestrationPolicyView {
        try await request(method: "PUT", path: "/api/v1/lists/\(listId)/orchestration-policy",
                          body: OrchestrationPolicyWrite(policy: policy))
    }

    /// Store the project's override, which every list in it inherits; `nil` clears it.
    func putProjectOrchestrationPolicy(projectId: String, policy: PolicyDocument?) async throws {
        let _: EmptyResponse = try await request(method: "PUT", path: "/api/v1/projects/\(projectId)/orchestration-policy",
                                                 body: OrchestrationPolicyWrite(policy: policy))
    }
}

/// `{ "policy": … }`, with an explicit `null` to clear (an absent key would be refused).
nonisolated struct OrchestrationPolicyWrite: Encodable, Sendable {
    let policy: PolicyDocument?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let policy { try c.encode(policy, forKey: .policy) } else { try c.encodeNil(forKey: .policy) }
    }

    private enum CodingKeys: String, CodingKey { case policy }
}
