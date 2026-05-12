import Foundation
import Combine
import CoreData

/// Project (status board) service. Mirrors the ListService pattern at
/// reduced scope: in-memory `projects`, Core Data cache, server-first
/// CRUD against /api/v1/projects.
///
/// Why no offline outbox for Phase B: project create/delete is a low-
/// frequency operation (a user creates a board, not 100s/min). The
/// Phase C board UI is online-only at launch. If offline-create becomes
/// a real need later, the `syncStatus` column on CDProject is already
/// in place and can be wired through an outbox identical to
/// `ListMemberService.syncPendingOperations`.
@MainActor
class ProjectService: ObservableObject {
    static let shared = ProjectService()

    @Published var projects: [Project] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiClient = AstridAPIClient.shared
    private let coreDataManager = CoreDataManager.shared

    private init() {
        loadCachedProjects()
    }

    // MARK: - Cache

    /// Synchronously hydrate `projects` from Core Data on startup so the
    /// UI has data available offline before any network call fires.
    private func loadCachedProjects() {
        do {
            let cached = try CDProject.fetchAll(context: coreDataManager.viewContext)
            self.projects = cached.map { $0.toDomainModel() }
        } catch {
            print("⚠️ [ProjectService] Failed to load cached projects: \(error)")
        }
    }

    private func saveProjectToCoreData(_ project: Project, syncStatus: String = "synced") {
        let context = coreDataManager.viewContext
        do {
            let cd: CDProject
            if let existing = try CDProject.fetchById(project.id, context: context) {
                cd = existing
            } else {
                cd = CDProject(context: context)
                cd.id = project.id
            }
            cd.update(from: project)
            cd.syncStatus = syncStatus
            cd.lastSyncedAt = Date()
            try context.save()
        } catch {
            print("⚠️ [ProjectService] Failed to save project to Core Data: \(error)")
        }
    }

    private func deleteProjectFromCoreData(_ id: String) {
        let context = coreDataManager.viewContext
        do {
            if let cd = try CDProject.fetchById(id, context: context) {
                context.delete(cd)
                try context.save()
            }
        } catch {
            print("⚠️ [ProjectService] Failed to delete cached project: \(error)")
        }
    }

    // MARK: - Server operations

    /// Pull every project the user can see, replace the in-memory cache,
    /// and write through to Core Data. Called by SyncManager during a
    /// full sync.
    @discardableResult
    func refreshFromServer() async throws -> [Project] {
        isLoading = true
        defer { isLoading = false }
        let fetched = try await apiClient.getProjects()
        self.projects = fetched

        // Reconcile Core Data: upsert new/updated, delete removed.
        let context = coreDataManager.viewContext
        let existing = (try? CDProject.fetchAll(context: context)) ?? []
        let serverIds = Set(fetched.map { $0.id })
        for cd in existing where !serverIds.contains(cd.id) {
            context.delete(cd)
        }
        for project in fetched {
            saveProjectToCoreData(project, syncStatus: "synced")
        }
        try? context.save()

        return fetched
    }

    /// Create a project + seed its status lists on the server, then
    /// reflect the new entity locally. iOS UI sees the project + lists
    /// instantly through the published `projects` array.
    @discardableResult
    func createProject(
        name: String,
        description: String? = nil,
        color: String? = nil,
        imageUrl: String? = nil
    ) async throws -> Project {
        let project = try await apiClient.createProject(
            name: name,
            description: description,
            color: color,
            imageUrl: imageUrl,
        )
        projects.insert(project, at: 0)
        saveProjectToCoreData(project, syncStatus: "synced")
        return project
    }

    /// Delete a project (owner only). On success, remove it from the
    /// in-memory cache and Core Data, and detach its domain lists.
    @discardableResult
    func deleteProject(id: String) async throws -> DeleteProjectResponse {
        let response = try await apiClient.deleteProject(id: id)
        projects.removeAll { $0.id == id }
        deleteProjectFromCoreData(id)
        return response
    }

    /// Look up a single project from the cache. The board UI uses this
    /// to resolve a project's status-list ordering when rendering.
    func project(id: String) -> Project? {
        projects.first { $0.id == id }
    }
}
