import Foundation

extension AstridAPIClient {
    // MARK: - Project board rows (AWTD-1660, AITD-674)

    /// Which lists the caller's multi-list project board shows as rows, saved per person per
    /// project on the server. `listIds` is nil when nothing has been saved — the project's own lists.
    func getProjectBoardRows(projectId: String) async throws -> ProjectBoardRowsResponse {
        try await request(method: "GET", path: "/api/v1/projects/\(projectId)/board-rows")
    }

    /// Save the board's rows, in order. `[]` is a board emptied on purpose. The server refuses the
    /// whole write (403) when any list is one the caller cannot see.
    func putProjectBoardRows(projectId: String, listIds: [String]) async throws -> ProjectBoardRowsResponse {
        try await request(method: "PUT", path: "/api/v1/projects/\(projectId)/board-rows",
                          body: ProjectBoardRowsRequest(listIds: listIds))
    }
}
