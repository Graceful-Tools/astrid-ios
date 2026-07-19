//  MacAutocomplete.swift
//  Astrid for Mac — @mention / #list / !task autocomplete for chat & comment inputs (Task cc67a3a5).
//  Pure trigger-detection + insertion (mirrors the iOS detectAutocompleteTrigger contract), kept
//  testable and separate from the view. The iOS AutocompleteSupport is excluded from the Mac
//  target, so this is the Mac-side implementation of the same behavior.

#if os(macOS)
import Foundation

enum MacAutocompleteKind: Equatable {
    case mention, list, task
    var trigger: Character { self == .mention ? "@" : (self == .list ? "#" : "!") }
}

struct MacAutocompleteHit: Equatable {
    let kind: MacAutocompleteKind
    let triggerOffset: Int    // character offset of the trigger in the text
    let search: String        // text typed after the trigger (no spaces)
}

enum MacAutocomplete {
    /// Detect an active @/#/! token at the caret tail: the trigger must start the string or follow
    /// whitespace, and must have no space after it. The right-most valid trigger wins.
    static func detectTrigger(in text: String) -> MacAutocompleteHit? {
        let triggers: [(Character, MacAutocompleteKind)] = [("@", .mention), ("#", .list), ("!", .task)]
        var best: MacAutocompleteHit?
        for (char, kind) in triggers {
            guard let idx = text.lastIndex(of: char) else { continue }
            if idx != text.startIndex {
                let before = text[text.index(before: idx)]
                if !before.isWhitespace && before != "\n" { continue }
            }
            let after = String(text[text.index(after: idx)...])
            if after.contains(" ") || after.contains("\n") { continue }
            let offset = text.distance(from: text.startIndex, to: idx)
            if best == nil || offset > best!.triggerOffset {
                best = MacAutocompleteHit(kind: kind, triggerOffset: offset, search: after)
            }
        }
        return best
    }

    /// Replace the active trigger token with "<trigger><label> " (trailing space ends the token).
    static func insert(label: String, into text: String, hit: MacAutocompleteHit) -> String {
        let start = text.index(text.startIndex, offsetBy: hit.triggerOffset)
        return String(text[..<start]) + String(hit.kind.trigger) + label + " "
    }

    struct Suggestion: Identifiable, Equatable {
        let id: String; let label: String; let icon: String
    }

    /// Build the suggestion list for an active trigger — SHARED by chat and task-detail comments
    /// so both inputs behave identically (Task eda86d23). Pure over the passed-in data.
    static func suggestions(for hit: MacAutocompleteHit, members: [ListMember],
                            lists: [TaskList], tasks: [Task], limit: Int = 6) -> [Suggestion] {
        let q = hit.search.lowercased()
        switch hit.kind {
        case .list:
            return lists.filter { q.isEmpty || $0.name.lowercased().contains(q) }
                .prefix(limit).map { Suggestion(id: $0.id, label: $0.name, icon: "list.bullet") }
        case .task:
            return tasks.filter { !$0.completed && (q.isEmpty || $0.title.lowercased().contains(q)) }
                .prefix(limit).map { Suggestion(id: $0.id, label: $0.title, icon: "circle") }
        case .mention:
            return members.filter { q.isEmpty || ($0.user?.displayName ?? $0.userId).lowercased().contains(q) }
                .prefix(limit).map { Suggestion(id: $0.userId, label: $0.user?.displayName ?? $0.userId, icon: "person.crop.circle") }
        }
    }
}
#endif
