import Foundation

/// The `@person` / `#list` / `!task` popup a comment or chat box is inside, if any —
/// astrid-core's `mentionTrigger` rule (`parse::mentions::find_trigger`, AITD-657).
///
/// The sigil closest to the caret, at the start of the text or after whitespace, with no
/// whitespace between it and the caret. Each sigil is judged on its last occurrence alone: an
/// invalid one opens nothing rather than reaching back to an earlier one (`"@jo@b"` → `nil`).
public struct MentionTrigger: Decodable, Equatable, Sendable {
    public enum Kind: String, Decodable, Sendable { case mention, list, task }

    public let kind: Kind
    /// Where the sigil sits, in **UTF-16** units — map it back with `utf16Index(in:)`.
    public let start: Int
    /// What has been typed after the sigil, as typed.
    public let query: String

    public init(kind: Kind, start: Int, query: String) {
        self.kind = kind; self.start = start; self.query = query
    }

    /// `start` as an index into `text`, the string it was asked about.
    public func utf16Index(in text: String) -> String.Index? {
        let utf16 = text.utf16
        guard let unit = utf16.index(utf16.startIndex, offsetBy: start, limitedBy: utf16.endIndex)
        else { return nil }
        return unit.samePosition(in: text)
    }
}

extension CoreRules {
    /// `caret` is in UTF-16 units; `nil` means the end of the text, where a typing caret sits.
    public static func mentionTrigger(text: String, caret: Int? = nil) throws -> MentionTrigger? {
        try ask(MentionTriggerRequest(text: text, caret: caret ?? text.utf16.count),
                as: MentionTrigger?.self)
    }
}

private struct MentionTriggerRequest: Encodable {
    let kind = "mentionTrigger"
    let text: String
    let caret: Int
}
