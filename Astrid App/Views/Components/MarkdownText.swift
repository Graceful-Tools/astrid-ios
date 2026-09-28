//  MarkdownText.swift
//  Astrid for iOS — a message, rendered. (Task AITD-416)
//
//  The iOS style for the shared `MarkdownView`: what the text means is astrid-core's
//  (`CoreRules.markdown`, the web's own rendering); what it looks like on a phone is this file's.
//  The Mac's twin is `MacMarkdownText`, and the two differ only in fonts and metrics.

import AstridCore
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
        MarkdownView(source: source, style: style)
    }

    private var style: MarkdownStyle {
        MarkdownStyle(
            body: Theme.Typography.body(),
            heading: Self.headingFont,
            code: .system(.footnote, design: .monospaced),
            text: defaultColor,
            muted: defaultColor.opacity(0.6),
            // Tinted from the text colour rather than a fixed Theme background: this sits inside
            // a bubble whose own background changes with the theme and with who sent it, so a
            // fixed grey would clash in at least one of those.
            codeBackground: defaultColor.opacity(0.08),
            blockSpacing: Theme.spacing4,
            markerSpacing: Theme.spacing8,
            codePadding: Theme.spacing8,
            codeCornerRadius: Theme.radiusSmall,
            fillsWidth: fillsWidth)
    }

    /// One block's worth of inline text — markdown marks and `@`/`#`/`!` references — as the
    /// block view draws it: the reference carries no font, so the block's font reaches it.
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
