//  ProjectDecisionsService.swift
//  ADEV-189 (web ADEV-180): a project's decisions. A decision is a task whose description holds a
//  `**Decision:**` and its trade-off grid, so it has an assignee, lanes and the agent handoff
//  already; this lists them, starts one from the project's goals, and records the choice.
//
//  `GET|POST /api/v1/projects/{id}/decisions`, `POST …/decisions/{taskId}/decide` (astrid-web
//  docs/API_CONTRACT.md). The server builds a new decision's grid and writes the decided record, so
//  neither is copied here. Online only, like the goals: it is project metadata. Editing the grid is
//  an ordinary description edit through `TaskService`, which keeps the Outbox.

import Combine
import Foundation

nonisolated struct ProjectDecision: Codable, Equatable, Identifiable, Sendable {
    struct Option: Codable, Equatable, Hashable, Sendable {
        let number: Int
        let text: String
        var recommended: Bool = false

        private enum CodingKeys: String, CodingKey { case number, text, recommended }

        init(number: Int, text: String, recommended: Bool = false) {
            self.number = number
            self.text = text
            self.recommended = recommended
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            number = try c.decode(Int.self, forKey: .number)
            text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
            recommended = try c.decodeIfPresent(Bool.self, forKey: .recommended) ?? false
        }
    }

    struct Chosen: Codable, Equatable, Sendable {
        let number: Int
        let text: String
    }

    let id: String
    var identifier: String?
    var title: String
    /// The question the Decision asks.
    var prompt: String
    var options: [Option]
    /// `open` or `decided`; anything newer reads as open.
    var status: String
    var chosen: Chosen?

    var isDecided: Bool { chosen != nil || status == "decided" }

    init(id: String, identifier: String? = nil, title: String, prompt: String, options: [Option],
         status: String = "open", chosen: Chosen? = nil) {
        self.id = id
        self.identifier = identifier
        self.title = title
        self.prompt = prompt
        self.options = options
        self.status = status
        self.chosen = chosen
    }

    private enum CodingKeys: String, CodingKey { case id, identifier, title, prompt, options, status, chosen }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        identifier = try c.decodeIfPresent(String.self, forKey: .identifier)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        options = try c.decodeIfPresent([Option].self, forKey: .options) ?? []
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "open"
        chosen = try c.decodeIfPresent(Chosen.self, forKey: .chosen)
    }
}

nonisolated struct ProjectDecisionsResponse: Codable, Sendable {
    let decisions: [ProjectDecision]
}

nonisolated struct NewProjectDecisionRequest: Codable, Equatable, Sendable {
    var title: String?
}

nonisolated struct NewProjectDecisionResponse: Codable, Sendable {
    struct CreatedTask: Codable, Sendable {
        let id: String
        let identifier: String?
        let title: String
    }
    let task: CreatedTask
}

nonisolated struct DecideProjectDecisionRequest: Codable, Equatable, Sendable {
    let option: Int
}

nonisolated struct DecideProjectDecisionResponse: Codable, Sendable {
    let chosen: ProjectDecision.Chosen
}

/// Each project's decisions, as last read.
@MainActor
final class ProjectDecisionsService: ObservableObject {
    static let shared = ProjectDecisionsService()

    typealias Fetch = @Sendable (String) async throws -> [ProjectDecision]
    typealias Create = @Sendable (String, NewProjectDecisionRequest) async throws -> NewProjectDecisionResponse
    typealias Decide = @Sendable (String, String, Int) async throws -> ProjectDecision.Chosen

    /// A missing key means not loaded yet.
    @Published private(set) var byProject: [String: [ProjectDecision]] = [:]

    private let fetch: Fetch
    private let createRequest: Create
    private let decideRequest: Decide

    /// - Parameters: how to read and write; the app's API client by default.
    init(fetch: Fetch? = nil, create: Create? = nil, decide: Decide? = nil) {
        self.fetch = fetch ?? { try await AstridAPIClient.shared.getProjectDecisions(projectId: $0).decisions }
        self.createRequest = create ?? { try await AstridAPIClient.shared.createProjectDecision(projectId: $0, $1) }
        self.decideRequest = decide ?? {
            try await AstridAPIClient.shared.decideProjectDecision(projectId: $0, taskId: $1, option: $2).chosen
        }
    }

    func decisions(projectId: String) -> [ProjectDecision]? { byProject[projectId] }

    /// Read them. Failure leaves what was there; true when the server answered.
    @discardableResult
    func load(projectId: String) async -> Bool {
        do {
            byProject[projectId] = Self.ordered(try await fetch(projectId))
            return true
        } catch {
            AppLog.debug("❌ [ProjectDecisions] load failed: \((error as NSError).localizedDescription)")
            return false
        }
    }

    /// Start one from the project's goals; the new task's id, or nil when the server refused.
    /// The list is read again so the new decision is in it.
    func create(projectId: String, title: String?) async -> String? {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let created = try await createRequest(projectId, NewProjectDecisionRequest(
                title: trimmed?.isEmpty == false ? trimmed : nil))
            await load(projectId: projectId)
            return created.task.id
        } catch {
            AppLog.debug("❌ [ProjectDecisions] create failed: \((error as NSError).localizedDescription)")
            return nil
        }
    }

    /// Record `option` as chosen; true when the server took it. The cached decision moves to the
    /// decided ones at once.
    @discardableResult
    func decide(projectId: String, decisionId: String, option: Int) async -> Bool {
        do {
            let chosen = try await decideRequest(projectId, decisionId, option)
            if var list = byProject[projectId], let i = list.firstIndex(where: { $0.id == decisionId }) {
                list[i].chosen = chosen
                list[i].status = "decided"
                byProject[projectId] = Self.ordered(list)
            }
            return true
        } catch {
            AppLog.debug("❌ [ProjectDecisions] decide failed: \((error as NSError).localizedDescription)")
            return false
        }
    }

    /// Open first, each group in the server's order (newest first).
    static func ordered(_ decisions: [ProjectDecision]) -> [ProjectDecision] {
        decisions.filter { !$0.isDecided } + decisions.filter(\.isDecided)
    }

    /// Forget everything — on sign-out.
    func clear() { byProject = [:] }
}
