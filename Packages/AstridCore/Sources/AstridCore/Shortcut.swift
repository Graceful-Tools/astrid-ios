import Foundation

/// What a bare key press does right now — astrid-core's `shortcut` rule (`keyboard::action_for`,
/// AITD-655), the single-key scheme every desktop client shares with the web.
///
/// The guards are part of the answer: a key pressed into a text field or under a modal, an
/// unbound key, and a selection-scoped key with nothing selected all answer `nil`.
public struct ShortcutAnswer: Decodable, Equatable, Sendable {
    /// The action's stable name — `newTask`, `selectNext`, …
    public let action: String
    public let title: String
    public let requiresSelection: Bool
}

extension CoreRules {
    /// `key` is the canonical key, an alias (`↓`), or a key-event name (`ArrowDown`).
    public static func shortcut(
        key: String, hasSelection: Bool = false, isTextFieldFocused: Bool = false,
        isModalPresented: Bool = false
    ) throws -> ShortcutAnswer? {
        try ask(ShortcutRequest(key: key, hasSelection: hasSelection,
                                isTextFieldFocused: isTextFieldFocused,
                                isModalPresented: isModalPresented),
                as: ShortcutAnswer?.self)
    }
}

private struct ShortcutRequest: Encodable {
    let kind = "shortcut"
    let key: String
    let hasSelection: Bool
    let isTextFieldFocused: Bool
    let isModalPresented: Bool
}
