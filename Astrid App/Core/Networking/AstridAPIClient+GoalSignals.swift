//  AstridAPIClient+GoalSignals.swift
//  The goal-signals writes astrid-core does not have yet: asking for an estimate (ADEV-329, web
//  ADEV-278), experiments on a task and the Pending results preset column (ADEV-330, web
//  ADEV-279/282), and asking for a gated feature. Called only by `GoalSignalsService` (ASTRID.md §0
//  rule 1); every read after them goes back through the core.

import Foundation

extension AstridAPIClient {
    /// Ask an estimator for an estimate of a task: 201 with it, or 202 `{ pending: true }` while a
    /// service works. Called only by `GoalSignalsService`; the core has no write for it yet.
    func requestTaskEstimate(taskId: String, estimator: String, projectId: String?) async throws -> EstimateRequestReply {
        struct Body: Encodable { let estimator: String; let projectId: String? }
        return try await request(method: "POST", path: "/api/v1/tasks/\(taskId)/estimates",
                                 body: Body(estimator: estimator, projectId: projectId))
    }

    /// Ask for a gated feature (`featureKey`); asking twice updates the one request.
    func requestFeatureAccess(featureKey: String) async throws {
        struct Body: Encodable { let featureKey: String }
        let _: EmptyResponse = try await request(method: "POST", path: "/api/v1/feature-requests",
                                                 body: Body(featureKey: featureKey))
    }

    /// Link an experiment, or start a verification window (ADEV-330). Only `GoalSignalsService`.
    func linkTaskExperiment(taskId: String, body: ExperimentLinkRequest.Body) async throws {
        let _: EmptyResponse = try await request(method: "POST", path: "/api/v1/tasks/\(taskId)/experiment", body: body)
    }

    func unlinkTaskExperiment(taskId: String, experimentId: String) async throws {
        let _: EmptyResponse = try await request(method: "DELETE", path: "/api/v1/tasks/\(taskId)/experiment",
                                                 queryItems: [URLQueryItem(name: "experimentId", value: experimentId)])
    }

    /// Read every open experiment on the task now; a task in Pending results may settle.
    func refreshTaskExperiments(taskId: String) async throws {
        let _: EmptyResponse = try await request(method: "POST", path: "/api/v1/tasks/\(taskId)/experiment/refresh")
    }

    /// A project's connectors (owner or admin only).
    func getProjectConnectors(projectId: String) async throws -> [ProjectConnector] {
        struct Response: Codable { let connectors: [ProjectConnector]? }
        let response: Response = try await request(method: "GET", path: "/api/v1/projects/\(projectId)/connectors")
        return response.connectors ?? []
    }

    /// Add an optional preset column to a board (its owner only).
    func addProjectPresetColumn(projectId: String, preset: String) async throws {
        struct Body: Encodable { let preset: String }
        let _: EmptyResponse = try await request(method: "POST", path: "/api/v1/projects/\(projectId)/statuses",
                                                 body: Body(preset: preset))
    }
}
