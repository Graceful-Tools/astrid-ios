//  OrchestrationPolicyService.swift
//  ADEV-333: the Canonical Control Point for a list's agent policy (web AWTD-1693). Reads the
//  list's view, stores the list's or the project's override, and keeps the last view per list for
//  the editor on both platforms. Every choice saves at once, as web's does.
//
//  astrid-core has no command for these, so the calls go to `AstridAPIClient` from here and
//  nowhere else (ASTRID.md §0 rule 1). A project write answers the project's view, so the list's is
//  read again afterwards to show what is now in effect on it.

import Combine
import Foundation

@MainActor
final class OrchestrationPolicyService: ObservableObject {
    static let shared = OrchestrationPolicyService()

    struct Calls: Sendable {
        var read: @Sendable (_ listId: String) async throws -> ListOrchestrationPolicyView
        var putList: @Sendable (_ listId: String, _ policy: PolicyDocument?) async throws -> ListOrchestrationPolicyView
        var putProject: @Sendable (_ projectId: String, _ policy: PolicyDocument?) async throws -> Void

        static let api = Calls(
            read: { try await AstridAPIClient.shared.getListOrchestrationPolicyView(listId: $0) },
            putList: { try await AstridAPIClient.shared.putListOrchestrationPolicy(listId: $0, policy: $1) },
            putProject: { try await AstridAPIClient.shared.putProjectOrchestrationPolicy(projectId: $0, policy: $1) })
    }

    /// The last view per list; a missing key means not read, or not readable.
    @Published private(set) var views: [String: ListOrchestrationPolicyView] = [:]
    /// The scope being saved for each list, so the editor disables while it writes.
    @Published private(set) var saving: [String: OrchestrationPolicyScope] = [:]

    private let calls: Calls

    init(calls: Calls = .api) {
        self.calls = calls
    }

    func view(listId: String) -> ListOrchestrationPolicyView? { views[listId] }

    /// Read it. A failure (an older server, no role on the list) leaves what was there.
    func load(listId: String) async {
        do {
            views[listId] = try await calls.read(listId)
        } catch {
            AppLog.debug("❌ [OrchestrationPolicy] load failed: \((error as NSError).localizedDescription)")
        }
    }

    /// Store one scope's override (`nil` clears it); true when the server took it.
    @discardableResult
    func save(listId: String, scope: OrchestrationPolicyScope, policy: PolicyDocument?) async -> Bool {
        guard let view = views[listId], view.canEdit(scope) else { return false }
        saving[listId] = scope
        defer { saving[listId] = nil }
        do {
            switch scope {
            case .list:
                views[listId] = try await calls.putList(listId, policy)
            case .project:
                guard let projectId = view.projectId else { return false }
                try await calls.putProject(projectId, policy)
                views[listId] = try await calls.read(listId)
            }
            return true
        } catch {
            AppLog.debug("❌ [OrchestrationPolicy] save failed: \((error as NSError).localizedDescription)")
            return false
        }
    }

    /// Forget everything — on sign-out.
    func clear() {
        views = [:]
        saving = [:]
    }
}
