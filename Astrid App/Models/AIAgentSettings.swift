import Foundation

// MARK: - AI Assistant Settings

struct AIAssistantSettings: Codable {
    var defaultAgentId: String?
    var preferredService: String?

    /// Whether the selected model is an on-device model (no API key / server needed)
    var isOnDeviceModel: Bool {
        defaultAgentId == kAppleFoundationModelId
    }
}

// MARK: - Available Agent

struct AvailableAgent: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let email: String
    let image: String?
    let service: String  // "claude", "openai", "gemini", "openclaw", "astrid"

    /// Whether this is a built-in service agent (vs OpenClaw/custom)
    var isBuiltIn: Bool {
        ["claude", "openai", "gemini", "astrid"].contains(service)
    }

    /// Display-friendly service name
    var serviceDisplayName: String {
        switch service {
        case "claude": return "Claude"
        case "openai": return "OpenAI"
        case "gemini": return "Gemini"
        case "openclaw": return "OpenClaw"
        case "astrid": return "Astrid"
        case "apple-fm": return "Apple Intelligence"
        default: return service.capitalized
        }
    }
}
