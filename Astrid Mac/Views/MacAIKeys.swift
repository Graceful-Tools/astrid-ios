//  MacAIKeys.swift
//  Astrid for Mac — pure model for the AI API-key providers (Task f8687dfb).

#if os(macOS)
import Foundation

enum MacAIKeys {
    struct Provider: Identifiable, Equatable { let id: String; let name: String }

    /// The built-in AI providers whose keys can be managed (serviceId matches the backend).
    static let providers: [Provider] = [
        .init(id: "claude", name: "Claude (Anthropic)"),
        .init(id: "openai", name: "OpenAI"),
        .init(id: "gemini", name: "Gemini (Google)"),
    ]

    /// A short status string for a provider given the keys response map.
    static func statusText(hasKey: Bool, preview: String?, isValid: Bool?) -> String {
        guard hasKey else { return NSLocalizedString("mac.ai_keys.not_set", comment: "") }
        let tail = preview.map { "•••\($0)" } ?? NSLocalizedString("mac.ai_keys.key_set", comment: "")
        if isValid == false { return String(format: NSLocalizedString("mac.ai_keys.invalid", comment: ""), tail) }
        return tail
    }
}
#endif
