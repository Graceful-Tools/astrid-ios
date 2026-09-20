//  MarkdownText.swift
//  Astrid for iOS — a message, rendered. (Task AITD-416)
//
//  The iOS twin of `MacMarkdownText`, and deliberately the same shape: BLOCK structure from the
//  shared `MarkdownBlocks`, INLINE marks and `@`/`#`/`!` references from the shared
//  `String.attributedWithReferences`. Neither half is enough alone — SwiftUI's `Text` renders
//  inline attributes out of an `AttributedString` but will not render block structure from one,
//  so a heading and a bullet arrive as ordinary lines with their syntax still attached.
//
//  Why iOS needed it: agent prose is now most of what these two bubbles carry — /fixall run
//  summaries in list chat, completion reports in task comments — and the phone is where it is
//  read. Until this, both bubbles parsed with `.inlineOnlyPreservingWhitespace`, so every `##`
//  and `-` in that prose was shown as a character.
//
//  Shared with the Mac at the parser, not at the view: the fonts and the bubble metrics are the
//  part that genuinely differs per platform, and everything above them is one implementation.

import SwiftUI

struct MarkdownText: View {
    let source: String
    /// The colour of ordinary prose. References keep their own (blue / green / orange).
    var defaultColor: Color = Theme.textPrimary
    /// Does this fill the width it is given, or hug its text?
    ///
    /// Both iOS callers are bubbles sized to their content, so they hug (`false`) — filling
    /// would stretch every bubble across the thread and undo the left/right layout that says at
    /// a glance whose message it is. The default matches the Mac's, for a caller that owns a
    /// column rather than a bubble.
    var fillsWidth: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing4) {
            ForEach(Array(MarkdownBlocks.parse(source).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    inline(text)
                        .font(Self.headingFont(level))
                        .padding(.top, Theme.spacing2)
                case .orderedItem(let number, let text):
                    marked("\(number).", text)
                case .bulletItem(let text):
                    marked("•", text)
                case .codeBlock(let text):
                    code(text)
                case .paragraph(let text):
                    inline(text)
                        .font(Theme.Typography.body())
                }
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
    }

    /// A list row: the marker keeps its own column so wrapped text lines up under itself rather
    /// than under the number.
    private func marked(_ marker: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing8) {
            Text(marker)
                .font(Theme.Typography.body())
                .foregroundColor(defaultColor.opacity(0.6))
                .frame(minWidth: 14, alignment: .trailing)
            inline(text)
                .font(Theme.Typography.body())
            // The spacer pins the marker column to the left edge of a view wider than its text.
            // A bubble has no spare width to take up, and asking for it would be another way of
            // demanding the whole thread's width.
            if fillsWidth { Spacer(minLength: 0) }
        }
    }

    /// A fence renders VERBATIM in a monospaced face — no inline pass, because the promise of a
    /// fence is that what is inside it is not markdown.
    private func code(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .foregroundColor(defaultColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.spacing8)
            // Tinted from the text colour rather than a fixed Theme background: this sits inside
            // a bubble whose own background changes with the theme and with who sent it, so a
            // fixed grey would clash in at least one of those.
            .background(defaultColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func inline(_ text: String) -> Text {
        Text(Self.attributed(text, defaultColor: defaultColor))
    }

    /// One block's worth of inline text: markdown marks AND `@`/`#`/`!` references, from the one
    /// shared pass.
    ///
    /// `referenceFont: nil` because the BLOCK sets the font here (AITD-390) — stamping `.body` on
    /// a reference inside an `##` heading would draw it at body size while the words either side
    /// of it stayed heading-sized.
    ///
    /// Static and pure so it can be asserted on without building a view.
    static func attributed(_ text: String, defaultColor: Color) -> AttributedString {
        text.attributedWithReferences(defaultColor: defaultColor, referenceFont: nil)
    }

    /// Headings stop growing apart at level 3. Below that the difference is invisible, and a
    /// `####` drawn smaller than the paragraph it introduces reads as a mistake rather than a
    /// heading. Text styles rather than point sizes, so Dynamic Type still moves them.
    static func headingFont(_ level: Int) -> Font {
        switch max(1, level) {
        case 1: return .system(.title3, design: .default, weight: .bold)
        case 2: return .system(.headline, design: .default, weight: .semibold)
        default: return .system(.subheadline, design: .default, weight: .semibold)
        }
    }
}
