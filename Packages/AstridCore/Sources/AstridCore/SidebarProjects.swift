import Foundation

/// The sidebar's Projects section, asked of astrid-core's `sidebar` rule (core `886817e`,
/// AWTD-1681, D70; ADEV-16). Which projects are rows, their order, and which lists sit under each
/// are the core's answer, not a Swift grouping: a list sits under the project its own `projectId`
/// names, only domain lists count, projects and their lists are ordered by name.

/// One list as the rule reads it: what decides whether it is a place and which project holds it.
public struct SidebarListInput: Encodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let projectId: String?
    public let listType: String?

    public init(id: String, name: String, projectId: String?, listType: String?) {
        self.id = id
        self.name = name
        self.projectId = projectId
        self.listType = listType
    }
}

/// One project the reader can see. `key` names a project whose name is empty.
public struct SidebarProjectInput: Encodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let key: String?
    public let color: String?

    public init(id: String, name: String, key: String?, color: String?) {
        self.id = id
        self.name = name
        self.key = key
        self.color = color
    }
}

/// One row of the Projects section: the project, and the ids of its lists in drawing order.
public struct SidebarProjectRow: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let color: String
    public let listIds: [String]

    public init(id: String, name: String, color: String, listIds: [String]) {
        self.id = id
        self.name = name
        self.color = color
        self.listIds = listIds
    }

    private enum CodingKeys: String, CodingKey { case id, name, color, lists }
    private struct ListId: Decodable { let id: String }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? ""
        listIds = try container.decodeIfPresent([ListId].self, forKey: .lists)?.map(\.id) ?? []
    }
}

extension CoreRules {
    /// The Projects section, or nil when none is drawn: Project Mode is off (`projects` nil), the
    /// reader sees no projects, or the core could not answer.
    public static func sidebarProjects(lists: [SidebarListInput],
                                       projects: [SidebarProjectInput]?) -> [SidebarProjectRow]? {
        (try? ask(SidebarRequest(lists: lists, projects: projects), as: SidebarAnswer.self))?.projects
    }
}

private struct SidebarRequest: Encodable {
    let kind = "sidebar"
    let lists: [SidebarListInput]
    let projects: [SidebarProjectInput]?

    private enum CodingKeys: String, CodingKey { case kind, lists, projects }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(lists, forKey: .lists)
        // `null`, never omitted: the rule reads absent and null alike, but say it on purpose.
        try container.encode(projects, forKey: .projects)
    }
}

private struct SidebarAnswer: Decodable {
    let projects: [SidebarProjectRow]?
}
