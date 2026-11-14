//  MacAutocomplete.swift
//  Astrid for Mac — @mention / #list / !task autocomplete for chat & comment inputs (Task cc67a3a5).
//  Trigger detection (astrid-core's `mentionTrigger`, AITD-657) + insertion, kept
//  testable and separate from the view. The iOS AutocompleteSupport is excluded from the Mac
//  target, so this is the Mac-side implementation of the same behavior.

#if os(macOS)
import AstridCore
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
    /// Detect an active @/#/! token at the caret tail — astrid-core's `mentionTrigger` (AITD-657),
    /// the rule iOS and web share: the sigil must start the string or follow whitespace, have no
    /// whitespace after it, and the right-most valid one wins. The core counts UTF-16 units; the
    /// offset here is in Characters, because `insert` and the views index by Character.
    static func detectTrigger(in text: String) -> MacAutocompleteHit? {
        guard let hit = try? CoreRules.mentionTrigger(text: text),
              let index = hit.utf16Index(in: text) else { return nil }
        let kind: MacAutocompleteKind
        switch hit.kind {
        case .mention: kind = .mention
        case .list: kind = .list
        case .task: kind = .task
        }
        return MacAutocompleteHit(kind: kind, triggerOffset: text.distance(from: text.startIndex, to: index),
                                  search: hit.query)
    }

    /// Replace the active trigger token with the reference iOS sends — `@[Name](id) ` (the
    /// trailing space ends the token). This wrote plain `@label`, which draws no pill and notifies
    /// nobody (CONTRACTS D23); Jon 2026-10-03: on disagreement follow iOS. The markup is shared.
    static func insert(label: String, id: String, into text: String, hit: MacAutocompleteHit) -> String {
        let start = text.index(text.startIndex, offsetBy: hit.triggerOffset)
        return String(text[..<start])
            + ReferenceMarkup.reference(trigger: hit.kind.trigger, name: label, id: id) + " "
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
