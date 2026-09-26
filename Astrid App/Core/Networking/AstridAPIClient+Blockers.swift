import Foundation

/// The "waiting on" half of `AstridAPIClient` (AITD-429 / AITD-430).
///
/// An extension for the reason `AstridAPIClient+ListOwnership.swift` is one: the client sits on
/// its `SourceFileSizeGuardTests` ceiling. Views never call these — they go through
/// `TaskBlockerService` (ASTRID.md §0 rule 1). All four routes are `/api/v1` and need a
/// project-mode task; shapes are `V1BlockersResponse` / `V1BlockerMutationResponse` in
/// astrid-web lib/api-contracts/v1-ios-shapes.ts.
///
/// `APIEndpointInventoryTests` scans this file too.
extension AstridAPIClient {

    func getTaskBlockers(taskId: String) async throws -> TaskBlockersResponse {
        try await request(method: "GET", path: "/api/v1/tasks/\(taskId)/blockers")
    }

    /// 201 when created, 200 when already linked — both decode the same. A 409 whose body says
    /// `dependency_cycle` is the cycle refusal; see `TaskBlockers.isCycleRefusal`.
    func addTaskBlocker(taskId: String, blockingTaskId: String) async throws -> TaskBlockerMutationResponse {
        struct AddBlockerRequest: Codable { let blockingTaskId: String }
        return try await request(
            method: "POST",
            path: "/api/v1/tasks/\(taskId)/blockers",
            body: AddBlockerRequest(blockingTaskId: blockingTaskId)
        )
    }

    func removeTaskBlocker(taskId: String, blockingTaskId: String) async throws -> TaskBlockerMutationResponse {
        try await request(method: "DELETE", path: "/api/v1/tasks/\(taskId)/blockers/\(blockingTaskId)")
    }

    /// Server-side task search. The picker must not filter loaded tasks locally — the server's
    /// search applies the visibility rules, and a second search path would be a second set.
    func searchTasksForBlockerPicker(query: String) async throws -> [BlockerSearchHit] {
        struct SearchResponse: Codable { let tasks: [BlockerSearchHit] }
        let response: SearchResponse = try await request(
            method: "GET",
            path: "/api/v1/search",
            queryItems: [URLQueryItem(name: "q", value: query)]
        )
        return response.tasks
    }
}
