import Foundation

// MARK: - Chat Channel

struct ChatChannel: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var listId: String?
    var virtualKey: String?
    var name: String?
    var createdAt: Date?
    var updatedAt: Date?
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable, Equatable, Hashable {
    var id: String  // Mutable to allow updating temp ID → real ID
    var channelId: String
    var authorId: String?  // Optional for system messages
    var author: User?
    var content: String
    var type: Comment.CommentType  // Reuse existing TEXT/MARKDOWN/ATTACHMENT enum
    var attachmentUrl: String?
    var attachmentName: String?
    var attachmentType: String?
    var attachmentSize: Int?
    var replyToId: String?
    var clientRequestId: String?
    var secureFiles: [SecureFile]?
    var createdAt: Date?
    var updatedAt: Date?

    /// Stable ID for SwiftUI ForEach - uses id if valid, otherwise generates from content hash
    var stableId: String {
        if !id.isEmpty {
            return id
        }
        // Fallback for corrupted data with empty IDs
        let contentHash = content.hashValue
        let dateHash = createdAt?.timeIntervalSince1970 ?? 0
        return "fallback_\(contentHash)_\(Int(dateHash))"
    }

    /// Whether this message was authored by an AI agent
    var isFromAgent: Bool {
        author?.isAIAgent == true
    }

    /// Whether this is a pending optimistic message not yet synced to server
    var isPending: Bool {
        id.hasPrefix("temp_")
    }
}
