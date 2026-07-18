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
}
#endif
