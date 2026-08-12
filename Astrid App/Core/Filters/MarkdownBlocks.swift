//  MarkdownBlocks.swift
//  Block structure of a markdown description. (Task f5520874)
//
//  `AttributedString(markdown:)` understands INLINE marks — bold, italic, links — but
//  SwiftUI's `Text` will not render block structure from it: a heading and an ordered list
//  arrive as ordinary lines. So the blocks are parsed here and the view draws each one,
//  handing the block's text to AttributedString for whatever inline marks it contains.
//
//  Pure, so the parsing is testable without a view, and shared rather than Mac-only: a
//  description is a description on every platform.

import Foundation

enum MarkdownBlock: Equatable {
    /// `#`–`######`. Level is kept as written; the view decides how small it stops getting.
    case heading(level: Int, text: String)
    /// `1.` / `2.` — the number is the one the author wrote, not a position. Renumbering
    /// someone's list is a lie about what they typed.
    case orderedItem(number: Int, text: String)
    /// `-` or `*`.
    case bulletItem(text: String)
    /// Everything else. Consecutive plain lines join, as markdown means them.
    case paragraph(text: String)
}

enum MarkdownBlocks {

    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []

        // A paragraph only ends when something else begins — a blank line, a list, a
        // heading, or the end of the text.
        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(text: paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                continue
            }
            if let heading = heading(from: line) {
                flushParagraph()
                blocks.append(heading)
                continue
            }
            if let ordered = orderedItem(from: line) {
                flushParagraph()
                blocks.append(ordered)
                continue
            }
            if let bullet = bulletItem(from: line) {
                flushParagraph()
                blocks.append(bullet)
                continue
            }
            paragraph.append(line)
        }
        flushParagraph()
        return blocks
    }

    /// `# ` … `###### `. The SPACE is required: `#header` is not a heading in markdown, and
    /// people write `#1` meaning a number — which must not silently become a title.
    private static func heading(from line: String) -> MarkdownBlock? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes.count,
                        text: String(rest).trimmingCharacters(in: .whitespaces))
    }

    /// `1. text`. The dot AND the space are both required, so "3.5 hours" stays prose.
    private static func orderedItem(from line: String) -> MarkdownBlock? {
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.first == ".", rest.dropFirst().first == " " else { return nil }
        return .orderedItem(number: number,
                            text: String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces))
    }

    /// `- text` or `* text`. The space keeps "*emphasis*" from reading as a bullet.
    private static func bulletItem(from line: String) -> MarkdownBlock? {
        guard let marker = line.first, marker == "-" || marker == "*" else { return nil }
        let rest = line.dropFirst()
        guard rest.first == " " else { return nil }
        return .bulletItem(text: String(rest).trimmingCharacters(in: .whitespaces))
    }
}
