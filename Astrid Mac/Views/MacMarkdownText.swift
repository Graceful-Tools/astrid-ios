//  MacMarkdownText.swift
//  Astrid for Mac — a description, a comment or a chat message, rendered. (Task f5520874)
//
//  The Mac style for the shared `MarkdownView`: what the text means is astrid-core's
//  (`CoreRules.markdown`, the web's own rendering); what it looks like on a Mac is this file's.
//
//  Only the DISPLAY is formatted. The editor stays plain text, because what you edit has to
//  be the characters you typed — showing rendered markdown in the editor would leave no way
//  to write the syntax.

#if os(macOS)
import AstridCore
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
        MarkdownView(source: source, style: style)
            .textSelection(.enabled)
            .frame(maxWidth: Self.maxWidth(fillsWidth: fillsWidth), alignment: .leading)
    }

    private var style: MarkdownStyle {
        MarkdownStyle(
            body: MacTypography.detailBody,
            heading: { .system(size: Self.headingSize($0), weight: .semibold) },
            code: .system(size: 12, design: .monospaced),
            text: Theme.textPrimary,
            muted: Theme.textMuted,
            codeBackground: Theme.bgTertiary,
            blockSpacing: 4,
            markerSpacing: 6,
            codePadding: 6,
            codeCornerRadius: 4,
            fillsWidth: fillsWidth)
    }

    /// `nil` is SwiftUI's "no constraint" — the view ends up as wide as its text.
    static func maxWidth(fillsWidth: Bool) -> CGFloat? {
        fillsWidth ? .infinity : nil
    }

    /// One block's worth of inline text, as an attributed string: markdown marks AND
    /// `@`/`#`/`!` references, from the one shared pass (AITD-390). `referenceFont: nil` because
    /// the BLOCK sets the font here: a heading's reference has to be heading-sized.
    ///
    /// Pure and static so it can be asserted on without building a view.
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
