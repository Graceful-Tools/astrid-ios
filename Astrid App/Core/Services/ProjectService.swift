import AstridCore
import Foundation
import Combine

/// The boards (projects) — through astrid-core.
///
/// The core caches every board, refreshes them on each sync pass (dropping one deleted
/// elsewhere), and makes and deletes them online: a board is a structure the server numbers and
/// seeds with its status columns, not a local fact. This service keeps the `projects` the board
/// views bind to and reads them back when the core says something moved.
@MainActor
class ProjectService: ObservableObject {
    static let shared = ProjectService()

    @Published var projects: [Project] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var core: CoreSession { AppCore.shared.session }

    private init() {
        // Boards draw their columns from these on the first frame, offline included.
        if let cached = try? core.runBlocking(CoreCommand(kind: "projects"), as: [Project].self) {
            projects = cached
        }
    }

    /// Read the cached boards again — after a sync pass, or anything the core could not describe.
    func coreDidChange(_ change: CoreChange) {
        switch change {
        // Not `.needsSync`: that asks for a pass, and the pass's own `.synced` brings the boards.
        case .synced, .delivered, .unknown:
            _Concurrency.Task { await self.reload() }
        default:
            break
        }
    }

    func reload() async {
        guard let cached = try? await core.run(CoreCommand(kind: "projects"), as: [Project].self),
              cached != projects else { return }
        projects = cached
    }

    // MARK: - Server operations

    /// Create a board; the server seeds its status columns.
    @discardableResult
    func createProject(
        name: String,
        description: String? = nil,
        color: String? = nil,
        imageUrl: String? = nil
    ) async throws -> Project {
        var command = CoreCommand(kind: "createProject", ["name": .value(name)])
        command.set("description", description)
        command.set("color", color)
        command.set("imageUrl", imageUrl)
        let project = try await core.run(command, as: Project.self)
        await reloadWithLists()
        return project
    }

    /// Build the PUT body that attaches an existing list to a newly-
    /// created project. Extracted as pure logic so a unit test can pin
    /// the field set without touching the network.
    /// Mirrors the web's `components/list-admin-settings.tsx`:
    ///   `body: JSON.stringify({ ...list, projectId, listType: 'regular' })`.
    static func buildAttachListRequest(projectId: String) -> UpdateListRequest {
        var body = UpdateListRequest()
        body.projectId = projectId
        return body
    }

    /// Create a project FOR a specific list, atomically: a single
    /// `POST /api/v1/projects/from-list` creates the project AND attaches the
    /// list in one server-side transaction. This replaces the old two-step
    /// (POST project, then PUT list) flow whose middle failure left an empty,
    /// same-named orphan project — root cause of the bug reported on 2026-05-12.
    /// The returned project's `lists` already contains the attached domain list
    /// (now `listType: regular`) plus the seeded status columns.
    @discardableResult
    func createBoardForList(_ list: TaskList) async throws -> Project {
        let project = try await core.run(
            CoreCommand(kind: "createBoardForList", ["listId": .value(list.id)]), as: Project.self)
        // The core cached the seeded columns and attached the list: without them the board has
        // no columns until the next pass, which reads as "Create Board didn't work".
        await reloadWithLists()
        return project
    }

    /// Delete a board (owner only). The core mirrors the server's cascade: its lists detached,
    /// kept; the status lists, which every board shares, untouched.
    @discardableResult
    func deleteProject(id: String) async throws -> DeleteProjectResponse {
        let response = try await core.run(
            CoreCommand(kind: "deleteProject", ["projectId": .value(id)]), as: DeleteProjectResponse.self)
        await reloadWithLists()
        return response
    }

    private func reloadWithLists() async {
        await reload()
        await ListService.shared.reload()
    }

    /// Look up a single project from the cache. The board UI uses this
    /// to resolve a project's status-list ordering when rendering.
    func project(id: String) -> Project? {
        projects.first { $0.id == id }
    }

    /// The custom board columns a project declares (AITD-379), or nil when the
    /// project is not in the cache yet.
    ///
    /// Nil and "no custom states" are deliberately the same answer here: both
    /// mean the board renders its defaults, which is the safe thing to show
    /// while the projects are still loading.
    func customStates(projectId: String?) -> [ProjectCustomState]? {
        guard let projectId else { return nil }
        return project(id: projectId)?.customStates
    }

    /// The custom board columns that apply to a task — those of the board it
    /// is on. Used by the state pickers, which are handed a task rather than a
    /// board; without this they would offer only the three defaults and
    /// disagree with the board about the same card (web's task 9ddf4a6f).
    func customStates(forTask task: Task, lists: [TaskList]) -> [ProjectCustomState]? {
        customStates(projectId: getProjectIdForTask(task, lists: lists))
    }
}
