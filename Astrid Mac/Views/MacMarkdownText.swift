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
    /// Does this fill the width it is given, or hug its text?
    ///
    /// A description owns its column, so it fills — that is what keeps a heading's underline and a
    /// list's markers aligned down the pane. A comment sits in a bubble sized to its content
    /// (AITD-389): filling there would stretch every bubble across the whole thread and undo the
    /// right-aligned "mine" layout that says at a glance whose comment it is.
    var fillsWidth: Bool = true

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
        .textSelection(.enabled)
        .frame(maxWidth: Self.maxWidth(fillsWidth: fillsWidth), alignment: .leading)
    }

    /// `nil` is SwiftUI's "no constraint" — the view ends up as wide as its text.
    static func maxWidth(fillsWidth: Bool) -> CGFloat? {
        fillsWidth ? .infinity : nil
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
            // The spacer is what pins the marker column to the left edge of a pane that is wider
            // than the text. In a bubble there is no spare width to take up, and asking for it
            // would be another way of demanding the whole thread's width.
            if fillsWidth { Spacer(minLength: 0) }
        }
    }

    /// Inline marks only. Falls back to the raw text when the fragment will not parse —
    /// showing the characters someone typed always beats showing nothing.
    private func inline(_ text: String) -> Text {
        Text(Self.attributed(text))
    }

    /// One block's worth of inline text, as an attributed string: markdown marks AND
    /// `@`/`#`/`!` references, from the one shared pass (AITD-390).
    ///
    /// `attributedWithReferences` splits at each reference and markdown-parses the gaps, so the
    /// two have never actually collided — what was missing is that this renderer called
    /// `AttributedString(markdown:)` directly and stepped around the reference pass, leaving a
    /// comment showing `![Name](id)` as characters while chat two panes over drew it as a link.
    ///
    /// `referenceFont: nil` because the BLOCK sets the font here: a heading's reference has to be
    /// heading-sized. A flat bubble keeps the extension's `.body` default.
    ///
    /// Pure and static so it can be asserted on without building a view — the same seam
    /// `maxWidth(fillsWidth:)` opens for the layout half.
    static func attributed(_ text: String) -> AttributedString {
        text.attributedWithReferences(defaultColor: Theme.textPrimary, referenceFont: nil)
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
