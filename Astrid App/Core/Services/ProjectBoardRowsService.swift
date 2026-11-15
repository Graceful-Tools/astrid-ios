import Combine
import Foundation

/// The wire shape of `GET|PUT /api/v1/projects/{id}/board-rows` (astrid-web API_CONTRACT.md).
/// `listIds` is null on GET when nothing has been saved.
struct ProjectBoardRowsResponse: Codable, Equatable {
    let listIds: [String]?
}

struct ProjectBoardRowsRequest: Encodable {
    let listIds: [String]
}

/// Which lists each project board shows as rows (AITD-674, web AWTD-1660). The choice is saved per
/// person per project on the server, so every device shows the same rows.
///
/// Online-first, like web: it is a view preference rather than task data, so it doesn't go
/// through the Outbox. A save shows at once and goes back to the previous rows if the server
/// refuses it, with `saveFailed` set so the board can say so.
@MainActor
final class ProjectBoardRowsService: ObservableObject {
    static let shared = ProjectBoardRowsService()

    /// What each project has saved. A missing key means not loaded yet. A nil value means loaded
    /// with nothing saved, so the board shows the project's own lists.
    @Published private(set) var saved: [String: [String]?] = [:]
    /// The project whose last save failed, so its board can show the error.
    @Published var saveFailed: String?

    private let client: AstridAPIClient

    init(client: AstridAPIClient = .shared) {
        self.client = client
    }

    /// Whether `projectId` has an answer from the server yet.
    func isLoaded(_ projectId: String) -> Bool { saved.keys.contains(projectId) }

    /// The ids to draw for `projectId`, before resolving against the lists this client can see.
    func rowIds(projectId: String, lists: [TaskList]) -> [String] {
        ProjectBoardRows.resolve(saved: saved[projectId] ?? nil, projectId: projectId, lists: lists)
            .map(\.id)
    }

    /// Read the saved rows. Failure leaves what was there (the defaults on a first open).
    func load(projectId: String) async {
        do {
            let response = try await client.getProjectBoardRows(projectId: projectId)
            saved[projectId] = .some(response.listIds)
        } catch {
            AppLog.debug("❌ [ProjectBoardRows] load failed: \((error as NSError).localizedDescription)")
        }
    }

    func addRow(projectId: String, listId: String, lists: [TaskList]) async {
        let current = rowIds(projectId: projectId, lists: lists)
        guard current.count < ProjectBoardRows.maxRows else { return }
        await save(projectId: projectId, listIds: ProjectBoardRows.add(listId, to: current))
    }

    func removeRow(projectId: String, listId: String, lists: [TaskList]) async {
        let current = rowIds(projectId: projectId, lists: lists)
        await save(projectId: projectId, listIds: ProjectBoardRows.remove(listId, from: current))
    }

    /// Save `listIds` as the board's rows. Shows them at once, keeps the server's answer, and
    /// goes back to the previous rows if the write fails.
    func save(projectId: String, listIds: [String]) async {
        let previous = saved[projectId]
        saved[projectId] = .some(listIds)
        if saveFailed == projectId { saveFailed = nil }
        do {
            let response = try await client.putProjectBoardRows(projectId: projectId, listIds: listIds)
            saved[projectId] = .some(response.listIds ?? listIds)
        } catch {
            AppLog.debug("❌ [ProjectBoardRows] save failed: \((error as NSError).localizedDescription)")
            if let previous { saved[projectId] = previous } else { saved.removeValue(forKey: projectId) }
            saveFailed = projectId
        }
    }

    /// Forget everything — on sign-out.
    func clear() {
        saved = [:]
        saveFailed = nil
    }
}
