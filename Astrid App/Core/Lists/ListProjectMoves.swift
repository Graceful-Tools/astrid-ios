import Foundation

/// What a list's "Project" control may offer (AITD-680, D68) — astrid-core's `listProjectMoves`
/// answer, decoded as it arrives. The core decides it; nothing here re-derives a permission.
///
/// - `canLeave`: the list may be taken out of the project it is in.
/// - `destinations`: the projects it may move into, its current one excluded, ordered by name.
/// - `creatableIn`: the projects a new list may be created in.
nonisolated struct ListProjectMoves: Decodable, Equatable, Sendable {
    var canLeave: Bool
    var destinations: [String]
    var creatableIn: [String]

    static let none = ListProjectMoves(canLeave: false, destinations: [], creatableIn: [])

    /// One move a control can offer, already in the core's order.
    enum Choice: Equatable, Hashable {
        case moveTo(projectId: String, name: String)
        case removeFromProject
    }

    /// The moves to draw, named from `projects`. A destination the cache has no project for is
    /// dropped rather than drawn as a bare id; the order is the core's (by name).
    func choices(projects: [Project]) -> [Choice] {
        let names = Dictionary(projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var choices: [Choice] = destinations.compactMap { id in
            names[id].map { .moveTo(projectId: id, name: $0) }
        }
        if canLeave { choices.append(.removeFromProject) }
        return choices
    }

    /// The projects a new list may be born in, named, in the core's order.
    func creatable(projects: [Project]) -> [Project] {
        let byId = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return creatableIn.compactMap { byId[$0] }
    }
}
