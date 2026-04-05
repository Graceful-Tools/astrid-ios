import Foundation

struct User: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let email: String? // Optional: admins in public lists API may not include email
    var name: String?
    var image: String?
    var createdAt: Date?
    var defaultDueTime: String? // HH:MM format
    var isPending: Bool?
    var isAIAgent: Bool?
    var aiAgentType: String?

    enum CodingKeys: String, CodingKey {
        case id, email, name, image, createdAt, defaultDueTime
        case isPending, isAIAgent, aiAgentType
    }

    var displayName: String {
        name ?? email ?? "Unknown User"
    }

    var initials: String {
        if let name = name {
            let components = name.split(separator: " ")
            if components.count >= 2 {
                return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
            } else {
                return String(name.prefix(2)).uppercased()
            }
        }
        return email.map { String($0.prefix(2)).uppercased() } ?? "??"
    }

    /// Returns the avatar URL - AI agents have their logos stored in the image field
    var avatarURL: String? {
        return image
    }

    /// Local asset image name for AI agent brand icon, if available
    var agentBrandImageAsset: String? {
        guard isAIAgent == true else { return nil }
        switch aiAgentType {
        case "claude", "claude_agent": return "ai-claude"
        case "openai", "openai_agent": return "ai-openai"
        case "gemini", "gemini_agent": return "ai-gemini"
        case "openclaw", "astrid": return "ai-openclaw"
        default: return nil
        }
    }
}
