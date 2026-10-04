import Foundation

// MARK: - Google Tasks connection and links (mirror astrid-web /api/v1/sync/google)
//
// The pass's own reads and writes (tasks, task links) are astrid-core's since AITD-463.

struct GoogleTasklistDTO: Codable, Identifiable, Equatable {
    let id: String
    let name: String
}

struct GoogleTasklistsResponse: Codable {
    let tasklists: [GoogleTasklistDTO]
    /// The default list's real id — maps to Astrid's My Tasks (unlisted).
    var defaultId: String? = nil
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
}
