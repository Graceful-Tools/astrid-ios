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
        ["claude", "openai", "gemini", Self.defaultAssistantService].contains(service)
    }

    /// The `service` value the server uses for the default assistant identity.
    ///
    /// The assistant's email address is brand-derived on the server and can differ
    /// per deployment, so clients must identify it by `service` — never by matching
    /// its address. Task 97208a72.
    static let defaultAssistantService = "astrid"

    /// Whether this row is the default assistant rather than a specific model/provider.
    var isDefaultAssistant: Bool {
        service == Self.defaultAssistantService
    }

    /// Display-friendly service name
    var serviceDisplayName: String {
        switch service {
        case "claude": return "Claude"
        case "openai": return "OpenAI"
        case "gemini": return "Gemini"
        case "openclaw": return "OpenClaw"
        case Self.defaultAssistantService: return Brand.appName
        case "apple-fm": return "Apple Intelligence"
        default: return service.capitalized
        }
    }

    /// Local asset image name for the service brand icon, if available
    var serviceImageAsset: String? {
        switch service {
        case "claude": return "ai-claude"
        case "openai": return "ai-openai"
        case "gemini": return "ai-gemini"
        case "openclaw": return "ai-openclaw"
        default: return nil
        }
    }
}

// MARK: - All Built-in Models

/// Static list of all built-in model agents (shown even without API keys)
enum BuiltInModel: String, CaseIterable {
    case claude = "claude"
    case openai = "openai"
    case gemini = "gemini"

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        }
    }

    var subtitle: String {
        switch self {
        case .claude: return "Anthropic"
        case .openai: return "OpenAI"
        case .gemini: return "Google"
        }
    }

    var imageAsset: String {
        switch self {
        case .claude: return "ai-claude"
        case .openai: return "ai-openai"
        case .gemini: return "ai-gemini"
        }
    }
}
