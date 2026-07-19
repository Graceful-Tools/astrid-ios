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
        guard hasKey else { return "Not set" }
        let tail = preview.map { "•••\($0)" } ?? "Key set"
        if isValid == false { return "\(tail) — invalid" }
        return tail
    }
}
#endif
