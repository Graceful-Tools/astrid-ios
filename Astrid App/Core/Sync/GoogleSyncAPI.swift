import Foundation

// MARK: - Google Tasks sync proxy DTOs (mirror astrid-web /api/v1/sync/google)

struct GoogleTasklistDTO: Codable, Identifiable, Equatable {
    let id: String
    let name: String
}

struct GoogleTasklistsResponse: Codable {
    let tasklists: [GoogleTasklistDTO]
    /// The default list's real id — maps to Astrid's My Tasks (unlisted).
    var defaultId: String? = nil
}

/// Provider-neutral remote item from the Google proxy. `dueDate` is RFC3339
/// with date-only semantics (Google Tasks has no time-of-day).
struct GoogleTaskItemDTO: Codable, Equatable {
    let remoteId: String        // "tasklistId:taskId"
    let title: String
    let notes: String?
    let completed: Bool
    var completedAt: String? = nil   // Google's completion timestamp
    let dueDate: String?
    let remoteUpdatedAt: String
    let metadata: [String: String]?
}

struct GoogleTasksPullResponse: Codable {
    var truncated: Bool? = nil
    let items: [GoogleTaskItemDTO]
    let cursor: String?
}

struct GoogleTaskPushRequest: Codable {
    var linkId: String? = nil
    var tasklistId: String? = nil   // direct mode (My Tasks ↔ default list)
    let title: String?
    let notes: String?
    let dueDate: String?        // RFC3339 date-only, null clears
    let completed: Bool?
    let remoteId: String?       // nil = insert
    let parentRemoteId: String? // nesting on insert
}

struct GoogleTaskPushResponse: Codable {
    let remoteId: String
    let remoteUpdatedAt: String?
}

// MARK: - API client surface

extension AstridAPIClient {
    func getGoogleAuthorizeURL() async throws -> GitHubAuthorizeResponse {
        try await request(method: "GET", path: "/api/v1/integrations/google/authorize")
    }

    func disconnectGoogle() async throws {
        struct Success: Codable { let success: Bool? }
        let _: Success = try await request(
            method: "DELETE", path: "/api/v1/integrations",
            queryItems: [URLQueryItem(name: "provider", value: "GOOGLE_TASKS")])
    }

    func getGoogleTasklists() async throws -> GoogleTasklistsResponse {
        try await request(method: "GET", path: "/api/v1/sync/google/tasklists")
    }

    func createGoogleTasklist(title: String) async throws -> GoogleTasklistDTO {
        struct Body: Codable { let title: String }
        struct Envelope: Codable { let tasklist: GoogleTasklistDTO }
        let envelope: Envelope = try await request(
            method: "POST", path: "/api/v1/sync/google/tasklists", body: Body(title: title))
        return envelope.tasklist
    }

    func getGoogleLinks(listId: String? = nil) async throws -> GitHubLinksResponse {
        try await request(method: "GET", path: "/api/v1/sync/google/links",
                          queryItems: listId.map { [URLQueryItem(name: "listId", value: $0)] })
    }

    func createGoogleLink(astridListId: String, tasklistId: String) async throws -> GitHubLinkResponse {
        try await request(method: "POST", path: "/api/v1/sync/google/links",
                          body: GitHubLinkCreateRequest(astridListId: astridListId, remoteContainerId: tasklistId))
    }

    func deleteGoogleLink(linkId: String) async throws {
        struct Success: Codable { let success: Bool? }
        let _: Success = try await request(
            method: "DELETE", path: "/api/v1/sync/google/links",
            queryItems: [URLQueryItem(name: "linkId", value: linkId)])
    }

    func pullGoogleTasks(linkId: String, full: Bool = false, deferCursor: Bool = false) async throws -> GoogleTasksPullResponse {
        var query = [URLQueryItem(name: "linkId", value: linkId)]
        if full { query.append(URLQueryItem(name: "full", value: "1")) }  // ignore + don't advance the cursor
        // Client-acknowledged cursor: server returns the cursor but doesn't
        // persist it; we commit after applying the pass (commitGoogleCursor).
        if deferCursor { query.append(URLQueryItem(name: "deferCursor", value: "1")) }
        return try await request(method: "GET", path: "/api/v1/sync/google/tasks", queryItems: query)
    }

    /// Persist the cursor the client just applied (client-acknowledged cursor).
    func commitGoogleCursor(linkId: String, cursor: String) async throws {
        struct Req: Codable { var action = "commitCursor"; let linkId: String; let cursor: String }
        struct Res: Codable { let ok: Bool? }
        let _: Res = try await request(method: "POST", path: "/api/v1/sync/google/tasks",
                                       body: Req(linkId: linkId, cursor: cursor))
    }

    /// Direct-tasklist pull (My Tasks ↔ Google default list — no list link row).
    func pullGoogleTasksDirect(tasklistId: String) async throws -> GoogleTasksPullResponse {
        try await request(method: "GET", path: "/api/v1/sync/google/tasks",
                          queryItems: [URLQueryItem(name: "tasklistId", value: tasklistId)])
    }

    func deleteGoogleTaskDirect(tasklistId: String, remoteId: String) async throws {
        struct Success: Codable { let success: Bool? }
        let _: Success = try await request(
            method: "DELETE", path: "/api/v1/sync/google/tasks",
            queryItems: [URLQueryItem(name: "tasklistId", value: tasklistId),
                         URLQueryItem(name: "remoteId", value: remoteId)])
    }

    func getGoogleTaskLinksByContainer(containerId: String) async throws -> GitHubTaskLinksResponse {
        try await request(method: "GET", path: "/api/v1/sync/google/task-links",
                          queryItems: [URLQueryItem(name: "containerId", value: containerId)])
    }

    func pushGoogleTask(_ body: GoogleTaskPushRequest) async throws -> GoogleTaskPushResponse {
        try await request(method: "POST", path: "/api/v1/sync/google/tasks", body: body)
    }

    func deleteGoogleTask(linkId: String, remoteId: String) async throws {
        struct Success: Codable { let success: Bool? }
        let _: Success = try await request(
            method: "DELETE", path: "/api/v1/sync/google/tasks",
            queryItems: [URLQueryItem(name: "linkId", value: linkId),
                         URLQueryItem(name: "remoteId", value: remoteId)])
    }

    func getGoogleTaskLinks(listId: String) async throws -> GitHubTaskLinksResponse {
        try await request(method: "GET", path: "/api/v1/sync/google/task-links",
                          queryItems: [URLQueryItem(name: "listId", value: listId)])
    }

    func upsertGoogleTaskLink(_ body: ExternalTaskLinkUpsertRequest) async throws {
        struct LinkEnvelope: Codable { let link: ExternalTaskLinkDTO }
        let _: LinkEnvelope = try await request(method: "PUT", path: "/api/v1/sync/google/task-links", body: body)
    }
}
