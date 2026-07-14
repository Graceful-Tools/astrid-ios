//  QuickEntryParser.swift
//  Astrid for Mac — parse quick-add text into title + list tokens + a due hint (M2).
//
//  Presentation-layer parsing for the global quick-entry window. Extracts `#list` tokens and
//  simple natural-language due hints ("today"/"tomorrow"), returning the cleaned task title.
//  The resulting title/lists/due are handed to TaskService (the shared write path).

import Foundation

struct QuickEntryParser {
    enum DueHint: Equatable { case today, tomorrow }

    struct Result: Equatable {
        var title: String
        var listNames: [String]
        var due: DueHint?
    }

    static func parse(_ input: String) -> Result {
        var lists: [String] = []
        var due: DueHint?
        var titleWords: [String] = []

        for raw in input.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            let word = String(raw)
            if word.hasPrefix("#"), word.count > 1 {
                lists.append(String(word.dropFirst()))
                continue
            }
            switch word.lowercased() {
            case "today": due = .today; continue
            case "tomorrow": due = .tomorrow; continue
            default: titleWords.append(word)
            }
        }

        return Result(
            title: titleWords.joined(separator: " ").trimmingCharacters(in: .whitespaces),
            listNames: lists,
            due: due
        )
    }
}
