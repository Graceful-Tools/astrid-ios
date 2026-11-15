import AstridCore
import Combine
import Foundation

/// Which lists each project board shows as rows (AITD-674, web AWTD-1660), answered by astrid-core
/// (AITD-676, core AWTD-1676). The choice is saved per person per project on the server, so every
/// device shows the same rows.
///
/// The core does the reading, the arithmetic and the saving: `projectBoardRows` answers which
/// lists are rows, which could be added and whether one more fits, and keeps its last answer for
/// offline (`fromCache`). `saveProjectBoardRows` adds, removes or replaces. Saving is online only,
/// like web: it is a view preference rather than task data, so it doesn't go through the Outbox.
/// A save shows at once and goes back to the previous rows if the core refuses it, with
/// `saveFailed` set so the board can say so.
@MainActor
final class ProjectBoardRowsService: ObservableObject {
    static let shared = ProjectBoardRowsService()

    /// The core's answer for one project board.
    nonisolated struct Answer: Equatable, Decodable, Sendable {
        let projectId: String
        /// What the server has saved; nil when nothing has been, so the project's own lists draw.
        let savedListIds: [String]?
        /// The rows to draw, in order.
        let rowListIds: [String]
        /// What *Add list* offers, sorted by name.
        let candidateListIds: [String]
        /// Whether one more row fits.
        let canAddRow: Bool
        /// The core served its last kept answer because the server could not be reached.
        let fromCache: Bool
    }

    /// Each project's last answer. A missing key means not loaded yet.
    @Published private(set) var answers: [String: Answer] = [:]
    /// The project whose last save failed, so its board can show the error.
    @Published var saveFailed: String?

    private let run: @Sendable (CoreCommand) async throws -> Answer

    /// - Parameter run: how to ask the core; the app's own session by default.
    init(run: (@Sendable (CoreCommand) async throws -> Answer)? = nil) {
        self.run = run ?? { command in
            try await AppCore.shared.session.run(command, as: Answer.self)
        }
    }

    /// Whether `projectId` has an answer yet.
    func isLoaded(_ projectId: String) -> Bool { answers.keys.contains(projectId) }

    /// The lists to draw as rows for `projectId`, in order; empty until the first answer.
    func rowIds(projectId: String) -> [String] { answers[projectId]?.rowListIds ?? [] }

    /// What *Add list* offers for `projectId`.
    func candidateIds(projectId: String) -> [String] { answers[projectId]?.candidateListIds ?? [] }

    /// Whether one more row fits on `projectId`'s board.
    func canAddRow(projectId: String) -> Bool { answers[projectId]?.canAddRow ?? false }

    /// Read the rows. Failure leaves what was there.
    func load(projectId: String) async {
        var command = CoreCommand(kind: "projectBoardRows")
        command.set("projectId", projectId)
        do {
            answers[projectId] = try await run(command)
        } catch {
            AppLog.debug("❌ [ProjectBoardRows] load failed: \((error as NSError).localizedDescription)")
        }
    }

    func addRow(projectId: String, listId: String) async {
        let current = rowIds(projectId: projectId)
        guard !current.contains(listId) else { return }
        await save(projectId: projectId, field: "addListId", value: listId, showing: current + [listId])
    }

    func removeRow(projectId: String, listId: String) async {
        let current = rowIds(projectId: projectId)
        await save(projectId: projectId, field: "removeListId", value: listId,
                   showing: current.filter { $0 != listId })
    }

    /// Save `listIds` as the board's rows, in order.
    func save(projectId: String, listIds: [String]) async {
        await save(projectId: projectId, field: "listIds", value: listIds, showing: listIds)
    }

    /// Shows `showing` at once, keeps the core's answer, and goes back to the previous rows if the
    /// save fails.
    private func save(projectId: String, field: String, value: some Encodable & Sendable,
                      showing: [String]) async {
        let previous = answers[projectId]
        if let previous {
            answers[projectId] = Answer(projectId: projectId, savedListIds: showing, rowListIds: showing,
                                        candidateListIds: previous.candidateListIds.filter { !showing.contains($0) },
                                        canAddRow: previous.canAddRow, fromCache: previous.fromCache)
        }
        if saveFailed == projectId { saveFailed = nil }
        var command = CoreCommand(kind: "saveProjectBoardRows")
        command.set("projectId", projectId)
        command.set(field, value)
        do {
            answers[projectId] = try await run(command)
        } catch {
            AppLog.debug("❌ [ProjectBoardRows] save failed: \((error as NSError).localizedDescription)")
            if let previous { answers[projectId] = previous } else { answers.removeValue(forKey: projectId) }
            saveFailed = projectId
        }
    }

    /// Forget everything — on sign-out.
    func clear() {
        answers = [:]
        saveFailed = nil
    }
}
