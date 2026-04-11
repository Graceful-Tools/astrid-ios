import SwiftUI

extension String {
    /// Convert markdown string to AttributedString
    /// Supports **bold**, *italic*, `code`, and other standard markdown
    func attributedMarkdown() -> AttributedString {
        do {
            // SwiftUI natively supports markdown in AttributedString (iOS 15+)
            return try AttributedString(markdown: self, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            // Fallback to plain text if markdown parsing fails
            print("⚠️ Failed to parse markdown: \(error)")
            return AttributedString(self)
        }
    }

    /// Convert content with @[Name](id), #[Name](id), ![Name](id) references into colored, tappable AttributedString
    /// @mentions → blue (links to profile), #lists → green (links to list), !tasks → orange (links to task). Also renders markdown.
    func attributedWithReferences(defaultColor: Color = .primary) -> AttributedString {
        let pattern = try! NSRegularExpression(pattern: #"([@#!])\[([^\]]+)\]\(([^)]+)\)"#)
        let nsText = self as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = pattern.matches(in: self, range: fullRange)

        // No references — use standard markdown rendering
        guard !matches.isEmpty else {
            var attr = attributedMarkdown()
            attr.foregroundColor = defaultColor
            return attr
        }

        // Build attributed string with colored, tappable references
        var result = AttributedString()
        var lastEnd = startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: self),
                  let triggerRange = Range(match.range(at: 1), in: self),
                  let nameRange = Range(match.range(at: 2), in: self),
                  let idRange = Range(match.range(at: 3), in: self) else { continue }

            // Plain text before this reference (render as markdown)
            if lastEnd < matchRange.lowerBound {
                let plainText = String(self[lastEnd..<matchRange.lowerBound])
                var plain = plainText.attributedMarkdown()
                plain.foregroundColor = defaultColor
                result += plain
            }

            // Colored, tappable reference: @Name, #Name, !Name
            let trigger = String(self[triggerRange])
            let name = String(self[nameRange])
            let refId = String(self[idRange])
            let color: Color
            let urlScheme: String
            switch trigger {
            case "@":
                color = .blue
                urlScheme = "astrid://users/\(refId)"
            case "#":
                color = .green
                urlScheme = "astrid://lists/\(refId)"
            case "!":
                color = .orange
                urlScheme = "astrid://tasks/\(refId)"
            default:
                color = defaultColor
                urlScheme = ""
            }
            var ref = AttributedString("\(trigger)\(name)")
            ref.foregroundColor = color
            ref.font = .body
            if let url = URL(string: urlScheme) {
                ref.link = url
            }
            result += ref

            lastEnd = matchRange.upperBound
        }

        // Remaining text after last reference
        if lastEnd < endIndex {
            let remainingText = String(self[lastEnd..<endIndex])
            var remaining = remainingText.attributedMarkdown()
            remaining.foregroundColor = defaultColor
            result += remaining
        }

        return result
    }

    /// Check if string contains markdown syntax
    var containsMarkdown: Bool {
        let markdownPatterns = [
            "**", "*", "__", "_",  // Bold/italic
            "`",                     // Code
            "[", "]", "(",  ")",    // Links
            "#", "-", "*",          // Headers/lists
            "```"                   // Code blocks
        ]

        return markdownPatterns.contains { self.contains($0) }
    }
}
