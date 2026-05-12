import Foundation

/// A project (status board). Mirrors `Project` in `types/task.ts` and the
/// `V1Project` shape served by `/api/v1/projects` on the web.
///
/// A board exists when `projectId` is set on a `TaskList`. The project
/// holds shared metadata + members; its `lists` array contains both
/// regular (domain) lists and status lists (one per board column).
/// Inbox and Done remain virtual columns derived from task state and are
/// never stored. See `docs/product/project-status-board.md` (astrid-web).
struct Project: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var description: String?
    var color: String?
    var imageUrl: String?
    var ownerId: String?
    var owner: User?
    var members: [ProjectMember]?
    var lists: [TaskList]?
    var createdAt: Date?
    var updatedAt: Date?

    init(
        id: String,
        name: String,
        description: String? = nil,
        color: String? = nil,
        imageUrl: String? = nil,
        ownerId: String? = nil,
        owner: User? = nil,
        members: [ProjectMember]? = nil,
        lists: [TaskList]? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.color = color
        self.imageUrl = imageUrl
        self.ownerId = ownerId
        self.owner = owner
        self.members = members
        self.lists = lists
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayColor: String {
        color ?? "#3b82f6"
    }
}

struct ProjectMember: Identifiable, Codable, Equatable, Hashable {
    var id: String
    let projectId: String?
    let userId: String
    let role: String
    var createdAt: Date?
    var updatedAt: Date?
    var user: User?

    init(
        id: String,
        projectId: String? = nil,
        userId: String,
        role: String,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        user: User? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.userId = userId
        self.role = role
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.user = user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.role = try container.decode(String.self, forKey: .role)
        self.projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        self.user = try container.decodeIfPresent(User.self, forKey: .user)
        // Embedded responses may omit `id`; fall back to userId so the
        // struct stays Identifiable.
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? userId
    }

    private enum CodingKeys: String, CodingKey {
        case id, projectId, userId, role, createdAt, updatedAt, user
    }
}
