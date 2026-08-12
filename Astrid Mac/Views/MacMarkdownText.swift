//  MacMarkdownText.swift
//  Astrid for Mac — a description, rendered. (Task f5520874)
//
//  Blocks come from the shared `MarkdownBlocks`; inline marks inside each block go to
//  `AttributedString(markdown:)`, which is what actually knows how to draw bold and links.
//  The two halves are deliberately separate: SwiftUI's Text renders inline attributes but
//  not block structure, so neither one alone is enough.
//
//  Only the DISPLAY is formatted. The editor stays plain text, because what you edit has to
//  be the characters you typed — showing rendered markdown in the editor would leave no way
//  to write the syntax.

#if os(macOS)
import SwiftUI

struct MacMarkdownText: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(MarkdownBlocks.parse(source).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    inline(text)
                        .font(.system(size: Self.headingSize(level), weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 2)
                case .orderedItem(let number, let text):
                    marked("\(number).", text)
                case .bulletItem(let text):
                    marked("•", text)
                case .paragraph(let text):
                    inline(text)
                        .font(MacTypography.detailBody)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A list row: the marker keeps its own column so wrapped text lines up under itself
    /// rather than under the number.
    private func marked(_ marker: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(marker)
                .font(MacTypography.detailBody)
                .foregroundStyle(Theme.textMuted)
                .frame(minWidth: 14, alignment: .trailing)
            inline(text)
                .font(MacTypography.detailBody)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
        }
    }

    /// Inline marks only. Falls back to the raw text when the fragment will not parse —
    /// showing the characters someone typed always beats showing nothing.
    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(text)
    }

    /// Headings stop shrinking at level 3 — below that the difference is invisible and the
    /// text just ends up smaller than the body it introduces.
    static func headingSize(_ level: Int) -> CGFloat {
        switch max(1, level) {
        case 1: return 17
        case 2: return 15
        default: return 13
        }
    }
}
#endif
