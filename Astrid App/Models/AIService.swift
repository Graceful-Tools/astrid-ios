//  AIService.swift
//  The built-in AI providers whose credentials "Astrid runs it" needs. Shared by the iOS and
//  Mac Agent Hubs (AITD-297); formerly declared inside the iOS key-manager view.

import Foundation

enum AIService: String, CaseIterable, Identifiable {
    case claude = "claude"
    case openai = "openai"
    case gemini = "gemini"
    case copilot = "copilot"
    /// Meta's Model API (Muse Spark), AITD-449 / web AWTD-1053.
    case muse = "muse"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .openai: return "OpenAI"
        case .gemini: return "Google Gemini"
        case .copilot: return "GitHub Copilot"
        case .muse: return "Muse (Meta)"
        }
    }

    var description: String {
        switch self {
        case .claude: return "Claude AI for task assistance and coding"
        case .openai: return "GPT-4 for task assistance and coding"
        case .gemini: return "Gemini for task assistance and coding"
        case .copilot: return "GitHub Copilot (OpenAI-compatible; requires an active Copilot subscription token)"
        case .muse: return "Muse Spark for task assistance and coding (Meta Model API key)"
        }
    }

    var imageAsset: String {
        switch self {
        case .claude: return "ai-claude"
        case .openai: return "ai-openai"
        case .gemini: return "ai-gemini"
        case .copilot: return "ai-copilot"   // no bundled asset → falls back to fallbackSystemIcon
        case .muse: return "ai-muse"
        }
    }

    /// SF Symbol used when `imageAsset` is not a bundled image (keeps the row from showing blank).
    var fallbackSystemIcon: String {
        switch self {
        case .copilot: return "chevron.left.forwardslash.chevron.right"
        default: return "cpu"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .claude: return "sk-ant-..."
        case .openai: return "sk-..."
        case .gemini: return "AIza..."
        case .copilot: return "Copilot token"
        case .muse: return "Meta API key"
        }
    }

    var documentationURL: URL? {
        switch self {
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .copilot: return URL(string: "https://docs.github.com/en/copilot")
        case .muse: return URL(string: "https://developer.meta.com/ai/")
        }
    }
}
