import Foundation

// Marked `nonisolated` so its Codable conformance is usable from nonisolated contexts —
// notably SSEClient's event decode, which runs off the main actor (AITD-320). The struct
// holds only value-type fields, so it is inherently thread-safe.
nonisolated struct User: Identifiable, Codable, Equatable, Hashable {
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
        // A single neutral glyph, not "??" — two question marks read as an error, and this is
        // simply a person (or agent) we have an id for and nothing else yet (42013da7).
        return email.map { String($0.prefix(2)).uppercased() } ?? "•"
    }

    /// Returns the avatar URL - AI agents have their logos stored in the image field
    var avatarURL: String? {
        return image
    }

    /// Local asset image name for AI agent brand icon, if available
    var agentBrandImageAsset: String? {
        guard isAIAgent == true else { return nil }
        return User.brandImageAsset(forAgentSlug: aiAgentType)
            ?? User.brandImageAsset(forAgentSlug: agentMailbox)
    }

    /// The local part of an agent identity address — `muse@astrid.cc` -> `muse`.
    ///
    /// This is the key web itself brands off (`lib/brand/agent-emails.ts`, and the `AGENT_ICONS`
    /// table behind `/api/v1/agent-icon/<slug>`), and it is the vocabulary `brandImageAsset`
    /// already speaks. `aiAgentType` is NOT: a locally polled harness arrives as the generic
    /// `local_harness_agent`, shared by Muse and Codex alike, so it can never name one mark
    /// (AITD-428 — Muse drew a placeholder in the list-settings picker on both platforms for
    /// exactly this reason). Scoped to `isAIAgent` rows, so a person whose address happens to
    /// look like an agent's never picks up a brand mark.
    var agentMailbox: String? {
        guard isAIAgent == true, let email, let at = email.firstIndex(of: "@") else { return nil }
        let mailbox = email[email.startIndex..<at].lowercased()
        return mailbox.isEmpty ? nil : mailbox
    }

    /// The one slug → bundled brand mark table. `aiAgentType` and the last path component of an
    /// `/api/v1/agent-icon/<slug>` URL speak the same vocabulary, so `AgentAvatarAsset` resolves
    /// through here too rather than keeping a second, shorter copy of the list (AITD-424 — the
    /// copy it kept knew only Copilot, so every other agent's avatar drew blank).
    static func brandImageAsset(forAgentSlug slug: String?) -> String? {
        switch slug {
        case "claude", "claude_agent": return "ai-claude"
        case "openai", "openai_agent": return "ai-openai"
        case "gemini", "gemini_agent": return "ai-gemini"
        case "copilot", "copilot_agent": return "ai-copilot"
        case "muse", "muse_agent": return "ai-muse"
        case "openclaw", "astrid": return "ai-openclaw"
        default: return nil
        }
    }
}
