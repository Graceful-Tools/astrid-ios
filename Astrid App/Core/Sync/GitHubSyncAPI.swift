import Foundation

// MARK: - GitHub sync proxy DTOs (mirror astrid-web /api/v1/sync/github)

struct SyncIntegrationDTO: Codable {
    let provider: String
    let externalAccountId: String?
    let metadata: Metadata?

    /// Known per-provider settings stored server-side (cross-device); unknown
    /// keys in the JSON are ignored.
    struct Metadata: Codable {
        let googleSyncMode: String?
        let listSuffix: String?
        let excludedTasklists: String?     // comma-joined tasklist ids
        let tombstonedRemoteIds: String?   // comma-joined remote ids deleted server-side
    }
}

struct SyncIntegrationsResponse: Codable {
    let integrations: [SyncIntegrationDTO]
}

struct GitHubAuthorizeResponse: Codable {
    let url: String
}

struct GitHubRepoDTO: Codable, Identifiable, Equatable {
    let id: String    // "owner/repo"
    let name: String
    let `private`: Bool?
}

struct GitHubReposResponse: Codable {
    let repos: [GitHubRepoDTO]
}

struct ExternalListLinkDTO: Codable, Identifiable, Equatable {
    let id: String
    let astridListId: String
    let remoteContainerId: String
    let remoteContainerName: String?
    let cursor: String?
}

struct GitHubLinksResponse: Codable {
    let links: [ExternalListLinkDTO]
}

struct GitHubLinkResponse: Codable {
    let link: ExternalListLinkDTO
}

/// Provider-neutral remote item as the proxy returns it (dates as ISO strings).
struct GitHubIssueItemDTO: Codable, Equatable {
    let remoteId: String        // "owner/repo#123"
    let title: String
    let notes: String?
    let completed: Bool
    var completedAt: String? = nil   // GitHub closed_at
    let remoteUpdatedAt: String
    let metadata: [String: String]?
}

struct GitHubCommentDTO: Codable, Equatable {
    let id: String
    let body: String
    let author: String
    let createdAt: String
}

struct GitHubCommentsResponse: Codable {
    let comments: [GitHubCommentDTO]
}

struct GitHubIssuesPullResponse: Codable {
    /// Server flags an incomplete (page-capped) listing — absence-based
    /// deletion must be skipped. Missing (old server) = treat as truncated.
    var truncated: Bool? = nil
    let items: [GitHubIssueItemDTO]
    let cursor: String?
}

struct GitHubIssuePushResponse: Codable {
    let remoteId: String
    let remoteUpdatedAt: String?
}

struct ExternalTaskLinkDTO: Codable, Equatable {
    let astridTaskId: String
    let remoteId: String
    let remoteContainerId: String
    let astridUpdatedAt: Date?
    let remoteUpdatedAt: Date?
    let metadata: [String: String]?
}

struct GitHubTaskLinksResponse: Codable {
    let links: [ExternalTaskLinkDTO]
}

// MARK: - Request bodies

struct GitHubLinkCreateRequest: Codable {
    let astridListId: String
    let remoteContainerId: String
}

struct GitHubIssuePushRequest: Codable {
    let linkId: String
    let title: String?
    let body: String?
    let state: String?              // "open" | "closed"
    let remoteId: String?           // nil = create
    var parentRemoteId: String? = nil  // create as a sub-issue of this issue
    var assigneeUserId: String? = nil  // Astrid assignee → GitHub login (server resolves)
}

struct ExternalTaskLinkUpsertRequest: Codable {
    let astridTaskId: String
    let remoteId: String
    let remoteContainerId: String
    let astridUpdatedAt: Date?
    let remoteUpdatedAt: String?
    let metadata: [String: String]?
}

// MARK: - API client surface

private struct SyncSuccessResponse: Codable { let success: Bool? }

extension AstridAPIClient {
    func getSyncIntegrations() async throws -> SyncIntegrationsResponse {
        try await request(method: "GET", path: "/api/v1/integrations")
    }

    /// Merge per-provider sync settings into Integration.metadata (server-side,
    /// so they follow the account across devices).
    func updateIntegrationMetadata(provider: String, metadata: [String: String]) async throws {
        struct Body: Codable { let provider: String; let metadata: [String: String] }
        struct Success: Codable { let success: Bool? }
        let _: Success = try await request(
            method: "PATCH", path: "/api/v1/integrations",
            body: Body(provider: provider, metadata: metadata))
    }

    func getGitHubAuthorizeURL() async throws -> GitHubAuthorizeResponse {
        try await request(method: "GET", path: "/api/v1/integrations/github/authorize")
    }

    func disconnectGitHub() async throws {
        let _: SyncSuccessResponse = try await request(
            method: "DELETE", path: "/api/v1/integrations",
            queryItems: [URLQueryItem(name: "provider", value: "GITHUB_ISSUES")])
    }

    func getGitHubRepos() async throws -> GitHubReposResponse {
        try await request(method: "GET", path: "/api/v1/sync/github/repos")
    }

    func getGitHubLinks(listId: String? = nil) async throws -> GitHubLinksResponse {
        try await request(method: "GET", path: "/api/v1/sync/github/links",
                          queryItems: listId.map { [URLQueryItem(name: "listId", value: $0)] })
    }

    func createGitHubLink(astridListId: String, repo: String) async throws -> GitHubLinkResponse {
        try await request(method: "POST", path: "/api/v1/sync/github/links",
                          body: GitHubLinkCreateRequest(astridListId: astridListId, remoteContainerId: repo))
    }

    func deleteGitHubLink(linkId: String) async throws {
        let _: SyncSuccessResponse = try await request(
            method: "DELETE", path: "/api/v1/sync/github/links",
            queryItems: [URLQueryItem(name: "linkId", value: linkId)])
    }

    func pullGitHubIssues(linkId: String, full: Bool = false, deferCursor: Bool = false) async throws -> GitHubIssuesPullResponse {
        var query = [URLQueryItem(name: "linkId", value: linkId)]
        if full { query.append(URLQueryItem(name: "full", value: "1")) }  // ignore + don't advance the cursor
        if deferCursor { query.append(URLQueryItem(name: "deferCursor", value: "1")) }
        return try await request(method: "GET", path: "/api/v1/sync/github/issues", queryItems: query)
    }

    /// Persist the cursor the client just applied (client-acknowledged cursor).
    func commitGitHubCursor(linkId: String, cursor: String) async throws {
        struct Req: Codable { let action = "commitCursor"; let linkId: String; let cursor: String }
        struct Res: Codable { let ok: Bool? }
        let _: Res = try await request(method: "POST", path: "/api/v1/sync/github/issues",
                                       body: Req(linkId: linkId, cursor: cursor))
    }

    func pushGitHubIssue(_ body: GitHubIssuePushRequest) async throws -> GitHubIssuePushResponse {
        try await request(method: "POST", path: "/api/v1/sync/github/issues", body: body)
    }

    func getGitHubIssueComments(linkId: String, remoteId: String) async throws -> GitHubCommentsResponse {
        try await request(method: "GET", path: "/api/v1/sync/github/comments",
                          queryItems: [URLQueryItem(name: "linkId", value: linkId),
                                       URLQueryItem(name: "remoteId", value: remoteId)])
    }

    func createGitHubIssueComment(linkId: String, remoteId: String, body: String) async throws -> String {
        struct Body: Codable { let linkId: String; let remoteId: String; let body: String }
        struct Response: Codable { let id: String }
        let response: Response = try await request(
            method: "POST", path: "/api/v1/sync/github/comments",
            body: Body(linkId: linkId, remoteId: remoteId, body: body))
        return response.id
    }

    func updateGitHubIssueComment(linkId: String, commentId: String, body: String) async throws {
        struct Body: Codable { let linkId: String; let commentId: String; let body: String }
        struct Response: Codable { let id: String? }
        let _: Response = try await request(
            method: "PATCH", path: "/api/v1/sync/github/comments",
            body: Body(linkId: linkId, commentId: commentId, body: body))
    }

    func deleteGitHubIssueComment(linkId: String, commentId: String) async throws {
        struct Success: Codable { let success: Bool? }
        let _: Success = try await request(
            method: "DELETE", path: "/api/v1/sync/github/comments",
            queryItems: [URLQueryItem(name: "linkId", value: linkId),
                         URLQueryItem(name: "commentId", value: commentId)])
    }

    func getGitHubTaskLinks(listId: String) async throws -> GitHubTaskLinksResponse {
        try await request(method: "GET", path: "/api/v1/sync/github/task-links",
                          queryItems: [URLQueryItem(name: "listId", value: listId)])
    }

    func upsertGitHubTaskLink(_ body: ExternalTaskLinkUpsertRequest) async throws {
        struct LinkEnvelope: Codable { let link: ExternalTaskLinkDTO }
        let _: LinkEnvelope = try await request(method: "PUT", path: "/api/v1/sync/github/task-links", body: body)
    }

    /// Additive v1 operation. GET/PUT remain unchanged for older app builds.
    func deleteGitHubTaskLink(astridTaskId: String, remoteId: String) async throws {
        struct Response: Codable { let success: Bool; let detached: Bool }
        let _: Response = try await request(
            method: "DELETE", path: "/api/v1/sync/github/task-links",
            queryItems: [
                URLQueryItem(name: "astridTaskId", value: astridTaskId),
                URLQueryItem(name: "remoteId", value: remoteId),
            ])
    }
}
